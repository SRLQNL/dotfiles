# dotfiles

Portable dotfiles for Void Linux + niri Wayland desktop.
Managed with [GNU Stow](https://www.gnu.org/software/stow/).

## Quick start (new Void machine)

```sh
# 1. Clone
# Use sudo or doas for root commands; install.sh auto-detects either helper.
sudo xbps-install -S git
git clone <repo-url> ~/dotfiles
cd ~/dotfiles

# 2. Create host config (see hosts/example/host.env)
HOST=$(hostname 2>/dev/null | cut -d. -f1)
[ -n "$HOST" ] || HOST=unknown
mkdir -p "hosts/$HOST"
cp hosts/example/host.env "hosts/$HOST/host.env"
$EDITOR "hosts/$HOST/host.env"   # set monitor names, profiles, etc.

# 3. Bootstrap
./install.sh --yes
```

Preview without making changes:
```sh
./install.sh --dry-run
```

---

## Structure

```
dotfiles/
├── install.sh          # Main bootstrap: hardware detection, profiles, stow, validation
├── profiles/           # Composable feature profiles
│   ├── base.env        # Always loaded
│   ├── desktop-nvidia.env
│   ├── laptop.env
│   ├── steam.env
│   ├── grub-themed.env
│   └── power-profile.env
├── hosts/              # Per-host overrides
│   ├── example/        # Template — copy and edit for your machine
│   └── desktop-srl/    # Reference: NVIDIA desktop with dual DP monitors
│
├── home/               # Shell, git, starship
├── desktop/            # niri, waybar, foot, mako, fuzzel, rofi, swaylock
├── apps/               # GTK, btop, mpv, fontconfig, etc.
├── media/              # PulseAudio/PipeWire configs
├── bin/                # ~/.local/bin scripts
│
├── packages/
│   ├── void-base.txt   # Default Void+niri package set
│   ├── void-nvidia.txt # 32-bit NVIDIA/Vulkan libs (Steam + Proton)
│   ├── void-gaming.txt # Steam, mono
│   └── void-laptop.txt # Battery/power tools for laptops
│
├── services/           # runit-enabled.txt — services to symlink into /var/service
├── scripts/            # Installation helpers (stow apply, GRUB, power profile, Steam)
└── system/             # Root-level configs installed by scripts (GRUB, /etc/environment)
```

---

## Profiles

Profiles are composable. Set them in `hosts/<hostname>/host.env`:

```sh
PROFILES="desktop-nvidia steam grub-themed power-profile"
```

Or pass on the command line:
```sh
./install.sh --profiles "desktop-nvidia steam"
# Equivalent:
./install.sh --profiles desktop-nvidia steam
```

| Profile | What it does |
|---------|-------------|
| `base` | Always applied: default package file, stow packages, oh-my-zsh |
| `desktop-nvidia` | `nvidia-drm.modeset=1`, 32-bit libs, power management |
| `laptop` | Battery tools, power-saving CPU defaults |
| `steam` | Steam + gaming packages, configurable data paths |
| `grub-themed` | MilkGrub theme, GRUB display mode |
| `power-profile` | srl-power-profile runit service (CPU/GPU power caps) |

Package files are accumulated in `INSTALL_PACKAGES_FILE`. `profiles/base.env`
sets the default to `packages/void-base.txt`; feature profiles append their own
files. Host configs can override or append to the same variable:

```sh
# Replace the default package set
INSTALL_PACKAGES_FILE="$DOTFILES_DIR/packages/void-base.txt"

# Append a host-local package file
INSTALL_PACKAGES_FILE="$INSTALL_PACKAGES_FILE $DOTFILES_DIR/hosts/$HOSTNAME_KEY/packages.txt"
```

`INSTALL_PACKAGES_EXTRA` is still accepted for older host configs, but new
profiles and hosts should use `INSTALL_PACKAGES_FILE`.

---

## Adding a new host

```sh
# 1. Copy example host config
HOST=$(hostname 2>/dev/null | cut -d. -f1)
[ -n "$HOST" ] || HOST=unknown
mkdir -p "hosts/$HOST"
cp hosts/example/host.env "hosts/$HOST/host.env"

# 2. Find monitor names (inside a running niri session)
niri msg outputs

# 3. Edit the host config with your monitor names, profiles, paths
$EDITOR "hosts/$HOST/host.env"

# 4. (Optional) add a niri outputs config for this host
cp hosts/desktop-srl/niri-outputs.kdl "hosts/$HOST/niri-outputs.kdl"
# Edit output names and modes — bootstrap will install it to ~/.config/niri/outputs-host.kdl

# 5. Run bootstrap
./install.sh --host "$HOST" --yes
```

---

## Manual component installation

```sh
# Apply stow only (skip packages and system)
./install.sh --skip-packages --skip-system

# Only specific stow packages
PACKAGES="home desktop" scripts/apply.sh

# GRUB theme
scripts/install-grub.sh

# Optional clean GRUB menu; disables distro grub.d scripts only with explicit opt-in
GRUB_INSTALL_CLEAN_MENU=1 GRUB_DISABLE_FOREIGN_SCRIPTS=1 scripts/install-grub.sh

# Power profile runit service
scripts/install-power-profile.sh

# Host-specific USB keyboard/mouse boot fix for desktop-srl
scripts/install-usb-input-power-fix.sh

# Steam + Millennium
STEAM_DATA_DIR=/your/drive/Steam scripts/install-steam-homebrew.sh

# Quiet runit boot (suppress console output)
scripts/install-runit-quiet-boot.sh
# For non-standard /etc/runit/1 or /etc/runit/2 only:
RUNIT_QUIET_FORCE=1 scripts/install-runit-quiet-boot.sh

# Sync live system back into repo
scripts/snapshot.sh && git -C ~/dotfiles status
```

---

## Hardware-specific notes

### NVIDIA (profile: desktop-nvidia)

- Adds `nvidia-drm.modeset=1` to GRUB cmdline
- Installs 32-bit NVIDIA/Vulkan libs required for Steam Proton
- `GPU_POWER_LIMIT` (W) is applied via `nvidia-smi` in the runit service
- Set per-host: `GPU_POWER_LIMIT=275` for RTX 3070 Ti, `150` for weaker cards

### Dual-monitor desktop (hosts/desktop-srl)

Two 1920×1080@144Hz DisplayPort monitors stacked vertically:
- `DP-2` — bottom, primary, workspaces 1–5
- `DP-1` — top

USB keyboard/mouse boot reliability:
- `hosts/desktop-srl/system/etc/udev/rules.d/99-srl-usb-input-power.rules`
  keeps USB hubs and the current keyboard/mouse (`258a:010c`, `046d:c08b`) in
  `power/control=on`.
- This is opt-in via `INSTALL_USB_INPUT_POWER_FIX=1` in `hosts/desktop-srl/host.env`.

Lock behavior: top monitor disables on lock, restores on unlock.
Configure output names via `LOCK_TOP_OUTPUT` / `LOCK_BOTTOM_OUTPUT` in `host.env`.

`workspace-cap-daemon.py` creates `b1..b5` workspaces dynamically while `DP-2` is
connected, and merges them back to `1..5` when only one output is present.

### Laptop (profile: laptop)

- CPU: `powersave` governor + `power` EPP
- GPU power cap disabled
- Extra packages: `acpi`, `tlp`, `thermald`

### Steam (profile: steam)

```sh
# host.env — override default paths
STEAM_DATA_DIR=/adata/Steam            # desktop-srl: separate drive
STEAM_LIBRARY_DIR=/adata/SteamLibrary
```
Default: `~/.local/share/Steam`.

Includes Millennium patcher (pinned to `3.0.0-beta.24`) and Steam-local fontconfig
wrapper to avoid Steam Runtime noise with newer host fontconfig files.

---

## Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SCREENSHOT_DIR` | `~/Pictures/Screenshots` | Where `screenshot-region` saves files |
| `LOCK_TOP_OUTPUT` | *(empty)* | Monitor to disable during lock screen — set to your output name (e.g. `DP-1`, `eDP-1`) |
| `LOCK_BOTTOM_OUTPUT` | *(empty)* | Secondary monitor for lock restore script — set to your output name |
| `DOTFILES_TARGET_USER` | auto-detect | User for `plasma-app-launch` when run as root |
| `STEAM_DATA_DIR` | `~/.local/share/Steam` | Steam data directory |
| `STEAM_LIBRARY_DIR` | `~/.local/share/Steam/SteamLibrary` | Steam library path |
| `GPU_POWER_LIMIT` | `150` | NVIDIA power cap in watts |

---

## Rollback / backup

`scripts/apply.sh` backs up conflicting files before stow:
```
~/.local/state/dotfiles/backups/YYYYMMDD-HHMMSS/
```

GRUB backup is at `/root/grub-backup-YYYYMMDD-HHMMSS/`. `scripts/install-grub.sh`
merges managed defaults into `/etc/default/grub`; it does not replace the whole
file or disable existing `/etc/grub.d` scripts unless explicitly requested.

Restore:
```sh
# Dotfiles backup
cp -a ~/.local/state/dotfiles/backups/20260507-120000/. ~/

# GRUB
sudo cp /root/grub-backup-*/grub.default /etc/default/grub
sudo grub-mkconfig -o /boot/grub/grub.cfg
```

---

## Validation

```sh
# Full validation (dry-run, no changes)
./install.sh --dry-run --skip-packages --skip-stow --skip-system

# Individual checks
niri validate --config ~/.config/niri/config.kdl
fuzzel --check-config
sh -n scripts/bootstrap.sh
```
