#!/bin/sh
# Monitor power control menu via wofi

PRIMARY="${NIRI_PRIMARY_OUTPUT:-}"
SECONDARY="${NIRI_SECONDARY_OUTPUT:-}"

# Load host env if not already set
if [ -z "$PRIMARY" ] && [ -f "$HOME/.config/environment.d/dotfiles-host.conf" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/environment.d/dotfiles-host.conf"
    PRIMARY="${NIRI_PRIMARY_OUTPUT:-}"
    SECONDARY="${NIRI_SECONDARY_OUTPUT:-}"
fi

# Build menu entries
entries="󰍹  Выключить все мониторы"
[ -n "$PRIMARY"   ] && entries="$entries\n󰹉  Выключить $PRIMARY"
[ -n "$SECONDARY" ] && entries="$entries\n󰹉  Выключить $SECONDARY"

choice=$(printf '%b' "$entries" | wofi --dmenu \
    --prompt "Мониторы" \
    --width 320 \
    --height 160 \
    --lines 3 \
    --hide-scroll \
    --no-actions \
    --insensitive)

[ -z "$choice" ] && exit 0

case "$choice" in
    *"Выключить все"*)
        niri msg action power-off-monitors
        ;;
    *"Выключить $PRIMARY"*)
        wlr-randr --output "$PRIMARY" --off 2>/dev/null \
            || niri msg action power-off-monitors
        ;;
    *"Выключить $SECONDARY"*)
        wlr-randr --output "$SECONDARY" --off 2>/dev/null \
            || niri msg action power-off-monitors
        ;;
esac
