#!/bin/bash
set -euo pipefail

WINDOW_INFO=$(niri msg --json focused-window 2>/dev/null)
WINDOW_ID=$(echo "$WINDOW_INFO" | jq -r '.id // empty')
if [[ -z "$WINDOW_ID" ]]; then exit 1; fi
OUTPUT_INFO=$(niri msg --json focused-output 2>/dev/null || true)
OUTPUT_W=$(echo "$OUTPUT_INFO" | jq -r '.logical.width // 1920')
OUTPUT_H=$(echo "$OUTPUT_INFO" | jq -r '.logical.height // 1080')

IS_FLOATING=$(echo "$WINDOW_INFO" | jq -r '.is_floating')
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/niri_float_col_${WINDOW_ID}"

TILE_W=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[0] // 0')
TILE_W_INT=$(printf "%.0f" "$TILE_W")
# window_size is the actual rendered size: fullscreen = full output, tiling = output-struts-gaps-panels
WIN_W=$(echo "$WINDOW_INFO" | jq -r '.layout.window_size[0] // 0')
WIN_H=$(echo "$WINDOW_INFO" | jq -r '.layout.window_size[1] // 0')

# Detect fullscreen via window_size == output size. tile_size is unreliable for this:
# when fullscreen niri may still report tile_size as the tiling-area size (output minus
# struts/gaps/panels), which equals a maximized-tiling window and causes false negatives.
if [[ "$IS_FLOATING" != "true" ]] \
    && (( OUTPUT_W > 0 && OUTPUT_H > 0 )) \
    && (( WIN_W == OUTPUT_W && WIN_H == OUTPUT_H )); then
    niri msg action fullscreen-window
    sleep 0.05
    # niri restores pre-fullscreen state: if window was floating before going
    # fullscreen, it returns to floating here. Always land in maximized tiling.
    IS_NOW_FLOATING=$(niri msg --json focused-window | jq -r '.is_floating')
    if [[ "$IS_NOW_FLOATING" == "true" ]]; then
        niri msg action move-window-to-tiling
        sleep 0.05
    fi
    niri msg action set-column-width "100%"
    niri msg action reset-window-height
    niri msg action center-column
    exit 0
fi

if [[ "$IS_FLOATING" == "true" ]]; then
    PREV_COL=$(cat "$STATE_FILE" 2>/dev/null)
    rm -f "$STATE_FILE"
    niri msg action move-window-to-tiling
    sleep 0.05
    niri msg action set-column-width "100%"
    niri msg action reset-window-height

    if [[ -n "$PREV_COL" ]]; then
        sleep 0.05
        CUR_COL=$(niri msg --json focused-window | jq -r '.layout.pos_in_scrolling_layout[0] // 0')
        CUR_COL_INT=$(printf "%.0f" "$CUR_COL")
        DIFF=$(( CUR_COL_INT - PREV_COL ))
        if (( DIFF > 0 )); then
            for _ in $(seq 1 "$DIFF"); do
                niri msg action move-column-left
            done
        elif (( DIFF < 0 )); then
            for _ in $(seq 1 "$((-DIFF))"); do
                niri msg action move-column-right
            done
        fi
    fi

    niri msg action center-column
    exit 0
fi

THRESHOLD=$(( OUTPUT_W * 85 / 100 ))

if (( TILE_W_INT >= THRESHOLD )); then
    FLOAT_PCT=75

    PREV_COL=$(echo "$WINDOW_INFO" | jq -r '.layout.pos_in_scrolling_layout[0] // 0')
    printf "%.0f" "$PREV_COL" > "$STATE_FILE"

    niri msg action move-window-to-floating
    niri msg action set-column-width "${FLOAT_PCT}%"
    niri msg action set-window-height "${FLOAT_PCT}%"
    niri msg action center-window
else
    niri msg action set-column-width "100%"
fi
