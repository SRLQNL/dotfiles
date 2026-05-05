#!/usr/bin/env bash

# Singleton: kill wofi if already open
if pgrep -x wofi > /dev/null; then
    pkill -x wofi
    exit 0
fi

options="󰐥 Shutdown\n󰜉 Reboot\n󰍃 Logout\n󰒲 Suspend\n Lock"

chosen="$(echo -e "$options" | wofi --dmenu --prompt "Power:" --lines 5)"
case $chosen in
    *Shutdown) loginctl poweroff ;;
    *Reboot)   loginctl reboot ;;
    *Logout)   NIRI_SOCKET=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1) niri msg action quit ;;
    *Suspend)  loginctl suspend ;;
    *Lock)     ~/.config/niri/scripts/lock.sh ;;
esac
