#!/bin/bash
set -euo pipefail

WINDOW_INFO=$(niri msg --json focused-window 2>/dev/null)
if [[ -z "$WINDOW_INFO" ]]; then exit 1; fi

TILE_W=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[0] // 0')
TILE_H=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[1] // 0')
OUTPUT_INFO=$(niri msg --json focused-output 2>/dev/null || true)
OUTPUT_W=$(echo "$OUTPUT_INFO" | jq -r '.logical.width // 0')
OUTPUT_H=$(echo "$OUTPUT_INFO" | jq -r '.logical.height // 0')

if (( OUTPUT_W > 0 && OUTPUT_H > 0 && $(printf "%.0f" "$TILE_W") == OUTPUT_W && $(printf "%.0f" "$TILE_H") == OUTPUT_H )); then
    niri msg action fullscreen-window
    niri msg action set-column-width "100%"
    niri msg action reset-window-height
else
    niri msg action fullscreen-window
fi
