#!/bin/bash
set -euo pipefail

if pgrep -x fuzzel > /dev/null; then
    pkill -x fuzzel
    exit 0
fi

WALLPAPER_DIR="$HOME/wallpapers"
PERSISTENCE_FILE="$HOME/.config/niri/last_wallpaper.txt"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

command -v fuzzel >/dev/null 2>&1 || { notify-send -u critical "Wallpaper" "fuzzel not found"; exit 1; }
command -v awww >/dev/null 2>&1 || { notify-send -u critical "Wallpaper" "awww not found"; exit 1; }
mkdir -p "$(dirname "$PERSISTENCE_FILE")"

wallpaper_list=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    -exec basename {} \; 2>/dev/null)

if [[ -z "$wallpaper_list" ]]; then
    notify-send -u critical "Wallpaper" "No wallpapers in $WALLPAPER_DIR"
    exit 1
fi

SELECTED=$(printf '%s\n' "$wallpaper_list" | fuzzel --dmenu --prompt="Wallpaper: ")
[[ -z "$SELECTED" ]] && exit 0

WALLPAPER_PATH="$WALLPAPER_DIR/$SELECTED"

# Get focused output connector name from niri (e.g. DP-1, HDMI-A-1)
OUTPUT=$(
    NIRI_SOCKET="${NIRI_SOCKET:-$(find "$RUNTIME_DIR" -maxdepth 1 -name 'niri.*.sock' 2>/dev/null | head -n 1)}" \
        niri msg --json focused-output 2>/dev/null | jq -r '.name // empty' || true
)

if [[ -n "$OUTPUT" ]]; then
    awww img "$WALLPAPER_PATH" -o "$OUTPUT" --transition-type fade
else
    awww img "$WALLPAPER_PATH" --transition-type fade
fi

# Save per-output wallpaper state
if [[ -n "$OUTPUT" ]]; then
    echo "$WALLPAPER_PATH" > "${PERSISTENCE_FILE%.txt}_${OUTPUT}.txt"
fi
echo "$WALLPAPER_PATH" > "$PERSISTENCE_FILE"
notify-send "Wallpaper" "[$OUTPUT] Set: $SELECTED"
