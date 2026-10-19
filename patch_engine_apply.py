import re
import os

with open("scripts/workflow_engine.py", "r") as f:
    content = f.read()

# Add state persistence methods
state_methods = """    def save_state(self, state_file: str) -> None:
        if not state_file:
            return
        os.makedirs(os.path.dirname(os.path.abspath(state_file)), exist_ok=True)
        
        workflow_status = "IN_PROGRESS"
        all_terminal = all(t.status in ("COMPLETED", "FAILED", "SKIPPED") for t in self.tasks.values())
        if all_terminal:
            all_success = all(t.status in ("COMPLETED", "SKIPPED") for t in self.tasks.values())
            workflow_status = "COMPLETED" if all_success else "FAILED"
            
        state = {
            "workflow_name": self.name,
            "updated_at": datetime.datetime.now(datetime.timezone.utc).isoformat(),
            "status": workflow_status,
            "tasks": {
                tid: {
                    "id": tid,
                    "status": t.status,
                    "session_id": t.session_id,
                    "branch": t.branch,
                    "error": t.error,
                    "start_time": getattr(t, "start_time", None),
                    "end_time": getattr(t, "end_time", None)
                }
                for tid, t in self.tasks.items()
            }
        }
        
        temp_file = state_file + ".tmp"
        with open(temp_file, "w", encoding="utf-8") as f:
            import json
            json.dump(state, f, indent=2)
        os.replace(temp_file, state_file)

    def load_state(self, state_file: str) -> None:
        if not os.path.isfile(state_file):
            return
        with open(state_file, "r", encoding="utf-8") as f:
            import json
            try:
                state = json.load(f)
            except json.JSONDecodeError:
                return
                
        for tid, tinfo in state.get("tasks", {}).items():
            if tid in self.tasks:
                task = self.tasks[tid]
                task.status = tinfo.get("status", "PENDING")
                task.session_id = tinfo.get("session_id")
                task.branch = tinfo.get("branch")
                task.error = tinfo.get("error")
                task.start_time = tinfo.get("start_time")
                task.end_time = tinfo.get("end_time")

"""

content = content.replace("    def validate(self) -> List[str]:", state_methods + "    def validate(self) -> List[str]:")

execute_sig_old = """    def execute(
        self,
        dry_run: bool = False,
        max_parallel: Optional[int] = None,
        progress_callback: Optional[Callable[[WorkflowTask], None]] = None
    ) -> Dict[str, Any]:
        \"\"\"Executes the workflow graph with parallel workers and dynamic unblocking.\"\"\"
        self.validate()
        parallelism = max_parallel or self.max_parallel"""

execute_sig_new = """    def execute(
        self,
        dry_run: bool = False,
        max_parallel: Optional[int] = None,
        progress_callback: Optional[Callable[[WorkflowTask], None]] = None,
        resume: bool = False,
        state_file: Optional[str] = None
    ) -> Dict[str, Any]:
        \"\"\"Executes the workflow graph with parallel workers and dynamic unblocking.\"\"\"
        self.validate()
        parallelism = max_parallel or self.max_parallel

        if resume and state_file:
            self.load_state(state_file)
            
        all_already_done = all(t.status in ("COMPLETED", "SKIPPED") for t in self.tasks.values())
        if resume and all_already_done:
            import sys
            print("Workflow already complete. Exiting.", file=sys.stderr)
            return {
                "workflow": self.name,
                "success": True,
                "total_duration_secs": 0.0,
                "tasks": {
                    tid: {
                        "status": t.status,
                        "session_id": t.session_id,
                        "branch": t.branch,
                        "error": t.error,
                        "duration_secs": round(t.duration_secs, 2)
                    }
                    for tid, t in self.tasks.items()
                }
            }

        if state_file:
            self.save_state(state_file)"""

content = content.replace(execute_sig_old, execute_sig_new)

loop_old = """                ready = ts.get_ready()
                for tid in ready:
                    task = self.tasks[tid]
                    if not self.evaluate_condition(task):
                        task.status = "SKIPPED"
                        ts.done(tid)
                        if progress_callback:
                            progress_callback(task)
                        continue

                    task.status = "RUNNING"
                    if progress_callback:
                        progress_callback(task)"""

