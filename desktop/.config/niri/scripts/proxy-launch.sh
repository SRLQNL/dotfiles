#!/bin/bash
# Launch any app through the local proxy.
# Shows icons like the native fuzzel launcher.
# Flatpak apps get --env= flags; regular apps get HTTP_PROXY env vars.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

PROXY_HTTP="http://127.0.0.1:8118"
PROXY_SOCKS="socks5://127.0.0.1:1080"
TERM_EMU="${TERM_EMULATOR:-foot}"

notify() { command -v notify-send &>/dev/null && notify-send "Proxy Launch" "$1"; }

# All app dirs: user first (overrides system), then XDG_DATA_DIRS
collect_dirs() {
    echo "${HOME}/.local/share/applications"
    printf '%s' "${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" \
        | tr ':' '\n' | sed 's|/*$|/applications|'
}

mapfile -t desktop_files < <(
    while IFS= read -r dir; do
        [[ -d "$dir" ]] && find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null
    done < <(collect_dirs)
)
(( ${#desktop_files[@]} == 0 )) && { notify "No applications found"; exit 1; }

# Parse [Desktop Entry] only; extract Name, Exec, Terminal, Icon
# Output: name TAB exec TAB terminal TAB icon
app_data=$(
    printf '%s\0' "${desktop_files[@]}" | xargs -0 awk '
        BEGIN { in_entry=0 }
        /^\[Desktop Entry\]/         { in_entry=1; name=""; exec=""; term="false"; icon=""; next }
        /^\[/                        { in_entry=0; next }
        !in_entry                    { next }
        /^(NoDisplay|Hidden)=true/   { name="SKIP"; next }
        /^Name=/ && name==""         { name=substr($0,6) }
        /^Exec=/ && exec==""         { exec=substr($0,6) }
        /^Terminal=true/             { term="true" }
        /^Icon=/ && icon==""         { icon=substr($0,6) }
        ENDFILE {
            if (name != "" && name != "SKIP" && exec != "") {
                gsub(/ ?%[fFuUdDnNickvm]/, "", exec)
                gsub(/@@u? ?|@@ ?/, "", exec)
                gsub(/  +/, " ", exec); sub(/^ | $/, "", exec)
                print name "\t" exec "\t" term "\t" icon
            }
            name=""; exec=""; term="false"; icon=""; in_entry=0
        }
    ' 2>/dev/null \
    | awk -F'\t' '!seen[$1]++' \
    | sort -t$'\t' -k1
)

[[ -z "$app_data" ]] && { notify "No applications found"; exit 1; }

# Build fuzzel dmenu input with icons: "Name\0icon\x1fIconName"
fuzzel_input=$(printf '%s' "$app_data" | awk -F'\t' '{
    if ($4 != "") printf "%s\0icon\x1f%s\n", $1, $4
    else           printf "%s\n", $1
}')

selected=$(printf '%s' "$fuzzel_input" \
    | fuzzel --dmenu --prompt="Proxy> " --lines=20 --width=40) || exit 0
[[ -z "$selected" ]] && exit 0

entry=$(printf '%s' "$app_data" | awk -F'\t' -v n="$selected" '$1==n{print;exit}')
exec_cmd=$(printf '%s' "$entry" | cut -f2)
is_term=$(printf '%s'  "$entry" | cut -f3)

# Inject proxy: Flatpak gets --env= flags; everything else gets env vars
if [[ "$exec_cmd" == *"flatpak run"* ]]; then
    exec_cmd="${exec_cmd/flatpak run/flatpak run \
        --env=HTTP_PROXY=$PROXY_HTTP \
        --env=HTTPS_PROXY=$PROXY_HTTP \
        --env=http_proxy=$PROXY_HTTP \
        --env=https_proxy=$PROXY_HTTP \
        --env=ALL_PROXY=$PROXY_SOCKS}"
    eval "$exec_cmd" &>/dev/null &
elif [[ "$is_term" == "true" ]]; then
    $TERM_EMU sh -c "proxychains4 $exec_cmd" &
else
    env HTTP_PROXY="$PROXY_HTTP"  http_proxy="$PROXY_HTTP" \
        HTTPS_PROXY="$PROXY_HTTP" https_proxy="$PROXY_HTTP" \
        ALL_PROXY="$PROXY_SOCKS"  all_proxy="$PROXY_SOCKS" \
        $exec_cmd &>/dev/null &
fi

notify "Started: $selected"
