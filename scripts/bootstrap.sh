#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
PACKAGE_FILE=${PACKAGE_FILE:-"$DOTFILES_DIR/packages/void-desktop.txt"}
SERVICE_FILE=${SERVICE_FILE:-"$DOTFILES_DIR/services/runit-enabled.txt"}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

install_void_packages() {
    [ -r "$PACKAGE_FILE" ] || return 0
    pkgs=$(sed 's/#.*//' "$PACKAGE_FILE" | awk 'NF { print $1 }')
    [ -n "$pkgs" ] || return 0

    repo_pkgs=$(printf '%s\n' $pkgs | awk '/^void-repo-/ { print }')
    if [ -n "$repo_pkgs" ]; then
        as_root xbps-install -Sy $repo_pkgs
        as_root xbps-install -S
    fi

    as_root xbps-install -Sy $pkgs
}

enable_runit_services() {
    [ -r "$SERVICE_FILE" ] || return 0
    [ -d /etc/sv ] || return 0

    while IFS= read -r service; do
        case "$service" in
            ''|'#'*) continue ;;
        esac
        [ -d "/etc/sv/$service" ] || {
            printf 'service not installed, skip: %s\n' "$service" >&2
            continue
        }
        [ -e "/var/service/$service" ] || as_root ln -s "/etc/sv/$service" /var/service/
    done < "$SERVICE_FILE"
}

install_oh_my_zsh() {
    [ -d "$HOME/.oh-my-zsh" ] && return 0
    command -v git >/dev/null 2>&1 || return 0

    git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
}

install_void_packages
install_oh_my_zsh
"$DOTFILES_DIR/scripts/apply.sh"
"$DOTFILES_DIR/scripts/install-power-profile.sh"
enable_runit_services

printf 'bootstrap finished\n'
