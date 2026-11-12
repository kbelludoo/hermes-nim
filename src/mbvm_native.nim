import std/[tables, strutils, json, os, times]
import types

type
  NodeKind* = enum
    nkUserRequest,
    nkToolCall,
    nkFileArtifact,
    nkTopicDecision

  GraphNode* = ref object
    id*: int
    kind*: NodeKind
    name*: string
    signature*: string
    fields*: seq[string]
    outgoing*: seq[int]
    incoming*: seq[int]

  ConversationGraph* = ref object
    nodes*: seq[GraphNode]
    nameIndex*: Table[string, int]
    aliasIndex*: Table[string, int]

proc newConversationGraph*(): ConversationGraph =
  new(result)
  result.nodes = @[]
  result.nameIndex = initTable[string, int]()
  result.aliasIndex = initTable[string, int]()

proc addNode*(g: ConversationGraph, kind: NodeKind, name: string, signature: string = "",
              fields: seq[string] = @[], aliases: seq[string] = @[]): int =
  let lowerName = name.toLowerAscii()
  if g.nameIndex.hasKey(lowerName):
    let existingId = g.nameIndex[lowerName]
    let node = g.nodes[existingId]
    if signature.len > 0: node.signature = signature
    for f in fields:
      if f notin node.fields: node.fields.add(f)
    return existingId

  let id = g.nodes.len
  var node = GraphNode(
    id: id,
    kind: kind,
    name: name,
    signature: signature,
    fields: fields,
    outgoing: @[],
    incoming: @[]
  )
  g.nodes.add(node)
  g.nameIndex[lowerName] = id

  for a in aliases:
    let clean = a.strip().toLowerAscii()
    if clean.len > 0 and not g.aliasIndex.hasKey(clean):
      g.aliasIndex[clean] = id

  return id

proc addEdge*(g: ConversationGraph, fromId: int, toId: int) =
  if fromId < 0 or fromId >= g.nodes.len: return
  if toId < 0 or toId >= g.nodes.len: return
  if fromId == toId: return

  if toId notin g.nodes[fromId].outgoing:
    g.nodes[fromId].outgoing.add(toId)
  if fromId notin g.nodes[toId].incoming:
    g.nodes[toId].incoming.add(fromId)

proc findNode*(g: ConversationGraph, query: string): int =
  let q = query.strip().toLowerAscii()
  if g.nameIndex.hasKey(q):
    return g.nameIndex[q]
  if g.aliasIndex.hasKey(q):
    return g.aliasIndex[q]

  # Substring search
  for name, id in g.nameIndex:
    if name.contains(q) or q.contains(name):
      return id

  for alias, id in g.aliasIndex:
    if alias.contains(q) or q.contains(alias):
      return id

  return -1

proc extractSlice*(g: ConversationGraph, query: string, maxDepth: int = 2): seq[GraphNode] =
  result = @[]
  if g.nodes.len == 0: return

  let startId = g.findNode(query)
  if startId < 0:
    return

  var visited = initTable[int, bool]()
  var queue: seq[int] = @[startId]
  visited[startId] = true

  var depth = 0
  while queue.len > 0 and depth < maxDepth:
    inc(depth)
    let levelSize = queue.len
    for i in 0 ..< levelSize:
      let curr = queue[0]
      queue.delete(0)

      if curr >= 0 and curr < g.nodes.len:
        result.add(g.nodes[curr])
        let n = g.nodes[curr]

        # Traverse outgoing edges
        for outId in n.outgoing:
          if not visited.hasKey(outId):
            visited[outId] = true
            queue.add(outId)

        # Traverse incoming edges
        for inId in n.incoming:
          if not visited.hasKey(inId):
            visited[inId] = true
            queue.add(inId)

proc projectSlice*(nodes: seq[GraphNode]): string =
  if nodes.len == 0:
    return ""

  var sb = "@MBVM:slice:native_nim%mode=dynamic_subgraph\n\n"
  for n in nodes:
    let kindBadge = case n.kind
      of nkUserRequest: "👤 Request"
      of nkToolCall: "⚡ Tool"
      of nkFileArtifact: "📄 File"
      of nkTopicDecision: "🧠 Knowledge"

    sb &= kindBadge & " [" & n.name & "]"
    if n.signature.len > 0:
      sb &= ": " & n.signature
    sb &= "\n"

    for f in n.fields:
      sb &= "    • " & f & "\n"

  return sb.strip()

