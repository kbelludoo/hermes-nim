import std/[os, strutils, tables, json]
import types
import tools/opencode

proc getHermesHome*(): string =
  let envHome = getEnv("HERMES_HOME")
  if envHome.len > 0:
    return envHome
  when defined(windows):
    let localAppData = getEnv("LOCALAPPDATA")
    if localAppData.len > 0:
      return localAppData / "hermes"
    return getHomeDir() / ".hermes"
  else:
    return getHomeDir() / ".hermes"

proc parseEnvFile*(filePath: string): Table[string, string] =
  result = initTable[string, string]()
  if not fileExists(filePath):
    return
  for line in lines(filePath):
    let trimmed = line.strip()
    if trimmed.len == 0 or trimmed.startsWith("#"):
      continue
    let eqPos = trimmed.find('=')
    if eqPos > 0:
      let key = trimmed[0 ..< eqPos].strip()
      var val = trimmed[(eqPos + 1) .. ^1].strip()
      if (val.startsWith("\"") and val.endsWith("\"")) or
         (val.startsWith("'") and val.endsWith("'")):
        if val.len >= 2:
          val = val[1 .. ^2]
      result[key] = val

proc isValidPythonExe(p: string): bool =
  if p.len == 0: return false
  if not fileExists(p): return false
  try:
    if getFileSize(p) < 5000:
      return false # Skip WindowsApps 0-byte alias
  except:
    discard
  return true

proc findPythonExecutable*(): string =
  # Priority: 1. HERMES_PYTHON env var
  let envPy = getEnv("HERMES_PYTHON")
  if isValidPythonExe(envPy):
    return envPy

  when defined(windows):
    # Check standard Python installation directories on Windows
    let localAppData = getEnv("LOCALAPPDATA")
    if localAppData.len > 0:
      let pyRoot = localAppData / "Programs" / "Python"
      if dirExists(pyRoot):
        for kind, path in walkDir(pyRoot):
          if kind == pcDir:
            let cand = path / "python.exe"
            if isValidPythonExe(cand):
              return cand

    let progFiles = getEnv("ProgramFiles")
    if progFiles.len > 0:
      let pyRoot = progFiles / "Python"
      if dirExists(pyRoot):
        for kind, path in walkDir(pyRoot):
          if kind == pcDir:
            let cand = path / "python.exe"
            if isValidPythonExe(cand):
              return cand

  # Check PATH executables
  for exeName in ["python3", "python"]:
    let cand = findExe(exeName)
    if isValidPythonExe(cand):
      return cand

  return "python"

proc loadSoulPrompt*(hermesHome: string): string =
  # Look for SOUL.md in current directory, then HERMES_HOME
  if fileExists("SOUL.md"):
    try:
      return readFile("SOUL.md").strip()
    except:
      discard
  let homeSoul = hermesHome / "SOUL.md"
  if fileExists(homeSoul):
    try:
      return readFile(homeSoul).strip()
    except:
      discard
  return "You are Hermes Agent, a hyper-efficient, direct personal AI assistant. " &
         "Be direct: match the length of your reply to the weight of the ask. " &
         "No filler, no restating the request. Use tools to verify and execute tasks."

proc loadTelegramCredentials*(): tuple[token, chatId: string] =
  var token = getEnv("TELEGRAM_TOKEN")
  var chat = getEnv("TELEGRAM_CHAT_ID")
  if token.len > 0:
    return (token, chat)

  let candidates = [
    ".secrets.json",
    "/home/ubuntu/.secrets.json",
    getHermesHome() / ".secrets.json",
    getHomeDir() / ".secrets.json",
    "C:/Users/kbell/Downloads/bot-template-go/.secrets.json"
  ]
  for path in candidates:
    if fileExists(path):
      try:
        let j = parseJson(readFile(path))
        let t = j{"telegramToken"}.getStr(j{"telegram_token"}.getStr(""))
        let c = j{"telegramChatId"}.getStr(j{"telegram_chat_id"}.getStr(""))
        if t.len > 0:
          return (t, c)
      except CatchableError:
        discard
  return ("", "")

