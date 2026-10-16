#!/usr/bin/env python3
import sys
import os
import json
import subprocess

def send_response(message):
    sys.stdout.write(json.dumps(message) + "\n")
    sys.stdout.flush()

def handle_initialize(msg_id, params):
    send_response({
        "jsonrpc": "2.0",
        "id": msg_id,
        "result": {
            "protocolVersion": "2024-11-05",
            "capabilities": {
                "tools": {}
            },
            "serverInfo": {
                "name": "jules-gate",
                "version": "3.4.0"
            }
        }
    })

def handle_tools_list(msg_id, params):
    tools = [
        {
            "name": "jules_dispatch",
            "description": "Dispatches remote session via jules remote new.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "repo": {"type": "string"},
                    "prompt": {"type": "string"}
                },
                "required": ["repo", "prompt"]
            }
        },
        {
            "name": "jules_wait",
            "description": "Waits token-free using jules_poll_wait.sh.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "timeout": {"type": "integer"},
                    "interactive": {"type": "boolean"}
                },
                "required": ["session_id", "timeout"]
            }
        },
        {
            "name": "jules_verify",
            "description": "Runs worktree_gate.sh in isolated worktree.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "base_branch": {"type": "string"},
                    "sandbox": {"type": "boolean"},
                    "retry_flaky": {"type": "integer"},
                    "skip_ci": {"type": "boolean"}
                },
                "required": ["session_id", "base_branch"]
            }
        },
        {
            "name": "jules_merge",
            "description": "Runs jules-gate merge.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "base_branch": {"type": "string"},
                    "delete_remote": {"type": "boolean"},
                    "skip_ci": {"type": "boolean"}
                },
                "required": ["session_id", "base_branch"]
            }
        },
        {
            "name": "jules_pr",
            "description": "Verifies session in isolated worktree, pushes review branch, and opens a GitHub PR via jules-gate pr.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "base_branch": {"type": "string"},
                    "skip_ci": {"type": "boolean"},
                    "title": {"type": "string"},
                    "auto_merge": {"type": "boolean"}
                },
                "required": ["session_id"]
            }
        },
        {
            "name": "jules_pr_merge",
            "description": "Runs local tests on branch, merges open GitHub PR into base_branch via jules-gate pr-merge, and syncs local workspace.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "branch_or_session_id": {"type": "string"},
                    "base_branch": {"type": "string"},
                    "skip_ci": {"type": "boolean"}
                },
                "required": ["branch_or_session_id"]
            }
        },
        {
            "name": "jules_review_branch",
            "description": "Dispatches a Mode 2 EULIS code review of a branch relative to base_branch via jules-gate review-branch.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "branch_or_session_id": {"type": "string"},
                    "base_branch": {"type": "string"},
                    "repo": {"type": "string"}
                },
                "required": ["branch_or_session_id"]
            }
        },
        {
            "name": "jules_inspect",
            "description": "Extracts question using jules_api.py inspect.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"}
                },
                "required": ["session_id"]
            }
        },
        {
            "name": "jules_interact",
            "description": "Sends feedback using jules_api.py interact.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"},
                    "message": {"type": "string"}
                },
                "required": ["session_id", "message"]
            }
        },
        {
            "name": "jules_auto_answer",
            "description": "Runs jules_api.py auto-answer.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "session_id": {"type": "string"}
                },
                "required": ["session_id"]
            }
        },
        {
            "name": "jules_status",
            "description": "Runs jules-gate status.",
            "inputSchema": {
                "type": "object",
                "properties": {}
            }
        }
    ]
    send_response({
        "jsonrpc": "2.0",
        "id": msg_id,
        "result": {
            "tools": tools
        }
    })

