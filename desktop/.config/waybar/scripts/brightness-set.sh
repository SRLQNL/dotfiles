#!/bin/bash
set -euo pipefail

# UP or DOWN — updates cache immediately (widget refreshes instantly),
# then applies to monitors only after scrolling stops.

CACHE="${XDG_RUNTIME_DIR:-/tmp}/waybar_brightness"
LOCK="${XDG_RUNTIME_DIR:-/tmp}/waybar_brightness.lock"
TOKEN_FILE="${XDG_RUNTIME_DIR:-/tmp}/waybar_brightness_token"
STEP=5
DEBOUNCE_SECONDS="${BRIGHTNESS_DEBOUNCE_SECONDS:-0.45}"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=/dev/null
. "$SCRIPT_DIR/brightness-ddc.sh"

# Atomic read-modify-write via flock to prevent race on rapid scroll
{
    flock -x 9

    CURRENT=$(cat "$CACHE" 2>/dev/null || echo 80)

    if [ "$1" = "UP" ]; then
        NEW=$(( CURRENT + STEP ))
        [ $NEW -gt 100 ] && NEW=100
    else
        NEW=$(( CURRENT - STEP ))
        [ $NEW -lt 5 ] && NEW=5
    fi

    echo "$NEW" > "$CACHE"
} 9>"$LOCK"

pkill -RTMIN+10 waybar 2>/dev/null || true

# Debounce: stamp this event; background process only applies if it's still the last one
TOKEN=$(date +%s%N)
echo "$TOKEN" > "$TOKEN_FILE"

(
    MY_TOKEN=$TOKEN
    sleep "$DEBOUNCE_SECONDS"
    [ "$(cat "$TOKEN_FILE" 2>/dev/null)" != "$MY_TOKEN" ] && exit 0
    VAL=$(cat "$CACHE")
    ddc_apply_brightness "$VAL"
) &
