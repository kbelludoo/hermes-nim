import std/[strutils, tables]
import types, utils, memory, agent, skills, cron, sessions, catalog, tools/mbvm_db, tools/opencode

proc printBanner*(config: AgentConfig) =
  let memMB = getResidentMemoryMB()
  echo colorize("╔════════════════════════════════════════════════════════════════╗", AnsiCyan)
  echo colorize("║       HERMES AGENT — Ultra-Lean Native Edition (Nim)           ║", AnsiBold & AnsiCyan)
  echo colorize("║  Zero-Bloat Core | Resident RAM: " & formatFloat(memMB, ffDecimal, 2) & " MB (Ceiling: < 50MB)      ║", AnsiGreen)
  echo colorize("║  Engine: MBVM-DB Slicing (-93% tokens) & AI-Rust-Browser       ║", AnsiDim)
  echo colorize("╚════════════════════════════════════════════════════════════════╝", AnsiCyan)
  echo colorize("Model:    ", AnsiBold) & config.model
  echo colorize("Endpoint: ", AnsiBold) & config.baseUrl
  echo colorize("Security: ", AnsiBold) & (if config.yoloMode: colorize("YOLO Mode (Auto-Approve)", AnsiRed) else: colorize("Safe Mode (Confirming destructive actions)", AnsiGreen))
  echo colorize("Type /help for slash commands, or enter your message to begin.\n", AnsiDim)

proc printHelp() =
  echo colorize("Available Commands:", AnsiBold)
  echo "  " & colorize("/help", AnsiYellow) & "          - Show this help menu"
  echo "  " & colorize("/clear", AnsiYellow) & "         - Reset conversation context"
  echo "  " & colorize("/model <name>", AnsiYellow) & "  - Change active LLM model"
  echo "  " & colorize("/opencode [m]", AnsiYellow) & "  - Switch to OpenCode AI model or list models"
  echo "  " & colorize("/memory", AnsiYellow) & "        - View persistent long-term memories"
  echo "  " & colorize("/skills", AnsiYellow) & "        - View loaded skills (or /skills [catalog|search|install])"
  echo "  " & colorize("/sessions", AnsiYellow) & "      - List recent saved conversation sessions"
  echo "  " & colorize("/cron", AnsiYellow) & "          - View scheduled background cron tasks"
  echo "  " & colorize("/mbvm", AnsiYellow) & "          - Inspect MBVM-DB status and codebase stats"
  echo "  " & colorize("/yolo", AnsiYellow) & "          - Toggle safety approval prompt on/off"
  echo "  " & colorize("/tools", AnsiYellow) & "         - List registered tools (Native, Browser & MBVM)"
  echo "  " & colorize("/stats", AnsiYellow) & "         - Display resident memory (RSS MB) & token stats"
  echo "  " & colorize("/exit, /quit", AnsiYellow) & "   - Exit the application\n"

proc printStats*(ag: AIAgent) =
  let memMB = getResidentMemoryMB()
  echo colorize("--- Hermes Performance Stats ---", AnsiBold)
  echo "  Resident Memory (RAM): " & colorize(formatFloat(memMB, ffDecimal, 2) & " MB", if memMB > 45.0: AnsiRed elif memMB > 30.0: AnsiYellow else: AnsiGreen)
  echo "  Memory Ceiling Limit:  50.00 MB"
  echo "  Session ID:            " & ag.sessionId
  echo "  Context Messages:      " & $ag.messages.len
  echo "  Prompt Tokens:         " & $ag.totalPromptTokens
  echo "  Completion Tokens:     " & $ag.totalCompletionTokens
  echo "  Total Tokens:          " & $(ag.totalPromptTokens + ag.totalCompletionTokens)
  echo "--------------------------------\n"

proc printTools*(ag: AIAgent) =
  echo colorize("Registered Tools (" & $ag.registry.tools.len & "):", AnsiBold)
  for name, def in ag.registry.tools:
    let badge = if def.name.startsWith("mbvm"):
      colorize("[MBVM-DB Graph]", AnsiMagenta)
    elif def.name.startsWith("browser"):
      colorize("[Rust Browser <10MB]", AnsiCyan)
    elif def.isPython:
      colorize("[Python Bridge <12MB]", AnsiYellow)
    else:
      colorize("[Native C/Nim ~0MB]", AnsiGreen)
    echo "  " & colorize(name, AnsiBold) & " " & badge
    echo "    " & def.description
  echo ""

