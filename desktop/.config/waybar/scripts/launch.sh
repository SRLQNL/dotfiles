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

killall -9 waybar    2>/dev/null || true
killall -9 cava      2>/dev/null || true
killall -9 nm-applet 2>/dev/null || true
sleep 0.3

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
envsubst < "$WAYBAR_TMPL" > "$WAYBAR_CFG"

# On single-monitor setup, drop the second bar
if [ -z "$NIRI_SECONDARY_OUTPUT" ]; then
    jq '[.[0]]' "$WAYBAR_CFG" > "${WAYBAR_CFG}.tmp" && mv "${WAYBAR_CFG}.tmp" "$WAYBAR_CFG"
fi

# Start nm-applet last so it registers its tray icon after everything else
# → always appears rightmost in tray (closest to bluetooth widget)
{ sleep 2; nm-applet --indicator & } &

exec waybar -c "$WAYBAR_CFG"
