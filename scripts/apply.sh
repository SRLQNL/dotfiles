#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TARGET_HOME=${TARGET_HOME:-$HOME}
PACKAGES=${PACKAGES:-"home desktop apps media bin"}
BACKUP_ROOT=${BACKUP_ROOT:-"$DOTFILES_DIR/backups/$(date +%Y%m%d-%H%M%S)"}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing command: %s\n' "$1" >&2
        exit 1
    }
}

is_ours() {
    target=$1
    src=$2
    [ -L "$target" ] || return 1
    [ "$(readlink -- "$target")" = "$src" ] && return 0
    case "$(readlink -- "$target")" in
        "$DOTFILES_DIR"/*) return 0 ;;
    esac
    return 1
}

backup_conflicts() {
    package=$1
    package_dir=$DOTFILES_DIR/$package

    [ -d "$package_dir" ] || {
        printf 'skip missing package: %s\n' "$package" >&2
        return 0
    }

    find "$package_dir" \( -type f -o -type l \) | while IFS= read -r src; do
        rel=${src#"$package_dir"/}
        target=$TARGET_HOME/$rel

        if [ -e "$target" ] || [ -L "$target" ]; then
            if is_ours "$target" "$src"; then
                continue
            fi

            backup=$BACKUP_ROOT/$rel
            mkdir -p "$(dirname -- "$backup")"
            mv -- "$target" "$backup"
            printf 'backup: %s -> %s\n' "$target" "$backup"
        fi
    done
}

need stow
mkdir -p "$TARGET_HOME"

for package in $PACKAGES; do
    backup_conflicts "$package"
    stow --dir="$DOTFILES_DIR" --target="$TARGET_HOME" --no-folding --restow "$package"
done

printf 'applied packages: %s\n' "$PACKAGES"
if [ -d "$BACKUP_ROOT" ]; then
    printf 'conflict backups: %s\n' "$BACKUP_ROOT"
fi
