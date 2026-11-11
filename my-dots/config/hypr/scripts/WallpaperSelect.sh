#!/usr/bin/env bash
# ==================================================
#  KoolDots (2026)
#  Project URL: https://github.com/LinuxBeginnings
#  License: GNU GPLv3
#  SPDX-License-Identifier: GPL-3.0-or-later
# ==================================================
# This script for selecting wallpapers (SUPER W)

# WALLPAPERS PATH
terminal=kitty
PICTURES_DIR="$(xdg-user-dir PICTURES 2>/dev/null || echo "$HOME/Pictures")"
wallDIR="$PICTURES_DIR/wallpapers"
SCRIPTSDIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/scripts"
# shellcheck source=/dev/null
. "$SCRIPTSDIR/WallpaperCmd.sh"
wallpaper_current="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper_effects/.wallpaper_current"
wallpaper_link="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/.current_wallpaper"
wallpaper_base="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper_effects/.wallpaper_base"

# Directory for swaync
iDIR="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/images"
iDIRi="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/icons"

# swww/awww transition config
FPS=60
TYPE="any"
DURATION=2
BEZIER=".43,1.19,1,.4"
if [[ "$WWW_CMD" == "swww" || "$WWW_CMD" == "awww" ]]; then
  SWWW_PARAMS=(--transition-fps "$FPS" --transition-type "$TYPE" --transition-duration "$DURATION" --transition-bezier "$BEZIER")
else
  SWWW_PARAMS=()
fi


# Check if package bc exists
if ! command -v bc &>/dev/null; then
  notify-send -i "$iDIR/error.png" "bc missing" "Install package bc first"
  exit 1
fi

# Variables
rofi_theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config-wallpaper.rasi"
focused_monitor=$(hyprctl monitors -j | jq -r '.[] | select(.focused) | .name')

per_monitor_wallpaper_current="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper_effects/.wallpaper_current_${focused_monitor}"
per_monitor_wallpaper_link="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/.current_wallpaper_${focused_monitor}"
per_monitor_wallpaper_base="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/wallpaper_effects/.wallpaper_base_${focused_monitor}"

# Ensure focused_monitor is detected
if [[ -z "$focused_monitor" ]]; then
  notify-send -i "$iDIR/error.png" "E-R-R-O-R" "Could not detect focused monitor"
  exit 1
fi

# Monitor details
scale_factor=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .scale')
monitor_height=$(hyprctl monitors -j | jq -r --arg mon "$focused_monitor" '.[] | select(.name == $mon) | .height')

icon_size=$(echo "scale=1; ($monitor_height * 3) / ($scale_factor * 150)" | bc)
adjusted_icon_size=$(echo "$icon_size" | awk '{if ($1 < 15) $1 = 20; if ($1 > 25) $1 = 25; print $1}')
rofi_override="element-icon{size:${adjusted_icon_size}%;}"

# Kill existing wallpaper daemons for video on the focused monitor only
kill_wallpaper_for_video() {
  pkill -f "mpvpaper.*$focused_monitor" 2>/dev/null
}

# Kill existing wallpaper daemons for image on the focused monitor only
kill_wallpaper_for_image() {
  pkill -f "mpvpaper.*$focused_monitor" 2>/dev/null
}

# Retrieve wallpapers (both images & videos)
mapfile -d '' PICS < <(find -L "${wallDIR}" -type f \( \
  -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o \
  -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.webp" -o \
  -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.mov" -o -iname "*.webm" \) -print0)

RANDOM_PIC="${PICS[$((RANDOM % ${#PICS[@]}))]}"
RANDOM_PIC_NAME="$(basename "$RANDOM_PIC")"

# Everything after "image: ", not the last word: names with spaces were cut
# to their last word ("Concept-Japanese house.png" -> "house.png")
CURRENT_MON_PIC_PATH=$("$WWW_CMD" query 2>/dev/null | grep -E "(^|[[:space:]:])${focused_monitor}:" | sed -n 's/.*image: //p' | head -n 1)
if [[ -z "$CURRENT_MON_PIC_PATH" ]]; then
  if [[ -L "$wallpaper_link" ]]; then
    CURRENT_MON_PIC_PATH="$(readlink -f "$wallpaper_link")"
  elif [[ -f "$wallpaper_link" ]]; then
    CURRENT_MON_PIC_PATH="$wallpaper_link"
  elif [[ -f "$wallpaper_current" ]]; then
    CURRENT_MON_PIC_PATH="$wallpaper_current"
  fi
fi
CURRENT_MON_PIC_NAME=$(basename "$CURRENT_MON_PIC_PATH")