def handle_tools_call(msg_id, params):
    name = params.get("name")
    args = params.get("arguments", {})
    
    cmd = []
    
    script_dir = os.path.dirname(os.path.realpath(__file__))
    plugin_root = os.path.dirname(script_dir)
    jules_gate = os.path.join(plugin_root, "bin", "jules-gate")
    jules_api = os.path.join(script_dir, "jules_api.py")
    jules_poll_wait = os.path.join(script_dir, "jules_poll_wait.sh")
    worktree_gate = os.path.join(script_dir, "worktree_gate.sh")
    
    if name == "jules_dispatch":
        cmd = ["jules", "remote", "new", "--repo", args["repo"]]
    elif name == "jules_wait":
        cmd = [jules_poll_wait, args["session_id"], "--timeout", str(args["timeout"])]
        if args.get("interactive"):
            cmd.append("--interactive")
    elif name == "jules_verify":
        cmd = [worktree_gate, args["session_id"], args["base_branch"]]
        if args.get("sandbox"):
            cmd.append("--sandbox")
        if args.get("retry_flaky"):
            cmd.extend(["--retry-flaky", str(args["retry_flaky"])])
        if args.get("skip_ci"):
            cmd.append("--skip-ci")
    elif name == "jules_merge":
        cmd = [jules_gate, "merge", args["session_id"], args["base_branch"]]
        if args.get("delete_remote"):
            cmd.append("--delete-remote")
        if args.get("skip_ci"):
            cmd.append("--skip-ci")
    elif name == "jules_pr":
        cmd = [jules_gate, "pr", args["session_id"]]
        if args.get("base_branch"):
            cmd.append(args["base_branch"])
        if args.get("skip_ci"):
            cmd.append("--skip-ci")
        if args.get("title"):
            cmd.extend(["--title", args["title"]])
        if args.get("auto_merge"):
            cmd.append("--auto-merge")
    elif name == "jules_pr_merge":
        cmd = [jules_gate, "pr-merge", args["branch_or_session_id"]]
        if args.get("base_branch"):
            cmd.append(args["base_branch"])
        if args.get("skip_ci"):
            cmd.append("--skip-ci")
    elif name == "jules_review_branch":
        cmd = [jules_gate, "review-branch", args["branch_or_session_id"]]
        if args.get("base_branch"):
            cmd.append(args["base_branch"])
        if args.get("repo"):
            cmd.extend(["--repo", args["repo"]])
    elif name == "jules_inspect":
        cmd = ["python3", jules_api, "inspect", args["session_id"]]
    elif name == "jules_interact":
        cmd = ["python3", jules_api, "interact", args["session_id"], args["message"]]
    elif name == "jules_auto_answer":
        cmd = ["python3", jules_api, "auto-answer", args["session_id"]]
    elif name == "jules_status":
        cmd = [jules_gate, "status"]
    else:
        send_response({
            "jsonrpc": "2.0",
            "id": msg_id,
            "error": {
                "code": -32601,
                "message": f"Method {name} not found"
            }
        })
        return

    try:
        if name == "jules_dispatch":
            prompt = args["prompt"]
            result = subprocess.run(cmd, input=prompt, capture_output=True, text=True, check=False)
        else:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
        output = result.stdout + result.stderr
        send_response({
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "content": [{"type": "text", "text": output}],
                "isError": result.returncode != 0
            }
        })
    except Exception as e:
        send_response({
            "jsonrpc": "2.0",
            "id": msg_id,
            "result": {
                "content": [{"type": "text", "text": str(e)}],
                "isError": True
            }
        })

def main():
    while True:
        line = sys.stdin.readline()
        if not line:
            break
        
        try:
            req = json.loads(line.strip())
        except json.JSONDecodeError:
            continue
            
        method = req.get("method")
        msg_id = req.get("id")
        params = req.get("params", {})
        
        if method == "initialize":
            handle_initialize(msg_id, params)
        elif method == "notifications/initialized":
            pass # Acknowledge cleanly
        elif method == "ping":
            send_response({
                "jsonrpc": "2.0",
                "id": msg_id,
                "result": {}
            })
        elif method == "tools/list":
            handle_tools_list(msg_id, params)
        elif method == "tools/call":
            handle_tools_call(msg_id, params)
        elif msg_id:
            send_response({
                "jsonrpc": "2.0",
                "id": msg_id,
                "error": {
                    "code": -32601,
                    "message": f"Method {method} not found"
                }
            })

if __name__ == "__main__":
    main()