proc startRepl*(ag: AIAgent) =
  printBanner(ag.config)

  while true:
    var line: string
    let prompt = colorize("hermes> ", AnsiBold & AnsiCyan)
    try:
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
      of "/skills":
        if parts.len == 1:
          echo colorize(ag.skillRegistry.listSkills() & "\n", AnsiCyan)
        else:
          let subcmd = parts[1].toLowerAscii()
          case subcmd
          of "catalog", "list", "marketplace":
            let cat = fetchCommunitySkills()
            echo colorize("Hermes Community Skills Catalog (" & $cat.len & " skills available):", AnsiBold & AnsiCyan)
            for s in cat:
              echo "  • " & colorize(s.id, AnsiBold) & " (" & s.category & ") by @" & s.author
              echo "    " & s.description
              echo "    Install with: /skills install " & s.id
            echo ""
          of "search":
            if parts.len >= 3:
              let q = parts[2 .. ^1].join(" ")
              let cat = fetchCommunitySkills()
              let matches = searchCommunitySkills(cat, q)
              if matches.len == 0:
                echo colorize("No skills found matching '" & q & "'.\n", AnsiYellow)
              else:
                echo colorize("Found " & $matches.len & " matching skill(s):", AnsiBold & AnsiCyan)
                for s in matches:
                  echo "  • " & colorize(s.id, AnsiBold) & " - " & s.name & " (" & s.category & ")"
                  echo "    " & s.description
                echo ""
            else:
              echo colorize("Usage: /skills search <query>\n", AnsiYellow)
          of "install":
            if parts.len >= 3:
              let sid = parts[2]
              echo colorize("Installing community skill '" & sid & "'...", AnsiCyan)
              let (ok, msg) = installCommunitySkill(sid, ag.config.hermesHome)
              if ok:
                ag.skillRegistry.reload(ag.config.hermesHome)
                echo colorize("✓ " & msg & "\n", AnsiGreen)
              else:
                echo colorize("✗ " & msg & "\n", AnsiRed)
            else:
              echo colorize("Usage: /skills install <skill_id>\n", AnsiYellow)
          of "uninstall", "remove":
            if parts.len >= 3:
              let sid = parts[2]
              let (ok, msg) = uninstallCommunitySkill(sid, ag.config.hermesHome)
              if ok:
                ag.skillRegistry.reload(ag.config.hermesHome)
                echo colorize("✓ " & msg & "\n", AnsiGreen)
              else:
                echo colorize("✗ " & msg & "\n", AnsiRed)
            else:
              echo colorize("Usage: /skills uninstall <skill_id>\n", AnsiYellow)
          else:
            echo colorize("Unknown skills command. Available: /skills, /skills catalog, /skills search <q>, /skills install <id>\n", AnsiYellow)
      of "/cron":
        echo colorize(ag.cronScheduler.listJobs() & "\n", AnsiYellow)
      of "/mbvm":
        echo colorize(mbvmInspectTool() & "\n", AnsiMagenta)
      of "/sessions":
        let sl = listSessions(ag.config.hermesHome)
        if sl.len == 0:
          echo "No saved sessions found in " & ag.config.hermesHome & "/sessions"
        else:
          echo colorize("Saved Sessions (" & $sl.len & "):", AnsiBold)
          for s in sl:
            echo "• [" & s.id & "] " & s.updated & " (" & $s.messageCount & " msgs) - " & s.preview
          echo ""
      of "/yolo":
        ag.config.yoloMode = not ag.config.yoloMode
        ag.registry.yoloMode = ag.config.yoloMode
        if ag.config.yoloMode:
          echo colorize("⚠️  YOLO Mode ENABLED: Dangerous commands will execute without prompt.\n", AnsiRed)
        else:
          echo colorize("🛡️  Safe Mode ENABLED: Destructive commands will request user confirmation.\n", AnsiGreen)
      of "/tools":
        printTools(ag)
      of "/model":
        if parts.len >= 2:
          ag.config.model = parts[1]
          ag.client.config.model = parts[1]
          echo colorize("Model switched to: ", AnsiGreen) & parts[1] & "\n"
        else:
          echo colorize("Usage: /model <model-name>\n", AnsiYellow)
      of "/opencode":
        if parts.len >= 2:
          let target = parts[1]
          ag.config.baseUrl = "opencode"
          ag.config.model = target
          ag.client.config.baseUrl = "opencode"
          ag.client.config.model = target
          echo colorize("✓ Switched to OpenCode AI Model: ", AnsiGreen) & target & "\n"
        else:
          echo colorize("Available OpenCode Headless AI Models:", AnsiCyan)
          let ms = listOpenCodeModels()
          for m in ms:
            echo "  • " & m
          echo colorize("\nUsage to switch: /opencode <model_name>\n", AnsiDim)
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
