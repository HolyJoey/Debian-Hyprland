#!/usr/bin/env bash
# ==================================================
#  apply-my-dots.sh - HolyJoey's Hyprland setup
#  Applies the snapshot in ./my-dots: a full copy of every KooL dots folder
#  as configured on HolyJoey's machine.
#
#  ./install.sh runs this automatically (it is the dots step), and it can
#  also be run on its own on an existing Hyprland install:
#      ./apply-my-dots.sh            (asks before overwriting)
#      ./apply-my-dots.sh --yes      (no questions)
#      ./apply-my-dots.sh --no-satty (skip building satty)
#      ./apply-my-dots.sh --no-wallpapers (skip the ~800MB wallpaper download)
# ==================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
SRC="$REPO_DIR/my-dots"
CFG="${XDG_CONFIG_HOME:-$HOME/.config}"
STAMP="$(date +%Y%m%d-%H%M%S)"
SATTY_TAG="v0.22.0"
BANK_COMMIT="f6fde9158feb6e0a283560c363233ff57ffdb65c"   # LinuxBeginnings/Wallpaper-Bank

ASSUME_YES=0
BUILD_SATTY=1
GET_BANK=1
for arg in "$@"; do
    case "$arg" in
    -y | --yes) ASSUME_YES=1 ;;
    --no-satty) BUILD_SATTY=0 ;;
    --no-wallpapers) GET_BANK=0 ;;
    -h | --help)
        sed -n '3,/^# ====/p' "$0" | sed '$d; s/^# \{0,1\}//'
        exit 0
        ;;
    *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

OK="$(tput setaf 2 2>/dev/null)[OK]$(tput sgr0 2>/dev/null)"
NOTE="$(tput setaf 3 2>/dev/null)[NOTE]$(tput sgr0 2>/dev/null)"
WARN="$(tput setaf 1 2>/dev/null)[WARN]$(tput sgr0 2>/dev/null)"
say() { echo -e "$*"; }

if [ "$(id -u)" -eq 0 ]; then
    say "$WARN Run this as your normal user, not root."
    exit 1
fi
[ -d "$SRC/config" ] || { say "$WARN $SRC/config not found."; exit 1; }

if [ "$ASSUME_YES" -ne 1 ]; then
    say "$NOTE This overwrites these folders in $CFG (a backup of each is made first):"
    say "      $(ls "$SRC/config" | tr '\n' ' ')"
    say "      plus ~/.zshrc"
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
fi

# ---------------------------------------------------------------- packages
# Tools the customised configs/scripts call that the base install may lack.
pkgs=(rsync jq network-manager grim slurp wl-clipboard libnotify-bin fonts-roboto
    zenity imagemagick libglib2.0-bin python3)  # wallpaper picker: add dialog, tile, trash; fastfetch accent
# VA-API driver for Intel iGPUs (see LIBVA_DRIVER_NAME below)
if lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi intel; then
    pkgs+=(intel-media-va-driver)
fi
# LibreOffice is told to use the gtk3 backend (SAL_USE_VCLPLUGIN=gtk3)
if dpkg -s libreoffice-core >/dev/null 2>&1; then
    pkgs+=(libreoffice-gtk3)
fi
missing=()
for p in "${pkgs[@]}"; do
    # dpkg-query rather than dpkg -s: the latter errors on multi-arch installs
    dpkg-query -W -f='${Status}\n' "$p" 2>/dev/null | grep -q 'install ok installed' || missing+=("$p")
done
if [ "${#missing[@]}" -gt 0 ]; then
    say "$NOTE Installing: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}" || say "$WARN Some packages failed to install, continuing."
fi

# ---------------------------------------------------------------- configs
# Each folder is mirrored exactly (rsync --delete), so the result matches the
# snapshot. Wallpaper state files are generated at runtime and left alone.
protect=(
    --filter='P wallpaper_effects/.wallpaper_base*'
    --filter='P wallpaper_effects/.wallpaper_modified'
    --filter='P wallpaper_effects/.hyprlock_current'
    --filter='P .current_wallpaper*'
    --filter='P /config'
    --filter='P /style.css'
)

