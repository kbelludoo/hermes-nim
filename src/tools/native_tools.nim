import std/[os, osproc, strutils, httpclient]
import ../utils

proc execTerminal*(command: string, workingDir: string = ""): string =
  if command.strip().len == 0:
    return "Error: Empty command provided."
    
  var cwd = workingDir
  if cwd.len == 0:
    cwd = getCurrentDir()
  elif not dirExists(cwd):
    return "Error: Working directory does not exist: " & cwd

  try:
    when defined(windows):
      let shellCmd = "cmd.exe /c " & command
    else:
      let shellCmd = "/bin/sh -c " & quoteShell(command)

    let (output, exitCode) = execCmdEx(shellCmd, options = {poUsePath, poStdErrToStdOut}, workingDir = cwd)
    var resultStr = output.strip()
    if resultStr.len == 0:
      resultStr = "(Command executed successfully with no output)"
    
    if exitCode != 0:
      resultStr = "Exit code " & $exitCode & "\n" & resultStr
      
    return truncateOutput(resultStr, 8000)
  except CatchableError as e:
    return "Execution error: " & e.msg

proc readFileTool*(path: string, startLine: int = 1, endLine: int = 0): string =
  let fullPath = if isAbsolute(path): path else: getCurrentDir() / path
  if not fileExists(fullPath):
    return "Error: File not found: " & path
    
  try:
    var linesSeq: seq[string] = @[]
    for line in lines(fullPath):
      linesSeq.add(line)
      
    let totalLines = linesSeq.len
    let startIdx = max(1, startLine)
    let endIdx = if endLine <= 0 or endLine > totalLines: totalLines else: endLine
    
    if startIdx > totalLines:
      return "Error: start_line " & $startIdx & " is beyond file length (" & $totalLines & " lines)"

    var outLines: seq[string] = @[]
    for i in (startIdx - 1) ..< endIdx:
      outLines.add($(i + 1) & ": " & linesSeq[i])
      
    let body = outLines.join("\n")
    return "Showing lines " & $startIdx & "-" & $endIdx & " of " & $totalLines & "\n" & truncateOutput(body, 12000)
  except CatchableError as e:
    return "Error reading file: " & e.msg

proc writeFileTool*(path: string, content: string): string =
  let fullPath = if isAbsolute(path): path else: getCurrentDir() / path
  try:
    let dir = parentDir(fullPath)
    if dir.len > 0 and not dirExists(dir):
      createDir(dir)
    writeFile(fullPath, content)
    return "Successfully wrote " & $content.len & " bytes to " & path
  except CatchableError as e:
    return "Error writing file: " & e.msg

proc editFileTool*(path: string, target: string, replacement: string): string =
  let fullPath = if isAbsolute(path): path else: getCurrentDir() / path
  if not fileExists(fullPath):
    return "Error: File not found: " & path
  if target.len == 0:
    return "Error: Target string cannot be empty."

  try:
    let original = readFile(fullPath)
    if not original.contains(target):
      return "Error: Target string not found in " & path
      
    let count = original.count(target)
    let updated = original.replace(target, replacement)
    writeFile(fullPath, updated)
    return "Successfully replaced " & $count & " occurrence(s) in " & path
  except CatchableError as e:
    return "Error editing file: " & e.msg

proc listDirTool*(path: string = "."): string =
  let targetPath = if path.len == 0: "." else: path
  let fullPath = if isAbsolute(targetPath): targetPath else: getCurrentDir() / targetPath
  if not dirExists(fullPath):
    return "Error: Directory not found: " & targetPath

  try:
    var entries: seq[string] = @[]
    for kind, entry in walkDir(fullPath):
      let base = extractFilename(entry)
      case kind
      of pcDir:
        entries.add("[DIR]  " & base & "/")
      of pcFile:
        let sz = getFileSize(entry)
        entries.add("[FILE] " & base & " (" & $sz & " bytes)")
      else:
        entries.add("[OTHER] " & base)
        
    if entries.len == 0:
      return "Directory is empty: " & targetPath
    return "Contents of " & targetPath & ":\n" & entries.join("\n")
  except CatchableError as e:
    return "Error listing directory: " & e.msg

proc searchFilesTool*(path: string = ".", query: string): string =
  if query.len == 0:
    return "Error: Query cannot be empty."
  let targetPath = if path.len == 0: "." else: path
  let fullPath = if isAbsolute(targetPath): targetPath else: getCurrentDir() / targetPath
  if not dirExists(fullPath):
    return "Error: Directory not found: " & targetPath

  try:
    var matches: seq[string] = @[]
    let qLower = query.toLowerAscii()
    
    for entry in walkDirRec(fullPath, yieldFilter = {pcFile}):
      let rel = relativePath(entry, fullPath)
      # Skip common noisy directories
      if rel.contains(".git") or rel.contains("node_modules") or rel.contains("nimcache") or rel.contains("__pycache__"):
        continue
      if rel.toLowerAscii().contains(qLower):
        matches.add("[Name match] " & rel)
        if matches.len >= 30: break
      else:
        # Check text file content if small
        try:
          if getFileSize(entry) < 200_000:
            let content = readFile(entry)
            if content.toLowerAscii().contains(qLower):
              matches.add("[Content match] " & rel)
              if matches.len >= 30: break
        except:
          discard

    if matches.len == 0:
      return "No files matching '" & query & "' found in " & targetPath
    return "Matches for '" & query & "':\n" & matches.join("\n")
  except CatchableError as e:
    return "Error searching files: " & e.msg

proc stripHtmlTags(html: string): string =
  # Clean HTML tags to text
  var inTag = false
  var s = ""
  for c in html:
    if c == '<':
      inTag = true
    elif c == '>':
      inTag = false
      s.add(' ')
    elif not inTag:
      s.add(c)
  return s.replace("&nbsp;", " ").replace("&amp;", "&").replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", "\"")

proc fetchUrlTool*(url: string): string =
  if not (url.startsWith("http://") or url.startsWith("https://")):
    return "Error: URL must begin with http:// or https://"
  try:
    var client = newHttpClient(timeout = 30_000)
    client.headers = newHttpHeaders({
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Hermes-Nim/1.0"
    })
    let resp = client.getContent(url)
    let cleaned = stripHtmlTags(resp).strip()
    # Normalize multiple newlines/spaces
    let lines = cleaned.splitLines()
    var filtered: seq[string] = @[]
    for line in lines:
      let t = line.strip()
      if t.len > 0:
        filtered.add(t)
    let finalContent = filtered.join("\n")
    return truncateOutput(finalContent, 6000)
  except CatchableError as e:
    return "Failed to fetch URL: " & e.msg
