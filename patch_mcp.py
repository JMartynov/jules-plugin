import re

with open("scripts/jules_mcp.py", "r") as f:
    content = f.read()

# Add jules_workflow_graph to tools list
tool_list_addition = """        {
            "name": "jules_workflow_run",
            "description": "Executes workflow DAG with parallel worker pooling.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string"},
                    "dry_run": {"type": "boolean"},
                    "parallel": {"type": "integer"},
                    "json_output": {"type": "boolean"}
                },
                "required": ["file_path"]
            }
        },
        {
            "name": "jules_workflow_graph",
            "description": "Generate visual DAG graph representation of a workflow.",
            "inputSchema": {
                "type": "object",
                "properties": {
                    "file_path": {"type": "string"},
                    "format": {"type": "string"},
                    "output_file": {"type": "string"},
                    "state_file": {"type": "string"}
                },
                "required": ["file_path"]
            }
        }"""
        
content = re.sub(r'        \{\n            "name": "jules_workflow_run".*?\}\n        \}', tool_list_addition, content, flags=re.DOTALL)

# Add handler for jules_workflow_graph
handler_addition = """    elif name == "jules_workflow_run":
        cmd = ["python3", workflow_engine, "run", args["file_path"]]
        if args.get("dry_run"):
            cmd.append("--dry-run")
        if args.get("parallel"):
            cmd.extend(["--parallel", str(args["parallel"])])
        if args.get("json_output"):
            cmd.append("--json")
    elif name == "jules_workflow_graph":
        cmd = ["python3", workflow_engine, "graph", args["file_path"]]
        if args.get("format"):
            cmd.extend(["--format", args["format"]])
        if args.get("output_file"):
            cmd.extend(["--output", args["output_file"]])
        if args.get("state_file"):
            cmd.extend(["--state-file", args["state_file"]])"""
            
content = re.sub(r'    elif name == "jules_workflow_run":.*?cmd\.append\("--json"\)', handler_addition, content, flags=re.DOTALL)

with open("scripts/jules_mcp.py", "w") as f:
    f.write(content)
