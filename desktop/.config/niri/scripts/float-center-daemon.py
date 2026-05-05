#!/usr/bin/env python3
"""Center floating windows that open fresh. Fix tiling windows with wrong size/position."""

import subprocess
import json

seen = set()

# Tiling windows that need to be maximized and scrolled into view on open.
FORCE_MAXIMIZE = {
    ("org.telegram.desktop", "Просмотр медиа"),
}

def run(args):
    subprocess.run(["niri", "msg", "action"] + args, capture_output=True)

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
        is_floating = win.get("is_floating", False)
        app_id = win.get("app_id", "")
        title = win.get("title", "")

        if win_id not in seen:
            if not is_floating and (app_id, title) in FORCE_MAXIMIZE:
                run(["focus-window", "--id", str(win_id)])
                run(["set-column-width", "100%"])
                run(["reset-window-height"])
                run(["center-column"])
            elif is_floating:
                run(["center-window", "--id", str(win_id)])

        seen.add(win_id)

    elif "WindowClosed" in event:
        win_id = event["WindowClosed"].get("id")
        if win_id:
            seen.discard(win_id)
