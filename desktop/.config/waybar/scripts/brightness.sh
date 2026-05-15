#!/bin/bash
set -euo pipefail

# Reads brightness from cache (populated by brightness-set.sh on scroll).
# Falls back to current DDC brightness across connected displays.

CACHE="${XDG_RUNTIME_DIR:-/tmp}/waybar_brightness"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=/dev/null
. "$SCRIPT_DIR/brightness-ddc.sh"

if [ ! -f "$CACHE" ]; then
    VAL=$(ddc_average_brightness || true)
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
