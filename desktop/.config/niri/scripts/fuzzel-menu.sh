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

clipboard_menu() {
    raw_tmp=$(mktemp)
    menu_tmp=$(mktemp)
    result_tmp=$(mktemp)
    confirm_tmp=$(mktemp)
    icon_dir=$(mktemp -d)
    tab=$(printf '\t')
    icon_count=0
    icon_limit=40

    cleanup_clipboard_menu() {
        rm -f "$raw_tmp" "$menu_tmp" "$result_tmp" "$confirm_tmp"
        rm -rf "$icon_dir"
    }

    trap cleanup_clipboard_menu EXIT INT TERM HUP

    cliphist list > "$raw_tmp"

    while IFS=$tab read -r id preview; do
        [ -n "$id" ] || continue

        display=$preview
        icon=edit-paste
        line=$(printf '%s\t%s' "$id" "$preview")

        case "$preview" in
            "[[ binary data "*)
                meta=${preview#'[[ binary data '}
                meta=${meta%' ]]'}
                # shellcheck disable=SC2086
                set -- $meta
                size="${1:-} ${2:-}"
                kind=${3:-binary}
                dims=${4:-}
                kind_upper=$(printf '%s' "$kind" | tr '[:lower:]' '[:upper:]')

                display="Image $kind_upper"
                [ -n "$dims" ] && display="$display $dims"
                display="$display - $size"
                icon=image-x-generic

                if [ "$icon_count" -lt "$icon_limit" ]; then
                    image_file=$icon_dir/$id.$kind
                    thumb_file=$icon_dir/$id-thumb.png

                    if printf '%s' "$line" | cliphist decode > "$image_file" 2>/dev/null; then
                        if magick "$image_file" -auto-orient -thumbnail 96x96^ -gravity center -extent 96x96 "$thumb_file" >/dev/null 2>&1; then
                            icon=$thumb_file
                        elif [ -s "$image_file" ]; then
                            icon=$image_file
                        fi
                    fi

                    icon_count=$((icon_count + 1))
                fi
                ;;
            http://*|https://*)
                icon=text-html
                ;;
        esac

        printf '%s\t%s' "$id" "$display" >> "$menu_tmp"
        printf '\0icon\037%s\n' "$icon" >> "$menu_tmp"
    done < "$raw_tmp"

    printf '%s\t%s' "__clear__" "Clear clipboard history" >> "$menu_tmp"
    printf '\0icon\037%s\n' "edit-clear-history" >> "$menu_tmp"

    if ! /usr/bin/fuzzel \
        --dmenu \
        --prompt "Clipboard: " \
        --with-nth=2 \
        --accept-nth=1 \
        --match-nth=2 \
        --only-match \
        < "$menu_tmp" > "$result_tmp"; then
        return 0
    fi

    selection=$(cat "$result_tmp")

    case "$selection" in
        "")
            return 0
            ;;
        "__clear__")
            if ! printf '%s\t%s\n%s\t%s\n' \
                "no" "No" \
                "yes" "Yes, clear clipboard history" \
                | /usr/bin/fuzzel \
                    --dmenu \
                    --prompt "Clear?: " \
                    --with-nth=2 \
                    --accept-nth=1 \
                    --match-nth=2 \
                    --only-match \
                    --lines=2 > "$confirm_tmp"; then
                return 0
            fi

            confirm=$(cat "$confirm_tmp")

            if [ "$confirm" = "yes" ]; then
                cliphist wipe
                wl-copy --clear || true
                notify-send "Clipboard history cleared" || true
            fi
            ;;
        *)
            line=$(awk -F '\t' -v id="$selection" '$1 == id { print; exit }' "$raw_tmp")
            if [ -n "$line" ]; then
                printf '%s' "$line" | cliphist decode | wl-copy
            fi
            ;;
    esac
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
