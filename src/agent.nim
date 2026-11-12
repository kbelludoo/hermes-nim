import std/[os, times]
import types, utils, llm_client, memory, skills, cron, sessions, subagent, mbvm_native
import tools/registry

type
  AIAgent* = ref object
    config*: AgentConfig
    client*: LLMClient
    memoryStore*: MemoryStore
    registry*: ToolRegistry
    skillRegistry*: SkillRegistry
    cronScheduler*: CronScheduler
    graph*: ConversationGraph
    messages*: seq[Message]
    sessionId*: string
    totalPromptTokens*: int
    totalCompletionTokens*: int

proc runConversation*(agent: AIAgent, userInput: string, onChunk: proc(text: string) = nil): string

proc newAIAgent*(config: AgentConfig, existingSessionId: string = "", initialMessages: seq[Message] = @[]): AIAgent =
  new(result)
  result.config = config
  result.client = newLLMClient(config)
  result.memoryStore = newMemoryStore(config.hermesHome)
  result.skillRegistry = newSkillRegistry(config.hermesHome)
  result.cronScheduler = newCronScheduler()
  
  if existingSessionId.len > 0:
    result.sessionId = existingSessionId
  else:
    result.sessionId = "session_" & now().format("yyyyMMdd") & "_" & now().format("HHmmss")

  let graphPath = config.hermesHome / "sessions" / (result.sessionId & ".mbvm.json")
  result.graph = loadFromJson(graphPath)

  # Resolve python worker script path
  let appDir = getAppDir()
  var wScript = appDir / ".." / "python_worker" / "tool_runner.py"
  if not fileExists(wScript):
    wScript = appDir / "python_worker" / "tool_runner.py"
  if not fileExists(wScript):
    wScript = getCurrentDir() / "python_worker" / "tool_runner.py"

  result.registry = newToolRegistry(
    result.memoryStore,
    config.pythonPath,
    wScript,
    rustBrowserExe = "",
    skillReg = result.skillRegistry,
    cronSched = result.cronScheduler,
    hermesHome = config.hermesHome,
    yoloMode = config.yoloMode
  )
  result.registry.initDefaultTools()

  result.totalPromptTokens = 0
  result.totalCompletionTokens = 0

  if initialMessages.len > 0:
    result.messages = initialMessages
  else:
    result.messages = @[]
    # Build initial system message with SOUL, memory, and skills overview
    var sysPrompt = config.systemPrompt
    
    let recalledMem = result.memoryStore.recall("")
    if recalledMem.len > 0 and recalledMem != "No memories stored yet.":
      sysPrompt &= "\n\n[Persistent Memory Context]:\n" & recalledMem

    let skillsList = result.skillRegistry.listSkills()
    if skillsList != "No skills currently installed.":
      sysPrompt &= "\n\n[Available Skills]:\n" & skillsList & "\nUse `skill_view` to read full instructions for any skill when relevant."

    result.messages.add(Message(
      role: "system",
      content: sysPrompt
    ))

  # Initialize Subagent delegate runner
  let baseCfg = config
  setSubagentRunner(proc(task: string, modelOverride: string = ""): string =
    var subCfg = baseCfg
    if modelOverride.len > 0:
      subCfg.model = modelOverride
    subCfg.maxTurns = 10
    subCfg.systemPrompt = "You are a focused subagent assistant. Complete the given task thoroughly and return a clear, structured summary report."
    let subAg = newAIAgent(subCfg)
    return subAg.runConversation(task)
  )

proc pruneContextIfNeeded*(agent: AIAgent, maxChars: int = 100_000) =
  var totalChars = 0
  for m in agent.messages:
    totalChars += m.content.len
  
  if totalChars <= maxChars or agent.messages.len <= 6:
    return

  # Keep system prompt (index 0) and the first user message (index 1)
  var pruned: seq[Message] = @[agent.messages[0]]
  if agent.messages.len > 1:
    pruned.add(agent.messages[1])

  # Keep the last 10 messages
  let startKeep = max(2, agent.messages.len - 10)
  pruned.add(Message(
    role: "system",
    content: "... [Prior conversation history compacted to conserve memory] ..."
  ))
  for i in startKeep ..< agent.messages.len:
    pruned.add(agent.messages[i])

  agent.messages = pruned

