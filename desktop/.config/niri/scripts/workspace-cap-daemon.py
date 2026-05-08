#!/usr/bin/env python3
"""Keep niri workspaces sane across one-output and two-output layouts."""

import json
import os
import subprocess
import time

MAX_WORKSPACES = 5
PRIMARY_OUTPUT = os.environ.get("NIRI_PRIMARY_OUTPUT", "")
SECONDARY_OUTPUT = os.environ.get("NIRI_SECONDARY_OUTPUT", "")
MERGE_PREFIXES = ("b",)
PRIMARY_WS_NAMES = frozenset(str(i) for i in range(1, MAX_WORKSPACES + 1))


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
    if not isinstance(name, str):
        return False
    return name.startswith(MERGE_PREFIXES) or name in PRIMARY_WS_NAMES


def primary_name(index):
    return str(index)


def secondary_name(index):
    return f"b{index}"


def sorted_workspaces(output=None):
    workspaces = msg("workspaces") or []
    if output is not None:
        workspaces = [ws for ws in workspaces if ws.get("output") == output]
    return sorted(workspaces, key=lambda ws: ws.get("idx", 0))


def restore_focus(focused_window_id):
    if focused_window_id is not None:
        action("focus-window", "--id", str(focused_window_id))


def ensure_output_workspaces(output, name_fn):
    windows = msg("windows") or []
    focused = next((win for win in windows if win.get("is_focused")), None)
    focused_window_id = focused.get("id") if focused else None

    for index in range(1, MAX_WORKSPACES + 1):
        name = name_fn(index)
        all_workspaces = msg("workspaces") or []
        existing = next((ws for ws in all_workspaces if ws.get("name") == name), None)

        if existing:
            if existing.get("output") != output:
                action("move-workspace-to-monitor", "--reference", name, output)
            action("move-workspace-to-index", "--reference", name, str(index))
            continue

        action("focus-monitor", output)
        output_workspaces = sorted_workspaces(output)
        candidate = next((ws for ws in output_workspaces if ws.get("idx") == index), None)
        if candidate and candidate.get("name") is None:
            action("set-workspace-name", "--workspace", str(index), name)
        else:
            action("focus-workspace", str(index))
            action("set-workspace-name", name)

        action("move-workspace-to-index", "--reference", name, str(index))

    restore_focus(focused_window_id)


def ensure_secondary_workspaces():
    ensure_output_workspaces(SECONDARY_OUTPUT, secondary_name)


def ensure_primary_workspaces():
    ensure_output_workspaces(PRIMARY_OUTPUT, primary_name)


def cleanup_single_output():
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
            action("unset-workspace-name", str(ws["idx"]))


def output_enabled(outputs, name):
    if name not in outputs:
        return False
    return outputs[name].get("current_mode") is not None


def reconcile():
    outputs = msg("outputs") or {}
    both_on = (
        SECONDARY_OUTPUT
        and output_enabled(outputs, PRIMARY_OUTPUT)
        and output_enabled(outputs, SECONDARY_OUTPUT)
    )
    if both_on:
        ensure_primary_workspaces()
        ensure_secondary_workspaces()
    else:
        cleanup_single_output()


def main():
    reconcile()
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
        reconcile()


if __name__ == "__main__":
    main()
