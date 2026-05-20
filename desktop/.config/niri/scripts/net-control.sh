#!/bin/bash
# Network control and monitoring menu via fuzzel.
# Shows live status in the menu header; each action opens a foot terminal or runs silently.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

TERM_EMU="${TERM_EMULATOR:-foot}"
SOCKS="127.0.0.1:1080"
HTTP_P="127.0.0.1:8118"

# ── helpers ───────────────────────────────────────────────────────────────────

notify() { command -v notify-send &>/dev/null && notify-send "Network" "$1"; }

run_term() {
    # Run a shell command in a new foot window; keep it open until Enter
    $TERM_EMU sh -c "$1; echo; printf 'Press Enter to close...'; read" &
}

proxy_status() {
    sudo sv status naive-proxy 2>/dev/null | grep -q "^run" && echo "ON" || echo "OFF"
}

# ── menu ──────────────────────────────────────────────────────────────────────

PROXY_STATE=$(proxy_status)

MENU=$(cat <<EOF
[proxy: $PROXY_STATE] Check IP direct
[proxy: $PROXY_STATE] Check IP via proxy
Proxy: toggle naive-proxy
Proxy: restart naive-proxy
Ports: show listening (ss)
Ports: show all connections
Interfaces: ip addr
Firewall: nftables ruleset
Firewall: reload nftables
DNS: test resolution
DNS: show resolv.conf
Docker: network info
VPN: AmneziaVPN status
VPN: restart AmneziaVPN
EOF
)

selected=$(echo "$MENU" | fuzzel --dmenu \
    --prompt="Network> " --lines=18 --width=50) || exit 0
[[ -z "$selected" ]] && exit 0

# ── actions ───────────────────────────────────────────────────────────────────

case "$selected" in

    *"Check IP direct"*)
        run_term "echo 'Direct IP:'; curl -s --max-time 8 https://api.ipify.org; echo"
        ;;

    *"Check IP via proxy"*)
        run_term "echo 'IP via proxy (naiveproxy):'; curl -s --max-time 8 --socks5-hostname $SOCKS https://api.ipify.org; echo"
        ;;

    *"toggle naive-proxy"*)
        if [[ "$PROXY_STATE" == "ON" ]]; then
            sudo sv down naive-proxy && notify "naive-proxy stopped"
        else
            sudo sv up   naive-proxy && notify "naive-proxy started"
        fi
        ;;

    *"restart naive-proxy"*)
        sudo sv restart naive-proxy && notify "naive-proxy restarted"
        ;;

    *"show listening"*)
        run_term "echo '=== TCP ==='; ss -tlnp; echo; echo '=== UDP ==='; ss -ulnp"
        ;;

    *"show all connections"*)
        run_term "ss -tnp"
        ;;

    *"ip addr"*)
        run_term "ip -c addr show"
        ;;

    *"nftables ruleset"*)
        run_term "sudo nft list ruleset"
        ;;

    *"reload nftables"*)
        sudo sv restart nftables && notify "nftables reloaded"
        ;;

    *"DNS: test"*)
        run_term "echo '=== 8.8.8.8 ==='; nslookup google.com 8.8.8.8; echo; echo '=== 1.1.1.1 ==='; nslookup google.com 1.1.1.1"
        ;;

    *"resolv.conf"*)
        run_term "cat /etc/resolv.conf"
        ;;

    *"Docker: network"*)
        run_term "docker network ls; echo; docker ps --format 'table {{.Names}}\t{{.Ports}}' 2>/dev/null || echo 'No containers running'"
        ;;

    *"AmneziaVPN status"*)
        run_term "sudo sv status AmneziaVPN-service; echo; ip addr show amn0 2>/dev/null || echo 'amn0 interface not up'"
        ;;

    *"restart AmneziaVPN"*)
        sudo sv restart AmneziaVPN-service && notify "AmneziaVPN restarted"
        ;;

esac
