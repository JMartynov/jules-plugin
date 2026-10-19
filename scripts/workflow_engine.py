#!/usr/bin/env python3
"""
workflow_engine.py - Directed Acyclic Graph (DAG) Task Orchestrator for Google Jules.
Powered by Python standard library graphlib.TopologicalSorter with dynamic condition evaluation.
"""

import os
import sys
import json
import re
import time
import datetime
import graphlib
import subprocess
import concurrent.futures
from dataclasses import dataclass, field
from typing import Dict, List, Any, Optional, Callable

@dataclass
class WorkflowTask:
    id: str
    prompt: str = ""
    prompt_file: Optional[str] = None
    repo: Optional[str] = None
    base_branch: Optional[str] = None
    depends_on: List[str] = field(default_factory=list)
    condition: str = "on_success"  # on_success | on_failure | always | any_success
    verify: bool = True
    auto_merge: bool = False
    timeout: int = 30
    retry_flaky: int = 0
    sandbox: bool = False
    skip_ci: bool = True
    model_tier: str = "flash"
    status: str = "PENDING"  # PENDING, RUNNING, COMPLETED, FAILED, SKIPPED
    session_id: Optional[str] = None
    branch: Optional[str] = None
    error: Optional[str] = None
    duration_secs: float = 0.0

def load_workflow(path_or_str: str) -> dict:
    """Load workflow specification from a YAML or JSON file or raw string."""
    content = path_or_str
    if os.path.isfile(path_or_str):
        with open(path_or_str, "r", encoding="utf-8") as f:
            content = f.read()

    # 1. Try PyYAML if available
    try:
        import yaml
        parsed = yaml.safe_load(content)
        if isinstance(parsed, dict):
            return parsed
    except ImportError:
        pass
    except Exception:
        pass

    # 2. Try JSON parser
    try:
        parsed = json.loads(content)
        if isinstance(parsed, dict):
            return parsed
    except json.JSONDecodeError as err:
        raise ValueError(
            "Failed to parse workflow file as YAML or JSON.\n"
            "Ensure PyYAML is installed (pip install pyyaml) or file is formatted as valid JSON."
        ) from err

    raise ValueError("Workflow specification must be a dictionary/object at the root level.")