# ---- "Previous" entry (HolyJoey) ----------------------------------------
# The last wallpaper this monitor showed before the current one, from the
# history WallustSwww.sh keeps. Skipped if that file has since been removed.
PREV_PIC_PATH=""
history_file="$HOME/.cache/wallpaper_select/history_${focused_monitor}"
if [[ -f "$history_file" ]]; then
  cur_real=$(readlink -f "$CURRENT_MON_PIC_PATH" 2>/dev/null)
  while IFS= read -r h; do
    if [[ -f "$h" && "$(readlink -f "$h")" != "$cur_real" ]]; then
      PREV_PIC_PATH="$h"
      break
    fi
  done < <(tac "$history_file")
fi
PREV_PIC_NAME=$(basename "$PREV_PIC_PATH")

# Rofi command
rofi_command="rofi -i -show -dmenu -config $rofi_theme -theme-str $rofi_override"

# ---- "Add Wallpaper" tile (HolyJoey) -------------------------------------
# First entry of the grid. Picking it opens a file dialog; the chosen images
# are copied into $wallDIR and the (last) one is applied as the wallpaper.
ADD_LABEL="Add Wallpaper"
add_tile="$HOME/.cache/wallpaper_select/add_wallpaper.png"
rofi_colors="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/wallust/colors-rofi.rasi"

# Draw the tile in the menu's own wallust colours; redraw when they change.
make_add_tile() {
  [[ -f "$add_tile" && "$add_tile" -nt "$rofi_colors" ]] && return 0
  local bg accent
  bg=$(sed -n 's/^background-color: *\(#[0-9A-Fa-f]\{6\}\).*/\1/p' "$rofi_colors" 2>/dev/null | head -1)
  accent=$(sed -n 's/^border-color: *\(#[0-9A-Fa-f]\{6\}\).*/\1/p' "$rofi_colors" 2>/dev/null | head -1)
  bg="${bg:-#1e1e2e}"
  accent="${accent:-#cdd6f4}"
  mkdir -p "$(dirname "$add_tile")"
  magick -size 1600x900 "xc:$bg" \
    -fill none -stroke "$accent" -strokewidth 12 \
    -draw "stroke-dasharray 70 45 roundrectangle 50,50 1550,850 70,70" \
    -stroke none -fill "$accent" \
    -draw "roundrectangle 765,290 835,610 22,22" \
    -draw "roundrectangle 640,415 960,485 22,22" \
    "$add_tile" 2>/dev/null
}

# ---- Remove a wallpaper (HolyJoey) ---------------------------------------
# Right-click a tile (hover-select makes it the selected one) or press
# Shift+Delete: rofi exits with code 10 (kb-custom-1). Right-click normally
# just selects, and Shift+Delete deletes history entries; both are rebound
# for this menu only.
remove_args=(
  -kb-delete-entry ""
  -me-select-entry ""
  -kb-custom-1 "Shift+Delete,MouseSecondary"
  -theme-str 'entry { placeholder: " 🎞️ Search / Choose Wallpaper   ·   Right-click or Shift+Del: remove"; }'
)
confirm_theme="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/config-wallpaper-effect.rasi"