loop_new = """                ready = ts.get_ready()
                for tid in ready:
                    task = self.tasks[tid]
                    
                    if getattr(self, "resume_flag", resume) and task.status in ("COMPLETED", "SKIPPED"):
                        ts.done(tid)
                        continue
                        
                    if not self.evaluate_condition(task):
                        task.status = "SKIPPED"
                        if state_file:
                            self.save_state(state_file)
                        ts.done(tid)
                        if progress_callback:
                            progress_callback(task)
                        continue

                    task.status = "RUNNING"
                    task.start_time = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    if state_file:
                        self.save_state(state_file)
                    if progress_callback:
                        progress_callback(task)"""

content = content.replace(loop_old, loop_new)

comp_old = """                for fut in done:
                    tid = in_flight.pop(fut)
                    task = self.tasks[tid]
                    try:
                        fut.result()
                        task.status = "COMPLETED"
                    except Exception as exc:
                        task.status = "FAILED"
                        task.error = str(exc)

                    ts.done(tid)
                    if progress_callback:
                        progress_callback(task)"""

comp_new = """                for fut in done:
                    tid = in_flight.pop(fut)
                    task = self.tasks[tid]
                    task.end_time = datetime.datetime.now(datetime.timezone.utc).isoformat()
                    try:
                        fut.result()
                        task.status = "COMPLETED"
                    except Exception as exc:
                        task.status = "FAILED"
                        task.error = str(exc)

                    if state_file:
                        self.save_state(state_file)
                    ts.done(tid)
                    if progress_callback:
                        progress_callback(task)"""

content = content.replace(comp_old, comp_new)

end_old = """        total_duration = time.time() - start_time
        all_success = all(t.status in ("COMPLETED", "SKIPPED") for t in self.tasks.values())

        return {"""

end_new = """        total_duration = time.time() - start_time
        all_success = all(t.status in ("COMPLETED", "SKIPPED") for t in self.tasks.values())
        
        if state_file:
            self.save_state(state_file)

        return {"""

content = content.replace(end_old, end_new)

# Add graph generation
graph_code = """
    def generate_graph(self, fmt: str = "mermaid", state_file: Optional[str] = None) -> str:
        self.validate()
        
        if state_file:
            self.load_state(state_file)
            
        if fmt == "ascii":
            return self._generate_ascii_graph()
        elif fmt == "html":
            mermaid_code = self._generate_mermaid_graph()
            return f\"\"\"<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Jules Workflow DAG: {self.name}</title>
  <style>
    body {{ font-family: sans-serif; margin: 2rem; background: #fff; color: #333; }}
    @media (prefers-color-scheme: dark) {{
      body {{ background: #1e1e1e; color: #ddd; }}
    }}
    .mermaid-container {{ text-align: center; margin-top: 2rem; }}
  </style>
</head>
<body>
  <h2>Jules Workflow: {self.name}</h2>
  <div class="mermaid-container">
    <div class="mermaid">
{mermaid_code}
    </div>
  </div>
  <script type="module">
    import mermaid from 'https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.esm.min.mjs';
    mermaid.initialize({{ startOnLoad: true, theme: window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'default' }});
  </script>
</body>
</html>\"\"\"
        else: # mermaid
            return self._generate_mermaid_graph()

    def _generate_mermaid_graph(self) -> str:
        lines = ["graph TD"]
        
        for tid, task in self.tasks.items():
            label = f"{tid}"
            if task.condition != "on_success":
                label += f" [{task.condition}]"
            lines.append(f"    {tid}(\\"{label}\\")")
            
            if task.status == "COMPLETED":
                lines.append(f"    style {tid} fill:#d4edda,stroke:#28a745")
            elif task.status == "FAILED":
                lines.append(f"    style {tid} fill:#f8d7da,stroke:#dc3545")
            elif task.status == "SKIPPED":
                lines.append(f"    style {tid} fill:#e2e3e5,stroke:#6c757d")
            elif task.status == "RUNNING":
                lines.append(f"    style {tid} fill:#cce5ff,stroke:#004085")
                
        for tid, task in self.tasks.items():
            for dep in task.depends_on:
                if task.condition == "on_success":
                    lines.append(f"    {dep} --> {tid}")
                else:
                    lines.append(f"    {dep} -->|{task.condition}| {tid}")
                    
        return "\\n".join(lines)

    def _generate_ascii_graph(self) -> str:
        waves = self.get_execution_waves()
        lines = []
        lines.append(f"Workflow: {self.name}")
        lines.append("=" * (len(self.name) + 10))
        
        for wave_idx, wave in enumerate(waves):
            lines.append(f"Wave {wave_idx + 1}:")
            for tid in wave:
                task = self.tasks[tid]
                status_icon = {
                    "COMPLETED": "[✅]",
                    "FAILED": "[❌]",
                    "SKIPPED": "[⏭️]",
                    "RUNNING": "[🚀]",
                    "PENDING": "[⏳]"
                }.get(task.status, "[ ]")
                
                cond_str = f" (condition: {task.condition})" if task.condition != "on_success" else ""
                dep_str = f" (depends on: {', '.join(task.depends_on)})" if task.depends_on else ""
                
                lines.append(f"  {status_icon} {tid}{cond_str}{dep_str}")
        
        return "\\n".join(lines)

"""

