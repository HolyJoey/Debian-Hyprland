# HolyJoey's Debian Hyprland

My complete Hyprland setup for Debian 13 (Trixie), installed with one script and no
questions asked.

Based on [JaKooLit's KooL Hyprland](https://github.com/LinuxBeginnings/Debian-Hyprland)
installer and dotfiles.

## Install

```bash
git clone --depth=1 https://github.com/HolyJoey/Debian-Hyprland.git ~/Debian-Hyprland
cd ~/Debian-Hyprland
./install.sh
```

Run it as your normal user, not root. `sudo` and `chsh` ask for your password; nothing else asks
anything. Reboot when it finishes.

Already have Hyprland and only want the configs?

```bash
./apply-my-dots.sh                  # asks once before overwriting
./apply-my-dots.sh --yes            # no questions
./apply-my-dots.sh --no-satty       # skip building satty
./apply-my-dots.sh --no-wallpapers  # skip the ~800MB wallpaper download
./apply-my-dots.sh --wallpaper ~/Pictures/mine.png   # theme everything to this image
```

Every folder it replaces is backed up to `~/.config/my-dots-backup-<date>/` first.
`~/.zshrc` and the zsh prompt theme get a `.my-dots-backup-<date>` copy next to them.

## What gets installed

- Hyprland, built from source (versions are in `hypr-tags.env`)
- SDDM with its theme, GTK themes, Bluetooth, Thunar, AGS, Quickshell and Yazi
- zsh with oh-my-zsh
- My configs from [`my-dots/`](my-dots), copied into `~/.config`

## The setup

- **Waybar**: TOP-Everforest layout with the Dark-Wallust-Obsidian-Edge style in fixed
  black and white, 24h clock, per-monitor workspaces, and a tray that slides out on hover.
  The clock's calendar takes the wallpaper accent (scroll to change month, right-click for
  today). Temp shows the CPU package sensor (Intel coretemp or AMD k10temp). The night-light
  button uses hyprsunset and Disk's right-click opens baobab; apply-my-dots.sh installs both
- **Game mode** (SUPER+SHIFT+G): no animations, blur, shadows, gaps or rounding, the wallpaper
  is stopped, and every window is fully opaque, kitty's background included
  (`kitty/gamemode.conf`). Turning it off reloads Hyprland, so your own config comes back
- **WiFi**: click the network module for a rofi network picker
  (`hypr/scripts/rofi-wifi-menu.sh`)
- **Workspaces**: every monitor owns 5 workspaces, re-applied on hotplug
  (`hypr/scripts/MonitorWorkspaces.sh`)
- **Claude Code icon**: a workspace whose terminal runs Claude Code shows the Claude logo
  instead of the terminal icon. It is a one-glyph font (`my-dots/home/fonts/ClaudeIcon`),
  matched on the status glyph Claude Code puts in the window title
