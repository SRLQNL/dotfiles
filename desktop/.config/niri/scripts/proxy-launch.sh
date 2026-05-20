#!/bin/bash
# Launch any .desktop app through the local proxy.
# GUI apps: HTTP_PROXY env vars. Terminal apps: proxychains4 inside foot.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

PROXY_HTTP="http://127.0.0.1:8118"
PROXY_SOCKS="socks5://127.0.0.1:1080"
TERM_EMU="${TERM_EMULATOR:-foot}"

notify() { command -v notify-send &>/dev/null && notify-send "Proxy Launch" "$1"; }

# Single awk pass: extract Name, Exec, Terminal from each .desktop file
# Output: "Name\tExec\tterminal_bool"
parse_desktop() {
    find /usr/share/applications "${HOME}/.local/share/applications" \
         -maxdepth 1 -name "*.desktop" 2>/dev/null \
    | xargs awk '
        BEGIN { FS="="; name=""; exec=""; term="false"; skip=0 }
        /^\[Desktop Entry\]/  { skip=0 }
        /^\[Desktop Action/   { skip=1 }
        skip { next }
        /^NoDisplay=true/     { name=""; next }
        /^Hidden=true/        { name=""; next }
        /^Name=/   && name=="" { name=substr($0, index($0,"=")+1) }
        /^Exec=/   && exec=="" { exec=substr($0, index($0,"=")+1) }
        /^Terminal=true/       { term="true" }
        ENDFILE {
            if (name != "" && exec != "") {
                # strip %f %u %F %U etc.
                gsub(/ ?%[fFuUdDnNickvm]/, "", exec)
                gsub(/  +/, " ", exec)
                sub(/^ | $/, "", exec)
                print name "\t" exec "\t" term
            }
            name=""; exec=""; term="false"; skip=0
        }
    ' 2>/dev/null | sort -t$'\t' -k1 -u
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