content = content.replace("    def _execute_single_task(", graph_code + "    def _execute_single_task(")


# CLI Parsing update
usage_str = """Usage: workflow_engine.py <validate|run|waves|graph> <workflow_file> [options]"""
content = re.sub(r'Usage: workflow_engine\.py <validate\|run\|waves> <workflow_file> \[options\]', usage_str, content)

help_str = """Google Jules DAG Workflow Engine
Commands:
  validate <file>           Validate workflow DAG syntax, task dependencies, and acyclicity.
  waves <file>              Compute and print parallel execution waves.
  run <file> [options]      Execute workflow DAG with parallel worker pooling.
  graph <file> [options]    Generate visual DAG graph representation.

Options for run:
  --dry-run                 Simulate execution without calling Google Jules remote API.
  --parallel <N>            Throttle concurrency to N parallel tasks.
  --json                    Output execution summary strictly in JSON format.
  --resume                  Resume execution from previous state.
  --state-file <path>       Customize path for workflow state file.

Options for graph:
  --format <fmt>            Format of the graph (mermaid, ascii, html). Default: mermaid.
  --state-file <path>       Style nodes by status from the specified state file.
  --output <file>           Write graph output to a file instead of stdout.
"""

content = re.sub(r'Google Jules DAG Workflow Engine.*?Output execution summary strictly in JSON format\.\n', help_str, content, flags=re.DOTALL)


graph_cmd_logic = """    elif cmd == "graph":
        fmt = "mermaid"
        if "--format" in sys.argv:
            try:
                fmt_idx = sys.argv.index("--format") + 1
                fmt = sys.argv[fmt_idx]
            except IndexError:
                pass
                
        state_file = None
        if "--state-file" in sys.argv:
            try:
                sf_idx = sys.argv.index("--state-file") + 1
                state_file = sys.argv[sf_idx]
            except IndexError:
                pass
                
        output_file = None
        if "--output" in sys.argv:
            try:
                out_idx = sys.argv.index("--output") + 1
                output_file = sys.argv[out_idx]
            except IndexError:
                pass
                
        try:
            graph_output = engine.generate_graph(fmt=fmt, state_file=state_file)
            if output_file:
                with open(output_file, "w", encoding="utf-8") as f:
                    f.write(graph_output)
                print(f"Graph written to {output_file}")
            else:
                print(graph_output)
            sys.exit(0)
        except Exception as e:
            print(f"❌ Graph generation failed: {e}", file=sys.stderr)
            sys.exit(1)

    elif cmd == "run":"""

content = content.replace('    elif cmd == "run":', graph_cmd_logic)

run_logic_old = """        res = engine.execute(dry_run=dry_run, max_parallel=parallel, progress_callback=on_progress)"""

run_logic_new = """        resume = "--resume" in sys.argv
        state_file = None
        if "--state-file" in sys.argv:
            try:
                sf_idx = sys.argv.index("--state-file") + 1
                state_file = sys.argv[sf_idx]
            except IndexError:
                pass
        else:
            state_file = f".jules/workflows/{engine.name}.state.json"

        if resume and not json_output:
            print(f"                      Resuming from state file: {state_file}")
            
        res = engine.execute(dry_run=dry_run, max_parallel=parallel, progress_callback=on_progress, resume=resume, state_file=state_file)"""

content = content.replace(run_logic_old, run_logic_new)

with open("scripts/workflow_engine.py", "w") as f:
    f.write(content)
