#!/usr/bin/env bash
# Lock screen clock (hyprlock.conf / hyprlock-2k.conf) in the same 12h/24h
# format as Waybar's clock. Follows "Toggle Waybar Clock (12H/24H)" in the
# quick-settings menu (ToggleWaybarTime.sh), which switches the clock formats
# in waybar/Modules: any active "%I:%M %p" format there means 12h.

modules="${XDG_CONFIG_HOME:-$HOME/.config}/waybar/Modules"

if grep -qE '^[[:space:]]*"format":[[:space:]]*"[^"]*\{:%I:%M %p' "$modules" 2>/dev/null; then
    date +"%I:%M %p"
else
    date +"%H:%M"
fi
