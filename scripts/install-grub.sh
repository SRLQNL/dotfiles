#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
BACKUP_ROOT=${BACKUP_ROOT:-"/root/grub-backup-$(date +%Y%m%d-%H%M%S)"}
GRUB_DEFAULT_TEMPLATE=${GRUB_DEFAULT_TEMPLATE:-"$DOTFILES_DIR/system/etc/default/grub"}
GRUB_EXTRA_CMDLINE=${GRUB_EXTRA_CMDLINE:-}
GRUB_GFXMODE=${GRUB_GFXMODE:-}
GRUB_INSTALL_CLEAN_MENU=${GRUB_INSTALL_CLEAN_MENU:-0}
GRUB_DISABLE_FOREIGN_SCRIPTS=${GRUB_DISABLE_FOREIGN_SCRIPTS:-0}
GRUBD_DISABLE_LIST=${GRUBD_DISABLE_LIST:-"10_linux 20_linux_xen 25_bli 30_os-prober 30_uefi-firmware 35_fwupd 40_custom 41_custom"}

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

extract_var() {
    extract_var_name=$1
    extract_var_file=$2
    awk -v var="$extract_var_name" '
        $0 ~ "^[[:space:]]*" var "=" {
            sub("^[[:space:]]*" var "=", "")
            print
            exit
        }
    ' "$extract_var_file"
}

strip_quotes() {
    strip_quotes_value=$1
    case $strip_quotes_value in
        \"*\") strip_quotes_value=${strip_quotes_value#\"}; strip_quotes_value=${strip_quotes_value%\"} ;;
        \'*\') strip_quotes_value=${strip_quotes_value#\'}; strip_quotes_value=${strip_quotes_value%\'} ;;
    esac
    printf '%s\n' "$strip_quotes_value"
}

quote_value() {
    quote_value_value=$1
    quote_value_value=$(printf '%s\n' "$quote_value_value" | sed 's/"/\\"/g')
    printf '"%s"\n' "$quote_value_value"
}

set_grub_var() {
    set_grub_var_file=$1
    set_grub_var_name=$2
    set_grub_var_value=$3
    set_grub_var_tmp="${set_grub_var_file}.tmp"

    awk -v var="$set_grub_var_name" -v value="$set_grub_var_value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*" var "=" && done == 0 {
            print var "=" value
            done = 1
            next
        }
        { print }
        END {
            if (done == 0) {
                print var "=" value
            }
        }
    ' "$set_grub_var_file" > "$set_grub_var_tmp"
    mv "$set_grub_var_tmp" "$set_grub_var_file"
}

merge_cmdline_default() {
    merge_cmdline_file=$1
    merge_cmdline_desired=$(strip_quotes "$(extract_var GRUB_CMDLINE_LINUX_DEFAULT "$GRUB_DEFAULT_TEMPLATE")")
    merge_cmdline_desired="${merge_cmdline_desired:+$merge_cmdline_desired }$GRUB_EXTRA_CMDLINE"
    merge_cmdline_current=$(strip_quotes "$(extract_var GRUB_CMDLINE_LINUX_DEFAULT "$merge_cmdline_file")")
    merge_cmdline_merged=$merge_cmdline_current

    for merge_cmdline_arg in $merge_cmdline_desired; do
        case " $merge_cmdline_merged " in
            *" $merge_cmdline_arg "*) ;;
            *) merge_cmdline_merged="${merge_cmdline_merged:+$merge_cmdline_merged }$merge_cmdline_arg" ;;
        esac
    done

    set_grub_var "$merge_cmdline_file" GRUB_CMDLINE_LINUX_DEFAULT "$(quote_value "$merge_cmdline_merged")"
}

merge_grub_defaults() {
    merge_defaults_tmp=$(mktemp)
    trap 'rm -f "$merge_defaults_tmp"' EXIT
    if [ -e /etc/default/grub ]; then
        cp /etc/default/grub "$merge_defaults_tmp"
    else
        {
            printf '# Configuration file for GRUB.\n'
            printf '# Created by %s.\n\n' "$0"
        } > "$merge_defaults_tmp"
    fi

    for merge_defaults_var in GRUB_TIMEOUT GRUB_DISTRIBUTOR GRUB_GFXMODE GRUB_DISABLE_SUBMENU; do
        merge_defaults_value=$(extract_var "$merge_defaults_var" "$GRUB_DEFAULT_TEMPLATE")
        if [ "$merge_defaults_var" = "GRUB_GFXMODE" ] && [ -n "$GRUB_GFXMODE" ]; then
            merge_defaults_value=$(quote_value "$GRUB_GFXMODE")
        fi
        [ -n "$merge_defaults_value" ] && set_grub_var "$merge_defaults_tmp" "$merge_defaults_var" "$merge_defaults_value"
    done
    # GRUB_THEME is set explicitly here (not read from template) because the
    # template keeps it commented out to avoid errors on machines without the theme.
    # install-grub.sh is only called when grub-themed profile is active, so it is
    # safe to always enable the theme when this script runs.
    set_grub_var "$merge_defaults_tmp" GRUB_THEME '"/boot/grub/themes/MilkGrub/theme.txt"'
    merge_cmdline_default "$merge_defaults_tmp"

    as_root install -m 0644 "$merge_defaults_tmp" /etc/default/grub
    rm -f "$merge_defaults_tmp" "${merge_defaults_tmp}.tmp"
}

[ -r "$GRUB_DEFAULT_TEMPLATE" ] || die "Missing GRUB template: $GRUB_DEFAULT_TEMPLATE"

if [ "$GRUB_DISABLE_FOREIGN_SCRIPTS" = 1 ] && [ "$GRUB_INSTALL_CLEAN_MENU" != 1 ]; then
    die "GRUB_DISABLE_FOREIGN_SCRIPTS=1 requires GRUB_INSTALL_CLEAN_MENU=1"
fi

as_root mkdir -p "$BACKUP_ROOT"
[ -e /etc/default/grub ] && as_root cp -a /etc/default/grub "$BACKUP_ROOT/grub.default"
[ -d /etc/grub.d ] && as_root cp -a /etc/grub.d "$BACKUP_ROOT/grub.d"
[ -e /boot/grub/grub.cfg ] && as_root cp -a /boot/grub/grub.cfg "$BACKUP_ROOT/grub.cfg"

merge_grub_defaults
as_root mkdir -p /boot/grub/themes
as_root rm -rf /boot/grub/themes/MilkGrub
as_root cp -a "$DOTFILES_DIR/system/boot/grub/themes/MilkGrub" /boot/grub/themes/MilkGrub

if [ "$GRUB_INSTALL_CLEAN_MENU" = 1 ]; then
    as_root install -m 0755 "$DOTFILES_DIR/system/etc/grub.d/10_void_clean" /etc/grub.d/10_void_clean
fi

if [ "$GRUB_DISABLE_FOREIGN_SCRIPTS" = 1 ]; then
    for script in $GRUBD_DISABLE_LIST; do
        [ -e "/etc/grub.d/$script" ] && as_root chmod -x "/etc/grub.d/$script"
    done
fi

as_root grub-mkconfig -o /boot/grub/grub.cfg
printf 'GRUB installed. Backup: %s\n' "$BACKUP_ROOT"
printf 'Clean menu opt-in: GRUB_INSTALL_CLEAN_MENU=%s, GRUB_DISABLE_FOREIGN_SCRIPTS=%s\n' "$GRUB_INSTALL_CLEAN_MENU" "$GRUB_DISABLE_FOREIGN_SCRIPTS"