- **Screenshots**: SUPER+SHIFT+S opens [satty](https://github.com/Satty-org/Satty). It is
  built from source, because the prebuilt needs a newer glibc than Debian 13
- **Lock screen**: hyprlock shows the current wallpaper, dimmed and blurred, with light text
  and soft shadows, so it stays readable on any wallpaper. The clock uses the same 12h/24h
  setting as Waybar (`hypr/scripts/LockClock.sh`). hypridle runs only from Hyprland's
  exec-once, and `hypridle.service` is masked, because a second daemon breaks locking
- **Night light**: `hyprsunset.service` is masked too. Hyprsunset.sh starts hyprsunset
  itself, and the packaged unit's copy made the Waybar button show "on" after every boot
- **Terminal**: kitty with the Brogrammer theme, and fastfetch without a logo. It picks the
  biggest layout that fits the window (full, compact or mini) by width and height, and skips
  itself in tiny windows. The layouts come from `fastfetch/gen_config.py`. Its accent colour
  and the zsh prompt's colours come from the wallpaper (see [Wallpapers](#wallpapers)).
  They are rebuilt in the background when the wallpaper changes and cached, so opening a
  terminal only reads the cache; re-runs on the same wallpaper are skipped
- **Themes**: Flat-Remix-GTK-Blue-Dark, Flat-Remix-Blue-Dark icons, Bibata-Modern-Ice cursor
- **GPU**: `lspci` decides the video env vars. Intel gets `LIBVA_DRIVER_NAME=iHD`, and NVIDIA
  gets the NVIDIA block
- **Tray**: no nm-applet or blueman-applet icons; waybar handles network
- **Update button** (in the notification drawer): checks this repo on GitHub instead of KooL's
  dots, and offers to pull and re-run `apply-my-dots.sh` when you are behind
- Flatpak apps show up in rofi

## Wallpapers

The installer puts my whole wallpaper folder (166 images) in `~/Pictures/wallpapers`. The 8
that are not in KooL's [Wallpaper-Bank](https://github.com/LinuxBeginnings/Wallpaper-Bank)
ship in [`my-dots/wallpapers/`](my-dots/wallpapers). The other 158 (~800MB) are downloaded
from the bank, pinned to the exact version I have. Skip that download with
`./apply-my-dots.sh --no-wallpapers`.

**Your own wallpaper comes along.** Set the wallpaper you want in your current desktop
(GNOME, KDE Plasma, XFCE, Cinnamon, MATE) before installing. The installer copies it into
`~/Pictures/wallpapers`, and the first Hyprland login themes everything to it: Hyprland borders,
Waybar, rofi, the terminal prompt, fastfetch, the lock screen and the SDDM login screen (the
picture is on the login screen from the very first boot; its colours follow after the first
login). Pick a file yourself with `./install.sh --wallpaper <file>`. If nothing is found you get
the dedsec wallpaper.

The login screen part needs SDDM. If another login manager (GDM, LightDM) is already running, the
installer leaves it alone and skips SDDM, so that login screen keeps its own look. `./install.sh
--sddm` switches to SDDM anyway (from the next reboot).

`./apply-my-dots.sh --restore` puts the newest backup back (the three newest are kept), and each
run is logged in `~/.local/state/holyjoey-dots/`. NVIDIA drivers are not installed (install them
yourself); the NVIDIA settings in the config are switched on when an NVIDIA card is found.

`./apply-my-dots.sh --dry-run` shows what would be installed and overwritten without changing
anything. `--no-wallpapers` (also on `install.sh`) skips the wallpaper pack. Screens of 1440p and
up get the 2k lock-screen layout, and a virtual machine gets hardware cursors turned off.

**Updating.** Running `apply-my-dots.sh` again (the Waybar update button does) keeps what belongs
to your machine: monitor layout, workspace rules, keyboard layout, Waybar layout/style and the
GTK/icon/cursor themes. `--fresh` resets those too. On a first install the keyboard layout is taken
from the system and monitors use their preferred mode.

| Keys | What it does |
| --- | --- |
| SUPER + W | Wallpaper picker: a rofi grid with previews |
| CTRL + ALT + W | Random wallpaper |
| SUPER + SHIFT + W | Effects on the current wallpaper (blur, sepia, oil paint, vignette...) |
| SUPER + SHIFT + E → Set Hyprlock Wallpaper | A different lock screen wallpaper, until the next wallpaper change |
| SUPER + SHIFT + E → Toggle Waybar Clock (12H/24H) | 12h or 24h clock, on Waybar and the lock screen |
| SUPER + SHIFT + E → Toggle Waybar Wallpaper Colors | Let Waybar follow the wallpaper, or go back to fixed black and white |

The picker starts with four special tiles: **Add Wallpaper**, **Random**, **Previous** and
**Current**.

- **Add Wallpaper** opens a file dialog. The images you pick are copied into
  `~/Pictures/wallpapers`, and the last one is applied. If a different file already has the
  same name, a number is added to the new one's name.
- **Previous** is the wallpaper this monitor showed before the current one, so picking it
  flips back and forth. Random picks and the auto-change count too. On a fresh install it
  appears after your first wallpaper change.
- **To remove a wallpaper**, right-click its tile, or highlight it and press Shift+Delete.
  A prompt shows the wallpaper and asks to confirm. Removed files go to the trash, so you
  can get them back.

When you change the wallpaper:

- **Only the focused monitor changes.** Each monitor keeps its own wallpaper, and it comes
  back after a reboot.
- **The colours follow it.** [wallust](https://codeberg.org/explosion-mental/wallust) builds
  a colour scheme from the image and applies it to Hyprland's window borders, rofi, cava and
  Ghostty.
- **Fastfetch, the prompt, rofi and the Waybar calendar take the wallpaper's accent.** This is the most vivid colour
  that covers a real part of the image, read straight from the image. Fastfetch uses it for
  the icons and your name, with a darker shade for the frame. The prompt's time and folder
  segments use a darker version, so their white text stays readable. Both update in the next
  terminal you open.
  rofi gets it through `rofi/99-overrides.rasi`, which `config.rasi` imports after the theme,
  so it applies to whichever rofi theme you pick (SUPER + CTRL + R)
- **Waybar stays black and white.** Its colours are fixed. To let it follow the wallpaper
  too, turn on SUPER + SHIFT + E → Toggle Waybar Wallpaper Colors.
- **Waybar, swaync and rofi restart** to load the new colours, so the bar flickers for a
  moment.
- **Some things keep their own look:** kitty stays on the Brogrammer theme, and the GTK
  theme, icons and cursor don't change.
- **The lock screen follows.** It shows the new wallpaper, dimmed and blurred behind the
  clock. Wallpaper effects (SUPER + SHIFT + W) don't change it. It keeps its own copy, so
  removing that wallpaper later doesn't leave the lock screen blank.
- **The login screen follows.** SDDM gets the new wallpaper and its colours
  (`hypr/scripts/SddmAutoSync.sh`). Text colours are checked against the part of the wallpaper
  behind the login form and the background is dimmed just enough to keep them readable. It
  writes to `/usr/share/sddm/themes`, so it needs passwordless sudo; without it, nothing
  happens and SUPER + SHIFT + E → Set SDDM Wallpaper still does it by hand.

On first login the dedsec wallpaper is set, and the colours are generated from it. Changing
the wallpaper automatically every 30 minutes is off. To turn it on, uncomment
`exec-once = $SwwwRandom $wallDIR` in `~/.config/hypr/configs/Startup_Apps.conf`.

## Options

```bash
./install.sh --interactive   # pick components yourself (my configs are still applied)
./install.sh --interactive --tty   # same, with plain text prompts instead of dialogs
```

If a newer Hyprland ever breaks the config, pin `HYPRLAND_TAG` in `hypr-tags.env`. This
setup was made on `v0.55.2`.

## Updating the configs in this repo

Copy the changed folder from `~/.config` into `my-dots/config/` and write `/home/<user>`
as `@HOME@`. `apply-my-dots.sh` fills in the real path on install. `~/.zshrc` lives in
`my-dots/home/`, and the zsh prompt theme in `my-dots/home/oh-my-zsh-custom/themes/`.

## License

GPL-3.0, see [LICENSE.md](LICENSE.md).
