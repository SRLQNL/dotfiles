#!/bin/bash

WINDOW_INFO=$(niri msg --json focused-window 2>/dev/null)
if [[ -z "$WINDOW_INFO" ]]; then exit 1; fi

TILE_W=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[0] // 0')
TILE_H=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[1] // 0')

if (( $(printf "%.0f" "$TILE_W") == 1920 && $(printf "%.0f" "$TILE_H") == 1080 )); then
    niri msg action fullscreen-window
    niri msg action set-column-width "100%"
    niri msg action reset-window-height
else
    niri msg action fullscreen-window
fi
