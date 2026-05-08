#!/bin/sh

if pgrep -x fuzzel >/dev/null 2>&1; then
    pkill -x fuzzel
    exit 0
fi

SELECTION="$(printf 'Shutdown\nReboot\nLogout\nSuspend' \
    | fuzzel --dmenu \
        --hide-prompt \
        --no-icons \
        --lines=4 \
        --width=24 \
        --horizontal-pad=30 \
        --vertical-pad=16 \
        --inner-pad=0 \
        --line-height=40 \
        --font='Noto Sans Mono:size=15' \
        --no-sort)"

case "$SELECTION" in
    Shutdown) loginctl poweroff ;;
    Reboot)   loginctl reboot ;;
    Logout)   niri msg action quit ;;
    Suspend)  loginctl suspend ;;

esac
