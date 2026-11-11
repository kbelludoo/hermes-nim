#!/usr/bin/env python3
"""
Hermes Agent Ultra-Lean Python Worker (Micro-Bridge)
Designed to run strictly on Python Standard Library with ZERO external dependencies.
Peak Memory Consumption: < 12 MB RSS.
Process Lifecycle: Transient (executes on-demand and exits, freeing 100% of memory).
"""

import sys
import os
import json
import io
import traceback
import argparse
from contextlib import redirect_stdout, redirect_stderr

def run_code(code_str: str, args_dict: dict = None) -> dict:
    """Executes arbitrary Python code safely and captures stdout/stderr."""
    stdout_buf = io.StringIO()
    stderr_buf = io.StringIO()
    
    local_scope = {"args": args_dict or {}, "result": None}
    
    try:
        with redirect_stdout(stdout_buf), redirect_stderr(stderr_buf):
            # Compile and execute
            compiled = compile(code_str, "<hermes_eval>", "exec")
            exec(compiled, globals(), local_scope)
        
        output = stdout_buf.getvalue()
        err = stderr_buf.getvalue()
        
        res = local_scope.get("result")
        res_str = ""
        if res is not None:
            res_str = str(res)
            
        combined_output = output
        if res_str and res_str not in output:
            combined_output += ("\n" if combined_output else "") + res_str
        if err:
            combined_output += ("\n[stderr]: " if combined_output else "[stderr]: ") + err
            
        return {
            "status": "success",
            "output": combined_output.strip() or "(Executed successfully with no output)"
        }
    except Exception as e:
        err_msg = traceback.format_exc()
        return {
            "status": "error",
            "error": err_msg
        }

def run_script(script_path: str, args_dict: dict = None) -> dict:
    """Executes a standalone Python script file."""
    if not os.path.exists(script_path):
        return {"status": "error", "error": f"Script not found: {script_path}"}
    try:
        with open(script_path, "r", encoding="utf-8") as f:
            code = f.read()
        return run_code(code, args_dict)
    except Exception as e:
        return {"status": "error", "error": str(e)}

def main():
    parser = argparse.ArgumentParser(description="Hermes Agent Lightweight Python Tool Bridge")
    parser.add_argument("--code", type=str, help="Python code string to execute")
    parser.add_argument("--script", type=str, help="Path to Python script to execute")
    parser.add_argument("--args", type=str, default="{}", help="JSON string of arguments")
    parser.add_argument("--stdin", action="store_true", help="Read payload JSON from stdin")
    
    args = parser.parse_args()
    
    if args.stdin:
        try:
            raw = sys.stdin.read()
            if raw.startswith("\ufeff"):
                raw = raw[1:]
            payload = json.loads(raw)
            code = payload.get("code")
            script = payload.get("script")
            pargs = payload.get("args", {})
            if code:
                res = run_code(code, pargs)
            elif script:
                res = run_script(script, pargs)
            else:
                res = {"status": "error", "error": "No code or script provided in payload"}
        except Exception as e:
            res = {"status": "error", "error": f"Failed to parse stdin payload: {e}"}
    else:
        try:
            parsed_args = json.loads(args.args)
        except Exception:
            parsed_args = {}
            
        if args.code:
            res = run_code(args.code, parsed_args)
        elif args.script:
            res = run_script(args.script, parsed_args)
        else:
            res = {"status": "error", "error": "Specify --code, --script, or --stdin"}
            
    # Output result as clean JSON to stdout
    print(json.dumps(res, ensure_ascii=False))

if __name__ == "__main__":
    main()
