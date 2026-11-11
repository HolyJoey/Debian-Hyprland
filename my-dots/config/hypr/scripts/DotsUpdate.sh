#!/usr/bin/env bash
# Waybar button: is this machine's HolyJoey/Debian-Hyprland clone behind GitHub?
# (Replaces KooL's KooLsDotsUpdate.sh, which checked LinuxBeginnings/Hyprland-Dots.)
# apply-my-dots.sh records where the clone is in ~/.local/state/holyjoey-dots/repo.
iDIR="${XDG_CONFIG_HOME:-$HOME/.config}/swaync/images"
title="HolyJoey dots"
state="${XDG_STATE_HOME:-$HOME/.local/state}/holyjoey-dots/repo"

repo=""
for d in "$(cat "$state" 2>/dev/null)" "$HOME/Debian-Hyprland-HolyJoey" "$HOME/Debian-Hyprland"; do
  [ -n "$d" ] && git -C "$d" rev-parse --git-dir >/dev/null 2>&1 &&
    git -C "$d" remote get-url origin 2>/dev/null | grep -qi 'HolyJoey/Debian-Hyprland' &&
    { repo="$d"; break; }
done
if [ -z "$repo" ]; then
  notify-send -i "$iDIR/error.png" "$title" "Can't find the Debian-Hyprland clone."
  exit 1
fi

if ! git -C "$repo" fetch -q 2>/dev/null; then
  notify-send -i "$iDIR/error.png" "$title" "Can't reach GitHub."
  exit 1
fi
behind=$(git -C "$repo" rev-list --count HEAD..@{u} 2>/dev/null || echo 0)
ahead=$(git -C "$repo" rev-list --count @{u}..HEAD 2>/dev/null || echo 0)
here=$(git -C "$repo" log -1 --format='%h, %cs')

if [ "$behind" -eq 0 ]; then
  extra=""; [ "$ahead" -gt 0 ] && extra=" ($ahead local commit(s) not pushed)"
  notify-send -i "$iDIR/note.png" "$title" "Up to date: $here$extra"
  exit 0
fi

latest=$(git -C "$repo" log -1 --format='%s' @{u})
response=$(notify-send -t 15000 -A update=Update -A no=Later -i "$iDIR/note.png" "$title" \
  "$behind update(s) available.\nLatest: $latest")
[ "$response" = update ] || exit 0

# Pull, then re-apply. apply-my-dots.sh lists what it overwrites, asks first and
# backs every folder up; wallpapers and satty are already in place, so skip them.
kitty --title "Dots update" -e bash -c "
  cd \"$repo\" && git log --oneline HEAD..@{u} && echo &&
  git pull --ff-only && ./apply-my-dots.sh --no-satty --no-wallpapers
  echo; read -rp 'Done. Press Enter to close.'"
