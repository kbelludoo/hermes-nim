import std/dynlib
when not defined(windows):
  import std/[os, strutils]

when defined(windows):
  type
    PROCESS_MEMORY_COUNTERS = object
      cb: uint32
      PageFaultCount: uint32
      PeakWorkingSetSize: uint
      WorkingSetSize: uint
      QuotaPeakPagedPoolUsage: uint
      QuotaPagedPoolUsage: uint
      QuotaPeakNonPagedPoolUsage: uint
      QuotaNonPagedPoolUsage: uint
      PagefileUsage: uint
      PeakPagefileUsage: uint

    GetCurrentProcessProc = proc(): int {.stdcall.}
    GetProcessMemoryInfoProc = proc(hProcess: int, ppsmst: pointer, cb: uint32): bool {.stdcall.}

  var
    k32Lib: LibHandle = nil
    fnGetCurrentProcess: GetCurrentProcessProc = nil
    fnGetProcessMemoryInfo: GetProcessMemoryInfoProc = nil
    memInitDone = false

  proc initMemInfo() =
    if memInitDone: return
    memInitDone = true
    k32Lib = loadLib("kernel32.dll")
    if k32Lib != nil:
      fnGetCurrentProcess = cast[GetCurrentProcessProc](symAddr(k32Lib, "GetCurrentProcess"))
      fnGetProcessMemoryInfo = cast[GetProcessMemoryInfoProc](symAddr(k32Lib, "K32GetProcessMemoryInfo"))
    if fnGetProcessMemoryInfo == nil:
      let psapi = loadLib("psapi.dll")
      if psapi != nil:
        fnGetProcessMemoryInfo = cast[GetProcessMemoryInfoProc](symAddr(psapi, "GetProcessMemoryInfo"))

  proc getResidentMemoryMB*(): float =
    initMemInfo()
    if fnGetCurrentProcess != nil and fnGetProcessMemoryInfo != nil:
      var pmc: PROCESS_MEMORY_COUNTERS
      pmc.cb = uint32(sizeof(pmc))
      let hProc = fnGetCurrentProcess()
      if fnGetProcessMemoryInfo(hProc, addr pmc, pmc.cb):
        return float(pmc.WorkingSetSize) / (1024.0 * 1024.0)
    return 0.0
else:
  proc getResidentMemoryMB*(): float =
    try:
      let statm = readFile("/proc/self/statm")
      let parts = statm.strip().split()
      if parts.len >= 2:
        let residentPages = parseBiggestInt(parts[1])
        return float(residentPages * 4096) / (1024.0 * 1024.0)
    except:
      discard
    return 0.0

# ANSI Color Codes
const
  AnsiReset* = "\e[0m"
  AnsiBold* = "\e[1m"
  AnsiDim* = "\e[2m"
  AnsiRed* = "\e[31m"
  AnsiGreen* = "\e[32m"
  AnsiYellow* = "\e[33m"
  AnsiBlue* = "\e[34m"
  AnsiMagenta* = "\e[35m"
  AnsiCyan* = "\e[36m"
  AnsiWhite* = "\e[37m"

proc colorize*(text: string, color: string): string =
  color & text & AnsiReset

proc truncateOutput*(text: string, maxLen: int = 4000): string =
  if text.len <= maxLen:
    return text
  let half = maxLen div 2
  let head = text[0 ..< half]
  let tail = text[(text.len - half) ..< text.len]
  let omitted = text.len - (half * 2)
  head & "\n\n... [omitted " & $omitted & " characters for memory efficiency] ...\n\n" & tail
