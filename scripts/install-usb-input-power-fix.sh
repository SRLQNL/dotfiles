#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
HOSTNAME_KEY=${HOSTNAME_KEY:-$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null | tr -d '\n' || echo unknown)}
RULE_SRC=${USB_INPUT_POWER_RULE:-"$DOTFILES_DIR/hosts/$HOSTNAME_KEY/system/etc/udev/rules.d/99-srl-usb-input-power.rules"}
RULE_DST="/etc/udev/rules.d/99-srl-usb-input-power.rules"

[ -r "$RULE_SRC" ] || {
    printf 'USB input power rule not found for host %s: %s\n' "$HOSTNAME_KEY" "$RULE_SRC" >&2
    exit 1
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_root install -d -m 755 /etc/udev/rules.d
as_root install -m 644 "$RULE_SRC" "$RULE_DST"

if command -v udevadm >/dev/null 2>&1; then
    as_root udevadm control --reload-rules
    as_root udevadm trigger --subsystem-match=usb --action=change
fi

printf 'installed USB input power udev rule: %s\n' "$RULE_DST"
