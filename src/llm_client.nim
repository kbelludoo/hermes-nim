import std/[httpclient, json, strutils, os]
import types

type
  LLMClient* = ref object
    config*: AgentConfig
    httpClient*: HttpClient

proc newLLMClient*(config: AgentConfig): LLMClient =
  new(result)
  result.config = config
  result.httpClient = newHttpClient(timeout = 120_000)

proc createChatCompletion*(client: LLMClient, messages: seq[Message], tools: seq[JsonNode] = @[]): LLMResponse =
  var endpoint = client.config.baseUrl.strip()
  if endpoint.endsWith("/"):
    endpoint = endpoint[0 .. ^2]
  if not endpoint.endsWith("/chat/completions"):
    endpoint &= "/chat/completions"

  var reqBody = newJObject()
  reqBody["model"] = %client.config.model
  reqBody["temperature"] = %client.config.temperature
  reqBody["max_tokens"] = %client.config.maxTokens

  var msgsArr = newJArray()
  for m in messages:
    msgsArr.add(m.toJson())
  reqBody["messages"] = msgsArr

  if tools.len > 0:
    var toolsArr = newJArray()
    for t in tools:
      toolsArr.add(t)
    reqBody["tools"] = toolsArr

  let payload = $reqBody

  var headers = newHttpHeaders({
    "Content-Type": "application/json",
    "User-Agent": "Hermes-Agent-Nim/1.0"
  })
  if client.config.apiKey.len > 0 and client.config.apiKey != "ollama":
    headers["Authorization"] = "Bearer " & client.config.apiKey

  # Retry loop with exponential backoff for rate limits or transient errors
  var retries = 3
  var delayMs = 1000
  var rawResponse = ""
  var statusCode = Http200

  while retries >= 0:
    try:
      client.httpClient.headers = headers
      let resp = client.httpClient.request(endpoint, httpMethod = HttpPost, body = payload)
      statusCode = resp.code
      rawResponse = resp.body

      if resp.code == Http200:
        break
      elif resp.code == Http429 or resp.code.int >= 500:
        if retries == 0:
          raise newException(IOError, "API returned status " & $resp.code & ": " & rawResponse)
        sleep(delayMs)
        delayMs *= 2
        dec(retries)
      else:
        raise newException(IOError, "API error (" & $resp.code & "): " & rawResponse)
    except CatchableError as e:
      if retries == 0:
        raise e
      sleep(delayMs)
      delayMs *= 2
      dec(retries)

  # Parse response JSON
  let root = parseJson(rawResponse)
  
  if root.hasKey("error"):
    let errNode = root["error"]
    let msg = if errNode.hasKey("message"): errNode["message"].getStr() else: $errNode
    raise newException(IOError, "LLM API Error: " & msg)

  var res = LLMResponse()
  
  if root.hasKey("usage"):
    let u = root["usage"]
    res.promptTokens = u.getOrDefault("prompt_tokens").getInt(0)
    res.completionTokens = u.getOrDefault("completion_tokens").getInt(0)
    res.totalTokens = u.getOrDefault("total_tokens").getInt(0)

  if root.hasKey("choices") and root["choices"].len > 0:
    let choice = root["choices"][0]
    res.finishReason = choice.getOrDefault("finish_reason").getStr("stop")
    
    if choice.hasKey("message"):
      let msgObj = choice["message"]
      if msgObj.hasKey("content") and msgObj["content"].kind == JString:
        res.content = msgObj["content"].getStr()
      
      if msgObj.hasKey("tool_calls") and msgObj["tool_calls"].kind == JArray:
        for tc in msgObj["tool_calls"]:
          var call = ToolCall()
          call.id = tc.getOrDefault("id").getStr("")
          if tc.hasKey("function"):
            let fn = tc["function"]
            call.functionName = fn.getOrDefault("name").getStr("")
            if fn.hasKey("arguments"):
              if fn["arguments"].kind == JString:
                call.arguments = fn["arguments"].getStr()
              else:
                call.arguments = $fn["arguments"]
          res.toolCalls.add(call)

  return res
