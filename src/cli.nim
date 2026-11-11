import std/[strutils, tables]
import types, utils, memory, agent

proc printBanner*(config: AgentConfig) =
  let memMB = getResidentMemoryMB()
  echo colorize("╔════════════════════════════════════════════════════════════════╗", AnsiCyan)
  echo colorize("║       HERMES AGENT — Ultra-Lean Native Edition (Nim)           ║", AnsiBold & AnsiCyan)
  echo colorize("║  Zero-Bloat Core | Resident RAM: " & formatFloat(memMB, ffDecimal, 2) & " MB (Ceiling: < 50MB)      ║", AnsiGreen)
  echo colorize("╚════════════════════════════════════════════════════════════════╝", AnsiCyan)
  echo colorize("Model:    ", AnsiBold) & config.model
  echo colorize("Endpoint: ", AnsiBold) & config.baseUrl
  echo colorize("Type /help for slash commands, or enter your message to begin.\n", AnsiDim)

proc printHelp() =
  echo colorize("Available Commands:", AnsiBold)
  echo "  " & colorize("/help", AnsiYellow) & "          - Show this help menu"
  echo "  " & colorize("/clear", AnsiYellow) & "         - Reset conversation context"
  echo "  " & colorize("/model <name>", AnsiYellow) & "  - Change active LLM model"
  echo "  " & colorize("/memory", AnsiYellow) & "        - View persistent long-term memories"
  echo "  " & colorize("/tools", AnsiYellow) & "         - List registered tools (Native & Python)"
  echo "  " & colorize("/stats", AnsiYellow) & "         - Display resident memory (RSS MB) & token stats"
  echo "  " & colorize("/exit, /quit", AnsiYellow) & "   - Exit the application\n"

proc printStats*(ag: AIAgent) =
  let memMB = getResidentMemoryMB()
  echo colorize("--- Hermes Performance Stats ---", AnsiBold)
  echo "  Resident Memory (RAM): " & colorize(formatFloat(memMB, ffDecimal, 2) & " MB", if memMB > 45.0: AnsiRed elif memMB > 30.0: AnsiYellow else: AnsiGreen)
  echo "  Memory Ceiling Limit:  50.00 MB"
  echo "  Context Messages:      " & $ag.messages.len
  echo "  Prompt Tokens:         " & $ag.totalPromptTokens
  echo "  Completion Tokens:     " & $ag.totalCompletionTokens
  echo "  Total Tokens:          " & $(ag.totalPromptTokens + ag.totalCompletionTokens)
  echo "--------------------------------\n"

proc printTools*(ag: AIAgent) =
  echo colorize("Registered Tools:", AnsiBold)
  for name, def in ag.registry.tools:
    let badge = if def.isPython: colorize("[Python Bridge <12MB]", AnsiYellow) else: colorize("[Native C/Nim ~0MB]", AnsiGreen)
    echo "  " & colorize(name, AnsiBold & AnsiCyan) & " " & badge
    echo "    " & def.description
  echo ""

proc startRepl*(ag: AIAgent) =
  printBanner(ag.config)

  while true:
    var line: string
    let prompt = colorize("hermes> ", AnsiBold & AnsiCyan)
    try:
      # Read input line
      stdout.write(prompt)
      stdout.flushFile()
      if not stdin.readLine(line):
        break
    except IOError:
      break

    let trimmed = line.strip()
    if trimmed.len == 0:
      continue

    # Handle Slash Commands
    if trimmed.startsWith("/"):
      let parts = trimmed.splitWhitespace()
      let cmd = parts[0].toLowerAscii()
      
      case cmd
      of "/exit", "/quit", "/q":
        echo colorize("Shutting down Hermes. Goodbye!", AnsiYellow)
        break
      of "/help":
        printHelp()
      of "/clear":
        let sysMsg = ag.messages[0]
        ag.messages = @[sysMsg]
        echo colorize("Conversation context cleared.\n", AnsiGreen)
      of "/stats":
        printStats(ag)
      of "/memory":
        echo colorize("Persistent Memories:\n", AnsiBold) & ag.memoryStore.recall("") & "\n"
      of "/tools":
        printTools(ag)
      of "/model":
        if parts.len >= 2:
          ag.config.model = parts[1]
          ag.client.config.model = parts[1]
          echo colorize("Model switched to: ", AnsiGreen) & parts[1] & "\n"
        else:
          echo colorize("Usage: /model <model-name>\n", AnsiYellow)
      else:
        echo colorize("Unknown command: " & cmd & ". Type /help for assistance.\n", AnsiRed)
      continue

    # Execute Agent Conversation Turn
    echo ""
    discard ag.runConversation(trimmed, proc(text: string) =
      stdout.write(text)
      stdout.flushFile()
    )
    echo "\n"
