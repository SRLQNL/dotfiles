#!/bin/sh
set -eu

mode=${1:-launcher}
runtime_dir=${XDG_RUNTIME_DIR:-/tmp}
state_file=$runtime_dir/fuzzel-menu.mode
lock_dir=$runtime_dir/fuzzel-menu.lock
locked=0

unlock() {
    if [ "$locked" -eq 1 ]; then
        rmdir "$lock_dir" 2>/dev/null || true
        locked=0
    fi
}

clipboard_menu() {
    thumbnail_dir="${XDG_CACHE_HOME:-$HOME/.cache}/cliphist/thumbnails"
    mkdir -p "$thumbnail_dir"

    cliphist_list=$(cliphist list)
    if [ -z "$cliphist_list" ]; then
        return 0
    fi

    # gawk: для картинок декодирует и кэширует thumbnail, добавляет \0icon
    thumbnail_awk='/^[0-9]+\s<meta http-equiv=/ { next }
match($0, /^([0-9]+)\s(\[\[\s)?binary.*(jpg|jpeg|png|bmp)/, grp) {
  id=grp[1]; ext=grp[3]
  f=id"."ext
  system("[ -f '"$thumbnail_dir"'/"f" ] || printf \"%s\\t\" "id" | cliphist decode >'"$thumbnail_dir"'/"f)
  print $0"\0icon\x1f'"$thumbnail_dir"'/"f
  next
}
1'

    set +e
    item=$(echo "$cliphist_list" \
        | gawk "$thumbnail_awk" \
        | fuzzel --dmenu \
            --prompt " " \
            --placeholder "Clipboard..." \
            --with-nth=2 \
            --accept-nth=1 \
            --no-sort)
    exit_code=$?
    set -e

    # Alt+0 — очистить всю историю
    if [ "$exit_code" -eq 19 ]; then
        confirmation=$(printf 'No\nYes, clear history' \
            | fuzzel --dmenu --prompt "Clear? " --lines=2 || true)
        if [ "$confirmation" = "Yes, clear history" ]; then
            cliphist wipe
            wl-copy --clear || true
            rm -rf "$thumbnail_dir"
            notify-send "Clipboard history cleared"
        fi
    # Alt+1 (custom-1) — удалить выбранный элемент
    elif [ "$exit_code" -eq 10 ]; then
        if [ -n "$item" ]; then
            item_id=$(printf '%s' "$item" | cut -f1)
            printf '%s' "$item_id" | cliphist delete
            find "$thumbnail_dir" -name "${item_id}.*" -delete 2>/dev/null || true
        fi
    elif [ "$exit_code" -eq 0 ] && [ -n "$item" ]; then
        printf '%s' "$item" | cliphist decode | wl-copy
    fi

    # Чистим orphaned thumbnails
    find "$thumbnail_dir" -type f | while IFS= read -r f; do
        item_id=$(basename "${f%.*}")
        echo "$cliphist_list" | grep -q "^${item_id}	" || rm -f "$f"
    done &
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
        clipboard_menu
        ;;
    *)
        printf 'unknown fuzzel menu mode: %s\n' "$mode" >&2
        exit 2
        ;;
esac

if [ "$(cat "$state_file" 2>/dev/null || true)" = "$mode" ]; then
    rm -f "$state_file"
fi
