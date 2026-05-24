#!/bin/sh
# Remote bootstrap entrypoint for a fresh Void Linux user session.
# Usage:
#   sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)"

set -eu

REPO_URL=${DOTFILES_REPO_URL:-https://github.com/SRLQNL/dotfiles.git}
BRANCH=${DOTFILES_BRANCH:-main}
TARGET_DIR=${DOTFILES_DIR:-$HOME/dotfiles}

die() {
    printf 'bootstrap: %s\n' "$*" >&2
    exit 1
}

root_helper() {
    if [ "$(id -u)" -eq 0 ]; then
        return 0
    elif [ -n "${ROOT_CMD:-}" ]; then
        printf '%s\n' "$ROOT_CMD"
    elif command -v sudo >/dev/null 2>&1; then
        printf '%s\n' sudo
    elif command -v doas >/dev/null 2>&1; then
        printf '%s\n' doas
    else
        return 1
    fi
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
        die "root command requires sudo or doas: $*"
    fi
}

[ -x /usr/bin/xbps-install ] || die "this script requires Void Linux (xbps-install not found)"

if [ "$(id -u)" -eq 0 ] && [ "${DOTFILES_ALLOW_ROOT:-0}" != "1" ]; then
    die "run this as your normal user, not root; it will use sudo/doas for system changes"
fi

if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    root_helper >/dev/null || die "install git/curl first or configure sudo/doas"
    as_root xbps-install -Sy git curl ca-certificates
fi

if [ -e "$TARGET_DIR/.git" ]; then
    remote=$(git -C "$TARGET_DIR" remote get-url origin 2>/dev/null || true)
    [ "$remote" = "$REPO_URL" ] || die "$TARGET_DIR is a git repo with unexpected origin: ${remote:-none}"
    git -C "$TARGET_DIR" fetch origin "$BRANCH"
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only origin "$BRANCH"
elif [ -e "$TARGET_DIR" ]; then
    die "$TARGET_DIR already exists and is not a git repo"
else
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
exec ./install.sh --bootstrap "$@"
