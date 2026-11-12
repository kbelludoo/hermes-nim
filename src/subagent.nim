import std/strutils

# Forward declaration or proc to spawn an isolated agent
type RunIsolatedAgentProc* = proc(task: string, modelOverride: string = ""): string {.closure.}

var gSubagentRunner*: RunIsolatedAgentProc = nil

proc setSubagentRunner*(runner: RunIsolatedAgentProc) =
  gSubagentRunner = runner

proc delegateTaskTool*(task: string, modelOverride: string = ""): string =
  if gSubagentRunner == nil:
    return "Error: Subagent runner is not initialized."
  if task.strip().len == 0:
    return "Error: Task description cannot be empty."

  return gSubagentRunner(task, modelOverride)
