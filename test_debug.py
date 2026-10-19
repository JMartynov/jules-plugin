from scripts.workflow_engine import DAGWorkflowEngine
import tempfile
spec = {
    "name": "Resume Test",
    "repo": "owner/repo",
    "tasks": [
        {"id": "t1", "prompt": "p1"},
        {"id": "t2", "prompt": "p2", "depends_on": ["t1"]}
    ]
}
engine = DAGWorkflowEngine(spec)
engine.tasks["t1"].status = "COMPLETED"
engine.tasks["t1"].session_id = "resume-session"

with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as f:
    state_file = f.name
    
engine.save_state(state_file)
engine_resume = DAGWorkflowEngine(spec)
res = engine_resume.execute(dry_run=True, resume=True, state_file=state_file)
print(res)
