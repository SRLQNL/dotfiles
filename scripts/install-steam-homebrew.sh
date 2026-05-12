#!/bin/sh
set -eu

STEAM_DATA_DIR=${STEAM_DATA_DIR:-$HOME/.local/share/Steam}
STEAM_LIBRARY_DIR=${STEAM_LIBRARY_DIR:-$HOME/.local/share/Steam/SteamLibrary}
STEAM_HOMEBREW_REPO=${STEAM_HOMEBREW_REPO:-SteamClientHomebrew/Millennium}
STEAM_HOMEBREW_VERSION=${STEAM_HOMEBREW_VERSION:-3.0.0-beta.24}

as_root() {
    if [ "$(id -u)" -eq 0 ]; then
        "$@"
    else
        sudo "$@"
    fi
}

require_cmd() {
    command -v "$1" >/dev/null 2>&1 || {
        printf 'missing command: %s\n' "$1" >&2
        exit 1
    }
}

install_void_steam() {
    as_root xbps-install -Sy void-repo-multilib void-repo-nonfree void-repo-multilib-nonfree
    as_root xbps-install -S
    as_root xbps-install -Sy \
        steam steam-udev-rules \
        nvidia-libs-32bit vulkan-loader-32bit libva-32bit \
        libssl3-32bit openssl-32bit \
        libpulseaudio-32bit alsa-plugins-pulseaudio-32bit \
        mono
}

setup_steam_paths() {
    mkdir -p "$HOME/.local/share" "$HOME/.steam" "$STEAM_DATA_DIR" "$STEAM_LIBRARY_DIR"
    ln -sfn "$STEAM_DATA_DIR" "$HOME/.local/share/Steam"
    ln -sfn "$STEAM_DATA_DIR" "$HOME/.steam/steam"
    ln -sfn "$STEAM_DATA_DIR" "$HOME/.steam/root"
}

setup_steam_fontconfig() {
    fcdir="$HOME/.config/steam-fontconfig"
    mkdir -p "$fcdir/conf.d" "$HOME/.local/bin" "$HOME/.local/share/applications"
    rm -f "$fcdir/conf.d"/*.conf

    for file in /etc/fonts/conf.d/*.conf; do
        base=${file##*/}
        [ "$base" = "10-scale-bitmap-fonts.conf" ] && continue
        sed '/<description>/d' "$file" > "$fcdir/conf.d/$base"
    done

    cat > "$fcdir/fonts.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <dir>/usr/share/fonts</dir>
  <dir>/usr/local/share/fonts</dir>
  <dir>$HOME/.local/share/fonts</dir>
  <dir>$HOME/.fonts</dir>
  <cachedir>/var/cache/fontconfig</cachedir>
  <cachedir>$HOME/.cache/fontconfig</cachedir>
  <include ignore_missing="yes">$fcdir/conf.d</include>
</fontconfig>
EOF

    cat > "$HOME/.local/bin/steam" <<EOF
#!/bin/sh
export FONTCONFIG_FILE="\${FONTCONFIG_FILE:-$fcdir/fonts.conf}"
exec /usr/bin/steam "\$@"
EOF
    chmod +x "$HOME/.local/bin/steam"

    if [ -r /usr/share/applications/steam.desktop ]; then
        cp /usr/share/applications/steam.desktop "$HOME/.local/share/applications/steam.desktop"
        sed -i "s#Exec=/usr/bin/steam#Exec=env FONTCONFIG_FILE=$fcdir/fonts.conf /usr/bin/steam#g" \
            "$HOME/.local/share/applications/steam.desktop"
    fi
}

bootstrap_steam_client() {
    bootstrap=/usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz
    [ -x "$STEAM_DATA_DIR/steam.sh" ] && return 0
    [ -r "$bootstrap" ] || {
        printf 'missing Steam bootstrap: %s\n' "$bootstrap" >&2
        exit 1
    }

    tar xJf "$bootstrap" -C "$STEAM_DATA_DIR"
}

patch_library_paths() {
    file="$STEAM_DATA_DIR/steamapps/libraryfolders.vdf"
    [ -r "$file" ] || return 0

    tmp=$(mktemp)
    sed "s#$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam#$STEAM_DATA_DIR#g" "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

install_millennium() {
    target=linux-x86_64
    version=${STEAM_HOMEBREW_VERSION#v}
    base="https://github.com/$STEAM_HOMEBREW_REPO/releases/download/v$version"
    name="millennium-v$version-$target.tar.gz"
    work=$(mktemp -d)
    trap 'rm -rf "$work"' EXIT INT TERM

    curl -fL "$base/$name" -o "$work/$name"
    curl -fsSL "$base/millennium-v$version-$target.sha256" -o "$work/$name.sha256"
    (cd "$work" && sha256sum -c "$name.sha256")

    mkdir -p "$work/files"
    tar xzf "$work/$name" -C "$work/files"
    as_root cp -r "$work/files"/* /

    as_root chmod +x /opt/python-i686-3.11.8/bin/python3.11 2>/dev/null || true
    as_root chmod +x /usr/lib/millennium/libmillennium_pvs64 2>/dev/null || true
    as_root chmod +x /usr/lib/millennium/libmillennium_luavm_x86 2>/dev/null || true

    if [ -d "$HOME/.steam/steam/ubuntu12_32" ]; then
        if [ -r /usr/lib/millennium/libmillennium_bootstrap_x86.so ]; then
            hook=/usr/lib/millennium/libmillennium_bootstrap_x86.so
        else
            hook=/usr/lib/millennium/libmillennium_bootstrap_86x.so
        fi
        ln -sf "$hook" "$HOME/.steam/steam/ubuntu12_32/libXtst.so.6"
    fi
}

require_cmd curl
require_cmd jq
require_cmd tar
require_cmd sha256sum

install_void_steam
setup_steam_paths
setup_steam_fontconfig
bootstrap_steam_client
patch_library_paths
install_millennium

printf 'Steam Homebrew installed. Steam data: %s\n' "$STEAM_DATA_DIR"
