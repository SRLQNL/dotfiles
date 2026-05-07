#!/bin/sh
# Waybar custom module: primary monitor toggle with state

[ -z "$NIRI_PRIMARY_OUTPUT" ] && [ -f "$HOME/.config/environment.d/dotfiles-host.conf" ] && \
    . "$HOME/.config/environment.d/dotfiles-host.conf"

OUTPUT="${NIRI_PRIMARY_OUTPUT:-DP-1}"

enabled() {
    wlr-randr 2>/dev/null | awk -v out="$OUTPUT" '
        $1 == out { found=1; next }
        found && /Enabled:/ { print $2; exit }
        found && /^[^ ]/ { exit }
    '
}

if [ "$1" = "toggle" ]; then
    if [ "$(enabled)" = "yes" ]; then
        wlr-randr --output "$OUTPUT" --off
    else
        wlr-randr --output "$OUTPUT" --on
    fi
    exit 0
fi

if [ "$(enabled)" = "yes" ]; then
    printf '{"text":"󰹉 %s","class":"on","tooltip":"Кликни чтобы выключить %s"}\n' "$OUTPUT" "$OUTPUT"
else
    printf '{"text":"󰹈 %s","class":"off","tooltip":"Кликни чтобы включить %s"}\n' "$OUTPUT" "$OUTPUT"
fi
