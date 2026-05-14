#!/bin/sh
# Usage: monitor-toggle.sh <OUTPUT_NAME> [toggle]

OUTPUT="$1"
if [ -z "$OUTPUT" ]; then
    printf '{"text":"","class":"absent","tooltip":"No output configured"}\n'
    exit 0
fi

enabled() {
    wlr-randr 2>/dev/null | awk -v out="$OUTPUT" '
        $1 == out { found=1; next }
        found && /Enabled:/ { print $2; exit }
        found && /^[^ ]/ { exit }
    '
}

if [ "$2" = "toggle" ]; then
    if [ "$(enabled)" = "yes" ]; then
        wlr-randr --output "$OUTPUT" --off
    else
        wlr-randr --output "$OUTPUT" --on
    fi
    pkill -RTMIN+11 -x waybar 2>/dev/null || true
    exit 0
fi

if [ "$(enabled)" = "yes" ]; then
    printf '{"text":"%s ON","class":"on","tooltip":"Turn off %s"}\n' "$OUTPUT" "$OUTPUT"
else
    printf '{"text":"%s OFF","class":"off","tooltip":"Turn on %s"}\n' "$OUTPUT" "$OUTPUT"
fi
