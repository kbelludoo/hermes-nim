import std/[os, osproc, strutils]
import ../utils

proc findMbvmDbExe*(): string =
  let envExe = getEnv("MBVM_DB_EXE")
  if envExe.len > 0 and fileExists(envExe):
    return envExe

  let knownPaths = [
    "C:\\Users\\kbell\\Downloads\\mbvm-db\\mbvm-db.exe",
    getHomeDir() / "Downloads" / "mbvm-db" / "mbvm-db.exe",
    getCurrentDir() / "mbvm-db" / "mbvm-db.exe"
  ]
  for kp in knownPaths:
    if fileExists(kp):
      return kp

  let fromPath = findExe("mbvm-db")
  if fromPath.len > 0: return fromPath
  return ""

proc mbvmSliceTool*(targetPath: string, symbol: string, depth: int = 1): string =
  let exe = findMbvmDbExe()
  if exe.len == 0:
    return "Error: mbvm-db executable not found. Configure MBVM_DB_EXE or ensure C:\\Users\\kbell\\Downloads\\mbvm-db\\mbvm-db.exe exists."

  var resolvedTarget = targetPath
  if not fileExists(resolvedTarget) and not dirExists(resolvedTarget):
    let localCand = getCurrentDir() / targetPath
    if fileExists(localCand) or dirExists(localCand):
      resolvedTarget = localCand
    else:
      let mbvmCand = "C:\\Users\\kbell\\Downloads\\mbvm-db" / targetPath
      if fileExists(mbvmCand):
        resolvedTarget = mbvmCand

  try:
    let cmd = quoteShell(exe) & " slice " & quoteShell(resolvedTarget) & " " & quoteShell(symbol) & " " & $depth
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      return "mbvm-db error (code " & $exitCode & "):\n" & output
    return truncateOutput(output.strip(), 10000)
  except CatchableError as e:
    return "Failed to run mbvm-db slice: " & e.msg

proc mbvmSliceBudgetTool*(targetPath: string, symbol: string, budgetTokens: int = 500): string =
  let exe = findMbvmDbExe()
  if exe.len == 0:
    return "Error: mbvm-db executable not found."

  try:
    let cmd = quoteShell(exe) & " slice-budget " & quoteShell(targetPath) & " " & quoteShell(symbol) & " " & $budgetTokens
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      return "mbvm-db error (code " & $exitCode & "):\n" & output
    return truncateOutput(output.strip(), 10000)
  except CatchableError as e:
    return "Failed to run mbvm-db slice-budget: " & e.msg

proc mbvmInspectTool*(targetPath: string = ""): string =
  let exe = findMbvmDbExe()
  if exe.len == 0:
    return "Error: mbvm-db executable not found."

  var target = targetPath
  if target.len == 0:
    target = "codebase.mbvmdb"
    if not fileExists(target):
      target = "C:\\Users\\kbell\\Downloads\\mbvm-db\\codebase.mbvmdb"

  try:
    let cmd = quoteShell(exe) & " inspect " & quoteShell(target)
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      return "mbvm-db error:\n" & output
    return output.strip()
  except CatchableError as e:
    return "Failed to inspect mbvm-db: " & e.msg

proc mbvmBuildTool*(dirPath: string = ".", outputFile: string = "codebase.mbvmdb"): string =
  let exe = findMbvmDbExe()
  if exe.len == 0:
    return "Error: mbvm-db executable not found."

  try:
    let cmd = quoteShell(exe) & " build " & quoteShell(dirPath) & " " & quoteShell(outputFile)
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      return "mbvm-db build error:\n" & output
    return "Successfully indexed codebase into " & outputFile & ":\n" & output.strip()
  except CatchableError as e:
    return "Failed to build mbvm-db: " & e.msg

proc mbvmIngestConversationTool*(transcriptPath: string, outputFile: string = "conversation.mbvmdb"): string =
  let exe = findMbvmDbExe()
  if exe.len == 0:
    return "Error: mbvm-db executable not found."

  try:
    let cmd = quoteShell(exe) & " ingest-conversation " & quoteShell(transcriptPath) & " " & quoteShell(outputFile)
    let (output, exitCode) = execCmdEx(cmd)
    if exitCode != 0:
      return "mbvm-db ingest-conversation error:\n" & output
    return output.strip()
  except CatchableError as e:
    return "Failed to ingest conversation into mbvm-db: " & e.msg
