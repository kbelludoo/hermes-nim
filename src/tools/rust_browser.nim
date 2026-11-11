import std/[os, osproc, json, strutils, streams]
import ../utils

type
  RustBrowserClient* = ref object
    exePath*: string
    process*: Process
    nextId*: int

var gBrowserClient: RustBrowserClient = nil

proc findRustBrowserExe*(): string =
  let envExe = getEnv("HERMES_BROWSER_EXE")
  if envExe.len > 0 and fileExists(envExe):
    return envExe

  let knownPaths = [
    "C:\\Users\\kbell\\Downloads\\ai-rust-browser\\target\\release\\ai-go-browser-cli.exe",
    getHomeDir() / "Downloads" / "ai-rust-browser" / "target" / "release" / "ai-go-browser-cli.exe",
    getCurrentDir() / "ai-rust-browser" / "target" / "release" / "ai-go-browser-cli.exe"
  ]
  for kp in knownPaths:
    if fileExists(kp):
      return kp

  let fromPath = findExe("ai-go-browser-cli")
  if fromPath.len > 0: return fromPath
  let fromPath2 = findExe("ai-rust-browser")
  if fromPath2.len > 0: return fromPath2
  return ""

proc getOrCreateBrowserClient*(exePath: string): RustBrowserClient =
  if gBrowserClient != nil and gBrowserClient.process != nil and gBrowserClient.process.running:
    return gBrowserClient

  if exePath.len == 0 or not fileExists(exePath):
    return nil

  try:
    new(gBrowserClient)
    gBrowserClient.exePath = exePath
    gBrowserClient.nextId = 1
    gBrowserClient.process = startProcess(
      command = exePath,
      args = ["mcp"],
      options = {poUsePath}
    )
    return gBrowserClient
  except CatchableError:
    return nil

proc closeBrowserClient*() =
  if gBrowserClient != nil and gBrowserClient.process != nil:
    try:
      if gBrowserClient.process.running:
        gBrowserClient.process.terminate()
      gBrowserClient.process.close()
    except CatchableError:
      discard
    gBrowserClient = nil

proc callRustBrowserMcp*(exePath: string, toolName: string, args: JsonNode): string =
  let client = getOrCreateBrowserClient(exePath)
  if client == nil:
    return "Error: Could not start or locate AI Rust Browser at " & exePath

  inc(client.nextId)
  let curId = client.nextId

  var req = newJObject()
  req["jsonrpc"] = %"2.0"
  req["id"] = %curId
  req["method"] = %"tools/call"
  
  var params = newJObject()
  params["name"] = %toolName
  params["arguments"] = if args != nil: args else: newJObject()
  req["params"] = params

  let inputLine = $req & "\n"

  try:
    let inStream = client.process.inputStream
    inStream.write(inputLine)
    inStream.flush()

    let outStream = client.process.outputStream
    var line = ""
    while outStream.readLine(line):
      let trimmed = line.strip()
      if trimmed.len == 0:
        continue
      
      try:
        let root = parseJson(trimmed)
        if root.hasKey("error"):
          let err = root["error"]
          return "Browser MCP Error: " & err.getOrDefault("message").getStr($err)
        if root.hasKey("result"):
          let res = root["result"]
          if res.hasKey("content") and res["content"].kind == JArray:
            var textParts: seq[string] = @[]
            for c in res["content"]:
              if c.hasKey("text"):
                textParts.add(c["text"].getStr())
            if textParts.len > 0:
              return truncateOutput(textParts.join("\n"), 8000)
          return truncateOutput($res, 8000)
      except CatchableError as e:
        return "Error parsing browser response: " & e.msg & "\nRaw: " & trimmed

    return "AI Rust Browser closed connection unexpectedly."
  except CatchableError as e:
    closeBrowserClient()
    return "Failed to communicate with AI Rust Browser: " & e.msg
