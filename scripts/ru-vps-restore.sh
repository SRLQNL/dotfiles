#!/bin/bash
# Host-specific emergency restore for RU VPS (193.124.67.5).
# Run as root via hosting console if SSH/Caddy is broken

set -e

WAN_IF=ens3
WAN_IP=193.124.67.5
WAN_GW=193.124.67.1
WG_IF=wg-se
WG_LOCAL=10.66.0.2
SE_IP=5.183.101.190
CADDY_UID=998
CONFIRM=${RU_VPS_RESTORE_CONFIRM:-}
SKIP_IP_CHECK=${RU_VPS_RESTORE_SKIP_IP_CHECK:-0}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "missing command: $1" >&2
        exit 1
    }
}

if [ "$(id -u)" -ne 0 ]; then
    echo "refusing to run: this host-specific restore must run as root" >&2
    exit 1
fi

if [ "$CONFIRM" != "$WAN_IP" ]; then
    echo "refusing to run host-specific RU VPS restore" >&2
    echo "set RU_VPS_RESTORE_CONFIRM=$WAN_IP to confirm this is the intended host" >&2
    exit 1
fi

require_cmd ip
require_cmd wg-quick
require_cmd systemctl
require_cmd runuser
require_cmd curl

if [ "$SKIP_IP_CHECK" != 1 ] &&
    ! ip -o -4 addr show dev "$WAN_IF" | grep -q " $WAN_IP/"; then
    echo "refusing to run: $WAN_IF does not have expected address $WAN_IP" >&2
    echo "set RU_VPS_RESTORE_SKIP_IP_CHECK=1 only when running from rescue context" >&2
    exit 1
fi

echo "=== 1. Bring up WireGuard ==="
wg-quick up "$WG_IF" 2>/dev/null || echo "already up or error"

echo "=== 2. Flush and rebuild table 100 ==="
ip route flush table 100 2>/dev/null || true
ip route replace default dev "$WG_IF" src "$WG_LOCAL" table 100
ip route replace "$SE_IP/32" via "$WAN_GW" dev "$WAN_IF" src "$WAN_IP" table 100

echo "=== 3. Remove stale ip rules (idempotent) ==="
ip rule del priority 80 2>/dev/null || true
ip rule del priority 90 2>/dev/null || true

echo "=== 4. Add ip rules for Caddy UID ==="
ip rule add uidrange "$CADDY_UID-$CADDY_UID" ipproto tcp sport 443 table main priority 80
ip rule add uidrange "$CADDY_UID-$CADDY_UID" table 100 priority 90
ip route flush cache

echo "=== 5. Restart Caddy ==="
systemctl restart caddy
sleep 2
systemctl is-active caddy && echo "Caddy OK" || echo "Caddy FAILED"

echo "=== 6. Verify: Caddy outbound IP should be SE VPS ==="
runuser -u caddy -- curl -4 --max-time 10 https://ifconfig.me || true

echo "=== Done ==="
