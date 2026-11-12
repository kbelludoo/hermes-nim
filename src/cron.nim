import std/[times, strutils, tables]

type
  CronJob* = object
    name*: string
    intervalSec*: int
    lastRun*: Time
    prompt*: string

  CronScheduler* = ref object
    jobs*: Table[string, CronJob]

proc newCronScheduler*(): CronScheduler =
  new(result)
  result.jobs = initTable[string, CronJob]()

proc addJob*(cs: CronScheduler, name: string, intervalMinutes: int, prompt: string): string =
  let sec = max(1, intervalMinutes) * 60
  cs.jobs[name] = CronJob(
    name: name,
    intervalSec: sec,
    lastRun: getTime(),
    prompt: prompt
  )
  return "Cron job '" & name & "' scheduled to run every " & $intervalMinutes & " minute(s)."

proc listJobs*(cs: CronScheduler): string =
  if cs.jobs.len == 0:
    return "No recurring cron jobs scheduled."
  var lines: seq[string] = @[]
  for name, j in cs.jobs:
    let mins = j.intervalSec div 60
    lines.add("• " & name & " (every " & $mins & " min): \"" & j.prompt & "\"")
  return "Active Cron Jobs (" & $cs.jobs.len & "):\n" & lines.join("\n")

proc removeJob*(cs: CronScheduler, name: string): string =
  if cs.jobs.hasKey(name):
    cs.jobs.del(name)
    return "Cron job '" & name & "' removed."
  return "Error: Cron job '" & name & "' not found."

proc checkDueJobs*(cs: CronScheduler): seq[CronJob] =
  result = @[]
  let nowTime = getTime()
  for name, j in cs.jobs.mpairs:
    let diffSec = (nowTime - j.lastRun).inSeconds
    if diffSec >= j.intervalSec:
      j.lastRun = nowTime
      result.add(j)
