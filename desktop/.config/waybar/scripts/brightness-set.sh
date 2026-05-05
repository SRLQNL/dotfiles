#!/bin/bash
# UP or DOWN — updates cache immediately (widget refreshes instantly),
# then applies to monitors only after scrolling stops (debounce 150ms).

CACHE="/tmp/waybar_brightness"
LOCK="/tmp/waybar_brightness.lock"
TOKEN_FILE="/tmp/waybar_brightness_token"
STEP=5

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

# Debounce: stamp this event; background process only applies if it's still the last one
TOKEN=$(date +%s%N)
echo "$TOKEN" > "$TOKEN_FILE"

(
    MY_TOKEN=$TOKEN
    sleep 0.15
    [ "$(cat "$TOKEN_FILE" 2>/dev/null)" != "$MY_TOKEN" ] && exit 0
    VAL=$(cat "$CACHE")
    ddcutil setvcp 10 "$VAL" --bus 4 --noverify --sleep-multiplier 0 &
    ddcutil setvcp 10 "$VAL" --bus 6 --noverify --sleep-multiplier 0 &
    wait
) &
