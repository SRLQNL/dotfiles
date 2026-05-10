#!/usr/bin/env python3
"""Keep niri workspaces sane across one-output and two-output layouts."""

import json
import os
import subprocess
import threading
import time

MAX_WORKSPACES = 5
PRIMARY_OUTPUT = os.environ.get("NIRI_PRIMARY_OUTPUT", "")
SECONDARY_OUTPUT = os.environ.get("NIRI_SECONDARY_OUTPUT", "")
MERGE_PREFIXES = ("b",)

SETTLE_DELAY = 1.5   # seconds of quiet after topology change before reconciling
COOLDOWN = 2.5       # seconds to ignore workspace events after our own reconcile


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
            action("unset-workspace-name", name)


def get_active_output(outputs):
    if output_enabled(outputs, PRIMARY_OUTPUT):
        return PRIMARY_OUTPUT
    for name, o in outputs.items():
        if o.get("current_mode") is not None:
            return name
    return None


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
        active = get_active_output(outputs)
        if active:
            ensure_output_workspaces(active, primary_name)


def main():
    reconcile()

    proc = subprocess.Popen(
        ["niri", "msg", "--json", "event-stream"],
        stdout=subprocess.PIPE,
        text=True,
    )

    prev_both_on = None
    settle_timer = [None]
    last_reconcile = [time.monotonic()]
    lock = threading.Lock()

    def run_reconcile():
        with lock:
            last_reconcile[0] = time.monotonic()
        reconcile()

    def arm_timer(delay):
        with lock:
            if settle_timer[0]:
                settle_timer[0].cancel()
            t = threading.Timer(delay, run_reconcile)
            t.daemon = True
            t.start()
            settle_timer[0] = t

    for line in proc.stdout:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue

        if "WorkspacesChanged" not in event and "OutputsChanged" not in event and "OutputChanged" not in event:
            continue

        now = time.monotonic()

        current_both_on = prev_both_on
        if "WorkspacesChanged" in event:
            ws_list = event["WorkspacesChanged"]["workspaces"]
            out_set = {w["output"] for w in ws_list}
            current_both_on = bool(
                SECONDARY_OUTPUT
                and PRIMARY_OUTPUT in out_set
                and SECONDARY_OUTPUT in out_set
            )

        with lock:
            is_transition = (prev_both_on is not None and current_both_on != prev_both_on)
            prev_both_on = current_both_on
            since_last = now - last_reconcile[0]

        if is_transition:
            arm_timer(SETTLE_DELAY)


if __name__ == "__main__":
    main()
