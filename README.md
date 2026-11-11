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
