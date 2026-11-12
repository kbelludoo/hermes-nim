import std/[json, strutils, times]
import ../src/types

proc extractToolCallFromText*(text: string): (string, seq[ToolCall]) =
  var toolCalls: seq[ToolCall] = @[]
  var cleanText = text

  # Pattern 1: ```tool_call ... ```
  let startMarker = "```tool_call"
  let endMarker = "```"
  var idx = cleanText.find(startMarker)
  if idx >= 0:
    let afterStart = idx + startMarker.len
    let closeIdx = cleanText.find(endMarker, afterStart)
    if closeIdx > idx:
      let jsonStr = cleanText[afterStart ..< closeIdx].strip()
      try:
        let j = parseJson(jsonStr)
        var tc = ToolCall()
        tc.id = "call_" & $now().toTime().toUnix()
        if j.hasKey("name"):
          tc.functionName = j["name"].getStr()
        elif j.hasKey("tool"):
          tc.functionName = j["tool"].getStr()
        if j.hasKey("arguments"):
          if j["arguments"].kind == JString:
            tc.arguments = j["arguments"].getStr()
          else:
            tc.arguments = $j["arguments"]
        if tc.functionName.len > 0:
          toolCalls.add(tc)
          cleanText = (cleanText[0 ..< idx] & cleanText[(closeIdx + endMarker.len) .. ^1]).strip()
      except CatchableError:
        discard

  # Pattern 2: ```json ... ``` with tool/name and arguments
  if toolCalls.len == 0:
    let jsonMarker = "```json"
    var jidx = cleanText.find(jsonMarker)
    if jidx >= 0:
      let afterJ = jidx + jsonMarker.len
      let closeIdx = cleanText.find(endMarker, afterJ)
      if closeIdx > jidx:
        let jsonStr = cleanText[afterJ ..< closeIdx].strip()
        try:
          let j = parseJson(jsonStr)
          if (j.hasKey("name") or j.hasKey("tool")) and j.hasKey("arguments"):
            var tc = ToolCall()
            tc.id = "call_" & $now().toTime().toUnix()
            tc.functionName = if j.hasKey("name"): j["name"].getStr() else: j["tool"].getStr()
            if j["arguments"].kind == JString:
              tc.arguments = j["arguments"].getStr()
            else:
              tc.arguments = $j["arguments"]
            if tc.functionName.len > 0:
              toolCalls.add(tc)
              cleanText = (cleanText[0 ..< jidx] & cleanText[(closeIdx + endMarker.len) .. ^1]).strip()
        except CatchableError:
          discard

  return (cleanText, toolCalls)

# Test 1: tool_call block
let sample1 = """Here is what I will do:
```tool_call
{"name": "read_file", "arguments": {"path": "README.md"}}
```
Please wait.
"""
let (t1, c1) = extractToolCallFromText(sample1)
assert c1.len == 1, "Expected 1 tool call"
assert c1[0].functionName == "read_file"
assert c1[0].arguments == "{\"path\":\"README.md\"}"
echo "Test 1 Passed: ", c1[0].functionName, " -> ", c1[0].arguments

# Test 2: json block with tool key
let sample2 = """I will execute the terminal:
```json
{"tool": "terminal", "arguments": {"command": "dir"}}
```
"""
let (t2, c2) = extractToolCallFromText(sample2)
assert c2.len == 1, "Expected 1 tool call"
assert c2[0].functionName == "terminal"
echo "Test 2 Passed: ", c2[0].functionName, " -> ", c2[0].arguments

# Test 3: Normal text without tool call
let sample3 = "Hello, how can I help you today?"
let (t3, c3) = extractToolCallFromText(sample3)
assert c3.len == 0
assert t3 == sample3
echo "Test 3 Passed: Normal text preserved"