backup_root="$CFG/my-dots-backup-$STAMP"
for src_dir in "$SRC"/config/*/; do
    name="$(basename "$src_dir")"
    dest="$CFG/$name"
    [ "$name" = "systemd" ] && continue   # merged below, never mirrored
    if [ -e "$dest" ]; then
        mkdir -p "$backup_root"
        cp -a "$dest" "$backup_root/"
    fi
    mkdir -p "$dest"
    rsync -a --delete "${protect[@]}" "$src_dir" "$dest/"
    say "$OK $name"
done
[ -d "$backup_root" ] && say "$NOTE Previous configs backed up to $backup_root"

# systemd user drop-ins (polkit agent, portal): merge, so other units survive
mkdir -p "$CFG/systemd"
rsync -a "$SRC/config/systemd/" "$CFG/systemd/"
systemctl --user daemon-reload >/dev/null 2>&1 || true
if systemctl --user list-unit-files 2>/dev/null | grep -q '^hyprpolkitagent\.service'; then
    systemctl --user enable hyprpolkitagent >/dev/null 2>&1 || true
fi

# rofi looks up themes in ~/.local/share/rofi/themes too
mkdir -p "$HOME/.local/share/rofi/themes"
ln -snf "$CFG/rofi/themes/"* "$HOME/.local/share/rofi/themes/"

# The snapshot stores the home path as @HOME@ (Hyprland/qt5ct don't expand $HOME there).
grep -rIl '@HOME@' "${CFG}"/{hypr,qt5ct,qt6ct} 2>/dev/null |
    xargs -r sed -i "s#@HOME@#${HOME}#g"

# Waybar layout + style (relative symlinks, so they survive a username change)
ln -sfn configs/TOP-Everforest "$CFG/waybar/config"
ln -sfn style/Dark-Wallust-Obsidian-Edge.css "$CFG/waybar/style.css"

# Scripts must stay executable
chmod +x "$CFG/hypr/scripts/"* "$CFG/hypr/UserScripts/"* "$CFG/hypr/initial-boot.sh" 2>/dev/null || true

# ---------------------------------------------------------------- wallpaper
WP_DIR="$HOME/Pictures/wallpapers"
WP="$WP_DIR/wp4020131-dedsec-wallpapers.png"
mkdir -p "$WP_DIR"
# The wallpapers that are not in KooL's Wallpaper-Bank ship in this repo.
cp -n "$SRC/wallpapers/"* "$WP_DIR/" 2>/dev/null || true
# The rest (158 files, ~800MB) come from Wallpaper-Bank, pinned to the commit
# my folder matches. Only the files listed in my-dots/wallpaper-bank.txt are
# downloaded; existing files are never overwritten.
if [ "$GET_BANK" -eq 1 ]; then
    say "$NOTE Downloading wallpapers from Wallpaper-Bank (~800MB, can take a while)..."
    bank_dir="$(mktemp -d)"
    if git -C "$bank_dir" init -q &&
        git -C "$bank_dir" remote add origin https://github.com/LinuxBeginnings/Wallpaper-Bank.git &&
        sed 's#^#/wallpapers/#' "$SRC/wallpaper-bank.txt" | git -C "$bank_dir" sparse-checkout set --no-cone --stdin &&
        git -C "$bank_dir" fetch -q --depth=1 --filter=blob:none origin "$BANK_COMMIT" &&
        git -C "$bank_dir" checkout -q FETCH_HEAD; then
        rsync -a --ignore-existing "$bank_dir/wallpapers/" "$WP_DIR/"
        say "$OK Wallpapers in $WP_DIR: $(find "$WP_DIR" -type f | wc -l)"
    else
        say "$WARN Wallpaper-Bank download failed; run ./apply-my-dots.sh --yes again later to retry."
    fi
    rm -rf "$bank_dir"
fi
ln -sfn "$WP" "$CFG/hypr/wallpaper_effects/.hyprlock_current"
ln -sfn "$WP" "$CFG/rofi/.current_wallpaper"
# .wallpaper_current (from the snapshot) is a copy of the same image. Since the
# snapshot has no .initial_startup_done, KooL's initial-boot.sh re-runs on next
# login: it sets the GTK/icon/cursor themes and generates wallust colours from it.

# ---------------------------------------------------------------- shell
if [ -f "$HOME/.zshrc" ]; then
    cp -a "$HOME/.zshrc" "$HOME/.zshrc.my-dots-backup-$STAMP"
fi
cp "$SRC/home/.zshrc" "$HOME/.zshrc"
[ -d "$HOME/.oh-my-zsh" ] || say "$NOTE ~/.zshrc expects oh-my-zsh (select the zsh option in install.sh)."
# My agnosterzak prompt (colours follow the wallpaper). custom/themes wins over
# the stock theme of the same name that install-scripts/zsh.sh puts in themes/.
ZSH_THEMES="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes"
mkdir -p "$ZSH_THEMES"
for theme in "$SRC/home/oh-my-zsh-custom/themes/"*.zsh-theme; do
    dest="$ZSH_THEMES/$(basename "$theme")"
    if [ -f "$dest" ] && ! cmp -s "$theme" "$dest"; then
        cp -a "$dest" "$dest.my-dots-backup-$STAMP"
    fi
    cp "$theme" "$dest"
done

# ---------------------------------------------------------------- GPU env
USER_ENV="$CFG/hypr/UserConfigs/ENVariables.conf"
SYS_ENV="$CFG/hypr/configs/ENVariables.conf"
if ! lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi intel; then
    # LIBVA_DRIVER_NAME=iHD is only right on Intel; libva does not fall back.
    sed -i 's/^env = LIBVA_DRIVER_NAME,iHD/#env = LIBVA_DRIVER_NAME,iHD  # disabled: no Intel GPU/' "$USER_ENV"
    say "$NOTE No Intel GPU found: disabled LIBVA_DRIVER_NAME=iHD"
fi
if lspci 2>/dev/null | grep -Ei 'vga|3d|display' | grep -qi nvidia; then
    sed -i -E 's/^#(env = (LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME|NVD_BACKEND),[a-z]+).*/\1/' "$SYS_ENV"
    sed -i 's/^env = LIBVA_DRIVER_NAME,iHD/#env = LIBVA_DRIVER_NAME,iHD  # disabled: NVIDIA GPU/' "$USER_ENV"
    say "$NOTE NVIDIA GPU found: re-enabled the NVIDIA env block"
