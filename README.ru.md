# dotfiles

Переносимые dotfiles для Void Linux + niri Wayland desktop.
Управляются через [GNU Stow](https://www.gnu.org/software/stow/).

## Установка На Новую Void Машину

После завершения установщика Void:

1. Загрузись в установленную систему.
2. Войди обычным пользователем, не `root`.
3. Убедись, что пользователь может выполнять root-команды через `sudo` или `doas`.
4. Запусти bootstrap одной строкой.

```sh
sudo xbps-install -Sy curl ca-certificates && sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)"
```

После завершения перезагрузи систему.

```sh
sudo reboot
```

На экране входа выбери `Niri (SDDM wrapper)`, если SDDM не выбрал эту сессию
автоматически.

### Что Делает Команда

Bootstrap-скрипт:

- проверяет, что система действительно Void Linux;
- устанавливает `git`, `curl` и `ca-certificates`, если их нет;
- клонирует или обновляет репозиторий в `~/dotfiles`;
- запускает `./install.sh --bootstrap`;
- автоматически создаёт `hosts/<hostname>/host.env`, если его нет;
- устанавливает базовый набор пакетов Void+niri desktop;
- применяет home-конфиги через stow;
- устанавливает wrapper-сессию niri для SDDM;
- включает базовые runit-сервисы для графического входа:
  `dbus`, `elogind`, `NetworkManager`, `polkitd`, `sddm`.

По умолчанию bootstrap не включает Steam, RGB, тему GRUB, USB quirks,
кастомные nftables-правила и SSH hardening. Это настройки конкретного хоста
или профиля.

### Требования

- Запускай команду от имени будущего desktop-пользователя.
- Не запускай её как `sudo sh ...` и не запускай напрямую из-под `root`.
- У пользователя уже должен быть доступ к `sudo` или `doas`.

Если на свежем Void ещё нет `sudo` или `doas`, сначала настрой это из-под root.
Пример для `sudo`:

```sh
su -
xbps-install -Sy sudo
usermod -aG wheel YOUR_USER
EDITOR=nano visudo
```

В `visudo` разреши группу `wheel`, затем выйди и снова войди как `YOUR_USER`.

### Дополнительные Профили

Передавай дополнительные профили, если новая машина в них нуждается.

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)" -- --profiles "steam grub-themed"
```

На NVIDIA-машинах `x86_64` glibc режим `--bootstrap` автоматически выбирает
профиль `desktop-nvidia`, чтобы у niri/Wayland был нужный драйверный стек.
На ноутбуках автоматически выбирается `laptop`. Steam, RGB и тема GRUB
включаются только явно.

Предпросмотр локального checkout без изменений:

```sh
./install.sh --bootstrap --dry-run
```

Ручной путь через clone:

```sh
sudo xbps-install -Sy git ca-certificates
git clone https://github.com/SRLQNL/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --bootstrap
```

### После Первого Входа

После первого успешного входа в niri проверь имена мониторов:

```sh
niri msg outputs
```

Затем отредактируй сгенерированный host config, если этой машине нужны
раскладка мониторов, пути Steam, тема GRUB, RGB, proxy, firewall или SSH policy:

```sh
$EDITOR ~/dotfiles/hosts/$(hostname | cut -d. -f1)/host.env
```

После изменений повторно запусти installer:

```sh
cd ~/dotfiles
./install.sh --bootstrap
```

---

## Структура

```
dotfiles/
├── bootstrap.sh        # Remote entrypoint для curl | sh
├── install.sh          # Основной installer: hardware detection, profiles, stow, validation
├── profiles/           # Составные feature-профили
│   ├── base.env        # Всегда загружается
│   ├── desktop-nvidia.env
│   ├── laptop.env
│   ├── steam.env
│   ├── grub-themed.env
│   └── power-profile.env
├── hosts/              # Настройки отдельных машин
│   ├── example/        # Полный шаблон
│   └── desktop-srl/    # Текущий NVIDIA desktop
│
├── home/               # Shell, git, starship
├── desktop/            # niri, waybar, foot, mako, fuzzel, swaylock
├── apps/               # GTK, btop, mpv, fontconfig и т.д.
├── media/              # PulseAudio/PipeWire configs
├── bin/                # ~/.local/bin scripts
│
├── packages/           # Списки пакетов Void
├── services/           # runit-enabled.txt
├── scripts/            # Вспомогательные installer-скрипты
└── system/             # Root-level configs
```

---

## Профили

Профили составные. `base` всегда загружается и содержит обязательный niri
desktop stack. Дополнительные профили задаются в `hosts/<hostname>/host.env`:

```sh
PROFILES="desktop-nvidia steam grub-themed power-profile"
```

Или передаются через CLI:

```sh
./install.sh --profiles "desktop-nvidia steam"
```

| Профиль | Что делает |
|---------|------------|
| `base` | Базовый Void+niri desktop, stow packages, oh-my-zsh |
| `desktop-nvidia` | `nvidia-drm.modeset=1`, 32-bit libs, power management |
| `laptop` | Battery tools и энергосберегающие CPU-настройки |
| `steam` | Steam + gaming packages, настраиваемые пути данных |
| `grub-themed` | Тема MilkGrub и GRUB display mode |
| `power-profile` | runit-сервис для CPU governor и GPU power cap |
| `rgb` | OpenRGB и выбранный host RGB service |

Автовыбор во время `--bootstrap`:

- `laptop` выбирается, если обнаружена батарея.
- `desktop-nvidia` выбирается на NVIDIA `x86_64` glibc системах.
- `steam`, `rgb` и `grub-themed` никогда не выбираются автоматически.

Сетевые и security-настройки не являются профилями, это переменные host config:

```sh
INSTALL_NFTABLES_CONFIG=1
INSTALL_SSH_HARDENING=1
```

На обычной новой машине оставляй их пустыми или `0`.

---

## Host Config

`./install.sh --bootstrap` автоматически создаёт:

```sh
hosts/<hostname>/host.env
```

Файл намеренно консервативный. Редактируй его после первого входа, когда уже
известны machine-specific значения:

```sh
cd ~/dotfiles
$EDITOR "hosts/$(hostname | cut -d. -f1)/host.env"
```

Полный шаблон находится в `hosts/example/host.env`.

Если нужна фиксированная раскладка мониторов niri, создай:

```sh
hosts/<hostname>/niri-outputs.kdl
```

Installer скопирует этот файл в `~/.config/niri/outputs-host.kdl`.

---

## Ручные Команды

```sh
# Полный локальный bootstrap из уже склонированного репозитория
./install.sh --bootstrap