remove_wallpaper() {
  local path="$1" name ans
  name=$(basename "$path")
  # Same look as the effects menu: the wallpaper as the banner, two choices
  ans=$(printf '%s\n' "Move to trash" "Cancel" |
    rofi -i -dmenu -no-custom -config "$confirm_theme" -theme-str "
      window { width: 30%; height: 44%; }
      inputbar { background-image: url(\"${path//\"/}\", width); padding: 190px 12px 12px 12px; }
      listview { columns: 1; lines: 2; scrollbar: false; fixed-height: true; }
      entry { placeholder: \" 🗑️ Remove ${name//\"/} ?\"; }")
  if [[ "$ans" == "Move to trash" ]]; then
    if gio trash -- "$path" 2>/dev/null; then
      notify-send -i user-trash-full "Wallpaper removed" "$name moved to the trash"
    else
      notify-send -i "$iDIR/error.png" "Could not remove wallpaper" "$name"
    fi
  fi
  # Back to the picker either way
  exec "$0"
}

add_wallpaper() {
  local picked f name base ext dest n last=""
  local added=0
  picked=$(zenity --file-selection --multiple --separator=$'\n' \
    --title="Add Wallpaper" --filename="$HOME/" \
    --file-filter="Images and videos | *.jpg *.jpeg *.png *.webp *.gif *.bmp *.JPG *.JPEG *.PNG *.WEBP *.GIF *.mp4 *.mkv *.mov *.webm" \
    --file-filter="All files | *" 2>/dev/null) || exit 0

  mkdir -p "$wallDIR"
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    name=$(basename "$f")
    dest="$wallDIR/$name"
    if [[ -e "$dest" ]]; then
      # Same file already there: nothing to copy, just select it
      if cmp -s "$f" "$dest"; then last="$name"; continue; fi
      # Different file with the same name: add a number
      base="${name%.*}"; ext="${name##*.}"; n=1
      while [[ -e "$wallDIR/$base-$n.$ext" ]]; do n=$((n + 1)); done
      name="$base-$n.$ext"; dest="$wallDIR/$name"
    fi
    cp -- "$f" "$dest" && added=$((added + 1)) && last="$name"
  done <<<"$picked"

  if [[ "$added" -gt 0 ]]; then
    notify-send -i "$wallDIR/$last" "Wallpaper added" \
      "$([[ $added -eq 1 ]] && echo "$last" || echo "$added wallpapers") added to ${wallDIR/#"$HOME"/\~}"
  fi
  # Nothing usable picked: leave the wallpaper as it is
  [[ -n "$last" ]] || exit 0
  # main() applies it like any other pick
  selected_file="$wallDIR/$last"
}

# Sorting Wallpapers
menu() {
  IFS=$'\n' sorted_options=($(sort <<<"${PICS[*]}"))

  make_add_tile
  printf "%s\x00icon\x1f%s\n" "$ADD_LABEL" "$add_tile"
  printf "%s\x00icon\x1f%s\n" "Random: $RANDOM_PIC_NAME" "$RANDOM_PIC"
  if [[ -n "$PREV_PIC_PATH" ]]; then
    printf "%s\x00icon\x1f%s\n" "Previous: $PREV_PIC_NAME" "$PREV_PIC_PATH"
  fi
  if [[ -n "$CURRENT_MON_PIC_PATH" ]]; then
    printf "%s\x00icon\x1f%s\n" "Current: $CURRENT_MON_PIC_NAME" "$CURRENT_MON_PIC_PATH"
  fi

  for pic_path in "${sorted_options[@]}"; do
    pic_name=$(basename "$pic_path")
    if [[ "$pic_name" =~ \.gif$ ]]; then
      cache_gif_image="$HOME/.cache/gif_preview/${pic_name}.png"
      if [[ ! -f "$cache_gif_image" ]]; then
        mkdir -p "$HOME/.cache/gif_preview"
        magick "$pic_path[0]" -resize 1920x1080 "$cache_gif_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_gif_image"
    elif [[ "$pic_name" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
      cache_preview_image="$HOME/.cache/video_preview/${pic_name}.png"
      if [[ ! -f "$cache_preview_image" ]]; then
        mkdir -p "$HOME/.cache/video_preview"
        ffmpeg -v error -y -i "$pic_path" -ss 00:00:01.000 -vframes 1 "$cache_preview_image"
      fi
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$cache_preview_image"
    else
      printf "%s\x00icon\x1f%s\n" "$pic_name" "$pic_path"
    fi
  done
}


modify_startup_config() {
  local selected_file="$1"
  local startup_config="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/UserConfigs/Startup_Apps.conf"

  # Check if it's a live wallpaper (video)
  if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm)$ ]]; then
    # For video wallpapers:
    sed -i '/^\s*exec-once\s*=\s*\$scriptsDir\/WallpaperDaemon\.sh\s*$/s/^/\#/' "$startup_config"
    sed -i '/^\s*exec-once\s*=\s*swww-daemon\s*--format\s*xrgb\s*$/s/^/\#/' "$startup_config"
    sed -i '/^\s*#\s*exec-once\s*=\s*mpvpaper\s*.*$/s/^#\s*//;' "$startup_config"

    # Update the livewallpaper variable with the selected video path (using $HOME)
    selected_file="${selected_file/#$HOME/\$HOME}" # Replace /home/user with $HOME
    sed -i "s|^\$livewallpaper=.*|\$livewallpaper=\"$selected_file\"|" "$startup_config"

    echo "Configured for live wallpaper (video)."
  else
    # For image wallpapers:
    sed -i '/^\s*#\s*exec-once\s*=\s*\$scriptsDir\/WallpaperDaemon\.sh\s*$/s/^\s*#\s*//;' "$startup_config"
    sed -i '/^\s*#\s*exec-once\s*=\s*swww-daemon\s*--format\s*xrgb\s*$/s/^\s*#\s*//;' "$startup_config"

    sed -i '/^\s*exec-once\s*=\s*mpvpaper\s*.*$/s/^/\#/' "$startup_config"

    echo "Configured for static wallpaper (image)."
  fi
}

# Apply Image Wallpaper
apply_image_wallpaper() {
  local image_path="$1"

  kill_wallpaper_for_image

  if ! pgrep -x "$WWW_DAEMON" >/dev/null; then
    echo "Starting $WWW_DAEMON..."
    "$WWW_DAEMON" "${WWW_DAEMON_ARGS[@]}" &
  fi
  # Wait for daemon to be ready before applying
  for _ in {1..20}; do
    "$WWW_CMD" query >/dev/null 2>&1 && break
    sleep 0.1
  done
  local resize_mode
  resize_mode="$(wallpaper_resize_mode "$image_path" "$focused_monitor")"
  "$WWW_CMD" img -o "$focused_monitor" --resize "$resize_mode" "$image_path" "${SWWW_PARAMS[@]}" || {
    sleep 0.2
    "$WWW_CMD" img -o "$focused_monitor" --resize "$resize_mode" "$image_path" "${SWWW_PARAMS[@]}"
  }
  "$WWW_CMD" img -o "$focused_monitor" --resize "$resize_mode" "$image_path" "${SWWW_PARAMS[@]}"

  # Persist per-monitor wallpaper selection
  mkdir -p "$(dirname "$per_monitor_wallpaper_current")" "$(dirname "$per_monitor_wallpaper_link")"
  ln -sf "$image_path" "$per_monitor_wallpaper_link" || true
  cp -f "$image_path" "$per_monitor_wallpaper_current" || true
  mkdir -p "$(dirname "$per_monitor_wallpaper_base")"
  cp -f "$image_path" "$per_monitor_wallpaper_base" || true
  cp -f "$image_path" "$wallpaper_base" || true

  # Run additional scripts (pass the image path to avoid cache race conditions)
  if ! "$SCRIPTSDIR/WallustSwww.sh" "$image_path"; then
    notify-send -i "$iDIR/error.png" "Wallust failed" "Wallpaper theme not refreshed"
    return 1
  fi
  sleep 0.5
  "$SCRIPTSDIR/Refresh.sh"
  sleep 0.3

}

apply_video_wallpaper() {
  local video_path="$1"

  # Check if mpvpaper is installed
  if ! command -v mpvpaper &>/dev/null; then
    notify-send -i "$iDIR/error.png" "E-R-R-O-R" "mpvpaper not found"
    return 1
  fi
  kill_wallpaper_for_video

  # Apply video wallpaper only to the focused monitor
  mpvpaper "$focused_monitor" -o "load-scripts=no no-audio --loop" "$video_path" &
}

# Main function
# Map the picked menu entry to a file: sets selected_file
resolve_choice() {
  if [[ "$raw_choice" == Random:\ * ]]; then
    selected_file="$RANDOM_PIC"
  elif [[ "$raw_choice" == Previous:\ * && -n "$PREV_PIC_PATH" ]]; then
    selected_file="$PREV_PIC_PATH"
  elif [[ "$raw_choice" == Current:\ * && -n "$CURRENT_MON_PIC_PATH" ]]; then
    selected_file="$CURRENT_MON_PIC_PATH"
  elif [[ -f "$choice" ]]; then
    selected_file="$choice"
  else
    # Handle random selection by name when needed
    if [[ "$choice" == "$RANDOM_PIC_NAME" ]]; then
      choice=$(basename "$RANDOM_PIC")
    fi
    choice_basename=$(basename "$choice" | sed 's/\(.*\)\.[^.]*$/\1/')

    # Exact file name first, so foo.jpg never resolves to foo.png (this also
    # decides which file a remove targets); then the original name-only match
    selected_file=$(find "$wallDIR" -name "$choice" -print -quit 2>/dev/null)
    [[ -n "$selected_file" ]] ||
      selected_file=$(find "$wallDIR" -iname "$choice_basename.*" -print -quit)
  fi
}

main() {
  local rc
  choice=$(menu | $rofi_command "${remove_args[@]}")
  rc=$?
  choice=$(echo "$choice" | xargs)
  RANDOM_PIC_NAME=$(echo "$RANDOM_PIC_NAME" | xargs)
  raw_choice="$choice"
  choice="${choice#Random: }"
  choice="${choice#Previous: }"
  choice="${choice#Current: }"

  if [[ -z "$choice" ]]; then
    echo "No choice selected. Exiting."
    exit 0
  fi

  # Right-click / Shift+Delete on a tile: offer to remove that wallpaper
  if [[ "$rc" -eq 10 ]]; then
    [[ "$raw_choice" == "$ADD_LABEL" ]] && exec "$0"
    resolve_choice
    [[ -n "$selected_file" && -f "$selected_file" ]] || exec "$0"
    remove_wallpaper "$selected_file"
  fi

  if [[ "$raw_choice" == "$ADD_LABEL" ]]; then
    add_wallpaper   # sets selected_file, or exits if nothing was picked
  else
    resolve_choice
  fi

  if [[ -z "$selected_file" ]]; then
    echo "File not found. Selected choice: $choice"
    exit 1
  fi

  # Modify the Startup_Apps.conf file based on wallpaper type
  modify_startup_config "$selected_file"

  # **CHECK FIRST** if it's a video or an image **before calling any function**
  if [[ "$selected_file" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
    apply_video_wallpaper "$selected_file"
  else
    apply_image_wallpaper "$selected_file"
  fi
}

# Check if rofi is already running
if pidof rofi >/dev/null; then
  pkill rofi
fi

main