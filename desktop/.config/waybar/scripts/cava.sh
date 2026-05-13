#!/usr/bin/env bash
set -euo pipefail

bar="▁▂▃▄▅▆▇█"

# write cava config
config_file="/tmp/polybar_cava_config"
cat > "$config_file" <<EOF
[general]
bars = 18

[input]
method = pulse

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

# read stdout from cava
cava -p "$config_file" | while IFS= read -r line; do
    line=${line//;/}
    out=""
    for ((i=0; i<${#line}; i++)); do
        ch=${line:i:1}
        case "$ch" in
            [0-7]) out+="${bar:ch:1}" ;;
            *) out+="$ch" ;;
        esac
    done
    if ! printf '%s\n' "$out" 2>/dev/null; then
        break
    fi
done