class DAGWorkflowEngine:
    def __init__(self, spec: Dict[str, Any], base_dir: str = "."):
        self.name = spec.get("name", "Jules DAG Workflow")
        self.description = spec.get("description", "")
        self.repo = spec.get("repo", "")
        self.base_branch = spec.get("base_branch", "main")
        self.vars = spec.get("vars", {})
        self.settings = spec.get("settings", {})
        self.max_parallel = int(self.settings.get("max_parallel", 3))
        self.base_dir = os.path.abspath(base_dir)
        self.tasks: Dict[str, WorkflowTask] = {}

        raw_tasks = spec.get("tasks", [])
        if not raw_tasks:
            raise ValueError("Workflow must contain a non-empty 'tasks' list.")

        for t in raw_tasks:
            tid = str(t.get("id", "")).strip()
            if not tid:
                raise ValueError("Every task in workflow must specify an 'id'.")
            if not re.match(r"^[a-zA-Z0-9_\-]+$", tid):
                raise ValueError(f"Task id '{tid}' contains invalid characters. Use alphanumeric, hyphens, or underscores.")
            if tid in self.tasks:
                raise ValueError(f"Duplicate task id '{tid}' detected in workflow.")

            task = WorkflowTask(
                id=tid,
                prompt=t.get("prompt", ""),
                prompt_file=t.get("prompt_file"),
                repo=t.get("repo", self.repo),
                base_branch=t.get("base_branch", self.base_branch),
                depends_on=[str(d).strip() for d in t.get("depends_on", [])],
                condition=t.get("condition", "on_success"),
                verify=bool(t.get("verify", True)),
                auto_merge=bool(t.get("auto_merge", False)),
                timeout=int(t.get("timeout", 30)),
                retry_flaky=int(t.get("retry_flaky", 0)),
                sandbox=bool(t.get("sandbox", self.settings.get("sandbox", False))),
                skip_ci=bool(t.get("skip_ci", self.settings.get("skip_ci", True))),
                model_tier=t.get("model_tier", "flash")
            )
            self.tasks[tid] = task

    def save_state(self, state_file: str) -> None:
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

    def validate(self) -> List[str]:
        """Validates acyclicity using TopologicalSorter and returns static topological order."""
        if hasattr(self, "_validated_order"):
            return self._validated_order
            
        ts = graphlib.TopologicalSorter()
        for tid, task in self.tasks.items():
            for dep in task.depends_on:
                if dep not in self.tasks:
                    raise ValueError(f"Task '{tid}' depends on non-existent task '{dep}'.")
                if dep == tid:
                    raise ValueError(f"Task '{tid}' cannot depend on itself.")
            ts.add(tid, *task.depends_on)
        try:
            order = tuple(ts.static_order())
            self._validated_order = list(order)
            return self._validated_order
        except graphlib.CycleError as e:
            cycle_path = " -> ".join(e.args[1])
            raise RuntimeError(f"Workflow contains a dependency cycle: {cycle_path}") from e

    def get_execution_waves(self) -> List[List[str]]:
        """Computes parallel execution waves (generations of independent tasks)."""
        self.validate()
        ts = graphlib.TopologicalSorter()
        for tid, task in self.tasks.items():
            ts.add(tid, *task.depends_on)
        ts.prepare()

        waves = []
        while ts.is_active():
            ready = ts.get_ready()
            if not ready:
                break
            waves.append(list(ready))
            for r in ready:
                ts.done(r)
        return waves

    def interpolate(self, text: str) -> str:
        """Interpolates ${tasks.<id>.<attr>} and ${workflow.vars.<key>} variables."""
        if not text:
            return ""

        pattern = re.compile(r"\$\{([a-zA-Z0-9_.]+)\}")

        ctx = {
            "workflow": {
                "name": self.name,
                "repo": self.repo,
                "base_branch": self.base_branch,
                "vars": self.vars
            },
            "tasks": {
                tid: {
                    "session_id": t.session_id or "",
                    "branch": t.branch or "",
                    "status": t.status,
                    "repo": t.repo or "",
                    "base_branch": t.base_branch or ""
                }
                for tid, t in self.tasks.items()
            },
            "env": dict(os.environ)
        }

        def repl(match):
            key_path = match.group(1).split(".")
            curr = ctx
            for part in key_path:
                if isinstance(curr, dict) and part in curr:
                    curr = curr[part]
                else:
                    return match.group(0)
            return str(curr)

        return pattern.sub(repl, text)

    def evaluate_condition(self, task: WorkflowTask) -> bool:
        """Evaluates whether task conditions are satisfied by completed parents."""
        if not task.depends_on:
            return True

        parent_statuses = [self.tasks[d].status for d in task.depends_on]
        all_terminal = all(s in ("COMPLETED", "FAILED", "SKIPPED") for s in parent_statuses)

        if not all_terminal:
            return False

        cond = task.condition.lower()
        if cond == "on_success":
            return all(s == "COMPLETED" for s in parent_statuses)
        elif cond == "on_failure":
            return any(s == "FAILED" for s in parent_statuses)
        elif cond == "always":
            return True
        elif cond == "any_success":
            return any(s == "COMPLETED" for s in parent_statuses)
        else:
            # Unknown condition: default to strict on_success
            return all(s == "COMPLETED" for s in parent_statuses)

    def execute(
        self,
        dry_run: bool = False,
        max_parallel: Optional[int] = None,
        progress_callback: Optional[Callable[[WorkflowTask], None]] = None,
        resume: bool = False,
        state_file: Optional[str] = None
    ) -> Dict[str, Any]:
        """Executes the workflow graph with parallel workers and dynamic unblocking."""
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
            self.save_state(state_file)

        ts = graphlib.TopologicalSorter()
        for tid, task in self.tasks.items():
            ts.add(tid, *task.depends_on)
        ts.prepare()

        start_time = time.time()

        with concurrent.futures.ThreadPoolExecutor(max_workers=parallelism) as executor:
            in_flight: Dict[concurrent.futures.Future, str] = {}

            while ts.is_active():
                ready = ts.get_ready()
                for tid in ready:
                    task = self.tasks[tid]
                    
                    if resume and task.status in ("COMPLETED", "SKIPPED"):
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
                        progress_callback(task)

                    fut = executor.submit(self._execute_single_task, task, dry_run)
                    in_flight[fut] = tid

                if not in_flight and not ts.is_active():
                    break
                elif not in_flight:
                    # we might have completed tasks that unblocked something, 
                    # but if there are no more tasks running and we still have active nodes, we might be stuck
                    # BUT with `resume`, we immediately marked some as done without submitting them.
                    # so ts.get_ready() could yield more in the next loop.
                    # Wait, if we continue to the top of the while loop, it'll fetch the next ready nodes!
                    continue

                done, _ = concurrent.futures.wait(
                    in_flight.keys(),
                    return_when=concurrent.futures.FIRST_COMPLETED
                )

                for fut in done:
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
                        progress_callback(task)

        total_duration = time.time() - start_time
        all_success = all(t.status in ("COMPLETED", "SKIPPED") for t in self.tasks.values())
        
        if state_file:
            self.save_state(state_file)

        return {
            "workflow": self.name,
            "success": all_success,
            "total_duration_secs": round(total_duration, 2),
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


    def generate_graph(self, fmt: str = "mermaid", state_file: Optional[str] = None) -> str:
        self.validate()
        
        if state_file:
            self.load_state(state_file)
            
        if fmt == "ascii":
            return self._generate_ascii_graph()
        elif fmt == "html":
            mermaid_code = self._generate_mermaid_graph()
            return f"""<!DOCTYPE html>
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
</html>"""
        else: # mermaid
            return self._generate_mermaid_graph()

    def _generate_mermaid_graph(self) -> str:
        lines = ["graph TD"]
        
        for tid, task in self.tasks.items():
            label = f"{tid}"
            if task.condition != "on_success":
                label += f" [{task.condition}]"
            lines.append(f"    {tid}(\"{label}\")")
            
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
                    
        return "\n".join(lines)

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
        
        return "\n".join(lines)

    def _execute_single_task(self, task: WorkflowTask, dry_run: bool = False) -> None:
        """Executes a single workflow task via Google Jules CLI and jules-gate."""
        t_start = time.time()

        # Resolve prompt
        prompt_content = task.prompt
        if task.prompt_file:
            pf = os.path.join(self.base_dir, task.prompt_file)
            if not os.path.isfile(pf):
                pf = task.prompt_file
            if os.path.isfile(pf):
                with open(pf, "r", encoding="utf-8") as f:
                    prompt_content = f.read()
            else:
                raise FileNotFoundError(f"Prompt file not found for task '{task.id}': {task.prompt_file}")

        interpolated_prompt = self.interpolate(prompt_content)

        if dry_run:
            time.sleep(0.2)
            task.session_id = f"dry-run-{task.id}"
            task.branch = f"jules/review-{task.session_id}"
            task.duration_secs = time.time() - t_start
            return

        # 1. Dispatch remote session
        if not task.repo:
            raise ValueError(f"Task '{task.id}' has no repo specified and no workflow repo was set.")

        dispatch_cmd = ["jules", "remote", "new", "--repo", task.repo]
        proc = subprocess.run(
            dispatch_cmd,
            input=interpolated_prompt,
            text=True,
            capture_output=True,
            check=False
        )
        if proc.returncode != 0:
            raise RuntimeError(f"jules remote new failed: {proc.stderr or proc.stdout}")

        # Extract session ID (e.g., Task created: 123456 or ID: 123456)
        match = re.search(r"(?:Task created:\s+|ID:\s+|session:\s+)(\d+)", proc.stdout + proc.stderr)
        if not match:
            # Fallback to pure digit sequence
            match = re.search(r"\b(\d{18,20})\b", proc.stdout + proc.stderr)
        if not match:
            raise RuntimeError(f"Could not extract Jules session ID from output:\n{proc.stdout}")

        task.session_id = match.group(1)
        task.branch = f"jules/review-{task.session_id}"

        # 2. Wait token-free using jules-gate wait
        script_dir = os.path.dirname(os.path.realpath(__file__))
        plugin_root = os.path.dirname(script_dir)
        jules_gate = os.path.join(plugin_root, "bin", "jules-gate")

        wait_cmd = [jules_gate, "wait", task.session_id, "--timeout", str(task.timeout), "--interactive"]
        w_res = subprocess.run(wait_cmd, capture_output=True, text=True, check=False)
        if w_res.returncode != 0:
            raise RuntimeError(f"jules-gate wait failed (exit code {w_res.returncode}):\n{w_res.stdout}\n{w_res.stderr}")

        # 3. Gated verification in isolated worktree
        if task.verify:
            verify_cmd = [jules_gate, "verify", task.session_id, task.base_branch]
            if task.sandbox:
                verify_cmd.append("--sandbox")
            if task.retry_flaky > 0:
                verify_cmd.extend(["--retry-flaky", str(task.retry_flaky)])
            if task.skip_ci:
                verify_cmd.append("--skip-ci")

            v_res = subprocess.run(verify_cmd, capture_output=True, text=True, check=False)
            if v_res.returncode != 0:
                raise RuntimeError(f"jules-gate verify failed:\n{v_res.stdout}\n{v_res.stderr}")

        # 4. Gated auto-merge
        if task.auto_merge:
            merge_cmd = [jules_gate, "merge", task.session_id, task.base_branch]
            if task.skip_ci:
                merge_cmd.append("--skip-ci")

            m_res = subprocess.run(merge_cmd, capture_output=True, text=True, check=False)
            if m_res.returncode != 0:
                raise RuntimeError(f"jules-gate merge failed:\n{m_res.stdout}\n{m_res.stderr}")

        task.duration_secs = time.time() - t_start

def main():
    if len(sys.argv) < 2:
        print("Usage: workflow_engine.py <validate|run|waves|graph> <workflow_file> [options]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd in ("-h", "--help", "help"):
        print("""Google Jules DAG Workflow Engine
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
""")
        sys.exit(0)

    if len(sys.argv) < 3:
        print(f"Error: Workflow file required for '{cmd}' command.", file=sys.stderr)
        sys.exit(1)

    file_path = sys.argv[2]
    try:
        spec = load_workflow(file_path)
        base_dir = os.path.dirname(os.path.abspath(file_path))
        engine = DAGWorkflowEngine(spec, base_dir=base_dir)
    except Exception as e:
        print(f"❌ Error loading workflow: {e}", file=sys.stderr)
        sys.exit(1)

    if cmd == "validate":
        try:
            order = engine.validate()
            waves = engine.get_execution_waves()
            print("==========================================================")
            print(f" [Jules DAG Workflow] Validation: {engine.name}")
            print("==========================================================")
            print(f"  Tasks:       {len(engine.tasks)}")
            print(f"  Concurrency: max_parallel={engine.max_parallel}")
            print(f"  Acyclicity:  ✅ PASSED (No dependency cycles detected)")
            print("\n  Execution Waves:")
            for idx, wave in enumerate(waves, start=1):
                tasks_str = ", ".join(wave)
                print(f"    Wave {idx}: [{tasks_str}] ({len(wave)} parallel task{'s' if len(wave) > 1 else ''})")
            print(f"\n  Topological Sequence: {' -> '.join(order)}")
            print("==========================================================")
            sys.exit(0)
        except Exception as e:
            print(f"❌ Validation failed: {e}", file=sys.stderr)
            sys.exit(1)

    elif cmd == "waves":
        waves = engine.get_execution_waves()
        for idx, wave in enumerate(waves, start=1):
            print(f"Wave {idx}: {wave}")
        sys.exit(0)

    elif cmd == "graph":
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

    elif cmd == "run":
        dry_run = "--dry-run" in sys.argv
        json_output = "--json" in sys.argv
        parallel = None
        if "--parallel" in sys.argv:
            try:
                p_idx = sys.argv.index("--parallel") + 1
                parallel = int(sys.argv[p_idx])
            except Exception:
                pass

        if not json_output:
            print("==========================================================")
            print(f" [Jules DAG Workflow] Running: {engine.name} {'(DRY RUN)' if dry_run else ''}")
            print("==========================================================")

        def on_progress(task: WorkflowTask):
            if not json_output:
                icon = {
                    "PENDING": "⏳",
                    "RUNNING": "🚀",
                    "COMPLETED": "✅",
                    "FAILED": "❌",
                    "SKIPPED": "⏭️ "
                }.get(task.status, "•")
                print(f"  {icon} [{task.status}] Task '{task.id}' (condition: {task.condition})")

        resume = "--resume" in sys.argv
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
            
        res = engine.execute(dry_run=dry_run, max_parallel=parallel, progress_callback=on_progress, resume=resume, state_file=state_file)

        if json_output:
            print(json.dumps(res, indent=2))
        else:
            print("==========================================================")
            print(f" Workflow Result: {'SUCCESS' if res['success'] else 'FAILED'}")
            print(f" Total Duration:  {res['total_duration_secs']}s")
            print(" Task Details:")
            for tid, tinfo in res["tasks"].items():
                err_str = f" Error: {tinfo['error']}" if tinfo.get("error") else ""
                print(f"   - {tid}: {tinfo['status']} ({tinfo['duration_secs']}s){err_str}")
            print("==========================================================")

        sys.exit(0 if res["success"] else 1)

    else:
        print(f"Unknown command '{cmd}'. Use validate, run, or waves.", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
