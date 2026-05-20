#!/bin/bash
# Launch any .desktop app through the local proxy.
# GUI apps: HTTP_PROXY env vars. Terminal apps: proxychains4 inside foot.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

PROXY_HTTP="http://127.0.0.1:8118"
PROXY_SOCKS="socks5://127.0.0.1:1080"
TERM_EMU="${TERM_EMULATOR:-foot}"

notify() { command -v notify-send &>/dev/null && notify-send "Proxy Launch" "$1"; }

# Parse .desktop files: user dir first so it takes priority over system dir.
# Only reads [Desktop Entry] section; skips [Desktop Action *] and duplicates by Name.
parse_desktop() {
    local dirs=("${HOME}/.local/share/applications" "/usr/share/applications")
    local all_files=()
    for d in "${dirs[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do all_files+=("$f"); done \
            < <(find "$d" -maxdepth 1 -name "*.desktop" 2>/dev/null)
    done
    (( ${#all_files[@]} == 0 )) && return

    printf '%s\0' "${all_files[@]}" | xargs -0 awk '
        BEGIN { FS="="; in_entry=0 }
        /^\[Desktop Entry\]/   { in_entry=1; name=""; exec=""; term="false"; next }
        /^\[/                  { in_entry=0; next }
        !in_entry              { next }
        /^NoDisplay=true/      { name=""; next }
        /^Hidden=true/         { name=""; next }
        /^Name=/ && name==""   { name=substr($0, index($0,"=")+1) }
        /^Exec=/ && exec==""   { exec=substr($0, index($0,"=")+1) }
        /^Terminal=true/       { term="true" }
        ENDFILE {
            if (name != "" && exec != "") {
                gsub(/ ?%[fFuUdDnNickvm]/, "", exec)
                gsub(/  +/, " ", exec); sub(/^ +| +$/, "", exec)
                print name "\t" exec "\t" term
            }
            name=""; exec=""; term="false"
        }
    ' 2>/dev/null \
    | awk -F'\t' '!seen[$1]++' \
    | sort -t$'\t' -k1
}

app_data=$(parse_desktop)
[[ -z "$app_data" ]] && { notify "No applications found"; exit 1; }

selected=$(printf '%s' "$app_data" | cut -f1 \
    | fuzzel --dmenu --prompt="Proxy> " --lines=20 --width=40) || exit 0
[[ -z "$selected" ]] && exit 0

entry=$(printf '%s' "$app_data" | awk -F'\t' -v n="$selected" '$1==n{print;exit}')
exec_cmd=$(printf '%s' "$entry" | cut -f2)
is_term=$(printf '%s'  "$entry" | cut -f3)

if [[ "$is_term" == "true" ]]; then
    $TERM_EMU sh -c "proxychains4 $exec_cmd" &
else
    env HTTP_PROXY="$PROXY_HTTP"  http_proxy="$PROXY_HTTP" \
        HTTPS_PROXY="$PROXY_HTTP" https_proxy="$PROXY_HTTP" \
        ALL_PROXY="$PROXY_SOCKS"  all_proxy="$PROXY_SOCKS" \
        $exec_cmd &>/dev/null &
fi

notify "Started: $selected"
