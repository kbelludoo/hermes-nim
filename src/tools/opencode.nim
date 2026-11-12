import std/[os, osproc, streams, json, strutils, times]
import ../types

const FallbackOpenCodeModels* = @[
  "google/gemini-2.5-flash",
  "google/gemini-2.5-flash-lite",
  "google/gemini-2.5-pro",
  "google/gemini-flash-latest",
  "opencode/deepseek-v4.1-flash-free",
  "opencode/glm-5.3-flash-free",
  "opencode/beam-free",
  "opencode/big-pickle",
  "9router/oc/deepseek-v4.1-flash-free"
]

proc getOpenCodeCliPath*(): string =
  let envPath = getEnv("OPENCODE_CLI_PATH")
  if envPath.len > 0 and fileExists(envPath):
    return envPath

  when defined(windows):
    let localApp = getEnv("LOCALAPPDATA")
    if localApp.len > 0:
      let cand = localApp / "Programs" / "@opencode-aidesktop" / "resources" / "opencode-cli.exe"
      if fileExists(cand):
        return cand
      let cand2 = localApp / "Programs" / "opencode" / "opencode-cli.exe"
      if fileExists(cand2):
        return cand2
      let cand3 = localApp / "Programs" / "opencode" / "resources" / "opencode-cli.exe"
      if fileExists(cand3):
        return cand3

    let progFiles = getEnv("ProgramFiles")
    if progFiles.len > 0:
      let cand4 = progFiles / "opencode" / "opencode-cli.exe"
      if fileExists(cand4):
        return cand4

  # Check PATH
  for name in ["opencode-cli", "opencode"]:
    let cand = findExe(name)
    if cand.len > 0 and fileExists(cand):
      return cand

  return ""

proc isOpenCodeInstalled*(): bool =
  getOpenCodeCliPath().len > 0

proc isOpenCodeModel*(modelName: string): bool =
  if modelName.len == 0: return false
  let prefixes = [
    "google/", "opencode/", "9router/", "github-copilot/",
    "codecraft/", "deepseek-local/", "clinepass/"
  ]
  for p in prefixes:
    if modelName.startsWith(p):
      return true
  return false

proc listOpenCodeModels*(): seq[string] =
  let cli = getOpenCodeCliPath()
  if cli.len == 0:
    return FallbackOpenCodeModels

  try:
    let p = startProcess(
      cli,
      args = ["models"],
      options = {poUsePath, poStdErrToStdOut}
    )
    p.inputStream.close()
    
    var lines: seq[string] = @[]
    while not p.outputStream.atEnd():
      let line = p.outputStream.readLine().strip()
      if line.len > 0 and not line.startsWith("=") and not line.contains(" "):
        lines.add(line)

    discard p.waitForExit()
    p.close()

    if lines.len > 0:
      return lines
  except CatchableError:
    discard

  return FallbackOpenCodeModels

proc queryOpenCode*(model: string, prompt: string, onChunk: proc(text: string) = nil, timeoutMs: int = 120_000): string =
  let cli = getOpenCodeCliPath()
  if cli.len == 0:
    return "Error: OpenCode CLI binary not found. Please install OpenCode or set OPENCODE_CLI_PATH."

  let targetModel = if model.len > 0: model else: "google/gemini-2.5-flash"
  let args = ["run", "--format", "json", "-m", targetModel]

  var p: Process
  try:
    p = startProcess(
      cli,
      args = args,
      options = {poUsePath, poStdErrToStdOut}
    )
  except CatchableError as e:
    return "Error starting OpenCode process: " & e.msg

  # Pipe prompt to stdin and immediately close to send EOF (avoids TTY hang)
  try:
    p.inputStream.write(prompt)
    p.inputStream.close()
  except CatchableError as e:
    p.close()
    return "Error writing to OpenCode stdin: " & e.msg

  var fullText = ""
  var errorText = ""

  while not p.outputStream.atEnd():
    var line = ""
    try:
      line = p.outputStream.readLine().strip()
    except CatchableError:
      break
    if line.len == 0: continue

    try:
      let j = parseJson(line)
      if j.hasKey("type"):
        let t = j["type"].getStr()
        if t == "text":
          if j.hasKey("part") and j["part"].hasKey("text"):
            let chunk = j["part"]["text"].getStr()
            fullText &= chunk
            if onChunk != nil:
              onChunk(chunk)
        elif t == "error":
          if j.hasKey("error") and j["error"].hasKey("message"):
            errorText = j["error"]["message"].getStr()
          elif j.hasKey("error"):
            errorText = $j["error"]
    except CatchableError:
      if line.startsWith("Error:") or line.startsWith("error:"):
        errorText = line

  discard p.waitForExit()
  p.close()

  if errorText.len > 0 and fullText.len == 0:
    return "OpenCode Error (" & targetModel & "): " & errorText

  return fullText