fi

# ---------------------------------------------------------------- hyprlock
# hyprlock segfaults when the source-built libhyprgraphics in /usr/local/lib
# shadows Debian's; the LD_LIBRARY_PATH prefix in hypridle.conf works around it.
# Only keep it when both copies actually exist.
if ! { ls /usr/local/lib/libhyprgraphics.so* && ls /lib/x86_64-linux-gnu/libhyprgraphics.so*; } >/dev/null 2>&1; then
    sed -i 's#|| LD_LIBRARY_PATH=/lib/x86_64-linux-gnu hyprlock#|| hyprlock#' "$CFG/hypr/hypridle.conf"
fi

# ---------------------------------------------------------------- hypridle
# hypridle is started by Hyprland (exec-once). The packaged systemd user unit
# would start a second copy; two daemons race two hyprlocks and locking breaks.
systemctl --user mask hypridle.service >/dev/null 2>&1 &&
    say "$OK hypridle.service masked (runs from exec-once only)" || true

# ---------------------------------------------------------------- satty
# Screenshot editor (SUPER+SHIFT+S). The upstream prebuilt needs a newer glibc
# than Debian 13, so build it from source.
if [ "$BUILD_SATTY" -eq 1 ] && ! command -v satty >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/satty" ]; then
    say "$NOTE Building satty $SATTY_TAG from source..."
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    if ! command -v cargo >/dev/null 2>&1; then
        sudo apt-get install -y cargo rustc || true
    fi
    # If libxkbcommon0 comes from backports, the -dev package must match it.
    xkb_ver="$(dpkg-query -W -f='${Version}' libxkbcommon0 2>/dev/null || true)"
    xkb_dev="libxkbcommon-dev"
    [[ "$xkb_ver" == *bpo* ]] && xkb_dev="libxkbcommon-dev=$xkb_ver"
    sudo apt-get install -y git pkg-config libgtk-4-dev libadwaita-1-dev "$xkb_dev" || true
    build_dir="$(mktemp -d)"
    if git clone --depth=1 -b "$SATTY_TAG" https://github.com/Satty-org/Satty.git "$build_dir/satty" &&
        (cd "$build_dir/satty" && cargo build --release); then
        install -Dm755 "$build_dir/satty/target/release/satty" "$HOME/.local/bin/satty"
        say "$OK satty installed to ~/.local/bin/satty"
    else
        say "$WARN satty build failed; SUPER+SHIFT+S will not open the editor until it is installed."
    fi
    rm -rf "$build_dir"
fi

# ---------------------------------------------------------------- reload
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
    pkill -x waybar >/dev/null 2>&1 || true
    (waybar >/dev/null 2>&1 &)
fi

say "$OK HolyJoey dots applied. Log out and back in for everything to take effect."
