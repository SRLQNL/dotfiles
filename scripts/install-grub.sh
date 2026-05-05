#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BACKUP_ROOT=${BACKUP_ROOT:-"/root/grub-backup-$(date +%Y%m%d-%H%M%S)"}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_root mkdir -p "$BACKUP_ROOT"
[ -e /etc/default/grub ] && as_root cp -a /etc/default/grub "$BACKUP_ROOT/grub.default"
[ -d /etc/grub.d ] && as_root cp -a /etc/grub.d "$BACKUP_ROOT/grub.d"
[ -e /boot/grub/grub.cfg ] && as_root cp -a /boot/grub/grub.cfg "$BACKUP_ROOT/grub.cfg"

as_root install -m 0644 "$DOTFILES_DIR/system/etc/default/grub" /etc/default/grub
as_root install -m 0755 "$DOTFILES_DIR/system/etc/grub.d/10_void_clean" /etc/grub.d/10_void_clean
as_root mkdir -p /boot/grub/themes
as_root rm -rf /boot/grub/themes/MilkGrub
as_root cp -a "$DOTFILES_DIR/system/boot/grub/themes/MilkGrub" /boot/grub/themes/MilkGrub

for script in 10_linux 20_linux_xen 25_bli 30_os-prober 30_uefi-firmware 35_fwupd 40_custom 41_custom; do
    [ -e "/etc/grub.d/$script" ] && as_root chmod -x "/etc/grub.d/$script"
done

as_root grub-mkconfig -o /boot/grub/grub.cfg
printf 'GRUB installed. Backup: %s\n' "$BACKUP_ROOT"