# Применить только stow, без пакетов и system config
./install.sh --skip-packages --skip-system

# Только конкретные stow packages
PACKAGES="home desktop" scripts/apply.sh

# Тема GRUB
scripts/install-grub.sh

# Power profile runit service
scripts/install-power-profile.sh

# Steam + Millennium
STEAM_DATA_DIR=/your/drive/Steam scripts/install-steam-homebrew.sh

# Quiet runit boot
scripts/install-runit-quiet-boot.sh

# Синхронизировать live-систему обратно в repo
scripts/snapshot.sh && git -C ~/dotfiles status
```

Полезные флаги:

| Флаг | Значение |
|------|----------|
| `--bootstrap` | First-run режим; создаёт отсутствующий `hosts/<hostname>/host.env` |
| `--dry-run` | Показать план без изменений файлов и пакетов |
| `--host NAME` | Использовать `hosts/NAME/host.env` вместо hostname системы |
| `--profiles "..."` | Добавить optional profiles для этого запуска |
| `--skip-packages` | Не запускать `xbps-install` |
| `--skip-stow` | Не применять home symlinks |
| `--skip-system` | Не устанавливать `/etc`, runit, SDDM, GRUB и services |
| `--no-host-create` | Упасть, если host config отсутствует |

---

## Проверка

```sh
# Полная проверка без изменений
./install.sh --bootstrap --dry-run --skip-packages --skip-system

# Отдельные проверки
niri validate --config ~/.config/niri/config.kdl
fuzzel --check-config
sh -n bootstrap.sh scripts/bootstrap.sh
```

Проверка remote bootstrap в dry-run:

```sh
DOTFILES_DIR=/tmp/dotfiles-test sh -c "$(curl -fsSL https://raw.githubusercontent.com/SRLQNL/dotfiles/main/bootstrap.sh)" -- --dry-run --skip-packages --skip-system --host test-host
```
