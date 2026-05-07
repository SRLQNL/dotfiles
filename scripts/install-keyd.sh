#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_root install -m 755 "$DOTFILES_DIR/system/usr/local/bin/srl-niri-launcher-toggle" /usr/local/bin/srl-niri-launcher-toggle
as_root install -d -m 755 /etc/keyd
as_root install -m 644 "$DOTFILES_DIR/system/etc/keyd/default.conf" /etc/keyd/default.conf

as_root keyd check /etc/keyd/default.conf
as_root keyd reload

if [ -d /etc/sv/keyd ] && [ ! -e /var/service/keyd ]; then
    as_root ln -s /etc/sv/keyd /var/service/
fi

as_root sv up keyd >/dev/null 2>&1 || true

printf 'installed keyd launcher binding\n'
