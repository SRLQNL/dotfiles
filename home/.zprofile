# Load host-specific env vars (monitor names, paths, etc.)
if [ -f "$HOME/.config/environment.d/dotfiles-host.conf" ]; then
    # shellcheck source=/dev/null
    . "$HOME/.config/environment.d/dotfiles-host.conf"
    export NIRI_PRIMARY_OUTPUT NIRI_SECONDARY_OUTPUT \
           NIRI_PRIMARY_MODE NIRI_SECONDARY_MODE \
           NIRI_PRIMARY_POSITION NIRI_SECONDARY_POSITION \
           LOCK_TOP_OUTPUT LOCK_BOTTOM_OUTPUT SCREENSHOT_DIR
fi

if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
    exec startx
fi
