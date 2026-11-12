import std/[parseopt, strutils, os]
import types, utils, config, agent, cli, sessions, catalog, tools/python_bridge, tools/opencode, gateway/telegram

proc printUsage() =
  echo """
Hermes Agent (Ultra-Lean Native Edition in Nim + MBVM-DB + AI-Rust-Browser)
Guaranteed Memory Footprint: < 50 MB RAM (Typical resident: ~6-12 MB)

Usage:
  hermes_nim [options]

Options:
  -p, --prompt <text>         Run a one-shot query and exit
  -m, --model <name>          Override model name (e.g. gpt-4o-mini, google/gemini-2.5-flash)
  -k, --key <api_key>         Override LLM API Key
  -u, --url <endpoint>        Override OpenAI-compatible base URL
  --opencode                  Use OpenCode headless AI models (Gemini, DeepSeek, etc. without API keys)
  --opencode-model <model>    Select specific OpenCode model (e.g. google/gemini-2.5-flash)
  --list-opencode-models      List all AI models available through local OpenCode
  --list-community-skills     List all skills in the decentralized community catalog
  --search-skills <query>     Search for community skills by keyword
  --install-skill <skill_id>  Install a community skill to ~/.hermes/skills/<skill_id>
  --uninstall-skill <id>      Uninstall an installed community skill
  -t, --telegram              Run as interactive Telegram Bot Gateway daemon
  -r, --resume [id|last]      Resume a previous saved session
  --list-sessions             List all saved conversation sessions
  --yolo                      Auto-approve all terminal commands without confirmation
  --slice <db> <symbol>       Extract an MBVM-DB code slice directly and exit
  --eval-py <code>            Run Python code via the lean micro-worker and exit
  --stats                     Show current process memory footprint
  -h, --help                  Show this help message

Without options, launches the interactive chat REPL.
"""

