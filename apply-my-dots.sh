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
#      ./apply-my-dots.sh --wallpaper FILE (theme everything to FILE)
#      ./apply-my-dots.sh --sddm-only (only the login-screen step below;
#                                      install.sh runs it after the SDDM theme)
#      ./apply-my-dots.sh --fresh     (reset everything, also what an update keeps)
#      ./apply-my-dots.sh --dry-run   (only show what would happen, change nothing)
#
#  Run again on a machine that already has these dots (the Waybar update button
#  does this) it is an UPDATE: your monitor layout, workspace rules, keyboard
#  layout, Waybar layout/style and GTK/icon/cursor themes are kept.
#
#  Without --wallpaper, the wallpaper you already use is kept: the one set in
#  GNOME, KDE Plasma, XFCE, Cinnamon, MATE or an earlier KooL/awww setup. The
#  first Hyprland login colours everything from it. Nothing found -> dedsec.
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
USER_WP=""
want_wp=0
SDDM_ONLY=0
FRESH=0
DRY_RUN=0
for arg in "$@"; do
    if [ "$want_wp" -eq 1 ]; then USER_WP="$arg"; want_wp=0; continue; fi
    case "$arg" in
    --wallpaper) want_wp=1 ;;
    --wallpaper=*) USER_WP="${arg#--wallpaper=}" ;;
    --sddm-only) SDDM_ONLY=1 ;;
    --fresh) FRESH=1 ;;
    --dry-run) DRY_RUN=1 ;;
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

# ---------------------------------------------------------------- SDDM
# The login screen follows the wallpaper (hypr/scripts/SddmAutoSync.sh, run on
# every wallpaper change). It only rewrites the theme's background and
# theme.conf, so those two files are handed to this user instead of needing
# passwordless sudo. The current wallpaper goes on the login screen right away,
# so even the first boot shows it; the colours follow on the first login.
sddm_setup() {
    local theme="/usr/share/sddm/themes/simple_sddm_2" wp
    [ -f "$theme/theme.conf" ] || return 0
    sudo install -d -m 755 "$theme/Backgrounds"
    sudo touch "$theme/Backgrounds/default"
    sudo chown "$(id -un)" "$theme/theme.conf" "$theme/Backgrounds/default"
    wp="$(readlink -f "$CFG/rofi/.current_wallpaper" 2>/dev/null || true)"
    if [ -f "$wp" ] && [[ ! "$wp" =~ \.(mp4|mkv|mov|webm)$ ]]; then
        cat -- "$wp" >"$theme/Backgrounds/default"
        rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/sddm_autosync/stamp"
        say "$OK SDDM login screen: $(basename "$wp")"
        # Colours too, when wallust is already installed: generate the palette
        # from the wallpaper (as the first login would) and let the sync script
        # write contrast-checked colours into theme.conf.
        if command -v wallust >/dev/null 2>&1 && [ -f "$CFG/wallust/wallust.toml" ] &&
            [ -x "$CFG/hypr/scripts/SddmAutoSync.sh" ]; then
            (
                wallust_args=()
                # shellcheck source=/dev/null
                [ -f "$CFG/hypr/scripts/WallustConfig.sh" ] && . "$CFG/hypr/scripts/WallustConfig.sh"
                wallust "${wallust_args[@]}" run -s "$wp"
            ) >/dev/null 2>&1 || true
            "$CFG/hypr/scripts/SddmAutoSync.sh" "$wp" >/dev/null 2>&1 || true
        fi
    fi
}
if [ "$SDDM_ONLY" -eq 1 ]; then
    sddm_setup
    exit 0
fi
if [ -n "$USER_WP" ]; then
    USER_WP="$(readlink -f -- "$USER_WP" 2>/dev/null || true)"
    [ -f "$USER_WP" ] || { say "$WARN --wallpaper: file not found."; exit 2; }
fi

