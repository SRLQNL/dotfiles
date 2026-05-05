#!/bin/bash
WALLPAPER_FILE="$HOME/.config/niri/last_wallpaper.txt"

if [[ -f "$WALLPAPER_FILE" ]]; then
    WALLPAPER=$(head -n1 "$WALLPAPER_FILE")
    if [[ -f "$WALLPAPER" ]]; then
        exec swaylock --image "$WALLPAPER"
    fi
fi

exec swaylock
