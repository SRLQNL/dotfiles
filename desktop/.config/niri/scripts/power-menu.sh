#!/bin/bash

# Singleton: close if wofi already open
if pgrep -x wofi > /dev/null; then
    pkill -x wofi
    exit 0
fi

SELECTION="$(printf " Lock\n󰒲 Suspend\n󰍃 Logout\n󰜉 Reboot\n󰐥 Shutdown" \
    | wofi --dmenu --prompt "Power:" --lines 5)"

case "$SELECTION" in
    *Lock)     ~/.config/niri/scripts/lock.sh ;;
    *Suspend)  loginctl suspend ;;
    *Logout)   NIRI_SOCKET=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1) niri msg action quit ;;
    *Reboot)   loginctl reboot ;;
    *Shutdown) loginctl poweroff ;;
esac
