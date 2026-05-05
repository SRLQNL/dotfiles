#!/bin/bash
PERSISTENCE_DIR="$HOME/.config/niri"
sleep 1  # wait for awww-daemon to be ready

# Restore per-output wallpapers if saved
loaded=0
for f in "$PERSISTENCE_DIR"/last_wallpaper_*.txt; do
    [[ -f "$f" ]] || continue
    OUTPUT="${f##*last_wallpaper_}"
    OUTPUT="${OUTPUT%.txt}"
    IMG=$(head -n1 "$f")
    [[ -f "$IMG" ]] && awww img "$IMG" -o "$OUTPUT" --transition-type none
    loaded=1
done

# Fallback: set same wallpaper on all outputs
if [[ "$loaded" -eq 0 ]]; then
    FALLBACK="$PERSISTENCE_DIR/last_wallpaper.txt"
    if [[ -f "$FALLBACK" ]]; then
        IMG=$(head -n1 "$FALLBACK")
        [[ -f "$IMG" ]] && awww img "$IMG" --transition-type none
    fi
fi
