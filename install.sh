#!/bin/sh
# install.sh — portable bootstrap for Void Linux dotfiles
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --dry-run           Show what would be done without making changes
#   --host HOSTNAME     Override hostname for host config (default: /etc/hostname basename)
#   --profiles LIST     Additional profiles to load (quoted, repeated, or space-separated)
#   --skip-packages     Skip xbps package installation
#   --skip-stow         Skip stow apply
#   --skip-system       Skip system-level changes (GRUB, runit services)
#   --yes               Non-interactive (no confirmation prompts)
#
# Profiles available: desktop-nvidia  laptop  steam  grub-themed  power-profile
#
# Quick start for a new Void machine:
#   git clone <repo> ~/dotfiles && cd ~/dotfiles
#   HOST=$(hostname 2>/dev/null | cut -d. -f1)
#   [ -n "$HOST" ] || HOST=unknown
#   mkdir -p "hosts/$HOST"
#   cp hosts/example/host.env "hosts/$HOST/host.env"
#   # edit "hosts/$HOST/host.env" for your hardware
#   ./install.sh

set -eu

DOTFILES_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG_FILE="${LOG_FILE:-/tmp/dotfiles-install.log}"
DRY_RUN=0
OPT_HOST=""
OPT_PROFILES=""
SKIP_PACKAGES=0
SKIP_STOW=0
SKIP_SYSTEM=0
YES=0

usage() {
    awk '
        /^# Usage:/ { in_usage = 1 }
        in_usage && /^#/ { sub(/^# ?/, ""); print; next }
        in_usage { exit }
    ' "$0"
}

hostname_key_default() {
    host=""
    if [ -r /etc/hostname ]; then
        IFS= read -r host < /etc/hostname || host=""
        host=${host%%.*}
    fi
    if [ -z "$host" ]; then
        host=$(hostname 2>/dev/null || true)
        host=${host%%.*}
    fi
    printf '%s\n' "${host:-unknown}"
}

append_words() {
    current=$1
    shift
    for word do
        [ -n "$word" ] || continue
        current="${current:+$current }$word"
    done
    printf '%s\n' "$current"
}

unique_words() {
    unique_seen=""
    for word do
        [ -n "$word" ] || continue
        case " $unique_seen " in
            *" $word "*) ;;
            *) unique_seen="${unique_seen:+$unique_seen }$word" ;;
        esac
    done
    printf '%s\n' "$unique_seen"
}

# --- argument parsing ---
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --host)
            shift
            [ $# -gt 0 ] || { printf 'Option --host requires a hostname\n' >&2; exit 1; }
            case "$1" in --*) printf 'Option --host requires a hostname\n' >&2; exit 1 ;; esac
            OPT_HOST="$1"
            ;;
        --host=*)
            OPT_HOST=${1#--host=}
            [ -n "$OPT_HOST" ] || { printf 'Option --host requires a hostname\n' >&2; exit 1; }
            ;;
        --profiles)
            shift
            [ $# -gt 0 ] || { printf 'Option --profiles requires at least one profile\n' >&2; exit 1; }
            profiles_before=$OPT_PROFILES
            while [ $# -gt 0 ]; do
                case "$1" in --*) break ;; esac
                OPT_PROFILES=$(append_words "$OPT_PROFILES" "$1")
                shift
            done
            [ "$OPT_PROFILES" != "$profiles_before" ] || { printf 'Option --profiles requires at least one profile\n' >&2; exit 1; }
            continue
            ;;
        --profiles=*)
            profiles_arg=${1#--profiles=}
            [ -n "$profiles_arg" ] || { printf 'Option --profiles requires at least one profile\n' >&2; exit 1; }
            OPT_PROFILES=$(append_words "$OPT_PROFILES" $profiles_arg)
            ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-stow)    SKIP_STOW=1 ;;
        --skip-system)  SKIP_SYSTEM=1 ;;
        --yes|-y)       YES=1 ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
    esac
    shift
done

# --- logging ---
mkdir -p "$(dirname "$LOG_FILE")"
log() {
    level=$1; shift
    ts=$(date '+%F %T')
    printf '[%s] %s: %s\n' "$ts" "$level" "$*" | tee -a "$LOG_FILE"
}
info()  { log INFO  "$*"; }
warn()  { log WARN  "$*"; }
error() { log ERROR "$*" >&2; }
die()   { error "$*"; exit 1; }

dry() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] $*"
    else
        info "run: $*"
        eval "$*"
    fi
}

