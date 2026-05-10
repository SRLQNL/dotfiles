#!/bin/bash
WALLPAPER_DIR="$HOME/wallpapers"
PERSISTENCE_FILE="$HOME/.config/niri/last_wallpaper.txt"

wallpaper_list=$(find "$WALLPAPER_DIR" -maxdepth 1 -type f \
    \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \) \
    -exec basename {} \; 2>/dev/null)

if [[ -z "$wallpaper_list" ]]; then
    notify-send -u critical "Wallpaper" "No wallpapers in $WALLPAPER_DIR"
    exit 1
fi

SELECTED=$(echo "$wallpaper_list" | fuzzel --dmenu --prompt="Wallpaper: ")
[[ -z "$SELECTED" ]] && exit 0

WALLPAPER_PATH="$WALLPAPER_DIR/$SELECTED"

# Get focused output connector name from niri (e.g. DP-1, HDMI-A-1)
OUTPUT=$(NIRI_SOCKET=$(ls /run/user/1000/niri.*.sock 2>/dev/null | head -1) niri msg focused-output 2>/dev/null | grep -oP '\([A-Z]+-\d+\)' | tr -d '()' | head -1)

if [[ -n "$OUTPUT" ]]; then
    awww img "$WALLPAPER_PATH" -o "$OUTPUT" --transition-type fade
else
    awww img "$WALLPAPER_PATH" --transition-type fade
fi

# Save per-output wallpaper state
echo "$WALLPAPER_PATH" > "${PERSISTENCE_FILE%.txt}_${OUTPUT}.txt"
echo "$WALLPAPER_PATH" > "$PERSISTENCE_FILE"
notify-send "Wallpaper" "[$OUTPUT] Set: $SELECTED"