proc ingestTurn*(g: ConversationGraph, userPrompt: string, toolCalls: seq[ToolCall],
                 toolResults: seq[string], assistantAnswer: string, stepIndex: int): int =
  let reqName = "Request_" & $stepIndex
  var aliases: seq[string] = @[]
  for word in userPrompt.splitWhitespace():
    let w = word.strip(chars = {',', '.', '!', '?', ':', ';', '"', '\''}).toLowerAscii()
    if w.len >= 4: aliases.add(w)

  let reqId = g.addNode(nkUserRequest, reqName, userPrompt, aliases = aliases)

  # Ingest tool executions
  for i, tc in toolCalls:
    let toolName = "Tool_" & $stepIndex & "_" & tc.functionName & "_" & $i
    var fields: seq[string] = @["args: " & tc.arguments]
    if i < toolResults.len:
      let resPreview = if toolResults[i].len > 250: toolResults[i][0 ..< 250] & "..." else: toolResults[i]
      fields.add("result: " & resPreview)

    let toolId = g.addNode(nkToolCall, toolName, tc.functionName, fields = fields, aliases = @[tc.functionName])
    g.addEdge(reqId, toolId)

    # Detect file targets in arguments
    if tc.arguments.contains("\"path\"") or tc.arguments.contains("\"command\""):
      try:
        let parsed = parseJson(tc.arguments)
        if parsed.hasKey("path"):
          let p = parsed["path"].getStr()
          let fId = g.addNode(nkFileArtifact, "File:" & extractFilename(p), p, aliases = @[extractFilename(p)])
          g.addEdge(toolId, fId)
      except CatchableError:
        discard

  # Ingest Assistant answer/decision if meaningful
  if assistantAnswer.len > 0:
    let ansPreview = if assistantAnswer.len > 200: assistantAnswer[0 ..< 200] & "..." else: assistantAnswer
    let decName = "Decision_" & $stepIndex
    let decId = g.addNode(nkTopicDecision, decName, ansPreview)
    g.addEdge(reqId, decId)

  return reqId

proc saveToJson*(g: ConversationGraph, filePath: string) =
  var root = newJObject()
  var nodesArr = newJArray()
  for n in g.nodes:
    var no = newJObject()
    no["id"] = %n.id
    no["kind"] = %($n.kind)
    no["name"] = %n.name
    no["signature"] = %n.signature
    var fa = newJArray()
    for f in n.fields: fa.add(%f)
    no["fields"] = fa
    var oa = newJArray()
    for o in n.outgoing: oa.add(%o)
    no["outgoing"] = oa
    var ia = newJArray()
    for i in n.incoming: ia.add(%i)
    no["incoming"] = ia
    nodesArr.add(no)
  root["nodes"] = nodesArr

  let parent = parentDir(filePath)
  if parent.len > 0 and not dirExists(parent):
    createDir(parent)
  writeFile(filePath, $root)

proc loadFromJson*(filePath: string): ConversationGraph =
  result = newConversationGraph()
  if not fileExists(filePath): return

  try:
    let root = parseJson(readFile(filePath))
    if root.hasKey("nodes") and root["nodes"].kind == JArray:
      for no in root["nodes"]:
        var n = GraphNode(
          id: no["id"].getInt(),
          name: no.getOrDefault("name").getStr(""),
          signature: no.getOrDefault("signature").getStr(""),
          fields: @[],
          outgoing: @[],
          incoming: @[]
        )
        let kStr = no.getOrDefault("kind").getStr("nkTopicDecision")
        case kStr
        of "nkUserRequest": n.kind = nkUserRequest
        of "nkToolCall": n.kind = nkToolCall
        of "nkFileArtifact": n.kind = nkFileArtifact
        else: n.kind = nkTopicDecision

        if no.hasKey("fields"):
          for f in no["fields"]: n.fields.add(f.getStr())
        if no.hasKey("outgoing"):
          for o in no["outgoing"]: n.outgoing.add(o.getInt())
        if no.hasKey("incoming"):
          for i in no["incoming"]: n.incoming.add(i.getInt())

        result.nodes.add(n)
        result.nameIndex[n.name.toLowerAscii()] = n.id
  except CatchableError:
    discard
