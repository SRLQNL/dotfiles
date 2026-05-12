#!/bin/bash
set -euo pipefail

BAT=$(find /sys/class/power_supply -maxdepth 1 -type l -name 'BAT*' | head -n 1)
AC=$(find /sys/class/power_supply -maxdepth 1 -type l \( -name 'AC*' -o -name 'ADP*' -o -name 'Mains*' \) | head -n 1)

if [[ -z "${BAT:-}" || ! -r "$BAT/status" || ! -r "$BAT/capacity" ]]; then
    printf '{"text":"","tooltip":"No battery detected","class":"absent"}\n'
    exit 0
fi

status=$(cat "$BAT/status")
ac=0
[[ -n "${AC:-}" && -r "$AC/online" ]] && ac=$(cat "$AC/online")
percentage=$(cat "$BAT/capacity")

get_icon() {
    local p=$1
    if [ "$p" -ge 80 ]; then echo ""; fi
    if [ "$p" -ge 60 ] && [ "$p" -lt 80 ]; then echo ""; fi
    if [ "$p" -ge 40 ] && [ "$p" -lt 60 ]; then echo ""; fi
    if [ "$p" -ge 20 ] && [ "$p" -lt 40 ]; then echo ""; fi
    if [ "$p" -lt 20 ]; then echo ""; fi
}

if [ "$status" = "Charging" ] || ([ "$status" = "Not charging" ] && [ "$ac" = "1" ]); then
    # Solo enchufe cuando está enchufado
    echo " $percentage%"
else
    # Solo icono de batería cuando está descargando
    icon=$(get_icon $percentage)
    echo "$icon $percentage%"
fi