proc main() =
  var prompt = ""
  var modelOverride = ""
  var keyOverride = ""
  var urlOverride = ""
  var evalPy = ""
  var resumeId = ""
  var showStatsOnly = false
  var runTelegram = false
  var listSessionsOnly = false
  var listOpenCodeOnly = false
  var listCommunitySkillsOnly = false
  var searchSkillsQuery = ""
  var installSkillId = ""
  var uninstallSkillId = ""
  var useOpenCodeFlag = false
  var yoloFlag = false
  var sliceDb = ""
  var sliceSymbol = ""

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      let k = p.key.toLowerAscii()
      var v = p.val
      if v.len == 0 and k notin ["stats", "t", "telegram", "yolo", "list-sessions", "opencode", "list-opencode-models", "list-community-skills", "h", "help"]:
        p.next()
        if p.kind == cmdArgument:
          v = p.key

      case k
      of "p", "prompt":
        prompt = v
      of "m", "model":
        modelOverride = v
      of "k", "key":
        keyOverride = v
      of "u", "url":
        urlOverride = v
      of "opencode":
        useOpenCodeFlag = true
      of "opencode-model":
        useOpenCodeFlag = true
        modelOverride = v
      of "list-opencode-models":
        listOpenCodeOnly = true
      of "list-community-skills":
        listCommunitySkillsOnly = true
      of "search-skills":
        searchSkillsQuery = v
      of "install-skill":
        installSkillId = v
      of "uninstall-skill":
        uninstallSkillId = v
      of "t", "telegram":
        runTelegram = true
      of "r", "resume":
        resumeId = if v.len > 0: v else: "last"
      of "list-sessions":
        listSessionsOnly = true
      of "yolo":
        yoloFlag = true
      of "eval-py":
        evalPy = v
      of "stats":
        showStatsOnly = true
      of "h", "help":
        printUsage()
        quit(0)
      else:
        echo "Unknown option: --", p.key
        quit(1)
    of cmdArgument:
      if prompt.len == 0:
        prompt = p.key
      else:
        prompt &= " " & p.key

  if showStatsOnly:
    let memMB = getResidentMemoryMB()
    echo "Current Process Working Set (RAM): ", formatFloat(memMB, ffDecimal, 2), " MB"
    quit(0)

  if listOpenCodeOnly:
    echo colorize("Available OpenCode Headless AI Models:", AnsiCyan)
    let models = listOpenCodeModels()
    for m in models:
      echo "  • " & m
    quit(0)

  var cfg = loadConfig(modelOverride, keyOverride, urlOverride, useOpenCode = useOpenCodeFlag)
  if yoloFlag:
    cfg.yoloMode = true

  if listCommunitySkillsOnly:
    let cat = fetchCommunitySkills()
    echo colorize("Hermes Community Skills Catalog (" & $cat.len & " skills available):", AnsiBold & AnsiCyan)
    for s in cat:
      echo "  • " & colorize(s.id, AnsiBold) & " (" & s.category & ") by @" & s.author
      echo "    " & s.description
      echo "    Install with: hermes_nim --install-skill " & s.id
    quit(0)

  if searchSkillsQuery.len > 0:
    let cat = fetchCommunitySkills()
    let matches = searchCommunitySkills(cat, searchSkillsQuery)
    if matches.len == 0:
      echo colorize("No community skills found matching '" & searchSkillsQuery & "'.", AnsiYellow)
    else:
      echo colorize("Matching Community Skills (" & $matches.len & "):", AnsiBold & AnsiCyan)
      for s in matches:
        echo "  • " & colorize(s.id, AnsiBold) & " - " & s.name & " (" & s.category & ")"
        echo "    " & s.description
        echo "    Install with: hermes_nim --install-skill " & s.id
    quit(0)

  if installSkillId.len > 0:
    echo colorize("Installing community skill '" & installSkillId & "'...", AnsiCyan)
    let (ok, msg) = installCommunitySkill(installSkillId, cfg.hermesHome)
    if ok:
      echo colorize("✓ " & msg, AnsiGreen)
      quit(0)
    else:
      echo colorize("✗ " & msg, AnsiRed)
      quit(1)

  if uninstallSkillId.len > 0:
    let (ok, msg) = uninstallCommunitySkill(uninstallSkillId, cfg.hermesHome)
    if ok:
      echo colorize("✓ " & msg, AnsiGreen)
      quit(0)
    else:
      echo colorize("✗ " & msg, AnsiRed)
      quit(1)

  if listSessionsOnly:
    let sl = listSessions(cfg.hermesHome)
    echo "Saved Sessions in " & cfg.hermesHome & "/sessions (" & $sl.len & "):"
    for s in sl:
      echo "  • [" & s.id & "] " & s.updated & " (" & $s.messageCount & " msgs) - " & s.preview
    quit(0)

  if evalPy.len > 0:
    let appDir = getAppDir()
    var wScript = appDir / ".." / "python_worker" / "tool_runner.py"
    if not fileExists(wScript):
      wScript = appDir / "python_worker" / "tool_runner.py"
    if not fileExists(wScript):
      wScript = getCurrentDir() / "python_worker" / "tool_runner.py"
    let outPy = runPythonCode(cfg.pythonPath, wScript, evalPy)
    echo outPy
    quit(0)

  # Check if resuming session
  var existingSessionId = ""
  var existingMessages: seq[Message] = @[]
  if resumeId.len > 0:
    let (found, id, msgs) = loadSession(cfg.hermesHome, resumeId)
    if found:
      existingSessionId = id
      existingMessages = msgs
      echo colorize("✓ Resumed session: ", AnsiGreen) & id & " (" & $msgs.len & " messages)"
    else:
      echo colorize("Warning: Session '" & resumeId & "' not found. Starting new session.", AnsiYellow)

  let ag = newAIAgent(cfg, existingSessionId, existingMessages)

  # Check if Telegram Gateway mode requested
  if runTelegram:
    let (tgToken, tgChatId) = loadTelegramCredentials()
    if tgToken.len == 0:
      echo colorize("Error: TELEGRAM_TOKEN not found in environment or .secrets.json.", AnsiRed)
      echo "Define it in your .env file or .secrets.json: TELEGRAM_TOKEN=123456:ABC-DEF..."
      quit(1)
    let bot = newTelegramBot(tgToken, tgChatId)
    startTelegramGateway(bot, ag)
    quit(0)

  if prompt.len > 0:
    let res = ag.runConversation(prompt, proc(chunk: string) =
      stdout.write(chunk)
      stdout.flushFile()
    )
    echo ""
    quit(0)
  else:
    startRepl(ag)

when isMainModule:
  main()