# --- privilege helpers ---
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

require_root_helper() {
    reason=$1
    if [ "$(id -u)" -eq 0 ]; then
        info "root privileges: already running as root"
        return 0
    fi

    helper=$(root_helper || true)
    if [ -n "$helper" ]; then
        info "root helper: $helper"
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        warn "no sudo/doas found; dry-run continues, but $reason would require root"
        return 0
    fi

    die "$reason requires root, but neither sudo nor doas is available. Run as root or install/configure sudo or doas."
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

dry_root() {
    if [ "$DRY_RUN" = "1" ]; then
        helper=$(root_helper || true)
        if [ -n "$helper" ]; then
            info "[dry-run] $helper $*"
        elif [ "$(id -u)" -eq 0 ]; then
            info "[dry-run] $*"
        else
            info "[dry-run] <sudo|doas> $*"
        fi
    else
        info "run(root): $*"
        as_root "$@"
    fi
}

# --- confirmation ---
confirm() {
    msg=$1
    [ "$YES" = "1" ] && return 0
    printf '%s [y/N] ' "$msg"
    read -r ans
    case "$ans" in [yY]*) return 0 ;; esac
    return 1
}

# ============================================================
# Hardware detection
# ============================================================

detect_gpu() {
    if lspci 2>/dev/null | grep -qi nvidia; then
        echo "nvidia"
    elif lspci 2>/dev/null | grep -qi "amd\|radeon"; then
        echo "amd"
    elif lspci 2>/dev/null | grep -qi "intel.*graphics\|intel.*vga"; then
        echo "intel"
    else
        echo "unknown"
    fi
}

detect_battery() {
    if ls /sys/class/power_supply/BAT* 2>/dev/null | grep -q BAT; then
        echo "yes"
    else
        echo "no"
    fi
}

detect_grub() {
    if [ -d /boot/grub ] || [ -d /boot/EFI ] || [ -d /boot/efi ]; then
        echo "yes"
    else
        echo "no"
    fi
}

detect_monitors() {
    if command -v niri >/dev/null 2>&1 && [ -n "${NIRI_SOCKET:-}" ]; then
        niri msg --json outputs 2>/dev/null | \
            command -p awk -F'"' '/"name"/{print $4}' || true
    elif command -v wlr-randr >/dev/null 2>&1; then
        wlr-randr 2>/dev/null | awk '/^[A-Z]/{print $1}' || true
    else
        echo "(detection unavailable outside running compositor)"
    fi
}

detect_steam() {
    if [ -d "${STEAM_DATA_DIR:-}" ] || command -v steam >/dev/null 2>&1; then
        echo "yes"
    else
        echo "no"
    fi
}

print_hardware_info() {
    info "=== Hardware detection ==="
    info "  GPU:      $(detect_gpu)"
    info "  Battery:  $(detect_battery)"
    info "  GRUB:     $(detect_grub)"
    info "  Monitors: $(detect_monitors | tr '\n' ' ')"
    info "=========================="
}

# ============================================================
# Profile loading
# ============================================================

# Accumulated package files (space-separated paths)
PACKAGE_FILES=""
INSTALL_PACKAGES_FILE=""
INSTALL_PACKAGES_EXTRA=""
INSTALL_OH_MY_ZSH=1
INSTALL_STOW_PACKAGES="home desktop apps media bin"
INSTALL_POWER_PROFILE=0
INSTALL_NVIDIA_WAYLAND_ENV=0
INSTALL_GRUB_THEME=0
INSTALL_NIRI_SDDM=1
INSTALL_STEAM=0
GRUB_EXTRA_CMDLINE=""
GRUB_GFXMODE="auto"
GPU_POWER_LIMIT=""
CPU_GOVERNOR="powersave"
CPU_EPP="balance_performance"
STEAM_DATA_DIR=""
STEAM_LIBRARY_DIR=""
SCREENSHOT_DIR=""

load_profile() {
    name=$1
    pfile="$DOTFILES_DIR/profiles/${name}.env"
    if [ -f "$pfile" ]; then
        info "loading profile: $name"
        # shellcheck source=/dev/null
        . "$pfile"
    else
        warn "profile not found: $name (skipping)"
    fi
}

add_package_file() {
    pfile=$1
    [ -n "$pfile" ] || return 0
    case " $PACKAGE_FILES " in
        *" $pfile "*) return 0 ;;
    esac
    PACKAGE_FILES="${PACKAGE_FILES:+$PACKAGE_FILES }$pfile"
}

