#!/bin/bash
set -euo pipefail

DDC_LOCK="${DDC_LOCK:-/tmp/waybar_ddcutil.lock}"

ddc_buses() {
    if [ -n "${DDCUTIL_BUSES:-}" ]; then
        printf '%s\n' $DDCUTIL_BUSES
        return 0
    fi

    command -v ddcutil >/dev/null 2>&1 || return 0

    ddcutil detect 2>/dev/null |
        sed -n 's#.*I2C bus:[[:space:]]*/dev/i2c-\([0-9][0-9]*\).*#\1#p'
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
            ddcutil setvcp 10 "$value" --bus "$bus" --noverify --sleep-multiplier 0
        done
    ) 9>"$DDC_LOCK" >/dev/null 2>&1
}
