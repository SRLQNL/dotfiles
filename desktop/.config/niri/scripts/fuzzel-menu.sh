#!/bin/sh
set -eu

mode=${1:-launcher}
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
state_file=$runtime_dir/srl-fuzzel-menu.mode
lock_dir=$runtime_dir/srl-fuzzel-menu.lock
locked=0

unlock() {
    if [ "$locked" -eq 1 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        locked=0
    fi
}

trap unlock EXIT INT TERM HUP

i=0
while ! mkdir "$lock_dir" 2>/dev/null; do
    if [ "$i" -ge 50 ]; then
        pkill -x fuzzel || true
        exit 0
    fi

    i=$((i + 1))
    sleep 0.03
done
locked=1

old_mode=
if pgrep -x fuzzel >/dev/null 2>&1; then
    old_mode=$(cat "$state_file" 2>/dev/null || true)
    pkill -x fuzzel || true

    j=0
    while pgrep -x fuzzel >/dev/null 2>&1 && [ "$j" -lt 30 ]; do
        j=$((j + 1))
        sleep 0.03
    done
fi

if [ "$old_mode" = "$mode" ]; then
    rm -f "$state_file"
    unlock
    exit 0
fi

printf '%s\n' "$mode" > "$state_file"
unlock

case "$mode" in
    launcher)
        /usr/bin/fuzzel || true
        ;;
    clipboard)
        tmp=$(mktemp)
        trap 'rm -f "$tmp"' EXIT
        cliphist list > "$tmp"
        selection=$(/usr/bin/fuzzel --dmenu --prompt "Clipboard: " < "$tmp" || true)
        if [ -n "$selection" ]; then
            printf '%s\n' "$selection" | cliphist decode | wl-copy
        fi
        ;;
    *)
        printf 'unknown fuzzel menu mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

if [ "$(cat "$state_file" 2>/dev/null || true)" = "$mode" ]; then
    rm -f "$state_file"
fi
