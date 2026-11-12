import std/[os, json, times, strutils]
import types

type
  SessionInfo* = object
    id*: string
    created*: string
    updated*: string
    preview*: string
    messageCount*: int

proc getSessionsDir*(hermesHome: string): string =
  result = hermesHome / "sessions"
  if not dirExists(result):
    createDir(result)

proc saveSession*(hermesHome: string, sessionId: string, messages: seq[Message]) =
  let sDir = getSessionsDir(hermesHome)
  let sFile = sDir / (sessionId & ".json")
  
  var arr = newJArray()
  for m in messages:
    arr.add(m.toJson())

  var root = newJObject()
  root["id"] = %sessionId
  root["updated"] = %($now())
  root["messages"] = arr
  
  try:
    writeFile(sFile, pretty(root, 2))
    writeFile(sDir / "last_session.txt", sessionId)
  except CatchableError:
    discard

proc loadSession*(hermesHome: string, targetId: string): tuple[found: bool, id: string, messages: seq[Message]] =
  let sDir = getSessionsDir(hermesHome)
  var realId = targetId.strip()
  if realId == "last" or realId.len == 0:
    let lastFile = sDir / "last_session.txt"
    if fileExists(lastFile):
      try:
        realId = readFile(lastFile).strip()
      except CatchableError:
        discard
        
  let sFile = sDir / (realId & ".json")
  if not fileExists(sFile):
    return (false, "", @[])

  try:
    let parsed = parseJson(readFile(sFile))
    var msgs: seq[Message] = @[]
    if parsed.hasKey("messages") and parsed["messages"].kind == JArray:
      for mNode in parsed["messages"]:
        var m: Message
        m.role = mNode.getOrDefault("role").getStr("user")
        if mNode.hasKey("content") and mNode["content"].kind == JString:
          m.content = mNode["content"].getStr()
        if mNode.hasKey("tool_call_id"):
          m.toolCallId = mNode["tool_call_id"].getStr()
        if mNode.hasKey("name"):
          m.name = mNode["name"].getStr()
        msgs.add(m)
    return (true, realId, msgs)
  except CatchableError:
    return (false, "", @[])

proc listSessions*(hermesHome: string): seq[SessionInfo] =
  result = @[]
  let sDir = getSessionsDir(hermesHome)
  if not dirExists(sDir): return

  for kind, path in walkDir(sDir):
    if kind == pcFile and path.endsWith(".json"):
      try:
        let parsed = parseJson(readFile(path))
        var info: SessionInfo
        info.id = parsed.getOrDefault("id").getStr(extractFilename(path).replace(".json", ""))
        info.updated = parsed.getOrDefault("updated").getStr("")
        if parsed.hasKey("messages") and parsed["messages"].kind == JArray:
          info.messageCount = parsed["messages"].len
          for m in parsed["messages"]:
            if m.getOrDefault("role").getStr() == "user":
              let c = m.getOrDefault("content").getStr()
              info.preview = if c.len > 50: c[0 ..< 50] & "..." else: c
              break
        result.add(info)
      except CatchableError:
        discard
