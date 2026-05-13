#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
TARGET_HOME=${TARGET_HOME:-$HOME}
PACKAGES=${PACKAGES:-"home desktop apps media bin"}
BACKUP_ROOT=${BACKUP_ROOT:-"${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/backups/$(date +%Y%m%d-%H%M%S)"}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing command: %s\n' "$1" >&2
        exit 1
    }
}

is_ours() {
    target=$1
    src=$2

    target_real=$(readlink -f -- "$target" 2>/dev/null || true)
    src_real=$(readlink -f -- "$src" 2>/dev/null || true)
    if [ -n "$target_real" ] && [ "$target_real" = "$src_real" ]; then
        return 0
    fi

    case "$target_real" in
        "$DOTFILES_DIR"/*) return 0 ;;
    esac

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

        case "$rel" in
            .config/niri/outputs-host.kdl) continue ;;
        esac

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
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles"
chmod 700 "${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles" 2>/dev/null || true

for package in $PACKAGES; do
    backup_conflicts "$package"
    stow --dir="$DOTFILES_DIR" --target="$TARGET_HOME" --no-folding --ignore='^\.config/niri/outputs-host\.kdl$' --restow "$package"
done

mime_src=$DOTFILES_DIR/apps/.config/mimeapps.list
mime_target=$TARGET_HOME/.config/mimeapps.list
if [ -e "$mime_src" ] && [ -L "$mime_target" ] && [ "$(readlink -f -- "$mime_target" 2>/dev/null || true)" = "$mime_src" ]; then
    mkdir -p "$(dirname -- "$mime_target")"
    ln -sfn -- "$mime_src" "$mime_target"
fi

printf 'applied packages: %s\n' "$PACKAGES"
if [ -d "$BACKUP_ROOT" ]; then
    printf 'conflict backups: %s\n' "$BACKUP_ROOT"
fi
