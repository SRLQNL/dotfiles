#!/bin/bash
# Restore routing and start services on RU VPS (193.124.67.5)
# Run as root via hosting console if SSH/Caddy is broken

set -e

WAN_IF=ens3
WAN_IP=193.124.67.5
WAN_GW=193.124.67.1
WG_IF=wg-se
WG_LOCAL=10.66.0.2
SE_IP=5.183.101.190
CADDY_UID=998

echo "=== 1. Bring up WireGuard ==="
wg-quick up $WG_IF 2>/dev/null || echo "already up or error"

echo "=== 2. Flush and rebuild table 100 ==="
ip route flush table 100 2>/dev/null || true
ip route replace default dev $WG_IF src $WG_LOCAL table 100
ip route replace $SE_IP/32 via $WAN_GW dev $WAN_IF src $WAN_IP table 100

echo "=== 3. Remove stale ip rules (idempotent) ==="
ip rule del priority 80 2>/dev/null || true
ip rule del priority 90 2>/dev/null || true

echo "=== 4. Add ip rules for Caddy UID ==="
ip rule add uidrange $CADDY_UID-$CADDY_UID ipproto tcp sport 443 table main priority 80
ip rule add uidrange $CADDY_UID-$CADDY_UID table 100 priority 90
ip route flush cache

echo "=== 5. Restart Caddy ==="
systemctl restart caddy
sleep 2
systemctl is-active caddy && echo "Caddy OK" || echo "Caddy FAILED"

echo "=== 6. Verify: Caddy outbound IP should be SE VPS ==="
runuser -u caddy -- curl -4 --max-time 10 https://ifconfig.me || true

echo "=== Done ==="