build_package_file_list() {
    PACKAGE_FILES=""
    for pfile in ${INSTALL_PACKAGES_FILE:-}; do
        add_package_file "$pfile"
    done
    for pfile in ${INSTALL_PACKAGES_EXTRA:-}; do
        add_package_file "$pfile"
    done
}

system_configuration_needs_root() {
    [ "$INSTALL_GRUB_THEME" = "1" ] && return 0
    [ "$INSTALL_POWER_PROFILE" = "1" ] && return 0
    [ "$INSTALL_NVIDIA_WAYLAND_ENV" = "1" ] && return 0
    [ "${INSTALL_USB_INPUT_POWER_FIX:-0}" = "1" ] && return 0
    [ "${INSTALL_NIRI_SDDM:-1}" = "1" ] && return 0
    [ -r "$DOTFILES_DIR/services/runit-enabled.txt" ] && [ -d /etc/sv ] && return 0
    # apply_system_etc always installs files to /etc/ — always needs root
    [ -d "$DOTFILES_DIR/system/etc" ] && return 0
    return 1
}

# ============================================================
# Package installation
# ============================================================

install_packages_from_file() {
    pfile=$1
    [ -r "$pfile" ] || { warn "package file not found: $pfile"; return 0; }
    pkgs=$(sed 's/#.*//' "$pfile" | awk 'NF { print $1 }')
    [ -n "$pkgs" ] || return 0

    repo_pkgs=$(printf '%s\n' $pkgs | awk '/^void-repo-/ { print }')
    if [ -n "$repo_pkgs" ]; then
        # shellcheck disable=SC2086
        dry_root xbps-install -Sy $repo_pkgs
        dry_root xbps-install -S
    fi

    # shellcheck disable=SC2086
    dry_root xbps-install -Sy $pkgs
}

install_oh_my_zsh() {
    [ "$INSTALL_OH_MY_ZSH" = "1" ] || return 0
    if [ -d "$HOME/.oh-my-zsh" ]; then
        info "oh-my-zsh already installed, skipping"
        return 0
    fi
    command -v git >/dev/null 2>&1 || { warn "git not found, skip oh-my-zsh"; return 0; }
    dry "git clone --depth 1 https://github.com/ohmyzsh/ohmyzsh.git \"\$HOME/.oh-my-zsh\""
}

# ============================================================
# Stow apply
# ============================================================

apply_stow() {
    stow_packages=$1

    if ! command -v stow >/dev/null 2>&1; then
        die "stow not found — install it first (xbps-install stow)"
    fi

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would run: scripts/apply.sh (PACKAGES='$stow_packages')"
        for pkg in $stow_packages; do
            info "[dry-run]   stow --no-folding --restow $pkg"
        done
        return 0
    fi

    PACKAGES="$stow_packages" "$DOTFILES_DIR/scripts/apply.sh"
}

# ============================================================
# Session environment (environment.d)
# ============================================================

generate_session_env() {
    env_dir="$HOME/.config/environment.d"
    env_file="$env_dir/dotfiles-host.conf"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would write: $env_file"
        return 0
    fi

    mkdir -p "$env_dir"
    cat > "$env_file" <<EOF
# Generated by install.sh — do not edit by hand
NIRI_PRIMARY_OUTPUT=${NIRI_PRIMARY_OUTPUT:-}
NIRI_SECONDARY_OUTPUT=${NIRI_SECONDARY_OUTPUT:-}
NIRI_PRIMARY_MODE=${NIRI_PRIMARY_MODE:-}
NIRI_SECONDARY_MODE=${NIRI_SECONDARY_MODE:-}
NIRI_PRIMARY_POSITION=${NIRI_PRIMARY_POSITION:-}
NIRI_SECONDARY_POSITION=${NIRI_SECONDARY_POSITION:-}
LOCK_TOP_OUTPUT=${LOCK_TOP_OUTPUT:-}
LOCK_BOTTOM_OUTPUT=${LOCK_BOTTOM_OUTPUT:-}
SCREENSHOT_DIR=${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}
EOF
    if [ "${INSTALL_NVIDIA_WAYLAND_ENV:-0}" = "1" ]; then
        cat >> "$env_file" <<EOF

# NVIDIA Wayland session hints.
GBM_BACKEND=nvidia-drm
__GLX_VENDOR_LIBRARY_NAME=nvidia
LIBVA_DRIVER_NAME=nvidia
ELECTRON_OZONE_PLATFORM_HINT=auto
EOF
    fi
    info "session env written: $env_file"

    # Generate niri screenshot-path override.
    # KDL doesn't support env var expansion, so we write a host-specific include file.
    screenshot_host_kdl="$HOME/.config/niri/screenshot-path-host.kdl"
    mkdir -p "$(dirname -- "$screenshot_host_kdl")"
    cat > "$screenshot_host_kdl" <<EOF
// Generated by install.sh — do not edit by hand
screenshot-path "${SCREENSHOT_DIR:-$HOME/Pictures/Screenshots}/Screenshot from %Y-%m-%d %H-%M-%S.png"
EOF
    info "niri screenshot-path written: $screenshot_host_kdl"
}