proc formatToolsForPrompt*(tools: seq[JsonNode]): string =
  if tools.len == 0: return ""
  result = "\n[Available Tools]:\n"
  for t in tools:
    if t.hasKey("function"):
      let fn = t["function"]
      let name = fn.getOrDefault("name").getStr("")
      let desc = fn.getOrDefault("description").getStr("")
      var paramsDesc = ""
      if fn.hasKey("parameters") and fn["parameters"].hasKey("properties"):
        for pName, pObj in fn["parameters"]["properties"]:
          let pType = pObj.getOrDefault("type").getStr("string")
          let pD = pObj.getOrDefault("description").getStr("")
          paramsDesc &= pName & ": " & pType & " (" & pD & "), "
        if paramsDesc.endsWith(", "):
          paramsDesc = paramsDesc[0 .. ^3]
      result &= "- " & name & "(" & paramsDesc & "): " & desc & "\n"

  result &= "\nTo call a tool, you MUST output ONLY a block like this:\n" &
            "```tool_call\n" &
            "{\"name\": \"<tool_name>\", \"arguments\": {<json_arguments>}}\n" &
            "```\n" &
            "If no tool is required, provide your direct final answer.\n\n"

proc formatConversationForPrompt*(messages: seq[Message], tools: seq[JsonNode] = @[]): string =
  var sb = ""
  for m in messages:
    case m.role
    of "system":
      sb &= "[System Instructions]:\n" & m.content & "\n\n"
    of "user":
      sb &= "[User]: " & m.content & "\n\n"
    of "assistant":
      if m.content.len > 0:
        sb &= "[Assistant]: " & m.content & "\n\n"
      for tc in m.toolCalls:
        sb &= "[Assistant Tool Call]: " & tc.functionName & "(" & tc.arguments & ")\n\n"
    of "tool":
      sb &= "[Tool Result (" & m.name & ")]: " & m.content & "\n\n"
    else:
      sb &= "[" & m.role & "]: " & m.content & "\n\n"

  if tools.len > 0:
    sb &= formatToolsForPrompt(tools)

  sb &= "[Assistant]: "
  return sb

proc extractToolCallFromText*(text: string): (string, seq[ToolCall]) =
  var toolCalls: seq[ToolCall] = @[]
  var cleanText = text

  # Pattern 1: ```tool_call ... ```
  let startMarker = "```tool_call"
  let endMarker = "```"
  var idx = cleanText.find(startMarker)
  if idx >= 0:
    let afterStart = idx + startMarker.len
    let closeIdx = cleanText.find(endMarker, afterStart)
    if closeIdx > idx:
      let jsonStr = cleanText[afterStart ..< closeIdx].strip()
      try:
        let j = parseJson(jsonStr)
        var tc = ToolCall()
        tc.id = "call_" & $now().toTime().toUnix()
        if j.hasKey("name"):
          tc.functionName = j["name"].getStr()
        elif j.hasKey("tool"):
          tc.functionName = j["tool"].getStr()
        if j.hasKey("arguments"):
          if j["arguments"].kind == JString:
            tc.arguments = j["arguments"].getStr()
          else:
            tc.arguments = $j["arguments"]
        if tc.functionName.len > 0:
          toolCalls.add(tc)
          cleanText = (cleanText[0 ..< idx] & cleanText[(closeIdx + endMarker.len) .. ^1]).strip()
      except CatchableError:
        discard

  # Pattern 2: ```json ... ``` with tool/name and arguments
  if toolCalls.len == 0:
    let jsonMarker = "```json"
    var jidx = cleanText.find(jsonMarker)
    if jidx >= 0:
      let afterJ = jidx + jsonMarker.len
      let closeIdx = cleanText.find(endMarker, afterJ)
      if closeIdx > jidx:
        let jsonStr = cleanText[afterJ ..< closeIdx].strip()
        try:
          let j = parseJson(jsonStr)
          if (j.hasKey("name") or j.hasKey("tool")) and j.hasKey("arguments"):
            var tc = ToolCall()
            tc.id = "call_" & $now().toTime().toUnix()
            tc.functionName = if j.hasKey("name"): j["name"].getStr() else: j["tool"].getStr()
            if j["arguments"].kind == JString:
              tc.arguments = j["arguments"].getStr()
            else:
              tc.arguments = $j["arguments"]
            if tc.functionName.len > 0:
              toolCalls.add(tc)
              cleanText = (cleanText[0 ..< jidx] & cleanText[(closeIdx + endMarker.len) .. ^1]).strip()
        except CatchableError:
          discard

  return (cleanText, toolCalls)
