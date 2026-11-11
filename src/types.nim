import std/json

type
  ToolCall* = object
    id*: string
    functionName*: string
    arguments*: string

  Message* = object
    role*: string            ## "system", "user", "assistant", "tool"
    content*: string
    toolCallId*: string      ## For role "tool"
    name*: string            ## Function name for role "tool"
    toolCalls*: seq[ToolCall]## For assistant requesting tool execution

  ToolParam* = object
    name*: string
    paramType*: string       ## "string", "integer", "boolean", "number", "array", "object"
    description*: string
    required*: bool

  ToolDefinition* = object
    name*: string
    description*: string
    parameters*: seq[ToolParam]
    isPython*: bool
    handler*: proc(args: JsonNode): string {.closure.}

  AgentConfig* = object
    apiKey*: string
    baseUrl*: string
    model*: string
    temperature*: float
    maxTokens*: int
    maxTurns*: int
    systemPrompt*: string
    hermesHome*: string
    pythonPath*: string
    maxMemoryMB*: float

  LLMResponse* = object
    content*: string
    toolCalls*: seq[ToolCall]
    promptTokens*: int
    completionTokens*: int
    totalTokens*: int
    finishReason*: string

proc toJson*(msg: Message): JsonNode =
  result = newJObject()
  result["role"] = %msg.role
  
  if msg.content.len > 0 or msg.toolCalls.len == 0:
    result["content"] = %msg.content
  else:
    result["content"] = newJNull()

  if msg.role == "tool":
    result["tool_call_id"] = %msg.toolCallId
    if msg.name.len > 0:
      result["name"] = %msg.name
      
  if msg.toolCalls.len > 0:
    var callsNode = newJArray()
    for tc in msg.toolCalls:
      var callObj = newJObject()
      callObj["id"] = %tc.id
      callObj["type"] = %"function"
      var fnObj = newJObject()
      fnObj["name"] = %tc.functionName
      fnObj["arguments"] = %tc.arguments
      callObj["function"] = fnObj
      callsNode.add(callObj)
    result["tool_calls"] = callsNode

proc toolToJsonSchema*(td: ToolDefinition): JsonNode =
  result = newJObject()
  result["type"] = %"function"
  
  var fnObj = newJObject()
  fnObj["name"] = %td.name
  fnObj["description"] = %td.description
  
  var paramsObj = newJObject()
  paramsObj["type"] = %"object"
  
  var propsObj = newJObject()
  var reqArr = newJArray()
  
  for p in td.parameters:
    var pNode = newJObject()
    pNode["type"] = %p.paramType
    pNode["description"] = %p.description
    propsObj[p.name] = pNode
    if p.required:
      reqArr.add(%p.name)
      
  paramsObj["properties"] = propsObj
  paramsObj["required"] = reqArr
  fnObj["parameters"] = paramsObj
  
  result["function"] = fnObj