# ============================================================
# Host overlay
# ============================================================

apply_host_overlay() {
    hostname_key=$1
    host_dir="$DOTFILES_DIR/hosts/$hostname_key"
    target="$HOME/.config/niri/outputs-host.kdl"

    if [ ! -d "$host_dir" ]; then
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] would ensure empty niri outputs overlay: $target"
        else
            mkdir -p "$(dirname -- "$target")"
            [ -e "$target" ] || : > "$target"
        fi
        return 0
    fi

    info "applying host overlay: $hostname_key"

    # niri outputs config
    outputs_kdl="$host_dir/niri-outputs.kdl"
    if [ -f "$outputs_kdl" ]; then
        dry "mkdir -p \"\$(dirname '$target')\""
        # Remove symlink first so cp doesn't write through into the dotfiles placeholder
        dry "rm -f '$target'"
        dry "cp '$outputs_kdl' '$target'"
        info "niri outputs: $target"
    elif [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would ensure empty niri outputs overlay: $target"
    else
        mkdir -p "$(dirname -- "$target")"
        [ -e "$target" ] || : > "$target"
    fi

    # Host stow packages — any directory in hosts/$hostname/ that isn't a reserved name
    # is treated as a stow package and linked to $HOME.
    # Reserved dirs: etc, system, scripts, niri-outputs.kdl (file, not dir)
    for pkg_dir in "$host_dir"/*/; do
        [ -d "$pkg_dir" ] || continue
        pkg_name=$(basename -- "$pkg_dir")
        case "$pkg_name" in
            etc|system|scripts) continue ;;
        esac
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run]   stow --no-folding --restow --dir='$host_dir' $pkg_name"
        else
            stow --no-folding --restow --dir="$host_dir" --target="$HOME" "$pkg_name"
            info "host stow: $pkg_name"
        fi
    done

    # Host etc/ overlay — install root-owned config files from hosts/$HOSTNAME/etc/
    # into /etc/, substituting $INSTALL_USER placeholder for the actual username.
    apply_host_etc "$hostname_key"
}

apply_system_etc() {
    src_etc="$DOTFILES_DIR/system/etc"
    [ -d "$src_etc" ] || return 0
    info "=== Global /etc overlay (system/etc/) ==="

    etc_files=$(find "$src_etc" -type f 2>/dev/null || true)
    [ -n "$etc_files" ] || return 0

    printf '%s\n' "$etc_files" | while IFS= read -r src; do
        rel="${src#"$src_etc/"}"
        dst="/etc/$rel"
        dst_dir="$(dirname -- "$dst")"

        # runit/1 and runit/2 are machine-critical boot scripts — never auto-install
        case "$rel" in
            runit/1|runit/2)
                info "  skip (boot-critical, apply manually if needed): $dst"
                continue ;;
        esac

        # NVIDIA application profile — only install when NVIDIA is selected
        case "$rel" in
            nvidia/*)
                if [ "${INSTALL_NVIDIA_WAYLAND_ENV:-0}" != "1" ]; then
                    info "  skip (no NVIDIA profile): $dst"
                    continue
                fi ;;
        esac

        # GRUB defaults and grub.d — only install when grub-themed profile is active
        case "$rel" in
            default/grub|grub.d/*)
                if [ "${INSTALL_GRUB_THEME:-0}" != "1" ]; then
                    info "  skip (no grub-themed profile): $dst"
                    continue
                fi ;;
        esac

        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] would install: $dst"
        else
            dry_root install -d -m 755 "$dst_dir"
            dry_root install -m 644 "$src" "$dst"
            info "  installed: $dst"
        fi
    done
}

apply_host_etc() {
    hostname_key=$1
    src_etc="$DOTFILES_DIR/hosts/$hostname_key/etc"
    [ -d "$src_etc" ] || return 0

    INSTALL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    info "=== Host /etc overlay ($hostname_key, user=$INSTALL_USER) ==="

    # Collect files first to avoid piping stdin (confirm() reads from stdin)
    etc_files=$(find "$src_etc" -type f 2>/dev/null || true)
    [ -n "$etc_files" ] || return 0

    printf '%s\n' "$etc_files" | while IFS= read -r src; do
        [ -f "$src" ] || continue
        rel="${src#"$src_etc/"}"
        dst="/etc/$rel"
        dst_dir="$(dirname -- "$dst")"

        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] would install: $dst (with username substitution: <username> -> $INSTALL_USER)"
        else
            tmp=$(mktemp)
            # Substitute literal "srl" username placeholder with actual username
            sed "s/[[:<:]]srl[[:>:]]/$INSTALL_USER/g" "$src" > "$tmp" 2>/dev/null || \
                sed "s/\bsrl\b/$INSTALL_USER/g" "$src" > "$tmp"
            dry_root install -d -m 755 "$dst_dir"
            dry_root install -m 644 "$tmp" "$dst"
            rm -f "$tmp"
            info "  installed: $dst"
        fi
    done
}

# ============================================================
# System-level: GRUB
# ============================================================

apply_grub() {
    [ "$INSTALL_GRUB_THEME" = "1" ] || return 0

    info "=== GRUB configuration ==="
    grub_cmdline="quiet loglevel=0 vt.global_cursor_default=0"
    [ -n "$GRUB_EXTRA_CMDLINE" ] && grub_cmdline="$grub_cmdline $GRUB_EXTRA_CMDLINE"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would configure GRUB:"
        info "  GRUB_CMDLINE_LINUX_DEFAULT=\"$grub_cmdline\""
        info "  GRUB_GFXMODE=\"$GRUB_GFXMODE\""
        info "  Theme: MilkGrub"
        return 0
    fi

    confirm "Install GRUB theme and update grub.cfg? (requires root)" || return 0
    dry_root env \
        DOTFILES_DIR="$DOTFILES_DIR" \
        GRUB_EXTRA_CMDLINE="$GRUB_EXTRA_CMDLINE" \
        GRUB_GFXMODE="$GRUB_GFXMODE" \
        "$DOTFILES_DIR/scripts/install-grub.sh"
}

# ============================================================
# System-level: power profile service
# ============================================================

apply_power_profile() {
    [ "$INSTALL_POWER_PROFILE" = "1" ] || return 0
    info "=== Power profile service ==="
    [ "$DRY_RUN" = "0" ] && confirm "Install power-profile runit service? (requires root)" || {
        info "[dry-run] would install power profile service"
        return 0
    }
    dry_root env \
        DOTFILES_DIR="$DOTFILES_DIR" \
        CPU_GOVERNOR="$CPU_GOVERNOR" \
        CPU_EPP="$CPU_EPP" \
        GPU_POWER_LIMIT="$GPU_POWER_LIMIT" \
        "$DOTFILES_DIR/scripts/install-power-profile.sh"
}

# ============================================================
# System-level: NVIDIA Wayland application profile
# ============================================================

apply_nvidia_wayland_profile() {
    [ "$INSTALL_NVIDIA_WAYLAND_ENV" = "1" ] || return 0
    src="$DOTFILES_DIR/system/etc/nvidia/nvidia-application-profiles-rc.d/50-limit-free-buffer-pool-in-wayland-compositors.json"
    dst_dir="/etc/nvidia/nvidia-application-profiles-rc.d"
    dst="$dst_dir/50-limit-free-buffer-pool-in-wayland-compositors.json"

    info "=== NVIDIA Wayland application profile ==="
    [ -r "$src" ] || die "NVIDIA application profile not found: $src"
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would install NVIDIA application profile: $dst"
        return 0
    fi
    confirm "Install NVIDIA Wayland application profile? (requires root)" || return 0
    dry_root install -d -m 755 "$dst_dir"
    dry_root install -m 644 "$src" "$dst"
}

# ============================================================
# System-level: USB input power
# ============================================================

apply_usb_input_power_fix() {
    [ "${INSTALL_USB_INPUT_POWER_FIX:-0}" = "1" ] || return 0
    info "=== USB input power fix ==="
    usb_input_power_rule="$DOTFILES_DIR/hosts/$HOSTNAME_KEY/system/etc/udev/rules.d/99-usb-input-power.rules"
    [ -r "$usb_input_power_rule" ] || die "USB input power rule not found: $usb_input_power_rule"
    [ "$DRY_RUN" = "0" ] && confirm "Install USB input power udev rule? (requires root)" || {
        info "[dry-run] would install USB input power udev rule: $usb_input_power_rule"
        return 0
    }
    dry_root env DOTFILES_DIR="$DOTFILES_DIR" HOSTNAME_KEY="$HOSTNAME_KEY" USB_INPUT_POWER_RULE="$usb_input_power_rule" "$DOTFILES_DIR/scripts/install-usb-input-power-fix.sh"
}

# ============================================================
# System-level: niri SDDM session
# ============================================================

apply_niri_sddm_session() {
    [ "${INSTALL_NIRI_SDDM:-1}" = "1" ] || return 0
    info "=== niri SDDM session ==="
    src_bin="$DOTFILES_DIR/system/usr/local/bin/niri-sddm-session"
    src_desktop="$DOTFILES_DIR/system/usr/share/wayland-sessions/niri.desktop"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would install /usr/local/bin/niri-sddm-session"
        info "[dry-run] would install /usr/share/wayland-sessions/niri.desktop"
        return 0
    fi

    confirm "Install niri SDDM session script and .desktop? (requires root)" || return 0
    dry_root install -m 755 "$src_bin" /usr/local/bin/niri-sddm-session
    dry_root install -d -m 755 /usr/share/wayland-sessions
    dry_root install -m 644 "$src_desktop" /usr/share/wayland-sessions/niri.desktop
}

# ============================================================
# System-level: runit services
# ============================================================

_enable_runit_from_file() {
    service_file="$1"
    [ -r "$service_file" ] || return 0
    [ -d /etc/sv ] || return 0

    while IFS= read -r service; do
        case "$service" in ''|'#'*) continue ;; esac
        svc_src="$DOTFILES_DIR/services/$service"
        if [ ! -d "/etc/sv/$service" ] && [ -d "$svc_src" ]; then
            dry_root cp -r "$svc_src" "/etc/sv/$service"
            dry_root chmod +x "/etc/sv/$service/run" 2>/dev/null || true
            info "installed service: $service → /etc/sv/$service"
        elif [ ! -d "/etc/sv/$service" ]; then
            warn "service not installed, skip: $service"
            continue
        fi
        if [ ! -e "/var/service/$service" ]; then
            dry_root ln -s "/etc/sv/$service" /var/service/
        else
            info "service already enabled: $service"
        fi
    done < "$service_file"
}

enable_runit_services() {
    _enable_runit_from_file "$DOTFILES_DIR/services/runit-enabled.txt"
    _enable_runit_from_file "$DOTFILES_DIR/hosts/$HOSTNAME_KEY/runit-enabled.txt"
}

# ============================================================
# System-level: modules-load.d configs
# ============================================================

apply_modules_load() {
    src_dir="$DOTFILES_DIR/system/etc/modules-load.d"
    dst_dir="/etc/modules-load.d"
    [ -d "$src_dir" ] || return 0

    info "=== modules-load.d ==="
    for src in "$src_dir"/*.conf; do
        [ -f "$src" ] || continue
        fname="${src##*/}"
        dst="$dst_dir/$fname"
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] would install: $dst"
        else
            dry_root install -d -m 755 "$dst_dir"
            dry_root install -m 644 "$src" "$dst"
            info "  installed: $dst"
        fi
    done
}

