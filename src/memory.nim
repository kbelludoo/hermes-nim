import std/[os, json, strutils, times]

type
  MemoryItem* = object
    key*: string
    content*: string
    timestamp*: string

  MemoryStore* = ref object
    filePath*: string
    items*: seq[MemoryItem]

proc newMemoryStore*(hermesHome: string): MemoryStore =
  new(result)
  result.filePath = hermesHome / "memory.json"
  result.items = @[]
  
  if fileExists(result.filePath):
    try:
      let raw = readFile(result.filePath)
      let parsed = parseJson(raw)
      if parsed.kind == JArray:
        for node in parsed:
          if node.hasKey("key") and node.hasKey("content"):
            result.items.add(MemoryItem(
              key: node["key"].getStr(),
              content: node["content"].getStr(),
              timestamp: node.getOrDefault("timestamp").getStr($now())
            ))
    except:
      discard

proc save(store: MemoryStore) =
  try:
    let dir = parentDir(store.filePath)
    if not dirExists(dir):
      createDir(dir)
    var arr = newJArray()
    for item in store.items:
      var obj = newJObject()
      obj["key"] = %item.key
      obj["content"] = %item.content
      obj["timestamp"] = %item.timestamp
      arr.add(obj)
    writeFile(store.filePath, pretty(arr, 2))
  except:
    discard

proc remember*(store: MemoryStore, key: string, content: string): string =
  let ts = $now()
  var updated = false
  for item in store.items.mitems:
    if item.key == key:
      item.content = content
      item.timestamp = ts
      updated = true
      break
  if not updated:
    store.items.add(MemoryItem(key: key, content: content, timestamp: ts))
  store.save()
  if updated:
    return "Memory '" & key & "' updated successfully."
  else:
    return "Memory '" & key & "' saved successfully."

proc recall*(store: MemoryStore, query: string = ""): string =
  if store.items.len == 0:
    return "No memories stored yet."
  
  var matches: seq[string] = @[]
  let qLower = query.toLowerAscii()
  for item in store.items:
    if query.len == 0 or
       item.key.toLowerAscii().contains(qLower) or
       item.content.toLowerAscii().contains(qLower):
      matches.add("- [" & item.key & "] " & item.content)
      
  if matches.len == 0:
    return "No memories matched query: " & query
  return matches.join("\n")

proc forget*(store: MemoryStore, key: string): string =
  var idx = -1
  for i, item in store.items:
    if item.key == key:
      idx = i
      break
  if idx >= 0:
    store.items.delete(idx)
    store.save()
    return "Memory '" & key & "' deleted."
  return "Memory '" & key & "' not found."
