import std/[os, httpclient, json, strutils, tables]
import ../types, ../utils, ../agent

type
  TelegramBot* = ref object
    token*: string
    allowedChatId*: string
    client*: HttpClient
    lastUpdateId*: int64

proc newTelegramBot*(token: string, allowedChatId: string): TelegramBot =
  new(result)
  result.token = token
  result.allowedChatId = allowedChatId
  result.client = newHttpClient(timeout = 40_000)
  result.lastUpdateId = 0

proc apiCall(bot: TelegramBot, methodStr: string, bodyJson: JsonNode = nil): JsonNode =
  let url = "https://api.telegram.org/bot" & bot.token & "/" & methodStr
  var headers = newHttpHeaders({
    "Content-Type": "application/json",
    "User-Agent": "Hermes-Nim-Telegram/1.0"
  })
  bot.client.headers = headers
  
  let payload = if bodyJson != nil: $bodyJson else: ""
  let resp = bot.client.request(url, httpMethod = (if bodyJson != nil: HttpPost else: HttpGet), body = payload)
  if resp.code != Http200:
    raise newException(IOError, "Telegram API error (" & $resp.code & "): " & resp.body)
  return parseJson(resp.body)

proc getMe*(bot: TelegramBot): string =
  try:
    let res = bot.apiCall("getMe")
    if res.hasKey("result") and res["result"].hasKey("username"):
      return res["result"]["username"].getStr()
  except CatchableError as e:
    echo "Warning: getMe failed: ", e.msg
  return "UnknownBot"

proc sendChatAction*(bot: TelegramBot, chatId: string, action: string = "typing") =
  try:
    var body = newJObject()
    body["chat_id"] = %chatId
    body["action"] = %action
    discard bot.apiCall("sendChatAction", body)
  except CatchableError:
    discard

proc splitMessage(text: string, maxLen: int = 4000): seq[string] =
  if text.len <= maxLen:
    return @[text]
  
  var parts: seq[string] = @[]
  var current = ""
  for line in text.splitLines():
    if current.len + line.len + 1 > maxLen:
      if current.len > 0:
        parts.add(current)
        current = ""
    if line.len > maxLen:
      # Hard wrap extremely long lines
      var i = 0
      while i < line.len:
        let chunk = line[i ..< min(line.len, i + maxLen)]
        parts.add(chunk)
        i += maxLen
    else:
      if current.len > 0:
        current.add("\n")
      current.add(line)
      
  if current.len > 0:
    parts.add(current)
  return parts

proc sendMessage*(bot: TelegramBot, chatId: string, text: string, parseMode: string = "") =
  let chunks = splitMessage(text, 3900)
  for chunk in chunks:
    try:
      var body = newJObject()
      body["chat_id"] = %chatId
      body["text"] = %chunk
      if parseMode.len > 0:
        body["parse_mode"] = %parseMode
      discard bot.apiCall("sendMessage", body)
    except CatchableError:
      # Retry without markdown if telegram formatting rejected it
      try:
        var fallback = newJObject()
        fallback["chat_id"] = %chatId
        fallback["text"] = %chunk
        discard bot.apiCall("sendMessage", fallback)
      except CatchableError as e:
        echo "Error sending Telegram message: ", e.msg

proc pollUpdates*(bot: TelegramBot): seq[JsonNode] =
  result = @[]
  var body = newJObject()
  body["timeout"] = %25
  if bot.lastUpdateId > 0:
    body["offset"] = %(bot.lastUpdateId + 1)
  
  try:
    let res = bot.apiCall("getUpdates", body)
    if res.hasKey("result") and res["result"].kind == JArray:
      for u in res["result"]:
        let updateId = u.getOrDefault("update_id").getBiggestInt(0)
        if updateId > bot.lastUpdateId:
          bot.lastUpdateId = updateId
        result.add(u)
  except CatchableError as e:
    echo "Polling warning: ", e.msg
    sleep(2000)

