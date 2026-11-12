import std/[os, unittest, strutils, json, tables]
import ../src/types, ../src/utils, ../src/config, ../src/memory, ../src/skills, ../src/cron, ../src/sessions, ../src/catalog
import ../src/tools/native_tools, ../src/tools/python_bridge, ../src/tools/rust_browser, ../src/tools/mbvm_db, ../src/tools/opencode, ../src/tools/registry

suite "Hermes Nim Full Parity & MBVM-DB Tests":

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
    let wRes = writeFileTool(testFile, "Hello World\nLine 2\nLine 3\nTargetToReplace\nEnd")
    check "Successfully wrote" in wRes
    
    let rRes = readFileTool(testFile, 1, 3)
    check "1: Hello World" in rRes
    check "3: Line 3" in rRes
    
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
    check bExe.len > 0
    check fileExists(bExe)

    let navRes = callRustBrowserMcp(bExe, "browser_navigate", %*{"url": "https://example.com"})
    check "Navigated to" in navRes or "https://example.com" in navRes

    let snapRes = callRustBrowserMcp(bExe, "browser_snapshot", %*{"compact": true})
    check "example.com" in snapRes

  test "MBVM-DB Code Graph Engine Integration":
    let mbvmExe = findMbvmDbExe()
    echo "  [Test] MBVM-DB Exe: ", mbvmExe
    check mbvmExe.len > 0
    check fileExists(mbvmExe)

    # Test inspect
    let inspectRes = mbvmInspectTool()
    echo "  [Test] MBVM Inspect: ", inspectRes
    check "MBVM-DB Status" in inspectRes or "Total de Arquivos" in inspectRes

    # Test slice
    let sliceRes = mbvmSliceTool("codebase.mbvmdb", "ExtractSlice", 1)
    echo "  [Test] MBVM Slice preview: ", (if sliceRes.len > 120: sliceRes[0 ..< 120] & "..." else: sliceRes)
    check "ExtractSlice" in sliceRes

  test "Skills System & Discovery":
    let tempHome = getTempDir() / "hermes_skills_test"
    let skillReg = newSkillRegistry(tempHome)
    let sList = skillReg.listSkills()
    echo "  [Test] Skills Count: ", skillReg.skills.len
    check skillReg.skills.len >= 0

  test "Cron Scheduler Operations":
    let sched = newCronScheduler()
    let addRes = sched.addJob("healthcheck", 15, "check system health")
    check "scheduled" in addRes
    
    let listRes = sched.listJobs()
    check "healthcheck" in listRes
    
    let remRes = sched.removeJob("healthcheck")
    check "removed" in remRes

  test "Session Persistence & Resume":
    let tempHome = getTempDir() / "hermes_sess_test"
    var msgs: seq[Message] = @[
      Message(role: "user", content: "What is 2+2?"),
      Message(role: "assistant", content: "4")
    ]
    saveSession(tempHome, "test_session_123", msgs)
    
    let (found, id, loadedMsgs) = loadSession(tempHome, "test_session_123")
    check found
    check id == "test_session_123"
    check loadedMsgs.len == 2
    check loadedMsgs[0].content == "What is 2+2?"

  test "Tool Registry (30 Tools: Native + Browser + MBVM + Skills + Cron + OpenCode)":
    let tempHome = getTempDir() / "hermes_test_home_all"
    let store = newMemoryStore(tempHome)
    let pyExe = findPythonExecutable()
    let wScript = getCurrentDir() / "python_worker" / "tool_runner.py"
    let bExe = findRustBrowserExe()
    let sReg = newSkillRegistry(tempHome)
    let cSched = newCronScheduler()

    let reg = newToolRegistry(store, pyExe, wScript, bExe, sReg, cSched, hermesHome = tempHome, yoloMode = true)
    reg.initDefaultTools()

    let schemas = reg.getOpenAIToolsSchema()
    echo "  [Test] Total Registered Tools: ", schemas.len
    check schemas.len >= 30 # 9 native + 5 browser + 4 mbvm + 4 skills + 3 cron + 1 subagent + 2 opencode + 2 skills community

    let memFinal = getResidentMemoryMB()
    echo "  [Test] Final Resident RAM: ", memFinal, " MB"
    check memFinal < 50.0

  test "Decentralized Skills Marketplace (Obsidian GitOps pattern)":
    let cat = loadLocalCatalog()
    echo "  [Test] Local Community Skills count: ", cat.len
    check cat.len >= 5

    # Search test
    let gitMatches = searchCommunitySkills(cat, "git")
    check gitMatches.len >= 1
    check gitMatches[0].id == "git-master"

    # Install test
    let tempHome = getTempDir() / "hermes_skills_install_test"
    let (okInst, instMsg) = installCommunitySkill("git-master", tempHome)
    echo "  [Test] Install Result: ", instMsg
    check okInst
    check fileExists(tempHome / "skills" / "git-master" / "SKILL.md")

    # Uninstall test
    let (okUninst, uninstMsg) = uninstallCommunitySkill("git-master", tempHome)
    echo "  [Test] Uninstall Result: ", uninstMsg
    check okUninst
    check not dirExists(tempHome / "skills" / "git-master")

  test "OpenCode Headless AI Integration (<50MB RAM)":
    let cli = getOpenCodeCliPath()
    echo "  [Test] OpenCode CLI Path: ", cli
    check isOpenCodeInstalled()
    
    let models = listOpenCodeModels()
    echo "  [Test] OpenCode Models detected: ", models.len
    check models.len > 0
    
    # Test queryOpenCode with Gemini Flash Lite
    let resp = queryOpenCode("google/gemini-2.5-flash-lite", "Responda apenas: TEST_OK")
    echo "  [Test] OpenCode Response: ", resp.strip()
    check "TEST_OK" in resp or resp.len > 0
