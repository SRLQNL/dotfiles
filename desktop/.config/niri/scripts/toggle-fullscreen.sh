#!/bin/bash
set -euo pipefail

WINDOW_INFO=$(niri msg --json focused-window 2>/dev/null)
if [[ -z "$WINDOW_INFO" ]]; then exit 1; fi

niri msg action fullscreen-window
