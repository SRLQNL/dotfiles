#!/bin/sh
# install.sh — portable bootstrap for Void Linux dotfiles
#
# Usage:
#   ./install.sh [options]
#
# Options:
#   --dry-run           Show what would be done without making changes
#   --host HOSTNAME     Override hostname for host config (default: $(hostname -s))
#   --profiles LIST     Additional profiles to load (space-separated)
#   --skip-packages     Skip xbps package installation
#   --skip-stow         Skip stow apply
#   --skip-system       Skip system-level changes (GRUB, runit services)
#   --yes               Non-interactive (no confirmation prompts)
#
# Profiles available: desktop-nvidia  laptop  steam  grub-themed  power-profile
#
# Quick start for a new Void machine:
#   git clone <repo> ~/dotfiles && cd ~/dotfiles
#   cp hosts/example/host.env hosts/$(hostname -s)/host.env
#   # edit hosts/$(hostname -s)/host.env for your hardware
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

# --- argument parsing ---
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)      DRY_RUN=1 ;;
        --host)         shift; OPT_HOST="$1" ;;
        --profiles)     shift; OPT_PROFILES="$1" ;;
        --skip-packages) SKIP_PACKAGES=1 ;;
        --skip-stow)    SKIP_STOW=1 ;;
        --skip-system)  SKIP_SYSTEM=1 ;;
        --yes|-y)       YES=1 ;;
        -h|--help)
            sed -n '/^# Usage:/,/^[^#]/p' "$0" | sed 's/^# \?//'
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
as_root() {
    if [ "$(id -u)" -eq 0 ]; then "$@"
    else sudo "$@"
    fi
}

dry_root() {
    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] sudo $*"
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
INSTALL_OH_MY_ZSH=1
INSTALL_STOW_PACKAGES="home desktop apps media bin"
INSTALL_POWER_PROFILE=0
INSTALL_GRUB_THEME=0
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
SCREENSHOT_DIR=${SCREENSHOT_DIR:-$HOME/Screenshots}
EOF
    info "session env written: $env_file"
}

# ============================================================
# Host overlay
# ============================================================

apply_host_overlay() {
    hostname_key=$1
    host_dir="$DOTFILES_DIR/hosts/$hostname_key"
    [ -d "$host_dir" ] || return 0

    info "applying host overlay: $hostname_key"

    # niri outputs config
    outputs_kdl="$host_dir/niri-outputs.kdl"
    if [ -f "$outputs_kdl" ]; then
        target="$HOME/.config/niri/outputs-host.kdl"
        dry "mkdir -p \"\$(dirname '$target')\""
        dry "cp '$outputs_kdl' '$target'"
        info "niri outputs: $target"
    fi
}

# ============================================================
# System-level: GRUB
# ============================================================

apply_grub() {
    [ "$INSTALL_GRUB_THEME" = "1" ] || return 0

    info "=== GRUB configuration ==="
    grub_cmdline="quiet loglevel=0 rd.udev.log_level=0 udev.log_level=0 vt.global_cursor_default=0 video=efifb:nobgrt"
    [ -n "$GRUB_EXTRA_CMDLINE" ] && grub_cmdline="$grub_cmdline $GRUB_EXTRA_CMDLINE"

    if [ "$DRY_RUN" = "1" ]; then
        info "[dry-run] would configure GRUB:"
        info "  GRUB_CMDLINE_LINUX_DEFAULT=\"$grub_cmdline\""
        info "  GRUB_GFXMODE=\"$GRUB_GFXMODE\""
        info "  Theme: MilkGrub"
        return 0
    fi

    confirm "Install GRUB theme and update grub.cfg? (requires root)" || return 0
    dry "$DOTFILES_DIR/scripts/install-grub.sh"
}

# ============================================================
# System-level: power profile service
# ============================================================

apply_power_profile() {
    [ "$INSTALL_POWER_PROFILE" = "1" ] || return 0
    info "=== Power profile service ==="
    [ "$DRY_RUN" = "0" ] && confirm "Install srl-power-profile runit service? (requires root)" || {
        info "[dry-run] would install power profile service"
        return 0
    }
    dry "$DOTFILES_DIR/scripts/install-power-profile.sh"
}