proc loadConfig*(customModel: string = "", customApiKey: string = "", customBaseUrl: string = "", useOpenCode: bool = false): AgentConfig =
  let hermesHome = getHermesHome()
  var envTable = initTable[string, string]()

  # 1. Load from HERMES_HOME/.env
  let homeEnv = hermesHome / ".env"
  if fileExists(homeEnv):
    let t = parseEnvFile(homeEnv)
    for k, v in t: envTable[k] = v

  # 2. Load from local .env or candidate env files
  let envCandidates = [
    ".env",
    "agent-go/.env",
    "/home/ubuntu/agent-go/.env",
    "/home/ubuntu/.env"
  ]
  for c in envCandidates:
    if fileExists(c):
      let t = parseEnvFile(c)
      for k, v in t:
        if not envTable.hasKey(k): envTable[k] = v

  # 3. Environment variables take highest precedence
  for key in ["OPENAI_API_KEY", "OPENAI_BASE_URL", "OPENROUTER_API_KEY",
              "GEMINI_API_KEY", "GOOGLE_API_KEY", "DEEPSEEK_API_KEY",
              "GROQ_API_KEY", "MISTRAL_API_KEY", "OLLAMA_BASE_URL", "OPENCODE_MODEL", "HERMES_MODEL", "LLM_MODEL"]:
    let v = getEnv(key)
    if v.len > 0:
      envTable[key] = v

  var apiKey = customApiKey
  var baseUrl = customBaseUrl
  var model = customModel

  # Determine Provider and BaseURL
  let hasOpenCode = isOpenCodeInstalled()
  if (useOpenCode or baseUrl == "opencode") or (hasOpenCode and (isOpenCodeModel(model) or (envTable.hasKey("OPENCODE_MODEL") and not envTable.hasKey("MISTRAL_API_KEY") and not envTable.hasKey("OPENAI_API_KEY") and not envTable.hasKey("OPENROUTER_API_KEY")))):
    baseUrl = "opencode"
    apiKey = "opencode-local"
    if model.len == 0 or not isOpenCodeModel(model):
      model = envTable.getOrDefault("OPENCODE_MODEL", "google/gemini-2.5-flash")
  elif apiKey.len == 0:
    if envTable.hasKey("OPENAI_API_KEY"):
      apiKey = envTable["OPENAI_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = envTable.getOrDefault("OPENAI_BASE_URL", "https://api.openai.com/v1")
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "gpt-4o-mini"))
    elif envTable.hasKey("OPENROUTER_API_KEY"):
      apiKey = envTable["OPENROUTER_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = "https://openrouter.ai/api/v1"
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "anthropic/claude-3.5-sonnet"))
    elif envTable.hasKey("DEEPSEEK_API_KEY"):
      apiKey = envTable["DEEPSEEK_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = "https://api.deepseek.com/v1"
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "deepseek-chat"))
    elif envTable.hasKey("GEMINI_API_KEY") or envTable.hasKey("GOOGLE_API_KEY"):
      apiKey = if envTable.hasKey("GEMINI_API_KEY"): envTable["GEMINI_API_KEY"] else: envTable["GOOGLE_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = "https://generativelanguage.googleapis.com/v1beta/openai"
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "gemini-2.0-flash"))
    elif envTable.hasKey("GROQ_API_KEY"):
      apiKey = envTable["GROQ_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = "https://api.groq.com/openai/v1"
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "llama-3.3-70b-versatile"))
    elif envTable.hasKey("MISTRAL_API_KEY"):
      apiKey = envTable["MISTRAL_API_KEY"]
      if baseUrl.len == 0:
        baseUrl = envTable.getOrDefault("MISTRAL_BASE_URL", "https://api.mistral.ai/v1")
      if model.len == 0:
        model = envTable.getOrDefault("MISTRAL_MODEL", envTable.getOrDefault("HERMES_MODEL", "codestral-latest"))
    elif envTable.hasKey("OLLAMA_BASE_URL"):
      apiKey = "ollama"
      if baseUrl.len == 0:
        baseUrl = envTable["OLLAMA_BASE_URL"]
      if model.len == 0:
        model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "llama3.2"))
    else:
      # Fallback defaults
      apiKey = envTable.getOrDefault("OPENAI_API_KEY", "")
      baseUrl = envTable.getOrDefault("OPENAI_BASE_URL", "https://api.openai.com/v1")
      model = envTable.getOrDefault("HERMES_MODEL", envTable.getOrDefault("LLM_MODEL", "gpt-4o-mini"))

  if baseUrl.len == 0:
    baseUrl = "https://api.openai.com/v1"
  if model.len == 0:
    model = "gpt-4o-mini"

  result = AgentConfig(
    apiKey: apiKey,
    baseUrl: baseUrl,
    model: model,
    temperature: 0.7,
    maxTokens: 4096,
    maxTurns: 30,
    systemPrompt: loadSoulPrompt(hermesHome),
    hermesHome: hermesHome,
    pythonPath: findPythonExecutable(),
    maxMemoryMB: 50.0, # Strict 50MB ceiling requirement
    yoloMode: false
  )
