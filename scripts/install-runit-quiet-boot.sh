#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BACKUP_ROOT=${BACKUP_ROOT:-"/root/runit-backup-$(date +%Y%m%d-%H%M%S)"}
RUNIT_QUIET_FORCE=${RUNIT_QUIET_FORCE:-0}

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
        die "root command requires sudo or doas"
    fi
}

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

looks_like_void_stage1() {
    file=$1
    [ -e "$file" ] || return 1
    grep -q '/etc/runit/functions' "$file" &&
        grep -q 'core-services' "$file"
}

looks_like_void_stage2() {
    file=$1
    [ -e "$file" ] || return 1
    grep -q 'runsvchdir' "$file" &&
        grep -q 'runsvdir' "$file"
}

[ -r "$DOTFILES_DIR/system/etc/runit/1" ] || die "Missing runit stage 1 template"
[ -r "$DOTFILES_DIR/system/etc/runit/2" ] || die "Missing runit stage 2 template"

if [ "$RUNIT_QUIET_FORCE" != 1 ]; then
    looks_like_void_stage1 /etc/runit/1 || die "Refusing to replace unrecognized /etc/runit/1; set RUNIT_QUIET_FORCE=1 to override"
    looks_like_void_stage2 /etc/runit/2 || die "Refusing to replace unrecognized /etc/runit/2; set RUNIT_QUIET_FORCE=1 to override"
fi

as_root mkdir -p "$BACKUP_ROOT"
[ -e /etc/runit/1 ] && as_root cp -a /etc/runit/1 "$BACKUP_ROOT/1"
[ -e /etc/runit/2 ] && as_root cp -a /etc/runit/2 "$BACKUP_ROOT/2"

as_root install -m 0755 "$DOTFILES_DIR/system/etc/runit/1" /etc/runit/1
as_root install -m 0755 "$DOTFILES_DIR/system/etc/runit/2" /etc/runit/2

printf 'runit quiet boot installed. Backup: %s\n' "$BACKUP_ROOT"
printf 'Force mode: RUNIT_QUIET_FORCE=%s\n' "$RUNIT_QUIET_FORCE"
