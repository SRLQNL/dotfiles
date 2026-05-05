#!/bin/bash
# Reads brightness from cache (populated by brightness-set.sh on scroll).
# Falls back to ddcutil once on first run.

CACHE="/tmp/waybar_brightness"

if [ ! -f "$CACHE" ]; then
    VAL=$(ddcutil getvcp 10 --display 1 2>/dev/null | grep -oP 'current value =\s+\K\d+')
    echo "${VAL:-80}" > "$CACHE"
fi

B=$(cat "$CACHE")

FILLED=$(( B / 10 ))
[ $FILLED -gt 10 ] && FILLED=10
EMPTY=$(( 10 - FILLED ))

BAR=""
for ((i=0; i<FILLED; i++)); do BAR+="▰"; done
for ((i=0; i<EMPTY; i++));  do BAR+="▱"; done

if   [ "$B" -le 30 ]; then ICON="󰃞"
elif [ "$B" -le 70 ]; then ICON="󰃟"
else ICON="󰃠"; fi

printf '{"text": "%s %s", "tooltip": "Brightness: %d%%", "alt": "%d"}\n' "$ICON" "$BAR" "$B" "$B"
