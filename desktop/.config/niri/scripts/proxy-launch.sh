#!/bin/bash
# Launch an application through the local proxy (privoxy HTTP → naiveproxy SOCKS5).
# GUI apps get HTTP_PROXY env vars; terminal apps run inside foot via proxychains4.

set -euo pipefail

if pgrep -x fuzzel > /dev/null; then pkill -x fuzzel; exit 0; fi

PROXY_HTTP="http://127.0.0.1:8118"
PROXY_SOCKS="socks5://127.0.0.1:1080"
TERM_EMU="${TERM_EMULATOR:-foot}"

# ── helpers ──────────────────────────────────────────────────────────────────

notify() { command -v notify-send &>/dev/null && notify-send "Proxy Launch" "$1"; }

# Strip .desktop Exec placeholders and extra whitespace
clean_exec() { echo "$1" | sed 's/%[fFuUdDnNickvm]//g;s/  */ /g' | xargs; }

# ── collect .desktop apps ────────────────────────────────────────────────────

get_apps() {
    local dirs=("/usr/share/applications" "$HOME/.local/share/applications")
    for dir in "${dirs[@]}"; do
        [[ -d "$dir" ]] || continue
        while IFS= read -r f; do
            grep -qE "^(NoDisplay|Hidden)=true" "$f" 2>/dev/null && continue
            local name exec terminal
            name=$(grep    "^Name="     "$f" | head -1 | cut -d= -f2-)
            exec=$(grep    "^Exec="     "$f" | head -1 | cut -d= -f2-)
            terminal=$(grep "^Terminal=" "$f" | head -1 | cut -d= -f2-)
            [[ -z "$name" || -z "$exec" ]] && continue
            printf '%s\t%s\t%s\n' "$name" "$exec" "${terminal:-false}"
        done < <(find "$dir" -maxdepth 1 -name "*.desktop" 2>/dev/null)
    done | sort -t$'\t' -k1 -u
}

app_data=$(get_apps)
[[ -z "$app_data" ]] && { notify "No applications found"; exit 1; }

# ── fuzzel picker ────────────────────────────────────────────────────────────

selected=$(echo "$app_data" | cut -f1 | fuzzel --dmenu \
    --prompt="Proxy> " --lines=20 --width=40) || exit 0
[[ -z "$selected" ]] && exit 0

entry=$(echo "$app_data" | awk -F'\t' -v name="$selected" '$1 == name { print; exit }')
exec_cmd=$(clean_exec "$(echo "$entry" | cut -f2)")
is_term=$(echo "$entry" | cut -f3)

# ── launch ───────────────────────────────────────────────────────────────────

if [[ "$is_term" == "true" ]]; then
    # Terminal app — wrap with proxychains inside a new foot window
    $TERM_EMU sh -c "proxychains4 $exec_cmd" &
else
    # GUI app — inject proxy env vars
    env HTTP_PROXY="$PROXY_HTTP"  http_proxy="$PROXY_HTTP" \
        HTTPS_PROXY="$PROXY_HTTP" https_proxy="$PROXY_HTTP" \
        ALL_PROXY="$PROXY_SOCKS"  all_proxy="$PROXY_SOCKS" \
        $exec_cmd &>/dev/null &
fi

notify "Started via proxy: $selected"
