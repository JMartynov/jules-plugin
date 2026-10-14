import os
import sys

import pytest

sys.path.insert(0, os.path.dirname(__file__))
import jules_api  # noqa: E402


@pytest.fixture
def sent(monkeypatch):
    calls = []
    monkeypatch.setattr(jules_api, "make_request", lambda path, method="GET", payload=None: calls.append((path, method, payload)) or {})
    monkeypatch.delenv("JULES_GATE_SENDER_LABEL", raising=False)
    return calls


def _text(calls):
    return calls[-1][2]["userActivity"]["feedbackGiven"]["feedback"]


def test_message_is_labelled_by_default(sent):
    jules_api.send_interact("1", "Yes, go on.")
    assert _text(sent) == "[sent via jules-gate] Yes, go on."


def test_label_can_be_changed(sent, monkeypatch):
    monkeypatch.setenv("JULES_GATE_SENDER_LABEL", "[Claude orchestrator]")
    jules_api.send_interact("1", "ok")
    assert _text(sent) == "[Claude orchestrator] ok"


def test_empty_label_turns_it_off(sent, monkeypatch):
    monkeypatch.setenv("JULES_GATE_SENDER_LABEL", "")
    jules_api.send_interact("1", "ok")
    assert _text(sent) == "ok"


def test_payload_shape_is_unchanged(sent):
    jules_api.send_interact("42", "x")
    path, method, payload = sent[-1]
    assert path == "tasks/42:interact" and method == "POST"
    assert payload["taskId"] == "42" and set(payload["userActivity"]) == {"feedbackGiven"}


@pytest.mark.parametrize("status,warns", [("COMPLETED", True), ("completed", True), ("AWAITING_USER_FEEDBACK", False),
                                          ("IN_PROGRESS", False), ("PLANNING", False)])
def test_repair_warning_only_for_completed_sessions(monkeypatch, status, warns):
    monkeypatch.setattr(jules_api, "make_request", lambda *a, **k: {"task": {"taskStatus": status}})
    assert (jules_api.repair_warning("1") is not None) is warns


def test_repair_warning_never_raises(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("network")
    monkeypatch.setattr(jules_api, "make_request", boom)
    assert jules_api.repair_warning("1") is None


def test_warning_text_names_the_alternative():
    assert "fresh, narrow task" in jules_api.REPAIR_WARNING and "locally" in jules_api.REPAIR_WARNING