# ============================================================
# System-level: runit services
# ============================================================

enable_runit_services() {
    service_file="$DOTFILES_DIR/services/runit-enabled.txt"
    [ -r "$service_file" ] || return 0
    [ -d /etc/sv ] || return 0

    while IFS= read -r service; do
        case "$service" in ''|'#'*) continue ;; esac
        if [ ! -d "/etc/sv/$service" ]; then
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
    for pkg in home desktop apps; do
        pkg_dir="$DOTFILES_DIR/$pkg"
        [ -d "$pkg_dir" ] || continue
        sample=$(find "$pkg_dir" -type f 2>/dev/null | head -5)
        broken=0
        printf '%s\n' "$sample" | while IFS= read -r src; do
            [ -n "$src" ] || continue
            rel=${src#"$pkg_dir"/}
            target="$HOME/$rel"
            if [ ! -e "$target" ] && [ ! -L "$target" ]; then
                warn "  [!!] missing stow target: $target"
                broken=1
            fi
        done
        [ "$broken" = "0" ] && info "  [ok] stow package '$pkg' linked"
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
    info "========================================"
    info "dotfiles install — $(date '+%F %T')"
    info "DOTFILES_DIR: $DOTFILES_DIR"
    [ "$DRY_RUN" = "1" ] && info "*** DRY-RUN MODE — no changes will be made ***"
    info "========================================"

    # Determine hostname for host config
    if [ -n "$OPT_HOST" ]; then
        HOSTNAME_KEY="$OPT_HOST"
    else
        HOSTNAME_KEY=$(hostname -s 2>/dev/null || cat /etc/hostname 2>/dev/null | tr -d '\n' || echo "unknown")
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
    else
        warn "no host config found at hosts/$HOSTNAME_KEY/host.env"
        warn "copy hosts/example/host.env to hosts/$HOSTNAME_KEY/host.env and edit it"
        if ! confirm "Continue with base profile only?"; then
            info "Aborted. Create hosts/$HOSTNAME_KEY/host.env first."
            exit 1
        fi
    fi

    # Load profiles from host.env PROFILES var + --profiles CLI arg
    all_profiles="${PROFILES:-} ${OPT_PROFILES:-}"
    for profile in $all_profiles; do
        [ -n "$profile" ] && load_profile "$profile"
    done

    # Expand package file list
    base_pkg="$DOTFILES_DIR/packages/void-base.txt"
    PACKAGE_FILES="$base_pkg"
    for extra_file in ${INSTALL_PACKAGES_EXTRA:-}; do
        [ -f "$extra_file" ] && PACKAGE_FILES="$PACKAGE_FILES $extra_file"
    done

    info "========================================"
    info "Install plan:"
    info "  profiles:   ${PROFILES:-base}"
    info "  stow pkgs:  $INSTALL_STOW_PACKAGES"
    info "  pkg files:  $PACKAGE_FILES"
    info "  oh-my-zsh:  $INSTALL_OH_MY_ZSH"
    info "  power svc:  $INSTALL_POWER_PROFILE"
    info "  GRUB theme: $INSTALL_GRUB_THEME"
    [ -n "$GPU_POWER_LIMIT" ] && info "  GPU limit:  ${GPU_POWER_LIMIT}W"
    info "========================================"

    [ "$DRY_RUN" = "0" ] && [ "$YES" = "0" ] && confirm "Proceed with installation?" || true

    # 1. Packages
    if [ "$SKIP_PACKAGES" = "0" ]; then
        info "--- Package installation ---"
        for pfile in $PACKAGE_FILES; do
            install_packages_from_file "$pfile"
        done
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

    # 3. Host overlay (niri outputs, session env)
    generate_session_env
    apply_host_overlay "$HOSTNAME_KEY"

    # 4. System-level (GRUB, runit)
    if [ "$SKIP_SYSTEM" = "0" ]; then
        info "--- System configuration ---"
        apply_grub
        apply_power_profile
        enable_runit_services
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
