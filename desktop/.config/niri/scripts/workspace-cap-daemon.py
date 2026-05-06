#!/usr/bin/env python3
"""Keep a single-output niri session capped to the first five workspaces."""

import json
import subprocess
import time

MAX_WORKSPACES = 5
MERGE_PREFIXES = ("b",)


def msg(*args):
    result = subprocess.run(
        ["niri", "msg", "--json", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        return None


def action(*args):
    subprocess.run(["niri", "msg", "action", *args], capture_output=True)


def target_index(idx):
    return ((idx - 1) % MAX_WORKSPACES) + 1


def should_unname(name):
    return isinstance(name, str) and name.startswith(MERGE_PREFIXES)


def cleanup():
    outputs = msg("outputs") or {}
    if len(outputs) != 1:
        return

    workspaces = msg("workspaces") or []
    windows = msg("windows") or []
    by_id = {ws["id"]: ws for ws in workspaces}

    focused_overflow = [
        ws for ws in workspaces
        if ws.get("is_focused") and ws.get("idx", 0) > MAX_WORKSPACES
    ]
    for ws in focused_overflow:
        action("focus-workspace", str(target_index(ws["idx"])))

    for window in windows:
        ws = by_id.get(window.get("workspace_id"))
        if not ws:
            continue
        idx = ws.get("idx", 0)
        if idx > MAX_WORKSPACES:
            action(
                "move-window-to-workspace",
                "--window-id",
                str(window["id"]),
                "--focus",
                "false",
                str(target_index(idx)),
            )

    for ws in workspaces:
        name = ws.get("name")
        if should_unname(name):
            action("unset-workspace-name", name)


def main():
    cleanup()
    proc = subprocess.Popen(
        ["niri", "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE,
        text=True,
    )

    last_cleanup = 0.0
    for line in proc.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        if not (
            "WorkspacesChanged" in event
            or "WindowsChanged" in event
            or "WindowClosed" in event
            or "OutputChanged" in event
            or "OutputsChanged" in event
        ):
            continue

        now = time.monotonic()
        if now - last_cleanup < 0.2:
            continue
        last_cleanup = now
        cleanup()


if __name__ == "__main__":
    main()
