#!/usr/bin/env python3
"""
Unit tests for Google Jules DAG Workflow Engine (scripts/workflow_engine.py).
"""

import os
import sys
import unittest
import tempfile
import json

sys.path.insert(0, os.path.dirname(__file__))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

try:
    from workflow_engine import DAGWorkflowEngine, WorkflowTask, load_workflow
except ImportError:
    from scripts.workflow_engine import DAGWorkflowEngine, WorkflowTask, load_workflow


class TestWorkflowEngine(unittest.TestCase):

    def test_load_workflow_json_and_yaml(self):
        spec_dict = {
            "name": "Test Workflow",
            "repo": "owner/repo",
            "tasks": [
                {"id": "t1", "prompt": "hello"}
            ]
        }
        # Test JSON string loading
        loaded = load_workflow(json.dumps(spec_dict))
        self.assertEqual(loaded["name"], "Test Workflow")

        # Test file loading
        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as f:
            json.dump(spec_dict, f)
            f.flush()
            temp_path = f.name

        try:
            loaded_file = load_workflow(temp_path)
            self.assertEqual(len(loaded_file["tasks"]), 1)
        finally:
            if os.path.exists(temp_path):
                os.remove(temp_path)

    def test_dag_validation_and_topological_sorting(self):
        spec = {
            "name": "Linear Workflow",
            "repo": "owner/repo",
            "tasks": [
                {"id": "c", "prompt": "step c", "depends_on": ["b"]},
                {"id": "a", "prompt": "step a", "depends_on": []},
                {"id": "b", "prompt": "step b", "depends_on": ["a"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        order = engine.validate()
        self.assertEqual(order, ["a", "b", "c"])

        waves = engine.get_execution_waves()
        self.assertEqual(waves, [["a"], ["b"], ["c"]])

    def test_parallel_execution_waves(self):
        # A and B are independent roots. C depends on A and B. D depends on C.
        spec = {
            "name": "Diamond Workflow",
            "repo": "owner/repo",
            "tasks": [
                {"id": "task_a", "prompt": "do a"},
                {"id": "task_b", "prompt": "do b"},
                {"id": "task_c", "prompt": "do c", "depends_on": ["task_a", "task_b"]},
                {"id": "task_d", "prompt": "do d", "depends_on": ["task_c"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        waves = engine.get_execution_waves()
        self.assertEqual(len(waves), 3)
        self.assertEqual(set(waves[0]), {"task_a", "task_b"})
        self.assertEqual(waves[1], ["task_c"])
        self.assertEqual(waves[2], ["task_d"])

    def test_cycle_detection(self):
        # A -> B -> C -> A
        spec = {
            "name": "Cyclic Workflow",
            "repo": "owner/repo",
            "tasks": [
                {"id": "node_a", "prompt": "a", "depends_on": ["node_c"]},
                {"id": "node_b", "prompt": "b", "depends_on": ["node_a"]},
                {"id": "node_c", "prompt": "c", "depends_on": ["node_b"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        with self.assertRaises(RuntimeError) as ctx:
            engine.validate()
        self.assertIn("cycle", str(ctx.exception).lower())

    def test_missing_dependency(self):
        spec = {
            "name": "Broken Workflow",
            "repo": "owner/repo",
            "tasks": [
                {"id": "task1", "prompt": "p1", "depends_on": ["ghost_task"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        with self.assertRaises(ValueError) as ctx:
            engine.validate()
        self.assertIn("non-existent task", str(ctx.exception))

    def test_variable_interpolation(self):
        spec = {
            "name": "Param Workflow",
            "repo": "owner/my-repo",
            "base_branch": "develop",
            "vars": {
                "version": "2.5.0",
                "component": "auth_service"
            },
            "tasks": [
                {"id": "t1", "prompt": "build ${workflow.vars.component} v${workflow.vars.version}"},
                {"id": "t2", "prompt": "verify ${tasks.t1.session_id} on ${workflow.base_branch}", "depends_on": ["t1"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        engine.tasks["t1"].session_id = "998877"

        res1 = engine.interpolate(engine.tasks["t1"].prompt)
        self.assertEqual(res1, "build auth_service v2.5.0")

        res2 = engine.interpolate(engine.tasks["t2"].prompt)
        self.assertEqual(res2, "verify 998877 on develop")

    def test_condition_evaluation(self):
        spec = {
            "name": "Condition Test",
            "repo": "owner/repo",
            "tasks": [
                {"id": "parent_ok", "prompt": "ok"},
                {"id": "parent_fail", "prompt": "fail"},
                {"id": "child_on_success", "prompt": "sub", "depends_on": ["parent_ok"], "condition": "on_success"},
                {"id": "child_on_fail", "prompt": "sub", "depends_on": ["parent_fail"], "condition": "on_failure"},
                {"id": "child_always", "prompt": "cleanup", "depends_on": ["parent_fail"], "condition": "always"},
                {"id": "child_any", "prompt": "any", "depends_on": ["parent_ok", "parent_fail"], "condition": "any_success"}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        engine.tasks["parent_ok"].status = "COMPLETED"
        engine.tasks["parent_fail"].status = "FAILED"

        self.assertTrue(engine.evaluate_condition(engine.tasks["child_on_success"]))
        self.assertTrue(engine.evaluate_condition(engine.tasks["child_on_fail"]))
        self.assertTrue(engine.evaluate_condition(engine.tasks["child_always"]))
        self.assertTrue(engine.evaluate_condition(engine.tasks["child_any"]))

        # Check negative cases
        engine.tasks["parent_ok"].status = "FAILED"
        self.assertFalse(engine.evaluate_condition(engine.tasks["child_on_success"]))

    def test_dry_run_execution(self):
        spec = {
            "name": "Full Dry Run",
            "repo": "owner/repo",
            "settings": {"max_parallel": 2},
            "tasks": [
                {"id": "step1", "prompt": "implement step 1"},
                {"id": "step2a", "prompt": "implement step 2a", "depends_on": ["step1"]},
                {"id": "step2b", "prompt": "implement step 2b", "depends_on": ["step1"]},
                {"id": "step3", "prompt": "finalize", "depends_on": ["step2a", "step2b"]}
            ]
        }
        engine = DAGWorkflowEngine(spec)
        res = engine.execute(dry_run=True)
        self.assertTrue(res["success"])
        self.assertEqual(len(res["tasks"]), 4)
        for tid, tinfo in res["tasks"].items():
            self.assertEqual(tinfo["status"], "COMPLETED")
            self.assertTrue(tinfo["session_id"].startswith(f"dry-run-{tid}"))

if __name__ == '__main__':
    unittest.main()
