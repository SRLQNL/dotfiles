#!/bin/sh
set -eu

DOTFILES_DIR=${DOTFILES_DIR:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
SERVICE_DIR=/etc/sv/srl-power-profile
CONFIG_FILE=$SERVICE_DIR/conf
LEGACY_SERVICE=cpu-performance
DISABLE_LEGACY=${SRL_POWER_PROFILE_DISABLE_LEGACY_CPU_PERFORMANCE:-0}

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
        printf 'root command requires sudo or doas\n' >&2
        exit 1
    fi
}

install_default_config() {
    [ ! -e "$CONFIG_FILE" ] || return 0

    tmp=$(mktemp)
    trap 'rm -f "$tmp"' EXIT INT TERM
    cat > "$tmp" <<EOF
# SRL power profile runtime config.
# Values can be left empty to skip that setting.
CPU_GOVERNOR=${CPU_GOVERNOR:-powersave}
CPU_EPP=${CPU_EPP:-balance_performance}
CPU_NO_TURBO=${CPU_NO_TURBO:-0}
CPU_MIN_PERF_PCT=${CPU_MIN_PERF_PCT:-15}
CPU_MAX_PERF_PCT=${CPU_MAX_PERF_PCT:-100}
GPU_POWER_LIMIT=${GPU_POWER_LIMIT:-}
GPU_PERSISTENCE_MODE=${GPU_PERSISTENCE_MODE:-1}
EOF
    as_root install -m 644 "$tmp" "$CONFIG_FILE"
}

disable_legacy_service() {
    [ "$DISABLE_LEGACY" = 1 ] || {
        if [ -e "/var/service/$LEGACY_SERVICE" ] || [ -e "/etc/sv/$LEGACY_SERVICE" ]; then
            printf 'left existing %s service intact; set SRL_POWER_PROFILE_DISABLE_LEGACY_CPU_PERFORMANCE=1 to disable it with backup\n' "$LEGACY_SERVICE"
        fi
        return 0
    }

    as_root sv down "$LEGACY_SERVICE" >/dev/null 2>&1 || true

    if [ -L "/var/service/$LEGACY_SERVICE" ]; then
        as_root rm -f "/var/service/$LEGACY_SERVICE"
    elif [ -e "/var/service/$LEGACY_SERVICE" ]; then
        printf 'refusing to remove non-symlink /var/service/%s\n' "$LEGACY_SERVICE" >&2
    fi

    if [ -e "/etc/sv/$LEGACY_SERVICE" ]; then
        backup="/etc/sv/$LEGACY_SERVICE.disabled.$(date +%Y%m%d%H%M%S)"
        as_root mv "/etc/sv/$LEGACY_SERVICE" "$backup"
        printf 'moved /etc/sv/%s to %s\n' "$LEGACY_SERVICE" "$backup"
    fi
}

as_root install -d -m 755 "$SERVICE_DIR"
as_root install -m 755 "$DOTFILES_DIR/system/etc/sv/srl-power-profile/run" "$SERVICE_DIR/run"
install_default_config
disable_legacy_service

if [ -d /etc/sv/thermald ] && [ ! -e /var/service/thermald ]; then
    as_root ln -s /etc/sv/thermald /var/service/
fi

if [ ! -e /var/service/srl-power-profile ]; then
    as_root ln -s /etc/sv/srl-power-profile /var/service/
fi

as_root sv up thermald >/dev/null 2>&1 || true
as_root sv restart srl-power-profile >/dev/null 2>&1 || as_root sv up srl-power-profile >/dev/null 2>&1 || true

printf 'installed SRL power profile\n'
