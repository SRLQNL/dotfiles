#!/bin/bash
set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

TERM_EMU="${TERM_EMULATOR:-foot}"

notify()   { command -v notify-send &>/dev/null && notify-send "Network" "$1"; }
run_term() { $TERM_EMU sh -c "$1; echo; printf 'Press Enter...'; read" & }

pgrep -x "naive" &>/dev/null && P="ON" || P="OFF"

selected=$(printf '%s\n' \
    "Proxy [$P]  toggle" \
    "Proxy [$P]  restart" \
    "Check IP via proxy" \
    "Firewall    reload" \
    | fuzzel --dmenu --prompt="Network> " --lines=4 --width=32) || exit 0
[[ -z "$selected" ]] && exit 0

case "$selected" in
    *"toggle")
        if [[ "$P" == "ON" ]]; then sudo sv down naive-proxy && notify "Proxy OFF"
                                else sudo sv up   naive-proxy && notify "Proxy ON"; fi ;;
    *"restart")
        sudo sv restart naive-proxy && notify "Proxy restarted" ;;
    "Check IP"*)
        run_term "curl -s --max-time 8 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org; echo" ;;
    "Firewall"*)
        sudo sv restart nftables && notify "Firewall reloaded" ;;
esac
