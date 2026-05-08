#!/bin/sh

if pgrep -x fuzzel >/dev/null 2>&1; then
    pkill -x fuzzel
    exit 0
fi

SELECTION="$(printf '⏻  Shutdown\n  Reboot\n󰍃  Logout\n󰒲  Suspend\n  Lock' \
    | fuzzel --dmenu \
        --prompt='   ' \
        --lines=5 \
        --width=18 \
        --match-mode=fzf \
        --no-sort)"

case "$SELECTION" in
    *Shutdown) loginctl poweroff ;;
    *Reboot)   loginctl reboot ;;
    *Logout)   niri msg action quit ;;
    *Suspend)  loginctl suspend ;;
    *Lock)     ~/.config/niri/scripts/lock.sh ;;
esac
