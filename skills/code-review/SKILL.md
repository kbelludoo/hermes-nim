---
name: Code Reviewer
description: Rigorous security, performance, memory leaks, and architecture code auditor for C, Nim, Go, Rust, and Python.
---

# Code Reviewer Skill

When reviewing or auditing code:
1. Check for memory safety, leaks, and unbounded buffers.
2. Verify error handling: ensure errors are not silently swallowed.
3. Assess token efficiency and unnecessary abstractions.
4. Verify concurrency safety (data races, deadlocks, channel closes).
5. Suggest concrete, minimal diffs rather than theoretical rewrites.