# ---------------------------------------------------------------- wallpaper detect
# Runs before anything is overwritten: find the wallpaper this user already has.
is_image() {
    [ -f "$1" ] && [ -r "$1" ] || return 1
    case "${1,,}" in *.png | *.jpg | *.jpeg | *.webp | *.bmp | *.gif) return 0 ;; esac
    file -b --mime-type "$1" 2>/dev/null | grep -q '^image/'
}
# file:///a%20b.png -> /a b.png
uri_to_path() {
    local p="${1#\'}"; p="${p%\'}"; p="${p#file://}"
    printf '%b' "${p//%/\\x}"
}
# GNOME's default is an XML (light/dark or slideshow): take its first image.
# A KDE wallpaper package is a folder: take its biggest image.
resolve_wp() {
    local p="$1" f
    [ -n "$p" ] || return 1
    if [ -d "$p" ]; then
        for d in "$p/contents/images_dark" "$p/contents/images" "$p"; do
            f="$(find "$d" -maxdepth 1 -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.webp' \) \
                -printf '%s\t%p\n' 2>/dev/null | sort -rn | head -n1 | cut -f2-)"
            [ -n "$f" ] && { printf '%s\n' "$f"; return 0; }
        done
        return 1
    fi
    if [[ "${p,,}" == *.xml ]] && [ -r "$p" ]; then
        f="$(grep -oE '<(file|filename)>[^<]+' "$p" | head -n1 | sed 's/^<[a-z]*>//')"
        p="$f"
    fi
    is_image "$p" && printf '%s\n' "$p"
}
detect_wallpaper() {
    local c
    # 1. an earlier KooL / HolyJoey install
    c="$(readlink -f "$CFG/rofi/.current_wallpaper" 2>/dev/null)" && resolve_wp "$c" && return
    # 2. GNOME (dark-mode image first when dark mode is on), Budgie, Cinnamon, MATE
    if command -v gsettings >/dev/null 2>&1; then
        local keys=()
        if gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null | grep -q dark; then
            keys+=("org.gnome.desktop.background picture-uri-dark")
        fi
        keys+=("org.gnome.desktop.background picture-uri"
            "org.cinnamon.desktop.background picture-uri"
            "org.mate.background picture-filename")
        for k in "${keys[@]}"; do
            # shellcheck disable=SC2086
            c="$(gsettings get $k 2>/dev/null)" || continue
            resolve_wp "$(uri_to_path "$c")" && return
        done
    fi
    # 3. KDE Plasma
    local kde="$CFG/plasma-org.kde.plasma.desktop-appletsrc"
    if [ -r "$kde" ]; then
        while read -r c; do
            resolve_wp "$(uri_to_path "$c")" && return
        done < <(sed -n 's/^Image=//p' "$kde")
    fi
    # 4. XFCE
    if command -v xfconf-query >/dev/null 2>&1; then
        while read -r k; do
            resolve_wp "$(xfconf-query -c xfce4-desktop -p "$k" 2>/dev/null)" && return
        done < <(xfconf-query -c xfce4-desktop -l 2>/dev/null | grep '/last-image$')
    fi
    # 5. an awww/swww or hyprpaper already showing something
    for q in awww swww; do
        command -v "$q" >/dev/null 2>&1 || continue
        c="$("$q" query 2>/dev/null | sed -n 's/.*image: //p' | head -n1)"
        resolve_wp "$c" && return
    done
    c="$(sed -n 's/^ *wallpaper *= *[^,]*, *//p' "$CFG/hypr/hyprpaper.conf" 2>/dev/null | head -n1)"
    resolve_wp "${c/#\~/$HOME}" && return
    return 1
}
if [ -n "$USER_WP" ]; then
    FOUND_WP="$USER_WP"
else
    FOUND_WP="$(detect_wallpaper || true)"
fi
# Keep a private copy: it may live in a folder this script is about to replace.
if [ -n "$FOUND_WP" ]; then
    WP_TMP="$(mktemp -d)"
    trap 'rm -rf "$WP_TMP"' EXIT
    cp -- "$FOUND_WP" "$WP_TMP/$(basename "$FOUND_WP")" || FOUND_WP=""
fi

# ---------------------------------------------------------------- update or fresh
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/holyjoey-dots"
UPDATE=0
if [ "$FRESH" -ne 1 ] && [ -f "$STATE_DIR/repo" ] && [ -f "$CFG/hypr/.initial_startup_done" ]; then
    UPDATE=1
    say "$NOTE These dots are already installed: updating (monitors, keyboard layout, Waybar layout and themes are kept; --fresh resets them)."
