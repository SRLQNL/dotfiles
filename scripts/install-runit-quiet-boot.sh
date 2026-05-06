#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BACKUP_ROOT=${BACKUP_ROOT:-"/root/runit-backup-$(date +%Y%m%d-%H%M%S)"}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_root mkdir -p "$BACKUP_ROOT"
[ -e /etc/runit/1 ] && as_root cp -a /etc/runit/1 "$BACKUP_ROOT/1"
[ -e /etc/runit/2 ] && as_root cp -a /etc/runit/2 "$BACKUP_ROOT/2"

as_root install -m 0755 "$DOTFILES_DIR/system/etc/runit/1" /etc/runit/1
as_root install -m 0755 "$DOTFILES_DIR/system/etc/runit/2" /etc/runit/2

printf 'runit quiet boot installed. Backup: %s\n' "$BACKUP_ROOT"
