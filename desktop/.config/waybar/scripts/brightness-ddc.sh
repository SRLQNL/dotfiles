#!/bin/bash
set -euo pipefail

DDC_LOCK="${DDC_LOCK:-/tmp/waybar_ddcutil.lock}"
DDC_BUSES_CACHE="${DDC_BUSES_CACHE:-/tmp/waybar_ddcutil_buses}"
DDC_BUSES_CACHE_TTL="${DDC_BUSES_CACHE_TTL:-3600}"
DDC_SET_SLEEP_MULTIPLIER="${DDC_SET_SLEEP_MULTIPLIER:-0}"

cache_is_fresh() {
    file=$1
    ttl=$2
    [ -s "$file" ] || return 1

    now=$(date +%s)
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo 0)
    [ $((now - mtime)) -lt "$ttl" ]
}

detect_buses() {
    command -v ddcutil >/dev/null 2>&1 || return 0

    ddcutil detect 2>/dev/null |
        sed -n 's#.*I2C bus:[[:space:]]*/dev/i2c-\([0-9][0-9]*\).*#\1#p'
}

refresh_bus_cache() {
    tmp="${DDC_BUSES_CACHE}.$$"
    buses=$(
        (
            flock -x 9
            detect_buses || true
        ) 9>"$DDC_LOCK"
    )
    [ -n "$buses" ] || return 1
    mkdir -p "$(dirname -- "$DDC_BUSES_CACHE")"
    printf '%s\n' $buses > "$tmp"
    mv "$tmp" "$DDC_BUSES_CACHE"
}

ddc_buses() {
    if [ -n "${DDCUTIL_BUSES:-}" ]; then
        printf '%s\n' $DDCUTIL_BUSES
        return 0
    fi

    if [ -s "$DDC_BUSES_CACHE" ]; then
        cat "$DDC_BUSES_CACHE"
        if ! cache_is_fresh "$DDC_BUSES_CACHE" "$DDC_BUSES_CACHE_TTL"; then
            refresh_bus_cache >/dev/null 2>&1 &
        fi
        return 0
    fi

    refresh_bus_cache >/dev/null 2>&1 || return 0
    [ -s "$DDC_BUSES_CACHE" ] && cat "$DDC_BUSES_CACHE"
}

ddc_read_values() {
    command -v ddcutil >/dev/null 2>&1 || return 0

    ddc_buses | while IFS= read -r bus; do
        [ -n "$bus" ] || continue
        ddcutil getvcp 10 --bus "$bus" 2>/dev/null |
            sed -n 's/.*current value = *\([0-9][0-9]*\).*/\1/p'
    done
}

ddc_average_brightness() {
    vals=$(ddc_read_values || true)
    [ -n "$vals" ] || return 1

    count=0
    sum=0
    for val in $vals; do
        count=$((count + 1))
        sum=$((sum + val))
    done
    [ "$count" -gt 0 ] || return 1
    printf '%s\n' $((sum / count))
}

ddc_apply_brightness() {
    value=$1
    buses=$(ddc_buses || true)
    [ -n "$buses" ] || return 0

    (
        flock -x 9
        for bus in $buses; do
            ddcutil setvcp 10 "$value" \
                --bus "$bus" \
                --noverify \
                --sleep-multiplier "$DDC_SET_SLEEP_MULTIPLIER" &
        done
        wait
    ) 9>"$DDC_LOCK" >/dev/null 2>&1
}
