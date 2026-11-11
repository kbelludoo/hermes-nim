import std/[tables, json, strutils]
import ../types, ../memory, native_tools, python_bridge, rust_browser

type
  ToolRegistry* = ref object
    tools*: Table[string, ToolDefinition]
    memoryStore*: MemoryStore
    pythonExe*: string
    workerScript*: string
    rustBrowserExe*: string

proc newToolRegistry*(memStore: MemoryStore, pythonExe: string, workerScript: string, rustBrowserExe: string = ""): ToolRegistry =
  new(result)
  result.tools = initTable[string, ToolDefinition]()
  result.memoryStore = memStore
  result.pythonExe = pythonExe
  result.workerScript = workerScript
  result.rustBrowserExe = if rustBrowserExe.len > 0: rustBrowserExe else: findRustBrowserExe()

proc registerTool*(reg: ToolRegistry, def: ToolDefinition) =
  reg.tools[def.name] = def

proc getOpenAIToolsSchema*(reg: ToolRegistry): seq[JsonNode] =
  result = @[]
  for _, def in reg.tools:
    result.add(def.toolToJsonSchema())

proc executeTool*(reg: ToolRegistry, name: string, argsJsonStr: string): string =
  if not reg.tools.hasKey(name):
    return "Error: Unknown tool '" & name & "'."
    
  var argsNode = newJObject()
  if argsJsonStr.strip().len > 0:
    try:
      argsNode = parseJson(argsJsonStr)
    except CatchableError as e:
      return "Error: Invalid JSON arguments: " & e.msg

  let def = reg.tools[name]
  try:
    return def.handler(argsNode)
  except CatchableError as e:
    return "Error executing tool '" & name & "': " & e.msg