proc runConversation*(agent: AIAgent, userInput: string, onChunk: proc(text: string) = nil): string =
  # 1. Native MBVM-DB Auto-Slicing (Invisible Context Injection in Pure Nim)
  let relevantSlice = agent.graph.extractSlice(userInput, maxDepth = 2)
  if relevantSlice.len > 0:
    let sliceText = projectSlice(relevantSlice)
    if sliceText.len > 0:
      agent.messages.add(Message(
        role: "system",
        content: "[MBVM Subgraph Knowledge (Native Nim -95% tokens)]:\n" & sliceText
      ))

  agent.messages.add(Message(
    role: "user",
    content: userInput
  ))

  agent.pruneContextIfNeeded()

  let toolsSchema = agent.registry.getOpenAIToolsSchema()
  var turnCount = 0
  var finalAnswer = ""
  var turnToolCalls: seq[ToolCall] = @[]
  var turnToolOutputs: seq[string] = @[]

  while turnCount < agent.config.maxTurns:
    inc(turnCount)
    
    # Enforce memory constraint
    let currentMemMB = getResidentMemoryMB()
    if currentMemMB > agent.config.maxMemoryMB:
      # Aggressive GC / memory trim if exceeding limit
      agent.pruneContextIfNeeded(maxChars = 40_000)

    var resp: LLMResponse
    try:
      resp = agent.client.createChatCompletion(agent.messages, toolsSchema)
    except CatchableError as e:
      let errStr = "Error calling LLM: " & e.msg
      if onChunk != nil: onChunk(colorize(errStr & "\n", AnsiRed))
      return errStr

    agent.totalPromptTokens += resp.promptTokens
    agent.totalCompletionTokens += resp.completionTokens

    # Check if assistant returned text
    if resp.content.len > 0:
      finalAnswer = resp.content
      if onChunk != nil:
        onChunk(resp.content)

    # Check if assistant invoked tools
    if resp.toolCalls.len > 0:
      var asstMsg = Message(
        role: "assistant",
        content: resp.content,
        toolCalls: resp.toolCalls
      )
      agent.messages.add(asstMsg)

      # Execute each requested tool
      for tc in resp.toolCalls:
        if onChunk != nil:
          let toolNotice = "\n" & colorize("► Executing tool: ", AnsiCyan) & colorize(tc.functionName, AnsiBold) & " " & colorize(tc.arguments, AnsiDim) & "\n"
          onChunk(toolNotice)

        let toolOutput = agent.registry.executeTool(tc.functionName, tc.arguments)
        turnToolCalls.add(tc)
        turnToolOutputs.add(toolOutput)

        if onChunk != nil:
          let preview = if toolOutput.len > 300: toolOutput[0 ..< 300] & "... (" & $toolOutput.len & " chars)" else: toolOutput
          onChunk(colorize("  ↳ Result: ", AnsiGreen) & preview & "\n")

        # Append tool result to context
        agent.messages.add(Message(
          role: "tool",
          name: tc.functionName,
          toolCallId: tc.id,
          content: toolOutput
        ))

      continue
    else:
      # No tool calls made; model finished its turn
      agent.messages.add(Message(
        role: "assistant",
        content: resp.content
      ))
      break

  # Automatically persist session
  saveSession(agent.config.hermesHome, agent.sessionId, agent.messages)

  # 2. Native MBVM-DB Auto-Ingestion (Invisible Background Graph Update in Pure Nim)
  discard agent.graph.ingestTurn(
    userInput,
    turnToolCalls,
    turnToolOutputs,
    finalAnswer,
    agent.messages.len
  )
  agent.graph.saveToJson(agent.config.hermesHome / "sessions" / (agent.sessionId & ".mbvm.json"))

  return finalAnswer
