#!/usr/bin/env bash
# Toggle whether Waybar's colours follow the wallpaper (wallust).
#
#   off: wallust stops writing waybar/wallust/colors-waybar.css, and the saved
#        fixed palette (colors-waybar-fixed.css) is put back. Wallpaper changes
#        and the theme switcher then leave Waybar alone.
#   on:  wallust writes Waybar's colours again; they are regenerated from the
#        current wallpaper straight away.
#
# Usage: ToggleWaybarWallust.sh [on|off|toggle|status]   (default: toggle)

set -u

cfg="${XDG_CONFIG_HOME:-$HOME/.config}"
scriptsDir="$cfg/hypr/scripts"
colors="$cfg/waybar/wallust/colors-waybar.css"
fixed="$cfg/waybar/wallust/colors-waybar-fixed.css"
iDIR="$cfg/swaync/images"
# wallust 3 reads wallust.toml, wallust 4 wallust-v4.toml: keep both in step
tomls=("$cfg/wallust/wallust.toml" "$cfg/wallust/wallust-v4.toml")

status() {
    if grep -qE '^\s*waybar\.template' "${tomls[0]}" 2>/dev/null; then
        echo on
    else
        echo off
    fi
}

set_off() {
    # Keep the current palette as the fixed one the first time
    [[ -f "$fixed" ]] || cp "$colors" "$fixed"
    for t in "${tomls[@]}"; do
        [[ -f "$t" ]] && sed -i -E 's/^(\s*)(waybar\.(template|target))/\1#\2/' "$t"
    done
    cp "$fixed" "$colors"
}

set_on() {
    for t in "${tomls[@]}"; do
        [[ -f "$t" ]] && sed -i -E 's/^(\s*)#(waybar\.(template|target))/\1\2/' "$t"
    done
    # Regenerate from the current wallpaper so the change shows right away
    local wp="$cfg/hypr/wallpaper_effects/.wallpaper_current"
    if [[ -f "$wp" ]] && command -v wallust >/dev/null 2>&1; then
        wallust_args=()
        [[ -f "$scriptsDir/WallustConfig.sh" ]] && . "$scriptsDir/WallustConfig.sh"
        wallust "${wallust_args[@]}" run -s "$wp" >/dev/null 2>&1
    fi
}

reload_waybar() {
    pkill -SIGUSR2 -x waybar 2>/dev/null || true
}

case "${1:-toggle}" in
status) status; exit 0 ;;
on) set_on ;;
off) set_off ;;
toggle) [[ "$(status)" == on ]] && set_off || set_on ;;
*) echo "usage: ${0##*/} [on|off|toggle|status]" >&2; exit 2 ;;
esac

reload_waybar
if [[ "$(status)" == on ]]; then
    notify-send -i "$iDIR/ja.png" "Waybar colours" "Now follow the wallpaper"
else
    notify-send -i "$iDIR/ja.png" "Waybar colours" "Fixed (no longer follow the wallpaper)"
fi