fi

# Keyboard layout: an update keeps the one in use; a fresh install takes the
# system's (/etc/default/keyboard) instead of my "us".
KB_LAYOUT=""
KB_VARIANT=""
old_sys="$CFG/hypr/configs/SystemSettings.conf"
if [ "$UPDATE" -eq 1 ] && [ -f "$old_sys" ]; then
    KB_LAYOUT="$(sed -n 's/^ *kb_layout *= *//p' "$old_sys" | head -n1 | tr -d '[:space:]')"
    KB_VARIANT="$(sed -n 's/^ *kb_variant *= *//p' "$old_sys" | head -n1 | tr -d '[:space:]')"
elif [ -r /etc/default/keyboard ]; then
    KB_LAYOUT="$(. /etc/default/keyboard 2>/dev/null; echo "${XKBLAYOUT:-}" | tr -d '[:space:]')"
    KB_VARIANT="$(. /etc/default/keyboard 2>/dev/null; echo "${XKBVARIANT:-}" | tr -d '[:space:]')"
fi
[[ "$KB_LAYOUT" =~ ^[A-Za-z0-9_,-]+$ ]] || KB_LAYOUT=""
[[ "$KB_VARIANT" =~ ^[A-Za-z0-9_,-]*$ ]] || KB_VARIANT=""