proc startTelegramGateway*(bot: TelegramBot, agent: AIAgent) =
  let botUsername = bot.getMe()
  let memMB = getResidentMemoryMB()
  echo colorize("╔════════════════════════════════════════════════════════════════╗", AnsiCyan)
  echo colorize("║       HERMES AGENT — Telegram Gateway (Nim Native)             ║", AnsiBold & AnsiCyan)
  echo colorize("║  Bot: @" & botUsername.alignLeft(20) & " RAM: " & formatFloat(memMB, ffDecimal, 2) & " MB (Ceiling: < 50MB) ║", AnsiGreen)
  echo colorize("╚════════════════════════════════════════════════════════════════╝", AnsiCyan)
  echo "Listening for messages from authorized chat: ", (if bot.allowedChatId.len > 0: bot.allowedChatId else: "ALL (Public)")
  echo "Ready. Press Ctrl+C to stop.\n"

  if bot.allowedChatId.len > 0:
    bot.sendMessage(bot.allowedChatId, "⚡ *Hermes Agent Online* (Nim Native Core)\n• RAM: `" & formatFloat(memMB, ffDecimal, 2) & " MB`\n• Modelo: `" & agent.config.model & "`\nEnvie uma mensagem para começar.", "Markdown")

  while true:
    let updates = bot.pollUpdates()
    for u in updates:
      if not u.hasKey("message"):
        continue
      let msg = u["message"]
      if not msg.hasKey("text") or not msg.hasKey("chat"):
        continue

      let chatId = $msg["chat"].getOrDefault("id").getBiggestInt(0)
      let text = msg["text"].getStr().strip()
      let fromUser = if msg.hasKey("from"): msg["from"].getOrDefault("first_name").getStr("User") else: "User"

      # Access Control Check
      if bot.allowedChatId.len > 0 and chatId != bot.allowedChatId:
        echo "🔒 [Telegram] Ignorando mensagem de chat não autorizado: ", chatId
        bot.sendMessage(chatId, "⛔ Acesso restrito. Este bot é privado.")
        continue

      echo "[Telegram] Recebido de ", fromUser, " (", chatId, "): ", text

      # Slash Commands
      if text == "/start" or text == "/help":
        let helpText = "⚡ *Hermes Agent (Nim Native)*\n\n" &
          "Comandos disponíveis:\n" &
          "• `/status` ou `/stats` - Exibe consumo de RAM e tokens\n" &
          "• `/clear` - Limpa o histórico da conversa\n" &
          "• `/tools` - Lista ferramentas nativas e do navegador\n" &
          "• `/model <nome>` - Altera o modelo de LLM ativo\n\n" &
          "Ou simplesmente envie sua dúvida ou tarefa para executar!"
        bot.sendMessage(chatId, helpText, "Markdown")
        continue

      if text == "/clear":
        let sysMsg = agent.messages[0]
        agent.messages = @[sysMsg]
        bot.sendMessage(chatId, "🧹 *Histórico de conversa limpo com sucesso.*", "Markdown")
        continue

      if text == "/stats" or text == "/status" or text.toLowerAscii().contains("memoria") or text.toLowerAscii().contains("ram"):
        let curMem = getResidentMemoryMB()
        let statsText = "🧠 *Hermes Agent Performance Stats*\n\n" &
          "• *Memória RAM Residente:* `" & formatFloat(curMem, ffDecimal, 2) & " MB`\n" &
          "• *Teto de Memória:* `50.00 MB`\n" &
          "• *Mensagens no Contexto:* `" & $agent.messages.len & "`\n" &
          "• *Tokens Consumidos:* `" & $(agent.totalPromptTokens + agent.totalCompletionTokens) & "`\n" &
          "• *Modelo Ativo:* `" & agent.config.model & "`"
        bot.sendMessage(chatId, statsText, "Markdown")
        continue

      if text == "/tools":
        var toolList = "🛠️ *Ferramentas Disponíveis no Hermes:*\n\n"
        for name, def in agent.registry.tools:
          toolList &= "• `" & name & "`: " & def.description & "\n"
        bot.sendMessage(chatId, toolList, "Markdown")
        continue

      if text.startsWith("/model"):
        let parts = text.splitWhitespace()
        if parts.len >= 2:
          agent.config.model = parts[1]
          agent.client.config.model = parts[1]
          bot.sendMessage(chatId, "✅ Modelo alternado para: `" & parts[1] & "`", "Markdown")
        else:
          bot.sendMessage(chatId, "Uso: `/model <nome-do-modelo>`", "Markdown")
        continue

      # Normal Prompt -> Run Conversation with Agent
      bot.sendChatAction(chatId, "typing")
      
      var toolExecBuffer = ""
      let answer = agent.runConversation(text, proc(chunk: string) =
        # If agent is running a tool, send live feedback on Telegram
        if chunk.contains("► Executing tool:"):
          bot.sendChatAction(chatId, "typing")
          let cleanTool = chunk.replace("\e[0m", "").replace("\e[1m", "").replace("\e[36m", "").replace("\e[2m", "").strip()
          bot.sendMessage(chatId, "⚙️ " & cleanTool)
      )

      bot.sendMessage(chatId, answer)
