#!/bin/bash
# Launch any app through the local proxy — reads the same XDG dirs as fuzzel.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

PROXY_HTTP="http://127.0.0.1:8118"
PROXY_SOCKS="socks5://127.0.0.1:1080"
TERM_EMU="${TERM_EMULATOR:-foot}"

notify() { command -v notify-send &>/dev/null && notify-send "Proxy Launch" "$1"; }

# Collect all application dirs the same way fuzzel does: XDG_DATA_DIRS + user dir.
# User dir first so it overrides system entries with the same Name.
collect_dirs() {
    echo "${HOME}/.local/share/applications"
    printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        | tr ':' '\n' \
        | sed 's|/*$|/applications|'
}

# Gather .desktop files, user dir first (for dedup priority)
mapfile -t desktop_files < <(
    while IFS= read -r dir; do
        [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null
    done < <(collect_dirs)
)

(( ${#desktop_files[@]} == 0 )) && { notify "No applications found"; exit 1; }

# Single awk pass: parse only [Desktop Entry], dedup by Name (first wins = user override)
app_data=$(
    printf '%s\0' "${desktop_files[@]}" | xargs -0 awk '
        BEGIN { in_entry=0 }
        /^\[Desktop Entry\]/  { in_entry=1; name=""; exec=""; term="false"; next }
        /^\[/                 { in_entry=0; next }
        !in_entry             { next }
        /^(NoDisplay|Hidden)=true/ { name="SKIP"; next }
        /^Name=/ && name==""  { name=substr($0,6) }
        /^Exec=/ && exec==""  { exec=substr($0,6) }
        /^Terminal=true/      { term="true" }
        ENDFILE {
            if (name != "" && name != "SKIP" && exec != "") {
                gsub(/ ?%[fFuUdDnNickvm]/, "", exec)
                gsub(/  +/, " ", exec); sub(/^ | $/, "", exec)
                print name "\t" exec "\t" term
            }
            name=""; exec=""; term="false"; in_entry=0
        }
    ' 2>/dev/null \
    | awk -F'\t' '!seen[$1]++' \
    | sort -t$'\t' -k1
)

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
