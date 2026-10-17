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
import time
import random

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

# Without a timeout a stalled connection (laptop sleep, network change) or a Keychain prompt blocks forever.
HTTP_TIMEOUT_SECS = 30
KEYCHAIN_TIMEOUT_SECS = 10

def get_ssl_context():
    """Create strict TLS context with certifi fallback for macOS compatibility."""
    try:
        import certifi
        return ssl.create_default_context(cafile=certifi.where())
    except (ImportError, Exception):
        return ssl.create_default_context()

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
            stderr=subprocess.DEVNULL,
            timeout=KEYCHAIN_TIMEOUT_SECS
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
    """Execute authenticated HTTPS request against Google Jules AIDA backend with retry and jitter."""
    token = get_oauth_token()
    if not token:
        raise RuntimeError("No Jules OAuth token found in environment, keychain, or auth cache.")

    ctx = get_ssl_context()
    url = f"{AIDA_BASE_URL}/{path.lstrip('/')}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }

    data = json.dumps(payload).encode("utf-8") if payload is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    
    max_retries = 3
    base_delay = 1.0
    max_delay = 10.0
    
    for attempt in range(max_retries + 1):
        try:
            with urllib.request.urlopen(req, context=ctx, timeout=HTTP_TIMEOUT_SECS) as resp:
                content = resp.read().decode("utf-8")
                return json.loads(content) if content else {}
        except urllib.error.HTTPError as e:
            if e.code == 401 and attempt == 0:
                try:
                    subprocess.run(["jules", "remote", "list", "--repo"], capture_output=True, timeout=10)
                    token = get_oauth_token()
                    if token:
                        headers["Authorization"] = f"Bearer {token}"
                        req = urllib.request.Request(url, data=data, headers=headers, method=method)
                        continue
                except Exception:
                    pass
            if e.code in (429, 500, 502, 503, 504) and attempt < max_retries:
                delay = min(max_delay, base_delay * (2 ** attempt))
                jitter = random.uniform(0, 0.1 * delay)
                sleep_time = delay + jitter
                print(f"HTTP {e.code} encountered. Retrying in {sleep_time:.2f} seconds... (Attempt {attempt + 1}/{max_retries})", file=sys.stderr)
                time.sleep(sleep_time)
            else:
                raise
        except Exception as e:
            if attempt < max_retries:
                delay = min(max_delay, base_delay * (2 ** attempt))
                jitter = random.uniform(0, 0.1 * delay)
                sleep_time = delay + jitter
                print(f"Network error encountered: {e}. Retrying in {sleep_time:.2f} seconds... (Attempt {attempt + 1}/{max_retries})", file=sys.stderr)
                time.sleep(sleep_time)
            else:
                raise

def inspect_session(session_id):
    """Inspect session activity stream and return rich operational status, interactive questions, failure details, patches, and stall detection."""
    path = f"tasks/{session_id}"
    res = make_request(path, method="GET")
    task = res.get("task", res)
    steps = task.get("activitySteps", [])

    raw_status = task.get("taskStatus")
    swebot_status = task.get("swebotTaskStatus")

    is_interactive = False
    latest_question = ""
    step_id = ""

    failure_type = None
    failure_message = None
    is_suspended = False

    answered = False
    for step in reversed(steps):
        agent_act = step.get("agentActivity", {})
        if step.get("userActivity"):
            answered = True
            continue

        if not failure_type and "taskFailed" in agent_act:
            failed_info = agent_act["taskFailed"]
            failure_type = failed_info.get("failureType", "FAILURE_TYPE_UNSPECIFIED")
            failure_message = failed_info.get("userVisibleFailureMessage", "")

        if not is_suspended and "taskSuspended" in agent_act:
            is_suspended = True

        agent_msg = agent_act.get("agentMessaged", {})
        if agent_msg and not latest_question:
            is_interactive = agent_msg.get("requiresUserResponse", False) and not answered
            latest_question = agent_msg.get("text", "")
            step_id = step.get("id", "")

    # Extract patch information
    patch_files = []
    top_patch = task.get("patch", "")
    if top_patch:
        for line in top_patch.splitlines():
            if line.startswith("diff --git a/"):
                parts = line.split(" ")
                if len(parts) >= 4:
                    fname = parts[3].lstrip("b/")
                    if fname not in patch_files:
                        patch_files.append(fname)
    if not patch_files:
        for step in reversed(steps):
            prog = step.get("agentActivity", {}).get("planStepProgressUpdated", {})
            cum_patch = prog.get("cumulativePatch", {})
            for diff_v2 in cum_patch.get("fileDiffsV2", []):
                fname = diff_v2.get("fileAfter", {}).get("path") or diff_v2.get("fileBefore", {}).get("path")
                if fname and fname not in patch_files:
                    patch_files.append(fname)
            if patch_files:
                break

    # Stall detection
    is_stalled = False
    stall_minutes = 0
    if steps:
        latest_step = steps[-1]
        create_time_str = latest_step.get("createdAt") or latest_step.get("createTime")
        if create_time_str:
            try:
                from datetime import datetime, timezone
                # Trim sub-microsecond precision (e.g. 9 digits to 6 digits) for datetime.fromisoformat
                clean_ts = re.sub(r'(\.\d{6})\d+Z?', r'\1', create_time_str).rstrip("Z")
                step_dt = datetime.fromisoformat(clean_ts).replace(tzinfo=timezone.utc)
                now_dt = datetime.now(timezone.utc)
                elapsed_secs = (now_dt - step_dt).total_seconds()
                stall_minutes = max(0, int(elapsed_secs / 60))
            except Exception:
                pass
        is_terminal = str(raw_status).upper() in ("COMPLETED", "FAILED") or bool(failure_type) or is_suspended
        if not is_terminal and stall_minutes >= 15:
            is_stalled = True

    # Normalize operational status
    if is_interactive:
        normalized_status = "AWAITING_USER"
    elif str(raw_status).upper() == "COMPLETED":
        normalized_status = "COMPLETED"
    elif str(raw_status).upper() == "FAILED" or failure_type:
        normalized_status = "FAILED"
    elif is_suspended:
        normalized_status = "SUSPENDED"
    elif is_stalled:
        normalized_status = "STALLED"
    elif str(raw_status).upper() in ("PLANNING", "IN_PROGRESS", "ACTIVE"):
        normalized_status = str(raw_status).upper()
    else:
        normalized_status = str(swebot_status or "UNKNOWN")

    auto_answerable, suggested_answer = evaluate_auto_answer(latest_question)

    return {
        "session_id": session_id,
        "task_status": normalized_status,
        "raw_status": raw_status,
        "swebot_status": swebot_status,
        "is_interactive": is_interactive,
        "is_suspended": is_suspended,
        "is_stalled": is_stalled,
        "stall_minutes": stall_minutes,
        "failure_type": failure_type,
        "failure_message": failure_message,
        "has_patch": len(patch_files) > 0,
        "patch_files_count": len(patch_files),
        "patch_files": patch_files,
        "question": latest_question,
        "step_id": step_id,
        "total_steps": len(steps),
        "auto_answerable": auto_answerable if is_interactive else False,
        "suggested_answer": suggested_answer if is_interactive else None
    }

