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

as_root install -d -m 755 /etc/sv/srl-power-profile
as_root install -m 755 "$DOTFILES_DIR/system/etc/sv/srl-power-profile/run" /etc/sv/srl-power-profile/run

if [ -e /var/service/cpu-performance ]; then
    as_root sv down cpu-performance >/dev/null 2>&1 || true
    as_root rm -f /var/service/cpu-performance
fi

as_root rm -rf /etc/sv/cpu-performance

if [ -d /etc/sv/thermald ] && [ ! -e /var/service/thermald ]; then
    as_root ln -s /etc/sv/thermald /var/service/
fi

if [ ! -e /var/service/srl-power-profile ]; then
    as_root ln -s /etc/sv/srl-power-profile /var/service/
fi

as_root sv up thermald >/dev/null 2>&1 || true
as_root sv restart srl-power-profile >/dev/null 2>&1 || as_root sv up srl-power-profile >/dev/null 2>&1 || true

printf 'installed SRL power profile\n'
