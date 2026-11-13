import std/[httpclient, json, strutils, os]

const
  DefaultNvidiaBaseUrl* = "https://integrate.api.nvidia.com/v1"
  DefaultNvidiaModel* = "meta/llama-3.2-90b-vision-instruct"
  DefaultNvidiaFallbackModel* = "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning"

  CuratedNvidiaModels* = @[
    "meta/llama-3.2-90b-vision-instruct",
    "nvidia/nemotron-3-nano-omni-30b-a3b-reasoning",
    "meta/llama-3.1-70b-instruct",
    "meta/llama-3.1-405b-instruct",
    "deepseek-ai/deepseek-v4.1-flash",
    "google/gemma-3-12b-it",
    "google/gemma-4-31b-it",
    "mistralai/mixtral-8x22b-instruct-v0.1",
    "qwen/qwen2.5-72b-instruct",
    "stepfun-ai/step-5-preview",
    "ibm/granite-3.0-8b-instruct"
  ]

proc parseEnvKeyValue(filePath: string, keyName: string): string =
  if not fileExists(filePath): return ""
  try:
    for line in lines(filePath):
      let t = line.strip()
      if t.len == 0 or t.startsWith("#"): continue
      let eqPos = t.find('=')
      if eqPos > 0:
        let k = t[0 ..< eqPos].strip()
        if k == keyName:
          var val = t[(eqPos + 1) .. ^1].strip()
          if (val.startsWith("\"") and val.endsWith("\"")) or (val.startsWith("'") and val.endsWith("'")):
            if val.len >= 2: val = val[1 .. ^2]
          return val
  except CatchableError:
    discard
  return ""

proc getNvidiaApiKey*(): string =
  let envKey = getEnv("NVIDIA_API_KEY")
  if envKey.len > 0: return envKey

  let cands = [
    ".env",
    "C:/Users/kbell/Downloads/nvidia build/.env",
    getHomeDir() / "Downloads" / "nvidia build" / ".env",
    getHomeDir() / ".hermes" / ".env",
    "/home/ubuntu/agent-go/.env",
    "/home/ubuntu/.hermes/.env",
    "agent-go/.env"
  ]
  for c in cands:
    let val = parseEnvKeyValue(c, "NVIDIA_API_KEY")
    if val.len > 0: return val
  return ""

proc getNvidiaBaseUrl*(): string =
  let envUrl = getEnv("NVIDIA_BASE_URL")
  if envUrl.len > 0: return envUrl

  let cands = [
    ".env",
    "C:/Users/kbell/Downloads/nvidia build/.env",
    getHomeDir() / "Downloads" / "nvidia build" / ".env",
    getHomeDir() / ".hermes" / ".env",
    "/home/ubuntu/agent-go/.env",
    "/home/ubuntu/.hermes/.env"
  ]
  for c in cands:
    let val = parseEnvKeyValue(c, "NVIDIA_BASE_URL")
    if val.len > 0: return val
  return DefaultNvidiaBaseUrl

proc isNvidiaModel*(modelName: string): bool =
  if modelName.len == 0: return false
  let prefixes = [
    "nvidia/", "meta/llama-3", "stepfun-ai/", "deepseek-ai/", "bigcode/",
    "ai21labs/", "ibm/granite", "adept/", "aisingapore/"
  ]
  for p in prefixes:
    if modelName.startsWith(p):
      return true
  return false

proc listNvidiaModels*(): seq[string] =
  let apiKey = getNvidiaApiKey()
  if apiKey.len > 0:
    try:
      var client = newHttpClient(timeout = 6_000)
      client.headers = newHttpHeaders({
        "Authorization": "Bearer " & apiKey,
        "Accept": "application/json"
      })
      let url = getNvidiaBaseUrl().strip().replace(r"/chat/completions", "") & "/models"
      let resp = client.getContent(url)
      let parsed = parseJson(resp)
      if parsed.hasKey("data") and parsed["data"].kind == JArray:
        var res: seq[string] = @[]
        for item in parsed["data"]:
          let id = item.getOrDefault("id").getStr("")
          if id.len > 0:
            res.add(id)
        if res.len > 0:
          return res
    except CatchableError:
      discard
  return CuratedNvidiaModels

proc queryNvidia*(model: string, prompt: string): string =
  let apiKey = getNvidiaApiKey()
  if apiKey.len == 0:
    return "Error: NVIDIA_API_KEY not configured. Define it in .env or environment."

  let targetModel = if model.strip().len == 0: DefaultNvidiaModel else: model.strip()
  var endpoint = getNvidiaBaseUrl().strip()
  if endpoint.endsWith("/"): endpoint = endpoint[0 .. ^2]
  if not endpoint.endsWith("/chat/completions"): endpoint &= "/chat/completions"

  let payload = %*{
    "model": targetModel,
    "messages": [
      {"role": "user", "content": prompt}
    ],
    "temperature": 0.6,
    "max_tokens": 4096
  }

  var client = newHttpClient(timeout = 90_000)
  client.headers = newHttpHeaders({
    "Authorization": "Bearer " & apiKey,
    "Content-Type": "application/json",
    "User-Agent": "Hermes-Agent-Nim/1.0"
  })

  var retries = 2
  while retries >= 0:
    try:
      let resp = client.request(endpoint, httpMethod = HttpPost, body = $payload)
      if resp.code == Http200:
        let root = parseJson(resp.body)
        if root.hasKey("choices") and root["choices"].len > 0:
          let choice = root["choices"][0]
          if choice.hasKey("message"):
            let msgObj = choice["message"]
            var content = msgObj.getOrDefault("content").getStr("")
            if content.len == 0 and msgObj.hasKey("reasoning_content"):
              content = msgObj["reasoning_content"].getStr("")
            return content.strip()
        return resp.body
      elif resp.code == Http429 or resp.code.int >= 500:
        if retries == 0:
          return "NVIDIA API Error (" & $resp.code & "): " & resp.body
        sleep(1500)
        dec(retries)
      else:
        return "NVIDIA API Error (" & $resp.code & "): " & resp.body
    except CatchableError as e:
      if retries == 0:
        return "NVIDIA Connection Error: " & e.msg
      sleep(1500)
      dec(retries)

  return "NVIDIA API query failed after retries."
