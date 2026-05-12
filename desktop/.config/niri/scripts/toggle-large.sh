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

# If fullscreen → exit fullscreen and maximize
TILE_W_FS=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[0] // 0')
TILE_H_FS=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[1] // 0')
if (( $(printf "%.0f" "$TILE_W_FS") >= OUTPUT_W * 95 / 100 && $(printf "%.0f" "$TILE_H_FS") >= OUTPUT_H * 85 / 100 )); then
    niri msg action fullscreen-window
    niri msg action set-column-width "100%"
    niri msg action reset-window-height
    exit 0
fi

if [[ "$IS_FLOATING" == "true" ]]; then
    PREV_COL=$(cat "$STATE_FILE" 2>/dev/null)
    rm -f "$STATE_FILE"
    niri msg action move-window-to-tiling
    niri msg action set-column-width "100%"
    niri msg action reset-window-height

    if [[ -n "$PREV_COL" ]]; then
        sleep 0.05
        CUR_COL=$(niri msg --json focused-window | jq -r '.layout.pos_in_scrolling_layout[0] // 0')
        CUR_COL_INT=$(printf "%.0f" "$CUR_COL")
        DIFF=$(( CUR_COL_INT - PREV_COL ))
        for i in $(seq 1 $DIFF); do
            niri msg action move-column-left
        done
    fi

    niri msg action center-column
    exit 0
fi

TILE_W=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[0] // 0')
TILE_W_INT=$(printf "%.0f" "$TILE_W")
THRESHOLD=$(( OUTPUT_W * 85 / 100 ))

if (( TILE_W_INT >= THRESHOLD )); then
    TILE_H=$(echo "$WINDOW_INFO" | jq -r '.layout.tile_size[1] // 1002')
    TILE_H_INT=$(printf "%.0f" "$TILE_H")
    FLOAT_PCT=75

    # Target position: centered at 75%x75%
    # K = panel+struts offset; available_float = OUTPUT_H - K; float_h = available_float * 0.75
    K=$(( OUTPUT_H - TILE_H_INT - 40 ))
    AVAIL=$(( OUTPUT_H - K ))
    FLOAT_H=$(( AVAIL * FLOAT_PCT / 100 ))
    FLOAT_W=$(( OUTPUT_W * FLOAT_PCT / 100 ))
    TARGET_X=$(( (OUTPUT_W - FLOAT_W) / 2 ))
    TARGET_Y=$(( K + (AVAIL - FLOAT_H) / 2 ))

    PREV_COL=$(echo "$WINDOW_INFO" | jq -r '.layout.pos_in_scrolling_layout[0] // 0')
    printf "%.0f" "$PREV_COL" > "$STATE_FILE"

    # Move to floating — position is set synchronously before ACK
    niri msg action move-window-to-floating
    FLOAT_INFO=$(niri msg --json focused-window)
    INIT_X=$(echo "$FLOAT_INFO" | jq -r '.layout.tile_pos_in_workspace_view[0] // 0')
    INIT_Y=$(echo "$FLOAT_INFO" | jq -r '.layout.tile_pos_in_workspace_view[1] // 0')
    INIT_X_INT=$(printf "%.0f" "$INIT_X")
    INIT_Y_INT=$(printf "%.0f" "$INIT_Y")

    DELTA_X=$(( TARGET_X - INIT_X_INT ))
    DELTA_Y=$(( TARGET_Y - INIT_Y_INT ))

    # Resize + immediately move to target (no sleep needed)
    niri msg action set-column-width "${FLOAT_PCT}%"
    niri msg action set-window-height "${FLOAT_PCT}%"
    niri msg action move-floating-window --x "+${DELTA_X}" --y "+${DELTA_Y}"
else
    niri msg action set-column-width "100%"
fi
