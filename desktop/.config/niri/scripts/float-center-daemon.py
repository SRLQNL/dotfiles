#!/usr/bin/env python3
"""Center floating windows that open fresh. Fix tiling windows with wrong size/position."""

import fcntl
import heapq
import json
import os
import subprocess
import sys
import threading
import time

QUIET_DELAY_SECONDS = 0.08

handled = set()
pending = {}
pending_heap = []
pending_cv = threading.Condition()

# Tiling windows that need to be maximized and scrolled into view on open.
FORCE_MAXIMIZE = {
    ("org.telegram.desktop", "Просмотр медиа"),
}


def take_lock():
    runtime_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    lock_path = os.path.join(
        runtime_dir, f"niri-float-center-daemon-{os.getuid()}.lock"
    )
    lock_file = open(lock_path, "w")
    try:
        fcntl.flock(lock_file, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        sys.exit(0)
    return lock_file


def run(args):
    subprocess.run(
        ["niri", "msg", "action"] + args,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def actions_for_window(win):
    win_id = str(win["id"])
    is_floating = win.get("is_floating", False)
    app_id = win.get("app_id", "")
    title = win.get("title", "")

    if not is_floating and (app_id, title) in FORCE_MAXIMIZE:
        return (
            ["focus-window", "--id", win_id],
            ["set-column-width", "100%"],
            ["reset-window-height"],
            ["center-column"],
        )

    if is_floating:
        return (["center-window", "--id", win_id],)

    return None


def schedule(win_id, actions):
    deadline = time.monotonic() + QUIET_DELAY_SECONDS
    with pending_cv:
        if win_id in handled:
            return
        pending[win_id] = (deadline, actions)
        heapq.heappush(pending_heap, (deadline, win_id))
        pending_cv.notify()


def cancel(win_id):
    with pending_cv:
        pending.pop(win_id, None)
        handled.discard(win_id)
        pending_cv.notify()


def action_worker():
    while True:
        with pending_cv:
            while not pending_heap:
                pending_cv.wait()

            deadline, win_id = pending_heap[0]
            delay = deadline - time.monotonic()
            if delay > 0:
                pending_cv.wait(delay)
                continue

            heapq.heappop(pending_heap)
            current = pending.get(win_id)
            if current is None or current[0] != deadline:
                continue

            _, actions = pending.pop(win_id)
            handled.add(win_id)

        for action in actions:
            run(action)


# Keep the descriptor alive so the flock remains held.
lock_file = take_lock()
threading.Thread(target=action_worker, daemon=True).start()

proc = subprocess.Popen(
    ["niri", "msg", "--json", "event-stream"],
    stdout=subprocess.PIPE,
    text=True,
)

for line in proc.stdout:
    line = line.strip()
    if not line:
        continue
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue

    if "WindowOpenedOrChanged" in event:
        win = event["WindowOpenedOrChanged"]["window"]
        win_id = win["id"]
        with pending_cv:
            already_handled = win_id in handled
        if already_handled:
            continue

        actions = actions_for_window(win)
        if actions:
            schedule(win_id, actions)
        else:
            cancel(win_id)

    elif "WindowClosed" in event:
        win_id = event["WindowClosed"].get("id")
        if win_id:
            cancel(win_id)
