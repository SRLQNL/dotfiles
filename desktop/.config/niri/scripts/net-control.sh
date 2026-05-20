#!/bin/bash
set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

TERM_EMU="${TERM_EMULATOR:-foot}"

notify() { command -v notify-send &>/dev/null && notify-send "Network" "$1"; }
run_term() { $TERM_EMU sh -c "$1; echo; printf 'Press Enter...'; read" & }

# Status without sudo — pgrep on the actual service binary
pgrep -x "naive"               &>/dev/null && P="ON" || P="OFF"
pgrep -x "AmneziaVPN-service"  &>/dev/null && V="ON" || V="OFF"

selected=$(printf '%s\n' \
    "Proxy [$P]  toggle" \
    "Proxy [$P]  restart" \
    "Proxy [$P]  check IP" \
    "VPN   [$V]  toggle" \
    "VPN   [$V]  restart" \
    "Firewall    reload" \
    | fuzzel --dmenu --prompt="Network> " --lines=6 --width=35) || exit 0
[[ -z "$selected" ]] && exit 0

case "$selected" in
    "Proxy"*"toggle")
        if [[ "$P" == "ON" ]]; then sudo sv down naive-proxy   && notify "Proxy OFF"
                                else sudo sv up   naive-proxy   && notify "Proxy ON"; fi ;;
    "Proxy"*"restart")
        sudo sv restart naive-proxy && notify "Proxy restarted" ;;
    "Proxy"*"check IP")
        run_term "curl -s --max-time 8 --socks5-hostname 127.0.0.1:1080 https://api.ipify.org; echo" ;;
    "VPN"*"toggle")
        if [[ "$V" == "ON" ]]; then sudo sv down AmneziaVPN-service && notify "VPN OFF"
                                else sudo sv up   AmneziaVPN-service && notify "VPN ON"; fi ;;
    "VPN"*"restart")
        sudo sv restart AmneziaVPN-service && notify "VPN restarted" ;;
    "Firewall"*"reload")
        sudo sv restart nftables && notify "Firewall reloaded" ;;
esac
