#!/bin/bash
set -euo pipefail

# UP or DOWN — updates cache immediately (widget refreshes instantly),
# then applies to monitors only after scrolling stops (debounce 150ms).

CACHE="/tmp/waybar_brightness"
LOCK="/tmp/waybar_brightness.lock"
TOKEN_FILE="/tmp/waybar_brightness_token"
STEP=5

apply_ddc() {
    command -v ddcutil >/dev/null 2>&1 || return 0

    if [ -n "${DDCUTIL_BUSES:-}" ]; then
        for bus in $DDCUTIL_BUSES; do
            ddcutil setvcp 10 "$1" --bus "$bus" --noverify --sleep-multiplier 0 &
        done
    else
        ddcutil setvcp 10 "$1" --noverify --sleep-multiplier 0 &
    fi
    wait
}

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
    sleep 0.15
    [ "$(cat "$TOKEN_FILE" 2>/dev/null)" != "$MY_TOKEN" ] && exit 0
    VAL=$(cat "$CACHE")
    apply_ddc "$VAL"
) &
