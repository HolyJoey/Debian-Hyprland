#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# Game Mode. Turning off all animations

notif="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/images/ja.png"
SCRIPTSDIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
# shellcheck source=/dev/null
. "$SCRIPTSDIR/WallpaperCmd.sh"

# Detect active Hyprland config mode (Lua entrypoint vs legacy .conf includes)
config_home="${XDG_CONFIG_HOME:-${XDG_CONFIG_HOME:-$HOME/.config}}"
hypr_dir="$config_home/hypr"
lua_entry="$hypr_dir/hyprland.lua"
legacy_lua_entry="$config_home/hyprland.lua"

if [[ -f "$lua_entry" || -f "$legacy_lua_entry" ]]; then
    hypr_config_mode="lua"
else
    hypr_config_mode="conf"
fi

# Check if animations are currently enabled
HYPRGAMEMODE=$(hyprctl getoption animations:enabled -j | jq -r '.bool' 2>/dev/null)
if [[ "$HYPRGAMEMODE" == "null" || -z "$HYPRGAMEMODE" ]]; then
    HYPRGAMEMODE=$(hyprctl getoption animations:enabled | awk 'NR==1{print $2}')
fi

if [ "$HYPRGAMEMODE" = "true" ] || [ "$HYPRGAMEMODE" = "1" ] ; then
    # ENABLE Game Mode (Disable animations/decorations)
    if [[ "$hypr_config_mode" == "lua" ]]; then
        hyprctl eval "hl.config({ 
            animations = { enabled = false },
            decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 },
            general = { gaps_in = 0, gaps_out = 0, border_size = 1 }
        })"
        hyprctl eval "hl.window_rule({ name = 'gamemode-opacity', match = { class = '.*' }, opacity = 1.0 })"
    else
        hyprctl --batch "\
            keyword animations:enabled 0;\
            keyword decoration:shadow:enabled 0;\
            keyword decoration:blur:enabled 0;\
            keyword general:gaps_in 0;\
            keyword general:gaps_out 0;\
            keyword general:border_size 1;\
            keyword decoration:rounding 0;\
            keyword decoration:active_opacity 1;\
            keyword decoration:inactive_opacity 1"
        # Hyprland 0.55 rule syntax (the old "opacity ..., ^(.*)$" form is rejected);
        # override also beats per-app opacity rules. Gone again on reload.
        hyprctl keyword windowrule "match:class .*, opacity 1.0 override 1.0 override"
    fi
    # kitty draws its own see-through background (background_opacity in kitty.conf),
    # which Hyprland can't touch: kitty.conf includes gamemode.conf last.
    echo "background_opacity 1.0" > "$config_home/kitty/gamemode.conf"
    pkill -USR1 -x kitty 2>/dev/null || true
    
    "$WWW_CMD" kill 
    notify-send -e -u low -i "$notif" " Gamemode:" " enabled"
    sleep 0.1
    exit
else
    # DISABLE Game Mode: reload re-reads the real config, so gaps/borders/blur/
    # opacity come back as configured (no copies of them here to go stale) and
    # the game mode window rule is dropped. Side effect: anything toggled by hand
    # this session (e.g. SUPER+CTRL+O opacity) is reset too.
    hyprctl reload >/dev/null
    : > "$config_home/kitty/gamemode.conf"
    pkill -USR1 -x kitty 2>/dev/null || true

    # Restore wallpaper using the official daemon script
    if [[ -x "${SCRIPTSDIR}/WallpaperDaemon.sh" ]]; then
        "${SCRIPTSDIR}/WallpaperDaemon.sh" &
    fi
    
    sleep 0.1
    ${SCRIPTSDIR}/WallustSwww.sh
    sleep 0.5
    
    # Refresh UI components
    if [[ -x "${SCRIPTSDIR}/Refresh.sh" ]]; then
        "${SCRIPTSDIR}/Refresh.sh"
    fi

    notify-send -e -u normal -i "$notif" " Gamemode:" " disabled"
    exit
fi
