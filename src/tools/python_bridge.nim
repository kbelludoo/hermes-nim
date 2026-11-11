import std/[os, osproc, json, strutils, streams]

proc runPythonCode*(pythonExe: string, workerScript: string, code: string, args: JsonNode = nil): string =
  if pythonExe.len == 0:
    return "Error: Python executable not found."
    
  var scriptPath = workerScript
  if not fileExists(scriptPath):
    # Try resolving relative to application directory
    let appDir = getAppDir()
    scriptPath = appDir / ".." / "python_worker" / "tool_runner.py"
    if not fileExists(scriptPath):
      scriptPath = appDir / "python_worker" / "tool_runner.py"
  
  if not fileExists(scriptPath):
    return "Error: Python worker script not found at " & scriptPath

  var payload = newJObject()
  payload["code"] = %code
  if args != nil:
    payload["args"] = args
  else:
    payload["args"] = newJObject()

  let inputStr = $payload

  try:
    var p = startProcess(
      command = pythonExe,
      args = [scriptPath, "--stdin"],
      options = {poUsePath, poStdErrToStdOut}
    )
    
    let inStream = p.inputStream
    inStream.write(inputStr)
    inStream.flush()
    inStream.close()
    
    var outputStr = ""
    let outStream = p.outputStream
    var line = ""
    while outStream.readLine(line):
      outputStr.add(line & "\n")
      
    discard p.waitForExit()
    p.close()
    
    let trimmed = outputStr.strip()
    if trimmed.len == 0:
      return "Python executed with empty output."
      
    try:
      let parsed = parseJson(trimmed)
      if parsed.hasKey("status"):
        if parsed["status"].getStr() == "success":
          return parsed.getOrDefault("output").getStr()
        else:
          return "Python Error: " & parsed.getOrDefault("error").getStr()
      return trimmed
    except:
      return trimmed
  except CatchableError as e:
    return "Failed to run Python subprocess: " & e.msg

proc runPythonScript*(pythonExe: string, workerScript: string, scriptFile: string, args: JsonNode = nil): string =
  if not fileExists(scriptFile):
    return "Error: Python script file not found: " & scriptFile
  try:
    let code = readFile(scriptFile)
    return runPythonCode(pythonExe, workerScript, code, args)
  except CatchableError as e:
    return "Error reading script file: " & e.msg
