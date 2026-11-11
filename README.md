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
./apply-my-dots.sh          # asks once before overwriting
./apply-my-dots.sh --yes    # no questions
./apply-my-dots.sh --no-satty
```

Every folder it replaces is backed up to `~/.config/my-dots-backup-<date>/` first, and
`~/.zshrc` to `~/.zshrc.my-dots-backup-<date>`.

## What gets installed

- Hyprland, built from source (versions are in `hypr-tags.env`)
- SDDM with its theme, GTK themes, Bluetooth, Thunar, AGS, Quickshell and Yazi
- zsh with oh-my-zsh
- My configs from [`my-dots/`](my-dots), copied into `~/.config`

## The setup

- **Waybar**: TOP-Everforest layout with the Dark-Wallust-Obsidian-Edge style, 24h clock,
  per-monitor workspaces, and a tray that slides out on hover
- **WiFi**: click the network module for a rofi network picker
  (`hypr/scripts/rofi-wifi-menu.sh`)
- **Workspaces**: every monitor owns 5 workspaces, re-applied on hotplug
  (`hypr/scripts/MonitorWorkspaces.sh`)
- **Screenshots**: SUPER+SHIFT+S opens [satty](https://github.com/Satty-org/Satty). It is
  built from source, because the prebuilt needs a newer glibc than Debian 13
- **Lock screen**: hyprlock shows the dedsec wallpaper. hypridle runs only from Hyprland's
  exec-once, and `hypridle.service` is masked, because a second daemon breaks locking
- **Terminal**: kitty with the Brogrammer theme, and fastfetch without a logo. It picks the
  biggest layout that fits the window (full, compact or mini) by width and height, and skips
  itself in tiny windows. The layouts come from `fastfetch/gen_config.py`
- **Themes**: Flat-Remix-GTK-Blue-Dark, Flat-Remix-Blue-Dark icons, Bibata-Modern-Ice cursor
- **GPU**: `lspci` decides the video env vars. Intel gets `LIBVA_DRIVER_NAME=iHD`, and NVIDIA
  gets the NVIDIA block
- **Tray**: no nm-applet or blueman-applet icons; waybar handles network
- Flatpak apps show up in rofi

## Wallpapers

The installer puts my whole wallpaper folder (166 images) in `~/Pictures/wallpapers`. The 8
that are not in KooL's [Wallpaper-Bank](https://github.com/LinuxBeginnings/Wallpaper-Bank)
ship in [`my-dots/wallpapers/`](my-dots/wallpapers). The other 158 (~800MB) are downloaded
from the bank, pinned to the exact version I have. Skip that download with
`./apply-my-dots.sh --no-wallpapers`. To add your own wallpapers, drop images in the folder.

| Keys | What it does |
| --- | --- |
| SUPER + W | Wallpaper picker: a rofi grid with previews, plus a "Random" entry |
| CTRL + ALT + W | Random wallpaper |
| SUPER + SHIFT + W | Effects on the current wallpaper (blur, sepia, oil paint, vignette...) |
| SUPER + SHIFT + E → Set Hyprlock Wallpaper | Change the lock screen wallpaper |

When you change the wallpaper:

- **Only the focused monitor changes.** Each monitor keeps its own wallpaper, and it comes
  back after a reboot.
- **The colours follow it.** [wallust](https://codeberg.org/explosion-mental/wallust) builds
  a colour scheme from the image and applies it to Hyprland's window borders, Waybar, rofi,
  cava and Ghostty.
- **Waybar, swaync and rofi restart** to load the new colours, so the bar
  flickers for a moment.
- **Some things keep their own look:** kitty stays on the Brogrammer theme, fastfetch stays
  red/white, and the GTK theme, icons and cursor don't change.
- **The lock screen does not follow.** It keeps the dedsec wallpaper until you pick another
  one through SUPER + SHIFT + E.

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
as `@HOME@`. `apply-my-dots.sh` fills in the real path on install.

## License

GPL-3.0, see [LICENSE.md](LICENSE.md).
