import std/strutils
import utils

const DangerPatterns = [
  "rm -rf", "rm -r", "rmdir /s", "del /f", "del /q", "format ", "mkfs",
  "git reset --hard", "git clean -fd", "git clean -f", "drop table", "drop database"
]

proc isPotentiallyDangerous*(cmd: string): bool =
  let lower = cmd.toLowerAscii()
  for p in DangerPatterns:
    if lower.contains(p):
      return true
  return false

proc confirmExecution*(cmd: string, yoloMode: bool): bool =
  if yoloMode:
    return true

  if not isPotentiallyDangerous(cmd):
    return true

  echo colorize("\n⚠️  [SECURITY WARNING] Potentially destructive command detected:", AnsiYellow & AnsiBold)
  echo "    " & colorize(cmd, AnsiRed)
  stdout.write(colorize("    Authorize execution? [y/N]: ", AnsiBold))
  stdout.flushFile()

  var resp = ""
  try:
    if not stdin.readLine(resp):
      return false
  except IOError:
    return false

  let t = resp.strip().toLowerAscii()
  return t == "y" or t == "yes" or t == "s" or t == "sim"
