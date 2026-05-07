# SRL dotfiles

Void Linux + niri desktop dotfiles, managed with GNU Stow.

## Why Stow

GNU Stow is a symlink-farm manager: files stay in this repository, while `~` receives symlinks. It is simple, transparent, easy to inspect with normal Git, and enough for this machine family.

`chezmoi` is the better next step if these configs need serious per-host templates, encrypted secrets, or different generated files per laptop/desktop. For the current goal, Stow plus an idempotent bootstrap keeps the system easier to reason about.

## Layout

- `home`: shell, Git, Starship and basic home dotfiles.
- `desktop`: niri, Waybar, Wofi/Rofi, Mako, Foot, Swaylock and portal config.
- `apps`: user app configs and desktop integration settings.
- `media`: audio configs without runtime databases or cookies.
- `bin`: selected personal scripts from `~/.local/bin`.
- `packages`: curated Void package manifest used by bootstrap.
- `services`: runit services that should be enabled.
- `scripts`: bootstrap, apply and snapshot commands.
- `system`: root-owned system config that is installed by dedicated scripts, not by Stow.

## Fresh Void install

```sh
sudo xbps-install -S git
git clone <repo-url> ~/dotfiles
~/dotfiles/scripts/bootstrap.sh
```

The bootstrap script installs packages from `packages/void-desktop.txt`, applies Stow packages, installs the SRL power profile, and enables runit services listed in `services/runit-enabled.txt`.

## Apply only dotfiles

```sh
~/dotfiles/scripts/apply.sh
```

Existing real files are moved to `~/dotfiles/backups/<timestamp>/` before Stow creates symlinks. Re-running is expected to be safe.

To apply only part of the repo:

```sh
PACKAGES="home desktop" ~/dotfiles/scripts/apply.sh
```

## Install GRUB Customization

```sh
~/dotfiles/scripts/install-grub.sh
```

This installs the MilkGrub theme, keeps only two GRUB entries (`Void Linux` and `Void Linux (recovery mode)`), disables extra GRUB generators, and backs up the previous GRUB config under `/root/grub-backup-<timestamp>/`.

## Install Quiet Runit Boot

```sh
~/dotfiles/scripts/install-runit-quiet-boot.sh
```

This installs the runit stage overrides that suppress normal boot console output when the kernel command line contains `quiet`. Recovery mode stays verbose because its GRUB entry does not use `quiet`.

## Install Power Profile

```sh
~/dotfiles/scripts/install-power-profile.sh
```

This installs the always-on SRL power profile: `intel_pstate` uses `powersave` with `balance_performance`, turbo stays enabled, CPU performance range remains `15..100%`, NVIDIA persistence is enabled, and the RTX 3070 Ti power limit is capped at `275W`.

## Install Keyd Bindings

```sh
~/dotfiles/scripts/install-keyd.sh
```

This installs the low-level `keyd` binding that runs the niri launcher on `Win+D`, even when an XWayland game grabs keyboard shortcuts.

## Install Steam Homebrew

```sh
~/dotfiles/scripts/install-steam-homebrew.sh
```

This installs native Void Steam, Steam 32-bit dependencies, Steam udev rules and Millennium from Steam Client Homebrew. Steam data is linked to `/adata/Steam` by default; override with `STEAM_DATA_DIR` and `STEAM_LIBRARY_DIR` when needed. The script also creates a Steam-local fontconfig wrapper to avoid Steam Runtime parsing noise from newer host fontconfig files. Millennium is pinned to `3.0.0-beta.24` because the current stable Linux package ships a 32-bit `hhx64` hook.

## Refresh repository from the live system

```sh
~/dotfiles/scripts/snapshot.sh
git -C ~/dotfiles status
```

Review the diff before committing. The snapshot script intentionally excludes histories, caches, browser profiles, Claude/Codex auth state, GitHub hosts, Pulse cookies/databases, stale app configs, unused backup files and other machine-private state.

## Notes for niri

The current niri setup assumes two `1920x1080@144Hz` outputs named `DP-1` and `DP-2`. If a laptop uses `eDP-1` or different monitor names, edit `desktop/.config/niri/config.kdl` before applying or add a host-specific layer later.

Only `1..5` are declared as persistent named workspaces. `workspace-cap-daemon.py` creates `b1..b5` dynamically while `DP-2` is connected, then removes those names and merges overflow workspaces back into `1..5` when only one output remains connected.
