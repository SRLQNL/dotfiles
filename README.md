# dotfiles

Portable dotfiles for Void Linux + niri Wayland desktop.
Managed with [GNU Stow](https://www.gnu.org/software/stow/).

Russian version: [README.ru.md](README.ru.md).

## Install On A New Void Machine

After the Void installer finishes:

1. Boot into the installed system.
2. Log in as your normal user, not as `root`.
3. Make sure that user can run root commands with `sudo` or `doas`.
4. Run the one-line bootstrap.

```sh
sudo xbps-install -Sy curl ca-certificates && sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)"
```

Then reboot.

```sh
sudo reboot
```

On the login screen choose `Niri (SDDM wrapper)` if SDDM does not select it
automatically.

### What the command does

The bootstrap script:

- checks that the system is Void Linux;
- installs `git`, `curl`, and `ca-certificates` if needed;
- clones or updates this repository at `~/dotfiles`;
- runs `./install.sh --bootstrap`;
- creates `hosts/<hostname>/host.env` automatically when it does not exist;
- installs the base Void+niri desktop package set;
- applies stow-managed home config;
- installs the niri SDDM wrapper session;
- enables the base runit services needed for a graphical login:
  `dbus`, `elogind`, `NetworkManager`, `polkitd`, and `sddm`.

The default bootstrap does not silently enable Steam, RGB, GRUB theming, USB quirks,
custom nftables rules, or SSH hardening. Those are host/profile choices.

### Requirements

- Run the command as the target desktop user.
- Do not run it with `sudo sh ...` or as direct `root`.
- The user must already be allowed to use `sudo` or `doas`.

If your fresh Void install does not have `sudo` or `doas`, configure one first as
root. Example for `sudo`:

```sh
su -
xbps-install -Sy sudo
usermod -aG wheel YOUR_USER
EDITOR=nano visudo
```

In `visudo`, allow the `wheel` group, then log out and back in as `YOUR_USER`.

### Optional Profiles

Pass extra profiles when the new host needs them.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)" -- --profiles "steam grub-themed"
```

On x86_64 glibc machines with NVIDIA hardware, `--bootstrap` auto-selects the
`desktop-nvidia` profile so niri/Wayland has the required driver stack. Laptop
hardware auto-selects the `laptop` profile. Steam, RGB, and GRUB theme remain
explicit.

Preview a local checkout without making changes:

```sh
./install.sh --bootstrap --dry-run
```

Manual clone path:

```sh
sudo xbps-install -Sy git ca-certificates
git clone https://github.com/SRLQNL/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --bootstrap
```

### After First Login

After the first successful niri login, check monitor names:

```sh
niri msg outputs
```

Then edit the generated host config if this machine needs monitor layout,
Steam paths, GRUB theme, RGB, proxy, firewall, or SSH policy:

```sh
$EDITOR ~/dotfiles/hosts/$(hostname | cut -d. -f1)/host.env
```

Re-run the installer after edits:

```sh
cd ~/dotfiles
./install.sh --bootstrap
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

Profiles are composable. `base` is always loaded and is the mandatory niri
desktop stack. Optional profiles live in `hosts/<hostname>/host.env`:

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
| `base` | Always applied: Void+niri desktop packages, stow packages, oh-my-zsh |
| `desktop-nvidia` | `nvidia-drm.modeset=1`, 32-bit libs, power management |
| `laptop` | Battery tools, power-saving CPU defaults |
| `steam` | Steam + gaming packages, configurable data paths |
| `grub-themed` | MilkGrub theme, GRUB display mode |
| `power-profile` | custom runit service for CPU governor and GPU power cap |
| `rgb` | OpenRGB package and host-selected RGB service |

Automatic selection during `--bootstrap`:

- `laptop` is selected when a battery is detected.
- `desktop-nvidia` is selected on NVIDIA `x86_64` glibc systems.
- `steam`, `rgb`, and `grub-themed` are never selected automatically.

Network/security toggles are not profiles, but host variables:

```sh
INSTALL_NFTABLES_CONFIG=1
INSTALL_SSH_HARDENING=1
```

Leave them unset or `0` on a generic new machine.

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

## Host Config

`./install.sh --bootstrap` creates this file automatically:

```sh
hosts/<hostname>/host.env
```

It is intentionally conservative. Edit it after first login when you know the
machine-specific values:

```sh
cd ~/dotfiles
$EDITOR "hosts/$(hostname | cut -d. -f1)/host.env"
```

Use `hosts/example/host.env` as the full reference template.

Monitor output layout is optional. If you need a fixed niri layout, create:

```sh
hosts/<hostname>/niri-outputs.kdl
```

The installer copies that file to `~/.config/niri/outputs-host.kdl`.

---

## Manual component installation

```sh
# Local full bootstrap from an existing checkout
./install.sh --bootstrap

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

Useful flags:

| Flag | Meaning |
|------|---------|
| `--bootstrap` | First-run mode; creates missing `hosts/<hostname>/host.env` |
| `--dry-run` | Print the plan without changing files or packages |
| `--host NAME` | Use `hosts/NAME/host.env` instead of the system hostname |
| `--profiles "..."` | Add optional profiles for this run |
| `--skip-packages` | Do not run `xbps-install` |
| `--skip-stow` | Do not apply home symlinks |
| `--skip-system` | Do not install `/etc`, runit, SDDM, GRUB, or service changes |
| `--no-host-create` | Fail if host config is missing |

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
- `hosts/desktop-srl/system/etc/udev/rules.d/99-usb-input-power.rules`
  keeps USB hubs and the current keyboard/mouse (`258a:010c`, `046d:c08b`) in
  `power/control=on`.
- This is opt-in via `INSTALL_USB_INPUT_POWER_FIX=1` in `hosts/desktop-srl/host.env`.

Lock behavior: top monitor disables on lock, restores on unlock.
Configure output names via `LOCK_TOP_OUTPUT` / `LOCK_BOTTOM_OUTPUT` in `host.env`.


### Laptop (profile: laptop)

- CPU: `powersave` governor + `power` EPP
- GPU power cap disabled
- Extra packages: `acpi`, `tlp`

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
./install.sh --bootstrap --dry-run --skip-packages --skip-system

# Individual checks
niri validate --config ~/.config/niri/config.kdl
fuzzel --check-config
sh -n bootstrap.sh scripts/bootstrap.sh
```

Remote bootstrap dry-run test:

```sh
DOTFILES_DIR=/tmp/dotfiles-test sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)" -- --dry-run --skip-packages --skip-system --host test-host
```