# ============================================================
# System-level: user group membership
# ============================================================

apply_user_groups() {
    [ "$SKIP_SYSTEM" = "0" ] || return 0

    INSTALL_USER="${SUDO_USER:-${USER:-$(id -un)}}"
    info "=== User group membership (user: $INSTALL_USER) ==="

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would run: usermod -aG i2c $INSTALL_USER"
        return 0
    fi

    # i2c group — required for ddcutil DDC/CI access without sudo
    if getent group i2c >/dev/null 2>&1; then
        dry_root usermod -aG i2c "$INSTALL_USER"
        info "  added $INSTALL_USER to group: i2c"
    else
        warn "  group 'i2c' not found, skipping (load i2c-dev module first)"
    fi
}

# ============================================================
# Validation
# ============================================================

run_validations() {
    info "=== Validation ==="
    fail=0

    # niri config
    if command -v niri >/dev/null 2>&1; then
        cfg="$HOME/.config/niri/config.kdl"
        if [ -f "$cfg" ]; then
            if niri validate --config "$cfg" 2>/dev/null; then
                info "  [ok] niri config valid"
            else
                warn "  [!!] niri config has errors"
                fail=1
            fi
        fi
    else
        info "  [--] niri not installed, skip config check"
    fi

    # fuzzel config
    if command -v fuzzel >/dev/null 2>&1; then
        cfg="$HOME/.config/fuzzel/fuzzel.ini"
        if [ -f "$cfg" ]; then
            if fuzzel --check-config 2>/dev/null; then
                info "  [ok] fuzzel config valid"
            else
                warn "  [!!] fuzzel config has errors"
            fi
        fi
    fi

    # shellcheck on scripts (if available)
    if command -v shellcheck >/dev/null 2>&1; then
        sc_fail=0
        for f in "$DOTFILES_DIR/scripts/"*.sh \
                 "$DOTFILES_DIR/bin/.local/bin/"* \
                 "$DOTFILES_DIR/desktop/.config/niri/scripts/"*.sh \
                 "$DOTFILES_DIR/desktop/.config/waybar/scripts/"*.sh; do
            [ -f "$f" ] || continue
            head -1 "$f" | grep -qE '^#!.*(sh|bash|zsh)' || continue
            if ! shellcheck -S error "$f" 2>/dev/null; then
                warn "  [!!] shellcheck: $f"
                sc_fail=1
            fi
        done
        [ "$sc_fail" = "0" ] && info "  [ok] shellcheck passed"
    else
        info "  [--] shellcheck not installed, skip"
    fi

    # Required commands check
    for cmd in stow git curl jq zsh; do
        if command -v "$cmd" >/dev/null 2>&1; then
            info "  [ok] $cmd found"
        else
            warn "  [!!] $cmd not found"
            fail=1
        fi
    done

    # Stow symlinks check
    for pkg in home desktop apps media bin; do
        pkg_dir="$DOTFILES_DIR/$pkg"
        [ -d "$pkg_dir" ] || continue
        missing=$(
            find "$pkg_dir" \( -type f -o -type l \) 2>/dev/null | while IFS= read -r src; do
            rel=${src#"$pkg_dir"/}
            case "$rel" in
                .stow-local-ignore|.config/niri/outputs-host.kdl|*__pycache__*|*.pyc)
                    continue
                    ;;
            esac

            target="$HOME/$rel"
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                printf 'missing stow target: %s\n' "$target"
                continue
            fi

            if [ ! -L "$target" ]; then
                printf 'not a stow symlink: %s\n' "$target"
                continue
            fi

            src_real=$(readlink -f -- "$src" 2>/dev/null || true)
            target_real=$(readlink -f -- "$target" 2>/dev/null || true)
            if [ -n "$src_real" ] && [ "$src_real" != "$target_real" ]; then
                printf 'stow target points elsewhere: %s -> %s\n' "$target" "$(readlink -- "$target")"
            fi
        done
        )

        if [ -n "$missing" ]; then
            printf '%s\n' "$missing" | while IFS= read -r line; do
                warn "  [!!] $line"
            done
            fail=1
        else
            info "  [ok] stow package '$pkg' linked"
        fi
    done

    if [ "$fail" = "0" ]; then
        info "=== Validation passed ==="
    else
        warn "=== Validation finished with warnings ==="
    fi
}

