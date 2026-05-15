# Load host-specific env vars (monitor names, paths, etc.)
if [ -f "$HOME/.config/environment.d/dotfiles-host.conf" ]; then
    # shellcheck source=/dev/null
    case $- in
        *a*) . "$HOME/.config/environment.d/dotfiles-host.conf" ;;
        *)
            set -a
            . "$HOME/.config/environment.d/dotfiles-host.conf"
            set +a
            ;;
    esac
fi

