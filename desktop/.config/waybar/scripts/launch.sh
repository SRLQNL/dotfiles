#!/bin/sh
set -e

# Load host env vars (NIRI_PRIMARY_OUTPUT, NIRI_SECONDARY_OUTPUT, etc.)
HOST_ENV="$HOME/.config/environment.d/dotfiles-host.conf"
if [ -f "$HOST_ENV" ]; then
    # shellcheck source=/dev/null
    . "$HOST_ENV"
fi

NIRI_PRIMARY_OUTPUT="${NIRI_PRIMARY_OUTPUT:-}"
NIRI_SECONDARY_OUTPUT="${NIRI_SECONDARY_OUTPUT:-}"

WAYBAR_CFG="/tmp/waybar-config-$(hostname).json"
WAYBAR_TMPL="$HOME/.config/waybar/config.tmpl"

pkill -TERM -x waybar    2>/dev/null || true
pkill -TERM -x cava      2>/dev/null || true
pkill -TERM -x swaync-client 2>/dev/null || true
sleep 0.3
pkill -KILL -x waybar    2>/dev/null || true
pkill -KILL -x cava      2>/dev/null || true
pkill -KILL -x swaync-client 2>/dev/null || true

# Keep tray clients alive across Waybar restarts. Killing nm-applet can leave stale
# StatusNotifier/menu state and makes tray clicks unreliable until it registers again.
if command -v nm-applet >/dev/null 2>&1 && ! pgrep -x nm-applet >/dev/null 2>&1; then
    nm-applet --indicator &
fi

# Wait for PipeWire pulse socket
for i in $(seq 1 20); do
    [ -S "${XDG_RUNTIME_DIR}/pulse/native" ] && break
    sleep 0.5
done

# Wait for niri IPC socket
for i in $(seq 1 20); do
    NIRI_SOCKET=$(ls "${XDG_RUNTIME_DIR}"/niri.*.sock 2>/dev/null | head -1 || true)
    [ -n "$NIRI_SOCKET" ] && break
    sleep 0.5
done
export NIRI_SOCKET

# Generate config from template
[ -n "$NIRI_PRIMARY_OUTPUT" ] || { printf 'ERROR: NIRI_PRIMARY_OUTPUT is not set\n' >&2; exit 1; }
envsubst < "$WAYBAR_TMPL" > "$WAYBAR_CFG"

# On single-monitor setup, drop the second bar
if [ -z "$NIRI_SECONDARY_OUTPUT" ]; then
    jq '[.[0]]' "$WAYBAR_CFG" > "${WAYBAR_CFG}.tmp" && mv "${WAYBAR_CFG}.tmp" "$WAYBAR_CFG"
fi

exec waybar -c "$WAYBAR_CFG"
