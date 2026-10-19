with open("rules/AGENTS.md", "r") as f:
    content = f.read()
if "--resume" not in content:
    content = content.replace("`workflow_engine.py run <file>`", "`workflow_engine.py run <file>` (supports `--resume` with state files via `.jules/workflows/<workflow_name>.state.json` or `--state-file`)")
    content = content.replace("workflow_engine.py waves <file>", "workflow_engine.py waves <file>\n- `workflow_engine.py graph <file>`: Generate visual DAG graph (mermaid, ascii, html).")
with open("rules/AGENTS.md", "w") as f:
    f.write(content)

with open("skills/jules-task-controller/SKILL.md", "r") as f:
    content = f.read()
if "--resume" not in content:
    content = content.replace("`jules-gate workflow run <file>`", "`jules-gate workflow run <file>` (supports `--resume` and state file checkpointing)")
    content = content.replace("jules-gate workflow waves <file>", "jules-gate workflow waves <file>\n- `jules-gate workflow graph <file>`: Visualize workflow DAG (formats: mermaid, ascii, html)")
with open("skills/jules-task-controller/SKILL.md", "w") as f:
    f.write(content)

with open("tests/test_invariants.sh", "r") as f:
    content = f.read()
content = content.replace("Ran 8 tests", "Ran 11 tests")
content = content.replace("jules_workflow_validate\" \"$SCRIPTS_DIR/jules_mcp.py\" && grep -q \"jules_workflow_run\" \"$SCRIPTS_DIR/jules_mcp.py\"", "jules_workflow_validate\" \"$SCRIPTS_DIR/jules_mcp.py\" && grep -q \"jules_workflow_run\" \"$SCRIPTS_DIR/jules_mcp.py\" && grep -q \"jules_workflow_graph\" \"$SCRIPTS_DIR/jules_mcp.py\"")
content = content.replace("workflow <validate|run|waves>", "workflow <validate|run|waves|graph>")
with open("tests/test_invariants.sh", "w") as f:
    f.write(content)
