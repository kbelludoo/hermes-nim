import std/[os, unittest, strutils, json]
import ../src/utils, ../src/config, ../src/memory
import ../src/tools/native_tools, ../src/tools/python_bridge, ../src/tools/rust_browser, ../src/tools/registry

suite "Hermes Nim Core & Memory Limit Tests":

  test "Memory footprint is strictly below 50 MB":
    let memMB = getResidentMemoryMB()
    echo "  [Test] Current Resident Memory: ", memMB, " MB"
    check memMB < 50.0
    check memMB > 0.0

  test "Memory Store operations":
    let tempHome = getTempDir() / "hermes_test_home"
    let store = newMemoryStore(tempHome)
    
    let res1 = store.remember("user_role", "Software Engineer")
    check "saved" in res1 or "updated" in res1
    
    let recalled = store.recall("role")
    check "Software Engineer" in recalled
    
    let forgetRes = store.forget("user_role")
    check "deleted" in forgetRes

  test "Native File Tools (Read, Write, Edit)":
    let testFile = getTempDir() / "hermes_sample.txt"
    
    # Write
    let wRes = writeFileTool(testFile, "Hello World\nLine 2\nLine 3\nTargetToReplace\nEnd")
    check "Successfully wrote" in wRes
    
    # Read
    let rRes = readFileTool(testFile, 1, 3)
    check "1: Hello World" in rRes
    check "3: Line 3" in rRes
    
    # Edit
    let eRes = editFileTool(testFile, "TargetToReplace", "ReplacementDone")
    check "Successfully replaced" in eRes
    
    let afterEdit = readFileTool(testFile, 4, 4)
    check "ReplacementDone" in afterEdit
    
    removeFile(testFile)

  test "Native Terminal Execution":
    let res = execTerminal("echo HermesTest")
    check "HermesTest" in res

  test "AI Rust Browser MCP Integration (~6-10MB RAM)":
    let bExe = findRustBrowserExe()
    echo "  [Test] AI Rust Browser Exe: ", bExe
    check bExe.len > 0
    check fileExists(bExe)

    let navRes = callRustBrowserMcp(bExe, "browser_navigate", %*{"url": "https://example.com"})
    echo "  [Test] Browser Nav Result: ", navRes
    check "Navigated to" in navRes or "https://example.com" in navRes

    let snapRes = callRustBrowserMcp(bExe, "browser_snapshot", %*{"compact": true})
    echo "  [Test] Browser Snapshot Result: ", snapRes
    check "example.com" in snapRes

    let memAfterBrowser = getResidentMemoryMB()
    echo "  [Test] Hermes RAM after Browser invocation: ", memAfterBrowser, " MB"
    check memAfterBrowser < 50.0

  test "Tool Registry & OpenAI Schema Generation":
    let tempHome = getTempDir() / "hermes_test_home_2"
    let store = newMemoryStore(tempHome)
    let pyExe = findPythonExecutable()
    let wScript = getCurrentDir() / "hermes_nim" / "python_worker" / "tool_runner.py"
    
    let reg = newToolRegistry(store, pyExe, wScript)
    reg.initDefaultTools()
    
    let schemas = reg.getOpenAIToolsSchema()
    echo "  [Test] Total Registered Tools (Native + Browser + Python): ", schemas.len
    check schemas.len >= 14 # 9 native + 5 browser + 1 python
    
    # Test dispatching browser tool through registry
    let bDispatch = reg.executeTool("browser_navigate", """{"url": "https://example.com"}""")
    check "https://example.com" in bDispatch