proc initDefaultTools*(reg: ToolRegistry) =
  # 1. terminal / bash
  reg.registerTool(ToolDefinition(
    name: "terminal",
    description: "Execute a command in the local shell/terminal. Use this for running build scripts, system commands, git, tests, etc.",
    parameters: @[
      ToolParam(name: "command", paramType: "string", description: "The shell command to execute", required: true),
      ToolParam(name: "working_dir", paramType: "string", description: "Directory to execute command in (default current dir)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let cmd = args.getOrDefault("command").getStr("")
      let wd = args.getOrDefault("working_dir").getStr("")
      return execTerminal(cmd, wd)
  ))

  # 2. read_file
  reg.registerTool(ToolDefinition(
    name: "read_file",
    description: "Read contents of a file with optional line range pagination.",
    parameters: @[
      ToolParam(name: "path", paramType: "string", description: "Absolute or relative file path", required: true),
      ToolParam(name: "start_line", paramType: "integer", description: "First line to read (1-based, default 1)", required: false),
      ToolParam(name: "end_line", paramType: "integer", description: "Last line to read (inclusive, default all)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let path = args.getOrDefault("path").getStr("")
      let sl = args.getOrDefault("start_line").getInt(1)
      let el = args.getOrDefault("end_line").getInt(0)
      return readFileTool(path, sl, el)
  ))

  # 3. write_file
  reg.registerTool(ToolDefinition(
    name: "write_file",
    description: "Create a new file or completely overwrite an existing file with the given content.",
    parameters: @[
      ToolParam(name: "path", paramType: "string", description: "File path to create or overwrite", required: true),
      ToolParam(name: "content", paramType: "string", description: "Complete content to write to the file", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let path = args.getOrDefault("path").getStr("")
      let content = args.getOrDefault("content").getStr("")
      return writeFileTool(path, content)
  ))

  # 4. edit_file
  reg.registerTool(ToolDefinition(
    name: "edit_file",
    description: "Search for an exact target string in a file and replace it with replacement content.",
    parameters: @[
      ToolParam(name: "path", paramType: "string", description: "File path to edit", required: true),
      ToolParam(name: "target", paramType: "string", description: "Exact string in the file to find and replace", required: true),
      ToolParam(name: "replacement", paramType: "string", description: "Replacement string", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let path = args.getOrDefault("path").getStr("")
      let target = args.getOrDefault("target").getStr("")
      let repl = args.getOrDefault("replacement").getStr("")
      return editFileTool(path, target, repl)
  ))

  # 5. list_directory
  reg.registerTool(ToolDefinition(
    name: "list_directory",
    description: "List the files and directories in a given path.",
    parameters: @[
      ToolParam(name: "path", paramType: "string", description: "Directory path (default current dir)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let path = args.getOrDefault("path").getStr(".")
      return listDirTool(path)
  ))

  # 6. search_files
  reg.registerTool(ToolDefinition(
    name: "search_files",
    description: "Search for files by name or search for text content inside files.",
    parameters: @[
      ToolParam(name: "path", paramType: "string", description: "Directory path to start search in", required: false),
      ToolParam(name: "query", paramType: "string", description: "Search query or pattern", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let path = args.getOrDefault("path").getStr(".")
      let query = args.getOrDefault("query").getStr("")
      return searchFilesTool(path, query)
  ))

  # 7. fetch_url
  reg.registerTool(ToolDefinition(
    name: "fetch_url",
    description: "Fetch web content from a URL via HTTP/HTTPS and return the stripped text content.",
    parameters: @[
      ToolParam(name: "url", paramType: "string", description: "Full URL to fetch (http:// or https://)", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let url = args.getOrDefault("url").getStr("")
      return fetchUrlTool(url)
  ))

  # 8. memory_save
  let mem = reg.memoryStore
  reg.registerTool(ToolDefinition(
    name: "memory_save",
    description: "Save a key-value fact, preference, or context into long-term persistent memory.",
    parameters: @[
      ToolParam(name: "key", paramType: "string", description: "Identifier key for the memory", required: true),
      ToolParam(name: "content", paramType: "string", description: "The content/fact to remember", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let key = args.getOrDefault("key").getStr("")
      let content = args.getOrDefault("content").getStr("")
      return mem.remember(key, content)
  ))

  # 9. memory_recall
  reg.registerTool(ToolDefinition(
    name: "memory_recall",
    description: "Recall saved memories matching a search query or view all memories.",
    parameters: @[
      ToolParam(name: "query", paramType: "string", description: "Query to match against memories (empty for all)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let query = args.getOrDefault("query").getStr("")
      return mem.recall(query)
  ))

  # 10. execute_python (Ultra-lean Python Bridge: runs strictly in isolated subprocess, <12MB transient RAM)
  let pyExe = reg.pythonExe
  let wScript = reg.workerScript
  reg.registerTool(ToolDefinition(
    name: "execute_python",
    description: "Execute Python code or scripts via an ultra-lightweight transient runner (<12MB RAM). Use this when Python calculation, scripting, or Python library execution is strictly required.",
    parameters: @[
      ToolParam(name: "code", paramType: "string", description: "Python code to execute", required: false),
      ToolParam(name: "script", paramType: "string", description: "Optional path to a python script file", required: false),
      ToolParam(name: "args", paramType: "object", description: "Optional arguments dict passed into the script/code", required: false)
    ],
    isPython: true,
    handler: proc(args: JsonNode): string =
      let code = args.getOrDefault("code").getStr("")
      let script = args.getOrDefault("script").getStr("")
      let pargs = args.getOrDefault("args")
      if script.len > 0:
        return runPythonScript(pyExe, wScript, script, pargs)
      elif code.len > 0:
        return runPythonCode(pyExe, wScript, code, pargs)
      else:
        return "Error: Neither 'code' nor 'script' was provided to execute_python."
  ))

  # 11. AI Rust Browser Tools (Ultra-lightweight headless browser, ~4-10MB RAM)
  let bExe = reg.rustBrowserExe
  if bExe.len > 0:
    reg.registerTool(ToolDefinition(
      name: "browser_navigate",
      description: "Navigate to any URL using the native AI Rust Browser (<10MB RAM). Returns status and page title.",
      parameters: @[
        ToolParam(name: "url", paramType: "string", description: "Destination URL to open", required: true),
        ToolParam(name: "render_js", paramType: "boolean", description: "Whether to render dynamic JavaScript (optional)", required: false)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return callRustBrowserMcp(bExe, "browser_navigate", args)
    ))

    reg.registerTool(ToolDefinition(
      name: "browser_snapshot",
      description: "Capture a token-optimized Markdown snapshot with deterministic #ref action markers for autonomous web interaction.",
      parameters: @[
        ToolParam(name: "compact", paramType: "boolean", description: "If true, returns only essential text and primary targets", required: false)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return callRustBrowserMcp(bExe, "browser_snapshot", args)
    ))

    reg.registerTool(ToolDefinition(
      name: "browser_click",
      description: "Click an interactive element by reference marker (#ref:N) with self-healing fallback.",
      parameters: @[
        ToolParam(name: "ref", paramType: "string", description: "The reference ID or marker to click", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return callRustBrowserMcp(bExe, "browser_click", args)
    ))

    reg.registerTool(ToolDefinition(
      name: "browser_type",
      description: "Type text into an input field by reference marker (#ref:N).",
      parameters: @[
        ToolParam(name: "ref", paramType: "string", description: "The reference ID of the input field", required: true),
        ToolParam(name: "text", paramType: "string", description: "The text to type into the field", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return callRustBrowserMcp(bExe, "browser_type", args)
    ))

    reg.registerTool(ToolDefinition(
      name: "browser_search",
      description: "Fast web search powered by the AI Rust Browser engine.",
      parameters: @[
        ToolParam(name: "query", paramType: "string", description: "Search query", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return callRustBrowserMcp(bExe, "browser_search", args)
    ))
