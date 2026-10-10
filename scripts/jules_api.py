#!/usr/bin/env python3
"""
jules_api.py - Direct bridge to Google Jules / AIDA REST API.
Enables inspecting activity streams, extracting interactive questions,
and sending user feedback directly into running Jules Cloud VMs.
"""

import os
import sys
import json
import base64
import subprocess
import urllib.request
import urllib.error
import ssl
import re

COMMON_BOILERPLATE_PATTERNS = [
    r"should i (?:open|create|file|submit) a (?:pr|pull request)",
    r"would you like me to (?:open|create|file|submit) a (?:pr|pull request)",
    r"would you like (?:me to )?(?:make )?(?:any|further|other)? ?(?:further|other)? ?(?:changes|adjustments|modifications)",
    r"should i (?:make|proceed with) (?:any|further)? ?(?:changes|adjustments)",
    r"let me know if you would like (?:me to )?(?:make )?(?:any|further|other)? ?(?:changes|adjustments)",
    r"do you want me to (?:open|create|file) a (?:pr|pull request)",
    r"is there anything else you would like me to",
    r"would you like me to proceed",
    r"please let me know if you(?: would like| want) me to",
]

DEFAULT_AUTO_ANSWER = (
    "Everything looks good. No further changes or pull request needed. "
    "Please finalize and complete the task directly without asking follow-up questions."
)

def evaluate_auto_answer(question):
    """Determine whether question matches boilerplate review sign-off patterns."""
    if not question:
        return False, None
    q_clean = question.strip().lower()
    for pattern in COMMON_BOILERPLATE_PATTERNS:
        if re.search(pattern, q_clean):
            return True, DEFAULT_AUTO_ANSWER
    return False, None

AIDA_BASE_URL = os.environ.get("JULES_API_BASE_URL", "https://aida.googleapis.com/v1/swebot")

def get_oauth_token():
    """Retrieve Google OAuth access token for Jules."""
    # 1. Environment variable override
    env_token = os.environ.get("JULES_API_TOKEN")
    if env_token:
        return env_token.strip()

    # 2. macOS Keychain
    try:
        raw = subprocess.check_output(
            ["security", "find-generic-password", "-s", "jules-cli", "-w"],
            stderr=subprocess.DEVNULL
        ).decode("utf-8").strip()
        if raw.startswith("go-keyring-base64:"):
            raw = raw[len("go-keyring-base64:"):]
        token_data = json.loads(base64.b64decode(raw).decode("utf-8"))
        return token_data.get("access_token")
    except Exception:
        pass

    # 3. File cache fallback
    cache_path = os.path.expanduser("~/.jules/auth.json")
    if os.path.exists(cache_path):
        try:
            with open(cache_path, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data.get("access_token")
        except Exception:
            pass

    return None

def make_request(path, method="GET", payload=None):
    """Execute authenticated HTTPS request against Google Jules AIDA backend."""
    token = get_oauth_token()
    if not token:
        raise RuntimeError("No Jules OAuth token found in environment, keychain, or auth cache.")

    ctx = ssl._create_unverified_context()
    url = f"{AIDA_BASE_URL}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, context=ctx) as resp:
        content = resp.read().decode("utf-8")
        return json.loads(content) if content else {}

def inspect_session(session_id):
    """Inspect session activity stream and return interactive question if present."""
    path = f"tasks/{session_id}/activities"
    res = make_request(path, method="GET")
    steps = res.get("activitySteps", [])

    is_interactive = False
    latest_question = ""
    step_id = ""

    for step in reversed(steps):
        agent_msg = step.get("agentActivity", {}).get("agentMessaged", {})
        if agent_msg:
            is_interactive = agent_msg.get("requiresUserResponse", False)
            latest_question = agent_msg.get("text", "")
            step_id = step.get("id", "")
            break

    auto_answerable, suggested_answer = evaluate_auto_answer(latest_question)

    return {
        "session_id": session_id,
        "is_interactive": is_interactive,
        "question": latest_question,
        "step_id": step_id,
        "total_steps": len(steps),
        "auto_answerable": auto_answerable if is_interactive else False,
        "suggested_answer": suggested_answer if is_interactive else None
    }

def send_interact(session_id, feedback_text):
    """Send user feedback directly to Jules Cloud VM to resume execution."""
    path = f"tasks/{session_id}:interact"
    payload = {
        "taskId": str(session_id),
        "userActivity": {
            "feedbackGiven": {
                "feedback": feedback_text
            }
        }
    }
    return make_request(path, method="POST", payload=payload)

def main():
    if len(sys.argv) < 3:
        print("Usage: jules_api.py <inspect|interact|auto-answer> <session_id> [message_or_file]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]
    session_id = sys.argv[2]

    try:
        if cmd == "inspect":
            data = inspect_session(session_id)
            if "--json" in sys.argv:
                print(json.dumps(data, indent=2))
            else:
                print("==========================================================")
                print(f" [Jules Gate API] Session Inspection: {session_id}")
                print("==========================================================")
                print(f"  Interactive State: {'YES (Awaiting User Response)' if data['is_interactive'] else 'NO'}")
                if data["is_interactive"]:
                    print(f"  Auto-Answerable:   {'YES (Boilerplate review prompt)' if data['auto_answerable'] else 'NO (Substantive decision)'}")
                if data["question"]:
                    print("  Jules Question / Prompt:")
                    print("  --------------------------------------------------------")
                    for line in data["question"].splitlines():
                        print(f"  {line}")
                    print("  --------------------------------------------------------")
                print(f"  Total Activity Steps: {data['total_steps']}")
                print("==========================================================")
            sys.exit(0 if not data["is_interactive"] else 10)

        elif cmd == "interact":
            if len(sys.argv) < 4:
                print("Error: Message or file path required for interact command.", file=sys.stderr)
                sys.exit(1)
            raw_input = sys.argv[3]
            if os.path.isfile(raw_input):
                with open(raw_input, "r", encoding="utf-8") as f:
                    feedback_text = f.read()
            else:
                feedback_text = raw_input

            send_interact(session_id, feedback_text)
            print(f"✅ Successfully dispatched feedback to Jules Cloud VM for session {session_id}.")
            print("   The cloud session has resumed execution.")
            sys.exit(0)

        elif cmd == "auto-answer":
            data = inspect_session(session_id)
            if not data["is_interactive"]:
                print(f"Session {session_id} is not in an interactive state.", file=sys.stderr)
                sys.exit(1)
            if data["auto_answerable"]:
                ans = data["suggested_answer"]
                send_interact(session_id, ans)
                print(f"🤖 [AUTO-ANSWER] Recognized boilerplate review prompt for session {session_id}.")
                print(f"   Dispatched automated completion feedback to Jules Cloud VM: '{ans}'")
                sys.exit(0)
            else:
                print(f"⚡ [SUBSTANTIVE PROMPT] Session {session_id} cannot be auto-answered.", file=sys.stderr)
                print(f"   Question: {data['question']}", file=sys.stderr)
                sys.exit(10)

        else:
            print(f"Unknown command: {cmd}", file=sys.stderr)
            sys.exit(1)

    except Exception as e:
        print(f"API Error: {e}", file=sys.stderr)
        sys.exit(1)

if __name__ == "__main__":
    main()
