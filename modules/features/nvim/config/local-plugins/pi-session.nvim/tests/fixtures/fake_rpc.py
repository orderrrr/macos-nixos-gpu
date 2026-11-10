#!/usr/bin/env python3
"""An offline protocol peer: validate isolation, mutate only the copy, emit fixtures."""

import hashlib
import json
import os
import signal
from pathlib import Path
import sys
import time


def emit(value):
    sys.stdout.write(json.dumps(value, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def main():
    mode, record_path = sys.argv[1:3]
    arguments = sys.argv[3:]
    snapshot = Path(arguments[arguments.index("--session") + 1])
    directory = Path(arguments[arguments.index("--session-dir") + 1])
    assert snapshot.parent == directory
    assert arguments[:2] == ["--mode", "rpc"]
    assert arguments[6:] == [
        "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-themes",
        "--no-context-files", "--no-tools", "--no-approve", "--offline",
    ]
    request = json.loads(sys.stdin.readline())
    assert request == {"type": "get_entries", "id": request["id"]}
    record = {
        "snapshot": str(snapshot),
        "directory": str(directory),
        "digest": hashlib.sha256(snapshot.read_bytes()).hexdigest(),
        "directory_mode": directory.stat().st_mode & 0o777,
        "file_mode": snapshot.stat().st_mode & 0o777,
        "cwd": os.getcwd(),
        "agent_dir": os.environ.get("PI_CODING_AGENT_DIR"),
        "npm_upper": os.environ.get("NPM_CONFIG_PREFIX"),
        "npm_lower": os.environ.get("npm_config_prefix"),
        "requests": [request],
        "pid": os.getpid(),
    }
    Path(record_path).write_text(json.dumps(record))
    snapshot.write_text("private copy was migrated\n")
    (directory / "startup-extra.jsonl").write_text("private startup output\n")
    response = {
        "type": "response", "command": "get_entries", "id": request["id"],
        "success": True,
        "data": {"entries": [{"id": "archive", "text": "café 雪\u2028tail\u2029end"}],
                 "leafId": "archive"},
    }
    if mode == "early":
        return
    if mode in {"timeout", "stubborn"}:
        if mode == "stubborn":
            signal.signal(signal.SIGTERM, signal.SIG_IGN)
        time.sleep(30)
        return
    if mode == "stderr":
        sys.stderr.write("PRIVATE STDERR" * 6000)
        sys.stderr.flush()
    elif mode == "oversize":
        sys.stdout.write("x" * 4096)
        sys.stdout.flush()
    elif mode == "malformed":
        sys.stdout.write("{PRIVATE INVALID JSON}\n")
        sys.stdout.flush()
    elif mode == "blank":
        sys.stdout.write("\n")
        sys.stdout.flush()
    elif mode == "events_cap":
        for _ in range(100):
            emit({"type": "agent_start"})
    elif mode == "unterminated":
        sys.stdout.write(json.dumps(response))
        sys.stdout.flush()
        return
    elif mode == "failed":
        response.update(success=False, error="PRIVATE SESSION CONTENT")
        emit(response)
    elif mode == "wrongcommand":
        response["command"] = "get_messages"
        emit(response)
    elif mode == "baddata":
        response["data"] = {"entries": {}, "leafId": None}
        emit(response)
    elif mode == "missing_leaf":
        del response["data"]["leafId"]
        emit(response)
    elif mode == "null":
        response["data"] = {"entries": [], "leafId": None}
        emit(response)
    elif mode == "unrelated":
        response["id"] = "other"
        emit(response)
        return
    else:
        emit({"type": "agent_start"})
        emit(dict(response, id="unrelated", success=False))
        emit({"type": "extension_ui_request", "id": "notice", "method": "notify"})
        for method in ["select", "confirm", "input", "editor"]:
            emit({"type": "extension_ui_request", "id": method, "method": method})
            cancellation = json.loads(sys.stdin.readline())
            assert cancellation == {
                "type": "extension_ui_response", "id": method, "cancelled": True,
            }
            record["requests"].append(cancellation)
        Path(record_path).write_text(json.dumps(record))
        # Byte-at-a-time writes force UTF-8/CRLF fragmentation without treating
        # Unicode line separators as JSONL boundaries.
        encoded = (json.dumps(response, ensure_ascii=False) + "\r\n").encode()
        for byte in encoded:
            os.write(sys.stdout.fileno(), bytes([byte]))
            time.sleep(0.0005)
        if mode == "duplicate":
            emit(response)
    time.sleep(30)


if __name__ == "__main__":
    main()
