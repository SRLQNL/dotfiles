#!/bin/bash
set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

notify() { command -v notify-send &>/dev/null && notify-send "Network" "$1"; }

# Load host-specific env (provides PROXY_SV_NAME and PROXY_SOCKS5)
HOST_ENV="${HOME}/.config/host.env"
[ -r "$HOST_ENV" ] && source "$HOST_ENV"
SV="${PROXY_SV_NAME:-naive-proxy}"
SOCKS5="${PROXY_SOCKS5:-127.0.0.1:1080}"

pgrep -x "${SV%-*}" &>/dev/null && P="ON" || P="OFF"

selected=$(printf '%s\n' \
    "Proxy [$P]  toggle" \
    "Proxy [$P]  restart" \
    "Check IP via proxy" \
    "Firewall    reload" \
    | fuzzel --dmenu --prompt="Network> " --lines=4 --width=30) || exit 0
[[ -z "$selected" ]] && exit 0

case "$selected" in
    *"toggle")
        if [[ "$P" == "ON" ]]; then sudo sv down "$SV" && notify "Proxy OFF"
                                else sudo sv up   "$SV" && notify "Proxy ON"; fi ;;
    *"restart")
        sudo sv restart "$SV" && notify "Proxy restarted" ;;
    "Check IP"*)
        foot -H -e sh -c "curl -s --max-time 8 --socks5-hostname $SOCKS5 https://api.ipify.org; echo" & ;;
    "Firewall"*)
        sudo sv restart nftables && notify "Firewall reloaded" ;;
    *)
        notify "Unknown: $selected" ;;
esac
