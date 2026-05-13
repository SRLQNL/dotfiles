#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
HOSTNAME_KEY=${HOSTNAME_KEY:-$(cat /etc/hostname 2>/dev/null | cut -d. -f1 || hostname 2>/dev/null || echo unknown)}
RULE_SRC=${USB_INPUT_POWER_RULE:-"$DOTFILES_DIR/hosts/$HOSTNAME_KEY/system/etc/udev/rules.d/99-srl-usb-input-power.rules"}
RULE_DST="/etc/udev/rules.d/99-srl-usb-input-power.rules"

[ -r "$RULE_SRC" ] || {
    printf 'USB input power rule not found for host %s: %s\n' "$HOSTNAME_KEY" "$RULE_SRC" >&2
    exit 1
}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    elif [ -n "${ROOT_CMD:-}" ]; then
        "$ROOT_CMD" "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        doas "$@"
    else
        printf 'root command requires sudo or doas\n' >&2
        exit 1
    fi
}

as_root install -d -m 755 /etc/udev/rules.d
as_root install -m 644 "$RULE_SRC" "$RULE_DST"

if command -v udevadm >/dev/null 2>&1; then
    as_root udevadm control --reload-rules
    as_root udevadm trigger --subsystem-match=usb --action=change
fi

printf 'installed USB input power udev rule: %s\n' "$RULE_DST"
