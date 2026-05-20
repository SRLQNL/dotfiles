#!/bin/bash
set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

notify() { command -v notify-send &>/dev/null && notify-send "Network" "$1"; }

pgrep -x "naive" &>/dev/null && P="ON" || P="OFF"

selected=$(printf '%s\n' \
    "Proxy [$P]  toggle" \
    "Proxy         restart" \
    "Check IP via proxy" \
    "Firewall      reload" \
    | fuzzel --dmenu --prompt="Network> " --lines=4 --width=30) || exit 0
[[ -z "$selected" ]] && exit 0

case "$selected" in
    *"toggle")
        if [[ "$P" == "ON" ]]; then sudo sv down naive-proxy && notify "Proxy OFF"
                                else sudo sv up   naive-proxy && notify "Proxy ON"; fi ;;
    *"restart")
        sudo sv restart naive-proxy && notify "Proxy restarted" ;;
    "Check IP"*)
        foot -H -e sh -c "curl -s --max-time 8 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org; echo" & ;;
    "Firewall"*)
        sudo sv restart nftables && notify "Firewall reloaded" ;;
esac
