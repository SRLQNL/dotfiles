#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}

copy_path() {
    src=$1
    dst=$2
    [ -e "$src" ] || return 0

    src_real=$(readlink -f -- "$src" 2>/dev/null || true)
    dst_real=$(readlink -f -- "$dst" 2>/dev/null || true)
    case "$src_real" in
        "$DOTFILES_DIR"/*)
            [ "$src_real" = "$dst_real" ] && return 0
            ;;
    esac

    tmp="${dst}.tmp.$$"
    rm -rf -- "$tmp"
    mkdir -p "$(dirname -- "$dst")"
    cp -a -- "$src" "$tmp"
    rm -rf -- "$dst"
    mv -- "$tmp" "$dst"
}

copy_path "$HOME/.zshrc" "$DOTFILES_DIR/home/.zshrc"
copy_path "$HOME/.zprofile" "$DOTFILES_DIR/home/.zprofile"
copy_path "$HOME/.bashrc" "$DOTFILES_DIR/home/.bashrc"
copy_path "$HOME/.bash_profile" "$DOTFILES_DIR/home/.bash_profile"
copy_path "$HOME/.gitconfig" "$DOTFILES_DIR/home/.gitconfig"
copy_path "$HOME/.gtkrc-2.0" "$DOTFILES_DIR/home/.gtkrc-2.0"
copy_path "$HOME/.inputrc" "$DOTFILES_DIR/home/.inputrc"
copy_path "$HOME/.vimrc" "$DOTFILES_DIR/home/.vimrc"
copy_path "$HOME/.hushlogin" "$DOTFILES_DIR/home/.hushlogin"
copy_path "$HOME/.config/starship.toml" "$DOTFILES_DIR/home/.config/starship.toml"
copy_path "$HOME/.config/git" "$DOTFILES_DIR/home/.config/git"

for d in niri waybar mako foot swaylock xdg-desktop-portal xsettingsd autostart; do
    copy_path "$HOME/.config/$d" "$DOTFILES_DIR/desktop/.config/$d"
done
find "$DOTFILES_DIR/desktop/.config/niri" -maxdepth 1 -type f \( -name '*backup-*' -o -name '*before-*' -o -name 'last_wallpaper*.txt' \) -delete 2>/dev/null || true
find "$DOTFILES_DIR/desktop/.config/foot" -maxdepth 1 -type f -name '*.before-*' -delete 2>/dev/null || true
rm -f "$DOTFILES_DIR/desktop/.config/waybar/save"
rm -f "$DOTFILES_DIR/desktop/.config/waybar/modules.json"
rm -f "$DOTFILES_DIR/desktop/.config/autostart/easyeffects.desktop"

for d in btop fastfetch fontconfig gtk-2.0 gtk-3.0 gtk-4.0 mpv viewnior xarchiver; do
    copy_path "$HOME/.config/$d" "$DOTFILES_DIR/apps/.config/$d"
done
rm -rf "$DOTFILES_DIR/apps/.config/fastfetch/ascii.txt" \
       "$DOTFILES_DIR/apps/.config/fastfetch/assets/anime-girl.png" \
       "$DOTFILES_DIR/apps/.config/fastfetch/assets/candidates" \
       "$DOTFILES_DIR/apps/.config/fastfetch/assets/selected-anime-girl.jpg"
if [ -e "$DOTFILES_DIR/apps/.config/gtk-4.0/gtk-Dark.css" ]; then
    rm -f "$DOTFILES_DIR/apps/.config/gtk-4.0/gtk-dark.css"
    ln -s gtk-Dark.css "$DOTFILES_DIR/apps/.config/gtk-4.0/gtk-dark.css"
fi
for f in mimeapps.list pavucontrol.ini user-dirs.conf user-dirs.dirs user-dirs.locale trashrc; do
    copy_path "$HOME/.config/$f" "$DOTFILES_DIR/apps/.config/$f"
done

for d in pipewire wireplumber pulse; do
    copy_path "$HOME/.config/$d" "$DOTFILES_DIR/media/.config/$d"
done
find "$DOTFILES_DIR/media/.config/pulse" \( -type f -o -type l \) \( -name '*.tdb' -o -name 'cookie' -o -name '*-runtime' -o -name '*-default-sink' -o -name '*-default-source' -o -name '*-stream-volumes.tdb' -o -name '*-device-volumes.tdb' -o -name '*-card-database.tdb' \) -delete 2>/dev/null || true

mkdir -p "$DOTFILES_DIR/bin/.local/bin"
for f in thunar-open-root-here thunar-open-terminal-here; do
    copy_path "$HOME/.local/bin/$f" "$DOTFILES_DIR/bin/.local/bin/$f"
done

if [ -d /var/service ]; then
    tmp="$DOTFILES_DIR/services/runit-enabled.txt.tmp.$$"
    find /var/service -maxdepth 1 -mindepth 1 -printf '%f\n' 2>/dev/null | sort > "$tmp"
    mv -- "$tmp" "$DOTFILES_DIR/services/runit-enabled.txt"
fi

printf 'snapshot updated: %s\n' "$DOTFILES_DIR"
