import std/[tables, json, strutils]
import ../types, ../memory, ../skills, ../cron, ../subagent
import native_tools, python_bridge, rust_browser, mbvm_db

type
  ToolRegistry* = ref object
    tools*: Table[string, ToolDefinition]
    memoryStore*: MemoryStore
    pythonExe*: string
    workerScript*: string
    rustBrowserExe*: string
    skillRegistry*: SkillRegistry
    cronScheduler*: CronScheduler
    yoloMode*: bool

proc newToolRegistry*(memStore: MemoryStore, pythonExe: string, workerScript: string,
                      rustBrowserExe: string = "", skillReg: SkillRegistry = nil,
                      cronSched: CronScheduler = nil, yoloMode: bool = true): ToolRegistry =
  new(result)
  result.tools = initTable[string, ToolDefinition]()
  result.memoryStore = memStore
  result.pythonExe = pythonExe
  result.workerScript = workerScript
  result.rustBrowserExe = if rustBrowserExe.len > 0: rustBrowserExe else: findRustBrowserExe()
  result.skillRegistry = skillReg
  result.cronScheduler = cronSched
  result.yoloMode = yoloMode

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
  let isYolo = reg.yoloMode
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
      return execTerminal(cmd, wd, isYolo)
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

  # 12. MBVM-DB Tools (Code Graph, Smart Slicing & 95%+ Token Reduction)
  reg.registerTool(ToolDefinition(
    name: "mbvm_slice",
    description: "Extract an intelligent subgraph code slice around a target symbol using MBVM-DB (-93% tokens over raw code).",
    parameters: @[
      ToolParam(name: "target_path", paramType: "string", description: "Path to .mbvmdb binary database or codebase directory", required: true),
      ToolParam(name: "symbol", paramType: "string", description: "Target function, struct, method or interface to slice", required: true),
      ToolParam(name: "depth", paramType: "integer", description: "Traversal depth in call-graph (default 1)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let tp = args.getOrDefault("target_path").getStr("")
      let sym = args.getOrDefault("symbol").getStr("")
      let depth = args.getOrDefault("depth").getInt(1)
      return mbvmSliceTool(tp, sym, depth)
  ))

  reg.registerTool(ToolDefinition(
    name: "mbvm_slice_budget",
    description: "Extract a token-bounded slice around a symbol with noise penalty and hard token ceiling using MBVM-DB.",
    parameters: @[
      ToolParam(name: "target_path", paramType: "string", description: "Path to .mbvmdb file or codebase directory", required: true),
      ToolParam(name: "symbol", paramType: "string", description: "Target symbol name", required: true),
      ToolParam(name: "token_budget", paramType: "integer", description: "Strict token budget limit (e.g. 300, 500)", required: true)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let tp = args.getOrDefault("target_path").getStr("")
      let sym = args.getOrDefault("symbol").getStr("")
      let b = args.getOrDefault("token_budget").getInt(500)
      return mbvmSliceBudgetTool(tp, sym, b)
  ))

  reg.registerTool(ToolDefinition(
    name: "mbvm_inspect",
    description: "Inspect the symbols, types, files and opcode status of a .mbvmdb database.",
    parameters: @[
      ToolParam(name: "target_path", paramType: "string", description: "Path to .mbvmdb file (optional, default codebase.mbvmdb)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let tp = args.getOrDefault("target_path").getStr("")
      return mbvmInspectTool(tp)
  ))

  reg.registerTool(ToolDefinition(
    name: "mbvm_build",
    description: "Compile and index a directory or repository into a persistent high-performance .mbvmdb binary database.",
    parameters: @[
      ToolParam(name: "dir_path", paramType: "string", description: "Root directory of codebase to index", required: true),
      ToolParam(name: "output_file", paramType: "string", description: "Output filename (default codebase.mbvmdb)", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let dp = args.getOrDefault("dir_path").getStr(".")
      let outF = args.getOrDefault("output_file").getStr("codebase.mbvmdb")
      return mbvmBuildTool(dp, outF)
  ))

  # 13. Skills System Tools
  let sReg = reg.skillRegistry
  if sReg != nil:
    reg.registerTool(ToolDefinition(
      name: "skills_list",
      description: "List all loaded skills and their descriptions.",
      parameters: @[],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return sReg.listSkills()
    ))

    reg.registerTool(ToolDefinition(
      name: "skill_view",
      description: "Read the complete instructions and prompts of a specific skill.",
      parameters: @[
        ToolParam(name: "skill_name", paramType: "string", description: "The name of the skill to view", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        let sName = args.getOrDefault("skill_name").getStr("")
        return sReg.viewSkill(sName)
    ))

  # 14. Cron & Recurring Task Scheduler Tools
  let cSched = reg.cronScheduler
  if cSched != nil:
    reg.registerTool(ToolDefinition(
      name: "cron_add",
      description: "Schedule a recurring background prompt/task at fixed minute intervals.",
      parameters: @[
        ToolParam(name: "name", paramType: "string", description: "Unique name identifier for the job", required: true),
        ToolParam(name: "interval_minutes", paramType: "integer", description: "Interval in minutes between runs", required: true),
        ToolParam(name: "prompt", paramType: "string", description: "Prompt or instruction to execute periodically", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        let name = args.getOrDefault("name").getStr("")
        let im = args.getOrDefault("interval_minutes").getInt(60)
        let prompt = args.getOrDefault("prompt").getStr("")
        return cSched.addJob(name, im, prompt)
    ))

    reg.registerTool(ToolDefinition(
      name: "cron_list",
      description: "List all currently scheduled background cron tasks.",
      parameters: @[],
      isPython: false,
      handler: proc(args: JsonNode): string =
        return cSched.listJobs()
    ))

    reg.registerTool(ToolDefinition(
      name: "cron_remove",
      description: "Cancel and remove a scheduled cron job by name.",
      parameters: @[
        ToolParam(name: "name", paramType: "string", description: "Name of the job to cancel", required: true)
      ],
      isPython: false,
      handler: proc(args: JsonNode): string =
        let name = args.getOrDefault("name").getStr("")
        return cSched.removeJob(name)
    ))

  # 15. Subagent Delegation Tool
  reg.registerTool(ToolDefinition(
    name: "delegate_task",
    description: "Delegate a complex subtask or research to an isolated background subagent, returning a concise summary report without cluttering main context.",
    parameters: @[
      ToolParam(name: "task", paramType: "string", description: "Detailed description of the task for the subagent", required: true),
      ToolParam(name: "model", paramType: "string", description: "Optional model override for the subagent", required: false)
    ],
    isPython: false,
    handler: proc(args: JsonNode): string =
      let task = args.getOrDefault("task").getStr("")
      let model = args.getOrDefault("model").getStr("")
      return delegateTaskTool(task, model)
  ))