if [ "$ASSUME_YES" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
    say "$NOTE This overwrites these folders in $CFG (a backup of each is made first):"
    say "      $(ls "$SRC/config" | tr '\n' ' ')"
    say "      plus ~/.zshrc"
    read -rp "Continue? [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]] || { say "Aborted."; exit 0; }
    if [ "$GET_BANK" -eq 1 ] && [ "$UPDATE" -ne 1 ]; then
        read -rp "Also download my wallpaper pack (158 images, ~800MB)? [Y/n] " ans
        [[ "$ans" =~ ^[Nn]$ ]] && GET_BANK=0
    fi
fi

# ---------------------------------------------------------------- packages
# Tools the customised configs/scripts call that the base install may lack.
pkgs=(rsync jq network-manager grim slurp wl-clipboard libnotify-bin fonts-roboto
    zenity imagemagick libglib2.0-bin python3   # wallpaper picker: add dialog, tile, trash; fastfetch accent
    python3-pil file                            # SDDM colours from the wallpaper; wallpaper detection
    firefox-esr neovim                          # SUPER+B; EDITOR in 01-UserDefaults.conf
    network-manager-gnome lsd                   # Waybar network click (nm-connection-editor); ls alias in .zshrc
    baobab)                                     # Waybar: right-click on Disk
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
if [ "${#missing[@]}" -gt 0 ] && [ "$DRY_RUN" -ne 1 ]; then
    say "$NOTE Installing: ${missing[*]}"
    sudo apt-get install -y "${missing[@]}" || say "$WARN Some packages failed to install, continuing."
fi

# Waybar's night-light button needs hyprsunset. A from-source install already
# built it into /usr/local/bin; otherwise take Debian's (trixie has it only in
# backports).
if [ "$DRY_RUN" -ne 1 ] && ! command -v hyprsunset >/dev/null 2>&1; then
    codename="$(. /etc/os-release && echo "${VERSION_CODENAME:-}")"
    if [ -n "$codename" ] && apt-cache policy hyprsunset 2>/dev/null | grep -q "${codename}-backports"; then
        sudo apt-get install -y -t "${codename}-backports" hyprsunset || say "$WARN hyprsunset failed to install; the night-light button won't work."
    else
        sudo apt-get install -y hyprsunset || say "$WARN hyprsunset failed to install; the night-light button won't work."
    fi
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

# An update leaves what is this machine's own: its monitors and workspace
# rules, and the marker that stops initial-boot.sh resetting the themes.
if [ "$UPDATE" -eq 1 ]; then
    protect+=(--exclude='/monitors.conf' --exclude='/workspaces.conf'
        --filter='P /.initial_startup_done')
fi

# Tallest connected screen, for the lock-screen layout below.
max_height=0
for st in /sys/class/drm/card*-*/status; do
    [ "$(cat "$st" 2>/dev/null)" = "connected" ] || continue
    h="$(head -n1 "${st%status}modes" 2>/dev/null | sed -n 's/^[0-9]*x\([0-9]*\).*/\1/p')"
    [ -n "$h" ] && [ "$h" -gt "$max_height" ] && max_height="$h"
done
IS_VM=0
systemd-detect-virt -q --vm 2>/dev/null && IS_VM=1

if [ "$DRY_RUN" -eq 1 ]; then
    say "$NOTE Dry run: nothing is changed."
    say "  Mode:            $([ "$UPDATE" -eq 1 ] && echo "update (monitors, keyboard, Waybar layout, themes kept)" || echo "fresh install")"
    say "  Wallpaper:       ${FOUND_WP:-dedsec default (none found)}"
    say "  Keyboard layout: ${KB_LAYOUT:-us (snapshot default)}${KB_VARIANT:+ ($KB_VARIANT)}"
    say "  Lock screen:     $([ "$max_height" -ge 1440 ] && echo "2k layout (${max_height}p screen)" || echo "standard layout")"
    say "  Virtual machine: $([ "$IS_VM" -eq 1 ] && echo "yes (hardware cursors off)" || echo no)"
    say "  Packages to install: ${missing[*]:-none}"
    command -v hyprsunset >/dev/null 2>&1 || say "  Also installs:   hyprsunset"
    say "  Wallpaper pack:  $([ "$GET_BANK" -eq 1 ] && echo "download ~800MB (existing files kept)" || echo skipped)"
    say "  Config folders (files that would change / be removed):"
    for src_dir in "$SRC"/config/*/; do
        name="$(basename "$src_dir")"
        [ "$name" = "systemd" ] && continue
        if [ -d "$CFG/$name" ]; then
            n="$(rsync -ani --delete "${protect[@]}" "$src_dir" "$CFG/$name/" | grep -vc '^\.d' || true)"
            say "    $name: $n"
        else
            say "    $name: new"
        fi
    done
    say "  Also replaced:   ~/.zshrc (backup kept), zsh prompt theme"
    exit 0
fi

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

# One-glyph "Claude Icon" font (Claude logo from simple-icons, at U+10CC00): Waybar shows it
# on workspaces whose terminal runs Claude Code. Waybar must be restarted to pick up new fonts.
mkdir -p "$HOME/.local/share/fonts"
cp -r "$SRC/home/fonts/." "$HOME/.local/share/fonts/"
fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || true

# The snapshot stores the home path as @HOME@ (Hyprland/qt5ct don't expand $HOME there).
grep -rIl '@HOME@' "${CFG}"/{hypr,qt5ct,qt6ct} 2>/dev/null |
    xargs -r sed -i "s#@HOME@#${HOME}#g"

if [ -n "$KB_LAYOUT" ]; then
    sed -i -E "s|^( *kb_layout *=).*|\\1 $KB_LAYOUT|; s|^( *kb_variant *=).*|\\1 $KB_VARIANT|" \
        "$CFG/hypr/configs/SystemSettings.conf"
    say "$OK Keyboard layout: $KB_LAYOUT${KB_VARIANT:+ ($KB_VARIANT)}"
fi

# Lock screen: the 2k layout on 1440p and taller screens (the standard one
# stays next to it as hyprlock-1080p.conf).
if [ "$max_height" -ge 1440 ] && [ -f "$CFG/hypr/hyprlock-2k.conf" ]; then
    cp "$CFG/hypr/hyprlock.conf" "$CFG/hypr/hyprlock-1080p.conf"
    cp "$CFG/hypr/hyprlock-2k.conf" "$CFG/hypr/hyprlock.conf"
    say "$OK Lock screen: 2k layout (${max_height}p screen)"
fi
# Virtual machine: hardware cursors are usually invisible there.
if [ "$IS_VM" -eq 1 ]; then
    sed -i -E 's|^( *no_hardware_cursors *=) *[0-9a-z]+|\1 1|' "$CFG/hypr/configs/SystemSettings.conf"
    say "$NOTE Virtual machine: hardware cursors disabled"
fi

# Waybar layout + style (relative symlinks, so they survive a username change).
# An update keeps the layout/style picked on this machine.
if [ "$UPDATE" -ne 1 ] || [ ! -e "$CFG/waybar/config" ]; then
    ln -sfn configs/TOP-Everforest "$CFG/waybar/config"
fi
if [ "$UPDATE" -ne 1 ] || [ ! -e "$CFG/waybar/style.css" ]; then
    ln -sfn style/Dark-Wallust-Obsidian-Edge.css "$CFG/waybar/style.css"
fi

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
# The wallpaper found earlier (or given with --wallpaper) replaces dedsec. It is
# copied into the wallpaper folder so the picker shows it and it survives the
# old desktop being removed.
if [ -n "$FOUND_WP" ]; then
    name="$(basename "$FOUND_WP")"
    src_copy="$WP_TMP/$name"
    if [ "$(readlink -f "$FOUND_WP")" = "$(readlink -f "$WP_DIR/$name" 2>/dev/null)" ]; then
        WP="$WP_DIR/$name"
    elif [ -e "$WP_DIR/$name" ] && ! cmp -s "$src_copy" "$WP_DIR/$name"; then
        WP="$WP_DIR/my-${name}"
        cp -- "$src_copy" "$WP"
    else
        WP="$WP_DIR/$name"
        cp -n -- "$src_copy" "$WP"
    fi
    say "$OK Wallpaper: $WP (everything gets themed to it on first login)"
fi
# initial-boot.sh shows .wallpaper_current and runs wallust on it at first login.
for f in "$CFG/hypr/wallpaper_effects/".wallpaper_current*; do
    [ -e "$f" ] && cp -- "$WP" "$f"
done
ln -sfn "$WP" "$CFG/hypr/wallpaper_effects/.hyprlock_current"
ln -sfn "$WP" "$CFG/rofi/.current_wallpaper"
# .wallpaper_current is now a copy of the same image. Since the
# snapshot has no .initial_startup_done, KooL's initial-boot.sh re-runs on next
# login: it sets the GTK/icon/cursor themes and generates wallust colours from it.
# Forget fastfetch/gen_config.py's "colours unchanged" fingerprint, so that run
# rebuilds the fastfetch configs, prompt accent and Waybar calendar for real.
rm -f "$HOME/.cache/fastfetch-gen.key"

sddm_setup

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

# ---------------------------------------------------------------- hyprsunset
# Hyprsunset.sh starts and stops hyprsunset itself. The packaged user unit
# starts a filter-less copy at login, which left the Waybar button on "on".
systemctl --user mask hyprsunset.service >/dev/null 2>&1 &&
    say "$OK hyprsunset.service masked (Hyprsunset.sh manages it)" || true

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

# ---------------------------------------------------------------- update button
# Waybar's update button (hypr/scripts/DotsUpdate.sh) checks this clone against GitHub.
mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/holyjoey-dots"
echo "$REPO_DIR" > "${XDG_STATE_HOME:-$HOME/.local/state}/holyjoey-dots/repo"

# ---------------------------------------------------------------- reload
if [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    hyprctl reload >/dev/null 2>&1 || true
    pkill -x waybar >/dev/null 2>&1 || true
    (waybar >/dev/null 2>&1 &)
    # The snapshot's generated colour files are for my wallpaper; an update has
    # no first-login run to redo them, so recolour from the current one now.
    if [ "$UPDATE" -eq 1 ] && [ -x "$CFG/hypr/scripts/WallustSwww.sh" ]; then
        "$CFG/hypr/scripts/WallustSwww.sh" "$WP" >/dev/null 2>&1 || true
    fi
fi

say ""
say "$OK HolyJoey dots $([ "$UPDATE" -eq 1 ] && echo updated || echo applied)."
say "      Wallpaper:  $WP"
[ -d "$backup_root" ] && say "      Backups:    $backup_root (and ~/.zshrc.my-dots-backup-$STAMP)"
[ -f /usr/share/sddm/themes/simple_sddm_2/theme.conf ] ||
    say "      Login screen: SDDM theme not installed, so it does not follow the wallpaper."
[ "$GET_BANK" -eq 1 ] || say "      Wallpaper pack skipped (--no-wallpapers)."
say "      Log out and back in for everything to take effect."