# ============================================================
# Main flow
# ============================================================

main() {
    [ -x /usr/bin/xbps-install ] || die "this script requires Void Linux (xbps not found)"

    info "========================================"
    info "dotfiles install — $(date '+%F %T')"
    info "DOTFILES_DIR: $DOTFILES_DIR"
    [ "$DRY_RUN" = "1" ] && info "*** DRY-RUN MODE — no changes will be made ***"
    info "========================================"

    # Determine hostname for host config
    if [ -n "$OPT_HOST" ]; then
        HOSTNAME_KEY="$OPT_HOST"
    else
        HOSTNAME_KEY=$(hostname_key_default)
    fi
    info "hostname: $HOSTNAME_KEY"

    # Hardware detection (informational)
    print_hardware_info

    # Load base profile (always)
    load_profile base

    # Load host-specific env (overrides base defaults)
    host_env="$DOTFILES_DIR/hosts/$HOSTNAME_KEY/host.env"
    if [ -f "$host_env" ]; then
        info "loading host config: $host_env"
        # shellcheck source=/dev/null
        . "$host_env"
        # Expose host.env to runtime scripts (e.g. net-control.sh, waybar scripts)
        if [ "$DRY_RUN" = "1" ]; then
            info "[dry-run] would run: ln -sf $host_env $HOME/.config/host.env"
        else
            ln -sf "$host_env" "$HOME/.config/host.env"
        fi
    else
        warn "no host config found at hosts/$HOSTNAME_KEY/host.env"
        warn "copy hosts/example/host.env to hosts/$HOSTNAME_KEY/host.env and edit it"
        if ! confirm "Continue with base profile only?"; then
            info "Aborted. Create hosts/$HOSTNAME_KEY/host.env first."
            exit 1
        fi
    fi

    # Load profiles from host.env PROFILES var + --profiles CLI arg
    all_profiles=$(unique_words ${PROFILES:-} ${OPT_PROFILES:-})
    for profile in $all_profiles; do
        [ -n "$profile" ] && load_profile "$profile"
    done

    # Expand package file list from base/profile/host configuration.
    # INSTALL_PACKAGES_EXTRA is kept for old host.env/profile snippets.
    build_package_file_list

    info "========================================"
    info "Install plan:"
    info "  profiles:   ${all_profiles:-base}"
    info "  stow pkgs:  $INSTALL_STOW_PACKAGES"
    info "  pkg files:  $PACKAGE_FILES"
    info "  oh-my-zsh:  $INSTALL_OH_MY_ZSH"
    info "  power svc:  $INSTALL_POWER_PROFILE"
    info "  USB input:  ${INSTALL_USB_INPUT_POWER_FIX:-0}"
    info "  GRUB theme: $INSTALL_GRUB_THEME"
    [ -n "$GPU_POWER_LIMIT" ] && info "  GPU limit:  ${GPU_POWER_LIMIT}W"
    info "========================================"

    if [ "$SKIP_PACKAGES" = "0" ] && [ -n "$PACKAGE_FILES" ]; then
        require_root_helper "package installation"
    fi
    if [ "$SKIP_SYSTEM" = "0" ] && system_configuration_needs_root; then
        require_root_helper "system configuration"
    fi

    if [ "$DRY_RUN" = "0" ] && [ "$YES" = "0" ]; then
        confirm "Proceed with installation?" || {
            info "Aborted."
            exit 1
        }
    fi

    # 1. Packages
    if [ "$SKIP_PACKAGES" = "0" ]; then
        info "--- Package installation ---"
        for pfile in $PACKAGE_FILES; do
            install_packages_from_file "$pfile"
        done
        # Install arch/firmware-appropriate GRUB package
        _grub_pkg=""
        if [ -d /sys/firmware/efi ]; then
            case "$(uname -m)" in
                x86_64)  _grub_pkg=grub-x86_64-efi ;;
                aarch64) _grub_pkg=grub-arm64-efi ;;
            esac
        else
            _grub_pkg=grub-i386-pc
        fi
        [ -n "$_grub_pkg" ] && dry_root xbps-install -Sy "$_grub_pkg"
        install_oh_my_zsh
    else
        info "--- Skipping package installation (--skip-packages) ---"
    fi

    # 2. Stow
    if [ "$SKIP_STOW" = "0" ]; then
        info "--- Applying stow packages ---"
        apply_stow "$INSTALL_STOW_PACKAGES"
    else
        info "--- Skipping stow (--skip-stow) ---"
    fi

    if [ "$INSTALL_STEAM" = "1" ]; then
        info "Running Steam Homebrew setup..."
        sh "$DOTFILES_DIR/scripts/install-steam-homebrew.sh"
    fi

    # 3. Host overlay (niri outputs, session env)
    generate_session_env
    apply_host_overlay "$HOSTNAME_KEY"

    # 4. System-level (GRUB, runit)
    if [ "$SKIP_SYSTEM" = "0" ]; then
        info "--- System configuration ---"
        apply_system_etc
        apply_grub
        apply_niri_sddm_session
        apply_usb_input_power_fix
        apply_power_profile
        apply_nvidia_wayland_profile
        apply_modules_load
        enable_runit_services
        apply_user_groups
    else
        info "--- Skipping system config (--skip-system) ---"
    fi

    # 5. Validate
    run_validations

    info "========================================"
    info "Install complete!"
    info "Log: $LOG_FILE"
    [ "$DRY_RUN" = "1" ] && info "(dry-run — no changes were made)"
    info "========================================"
}

main "$@"
