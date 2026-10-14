import os
import sys

sys.path.insert(0, os.path.dirname(__file__))
import jules_api  # noqa: E402


def _inspect(monkeypatch, steps):
    monkeypatch.setattr(jules_api, "make_request", lambda *a, **k: {"task": {"activitySteps": steps}})
    return jules_api.inspect_session("s1")


def _agent(text, requires):
    return {"id": "a", "agentActivity": {"agentMessaged": {"text": text, "requiresUserResponse": requires}}}


def test_open_question_is_interactive(monkeypatch):
    r = _inspect(monkeypatch, [_agent("work", False), _agent("Is this ok?", True)])
    assert r["is_interactive"] is True and r["question"] == "Is this ok?"


def test_question_followed_by_agent_progress_only_is_still_interactive(monkeypatch):
    steps = [_agent("Is this ok?", True), {"id": "p", "agentActivity": {"planStepProgressUpdated": {}}}]
    assert _inspect(monkeypatch, steps)["is_interactive"] is True


def test_answered_question_is_not_interactive(monkeypatch):
    steps = [_agent("Is this ok?", True), {"id": "u", "userActivity": {"feedbackGiven": {}}},
             {"id": "p", "agentActivity": {"devBoxStarted": {}}}]
    r = _inspect(monkeypatch, steps)
    assert r["is_interactive"] is False and r["auto_answerable"] is False


def test_no_steps(monkeypatch):
    r = _inspect(monkeypatch, [])
    assert r["is_interactive"] is False and r["question"] == "" and r["total_steps"] == 0


def test_only_user_steps(monkeypatch):
    r = _inspect(monkeypatch, [{"id": "u", "userActivity": {"feedbackGiven": {}}}])
    assert r["is_interactive"] is False


def test_old_answered_question_then_new_question_is_interactive(monkeypatch):
    steps = [_agent("first?", True), {"id": "u", "userActivity": {"feedbackGiven": {}}},
             {"id": "p", "agentActivity": {"devBoxStarted": {}}}, _agent("second?", True)]
    r = _inspect(monkeypatch, steps)
    assert r["is_interactive"] is True and r["question"] == "second?"


def test_non_blocking_agent_message_after_answer_is_not_interactive(monkeypatch):
    steps = [_agent("first?", True), {"id": "u", "userActivity": {"feedbackGiven": {}}}, _agent("done, thanks", False)]
    r = _inspect(monkeypatch, steps)
    assert r["is_interactive"] is False and r["question"] == "done, thanks"


def test_agent_message_without_flag_is_not_interactive(monkeypatch):
    assert _inspect(monkeypatch, [{"id": "a", "agentActivity": {"agentMessaged": {"text": "hi"}}}])["is_interactive"] is False


def test_task_without_wrapper_key(monkeypatch):
    monkeypatch.setattr(jules_api, "make_request", lambda *a, **k: {"activitySteps": [_agent("q?", True)]})
    assert jules_api.inspect_session("s")["is_interactive"] is True