DEFAULT_SENDER_LABEL = "[sent via jules-gate]"


def sender_label():
    """Prefix for messages sent through `interact`. Jules shows them as written by the account owner, so the
    message says that an orchestrator sent it. JULES_GATE_SENDER_LABEL overrides it; an empty value turns it off."""
    return os.environ.get("JULES_GATE_SENDER_LABEL", DEFAULT_SENDER_LABEL)


def labelled(feedback_text):
    label = sender_label()
    return f"{label} {feedback_text}" if label else feedback_text


REPAIR_WARNING = (
    "⚠️  This session is already Completed. A repair round in the same session restarts the VM and replays the whole\n"
    "   history: in practice it was several times slower than the first attempt. Prefer a fresh, narrow task, or fix a\n"
    "   small problem locally. (Sending anyway.)"
)


def repair_warning(session_id):
    """The warning text when the session is Completed (a repair round), else None. Never raises."""
    try:
        res = make_request(f"tasks/{session_id}", method="GET")
        task = res.get("task", res)
        if str(task.get("taskStatus", "")).upper() == "COMPLETED":
            return REPAIR_WARNING
    except Exception:
        pass
    return None


def send_interact(session_id, feedback_text):
    """Send user feedback directly to Jules Cloud VM to resume execution."""
    path = f"tasks/{session_id}:interact"
    payload = {
        "taskId": str(session_id),
        "userActivity": {
            "feedbackGiven": {
                "feedback": labelled(feedback_text)
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
                print(f"  Operational Status: {data['task_status']}")
                print(f"  Interactive State:  {'YES (Awaiting User Response)' if data['is_interactive'] else 'NO'}")
                if data["is_interactive"]:
                    print(f"  Auto-Answerable:    {'YES (Boilerplate review prompt)' if data['auto_answerable'] else 'NO (Substantive decision)'}")
                if data["is_suspended"]:
                    print("  Suspension Status:  YES (DevBox suspended by backend)")
                if data["is_stalled"]:
                    print(f"  Stall Detection:    YES (No activity steps for {data['stall_minutes']} minutes!)")
                if data["failure_type"]:
                    print(f"  Failure Type:       {data['failure_type']}")
                    if data["failure_message"]:
                        print(f"  Failure Message:    {data['failure_message']}")
                if data["has_patch"]:
                    print(f"  Cumulative Patch:   YES ({data['patch_files_count']} files modified)")
                    for pf in data["patch_files"][:5]:
                        print(f"    - {pf}")
                    if data["patch_files_count"] > 5:
                        print(f"    ... and {data['patch_files_count'] - 5} more files")
                if data["question"]:
                    print("  Jules Question / Prompt:")
                    print("  --------------------------------------------------------")
                    for line in data["question"].splitlines():
                        print(f"  {line}")
                    print("  --------------------------------------------------------")
                print(f"  Total Activity Steps: {data['total_steps']}")
                print("==========================================================")

            if data["is_interactive"]:
                sys.exit(10)
            elif data["task_status"] == "FAILED":
                sys.exit(2)
            elif data["is_stalled"]:
                sys.exit(12)
            else:
                sys.exit(0)

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

            warning = repair_warning(session_id)
            if warning:
                print(warning, file=sys.stderr)
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
