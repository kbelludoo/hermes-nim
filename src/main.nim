import std/[parseopt, strutils, os]
import types, utils, config, agent, cli, tools/python_bridge, gateway/telegram

proc printUsage() =
  echo """
Hermes Agent (Ultra-Lean Native Edition in Nim)
Guaranteed Memory Footprint: < 50 MB RAM (Typical resident: ~6-12 MB)

Usage:
  hermes_nim [options]

Options:
  -p, --prompt <text>     Run a one-shot query and exit
  -m, --model <name>      Override model name (e.g. gpt-4o-mini, claude-3-5-sonnet)
  -k, --key <api_key>     Override LLM API Key
  -u, --url <endpoint>    Override OpenAI-compatible base URL
  -t, --telegram          Run as interactive Telegram Bot Gateway daemon
  --eval-py <code>        Run Python code via the lean micro-worker and exit
  --stats                 Show current process memory footprint
  -h, --help              Show this help message

Without options, launches the interactive chat REPL.
"""

proc main() =
  var prompt = ""
  var modelOverride = ""
  var keyOverride = ""
  var urlOverride = ""
  var evalPy = ""
  var showStatsOnly = false
  var runTelegram = false

  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      let k = p.key.toLowerAscii()
      var v = p.val
      if v.len == 0 and k notin ["stats", "t", "telegram", "h", "help"]:
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
      of "t", "telegram":
        runTelegram = true
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

  let cfg = loadConfig(modelOverride, keyOverride, urlOverride)

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

  let ag = newAIAgent(cfg)

  # Check if Telegram Gateway mode requested
  if runTelegram:
    let tgToken = getEnv("TELEGRAM_TOKEN")
    let tgChatId = getEnv("TELEGRAM_CHAT_ID")
    if tgToken.len == 0:
      echo colorize("Error: TELEGRAM_TOKEN environment variable is not set.", AnsiRed)
      echo "Define it in your .env file or environment: TELEGRAM_TOKEN=123456:ABC-DEF..."
      quit(1)
    let bot = newTelegramBot(tgToken, tgChatId)
    startTelegramGateway(bot, ag)
    quit(0)

  if prompt.len > 0:
    # One-shot execution mode
    let res = ag.runConversation(prompt, proc(chunk: string) =
      stdout.write(chunk)
      stdout.flushFile()
    )
    echo ""
    quit(0)
  else:
    # Interactive REPL mode
    startRepl(ag)

when isMainModule:
  main()
