#!/usr/bin/env bash
# Keep the SDDM login screen (simple_sddm_2) in step with the desktop wallpaper.
# Called in the background by WallustSwww.sh after wallust has written its
# templates, so every wallpaper change (picker, random, auto-change, boot)
# updates it. Needs passwordless sudo; without it this quietly does nothing
# (the manual "SDDM wallpaper" quick-settings entry still works).
#
# Colours come from the wallust palette, but are checked against the part of
# the wallpaper the login form sits on: text gets at least 4.5:1 contrast, and
# the background is dimmed only as much as needed to get there.
#
# Usage: SddmAutoSync.sh /path/to/wallpaper

set -uo pipefail

wallpaper="${1:-}"
[[ -n "$wallpaper" && -f "$wallpaper" ]] || exit 0

theme_dir="/usr/share/sddm/themes/simple_sddm_2"
theme_conf="$theme_dir/theme.conf"
colors="${XDG_CONFIG_HOME:-$HOME/.config}/rofi/wallust/colors-rofi.rasi"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/sddm_autosync"
log="$cache/log"
mkdir -p "$cache"

[[ -f "$theme_conf" && -f "$colors" ]] || exit 0
sudo -n true 2>/dev/null || { echo "$(date) no passwordless sudo, skipped" >>"$log"; exit 0; }

# Only one run at a time; a newer wallpaper change wins over an older one.
exec 9>"$cache/lock"
flock -w 30 9 || exit 0

# Video wallpapers: SDDM gets a still frame.
bg="$wallpaper"
if [[ "$wallpaper" =~ \.(mp4|mkv|mov|webm|MP4|MKV|MOV|WEBM)$ ]]; then
    command -v ffmpeg >/dev/null || exit 0
    bg="$cache/frame.png"
    ffmpeg -v error -y -i "$wallpaper" -ss 00:00:01.000 -vframes 1 "$bg" || exit 0
fi

# Skip when nothing changed (same picture, same palette).
stamp="$(sha1sum "$bg" "$colors" | sha1sum | cut -d' ' -f1)"
[[ "$(cat "$cache/stamp" 2>/dev/null)" == "$stamp" ]] && exit 0

form_pos="$(sed -n 's/^FormPosition="\(.*\)"/\1/p' "$theme_conf")"

settings="$(python3 -I - "$bg" "$colors" "${form_pos:-left}" <<'PY' 2>>"$log"
import re, sys
from PIL import Image

img_path, colors_path, form_pos = sys.argv[1:4]
pal = dict(re.findall(r'^\s*([\w-]+):\s*(#[0-9A-Fa-f]{6})', open(colors_path).read(), re.M))

def rgb(h): return tuple(int(h[i:i + 2], 16) for i in (1, 3, 5))
def hexc(c): return '#%02X%02X%02X' % tuple(max(0, min(255, round(v))) for v in c)
def lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = c
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
def mix(a, b, t): return tuple(x * (1 - t) + y * t for x, y in zip(a, b))
def toward(c, target, other, ratio):
    """Move c toward target (white/black) until it reaches ratio against other."""
    for i in range(41):
        m = mix(c, target, i / 40)
        if contrast(m, other) >= ratio:
            return m
    return target

white, black = (255, 255, 255), (0, 0, 0)
P = lambda k, d: rgb(pal.get(k, d))

# Dark base: the palette's background, forced dark enough to sit text on.
base = P('background-color', '#1E1E2E')
while lum(base) > 0.04:
    base = mix(base, black, 0.15)

# Wallpaper behind the form. Use a bright-ish percentile, not the mean, so a
# few bright patches behind the text still count.
im = Image.open(img_path).convert('RGB')
im.thumbnail((480, 270))
w, h = im.size
x0, x1 = {'left': (0, 0.45), 'right': (0.55, 1), 'center': (0.25, 0.75)}.get(form_pos, (0, 0.45))
region = im.crop((int(w * x0), 0, int(w * x1), h))
px = sorted(region.getdata(), key=lum)
behind = px[int(len(px) * 0.80)]

# Accent for big text (clock, date, icons): the palette's light accent,
# lightened if needed. Body text: palette foreground.
accent = toward(P('color13', '#CBA6F7'), white, base, 7.0)
text = toward(P('foreground', '#E0E0E0'), white, base, 7.0)
subtle = toward(P('color7', '#BAC2DE'), white, base, 4.5)

# Dim the wallpaper by the minimum that gives the accent and text 4.5:1 over
# the form area (the partial blur adds its own 0.3 tint of `base` on top).
dim = 0.0
for i in range(0, 86):
    d = i / 100
    seen = mix(mix(behind, base, d), base, 0.3)
    if min(contrast(accent, seen), contrast(text, seen)) >= 4.5:
        dim = d
        break
else:
    dim = 0.85
dim = round(max(dim, 0.15), 2)  # a light dim always helps

# Button / selection: a saturated accent with text that reads on it.
btn = P('color12', '#89B4FA')
btn_text = black if contrast(btn, black) >= contrast(btn, white) else white
if contrast(btn, btn_text) < 4.5:
    btn = toward(btn, black if btn_text == white else white, btn_text, 4.5)
sel = toward(P('color4', '#89B4FA'), black, text, 4.5)  # under dropdown text
warn = toward(P('color9', '#F38BA8'), white, base, 4.5)
border = P('color12', '#89B4FA')

out = {
    'HeaderTextColor': accent, 'DateTextColor': accent, 'TimeTextColor': accent,
    'FormBackgroundColor': base, 'BackgroundColor': base, 'DimBackgroundColor': base,
    'LoginFieldBackgroundColor': base, 'PasswordFieldBackgroundColor': base,
    'LoginFieldTextColor': text, 'PasswordFieldTextColor': text,
    'UserIconColor': accent, 'PasswordIconColor': accent,
    'PlaceholderTextColor': subtle, 'WarningColor': warn,
    'LoginButtonTextColor': btn_text, 'LoginButtonBackgroundColor': btn,
    'SystemButtonsIconsColor': accent, 'SessionButtonTextColor': accent,
    'VirtualKeyboardButtonTextColor': accent,
    'DropdownTextColor': text, 'DropdownSelectedBackgroundColor': sel,
    'DropdownBackgroundColor': base,
    'HighlightTextColor': btn_text, 'HighlightBackgroundColor': btn,
    'HighlightBorderColor': border,
    'HoverUserIconColor': text, 'HoverPasswordIconColor': text,
    'HoverSystemButtonsIconsColor': text, 'HoverSessionButtonTextColor': text,
    'HoverVirtualKeyboardButtonTextColor': text,
}
for k, v in out.items():
    print(f'{k}={hexc(v)}')
print(f'DimBackground={dim}')
print('HaveFormBackground=true')
print('PartialBlur=true')
PY
)" || exit 0
[[ -n "$settings" ]] || exit 0

# Build the new theme.conf in the cache, then install it in one step.
tmp="$cache/theme.conf"
cp -f "$theme_conf" "$tmp"
while IFS='=' read -r key val; do
    [[ -n "$key" ]] || continue
    sed -i "s|^${key}=\".*\"|${key}=\"${val}\"|" "$tmp"
done <<<"$settings"

sudo -n install -m 644 "$bg" "$theme_dir/Backgrounds/default" &&
    sudo -n install -m 644 "$tmp" "$theme_conf" &&
    printf '%s\n' "$stamp" >"$cache/stamp" &&
    echo "$(date) synced $(basename "$wallpaper")" >>"$log"
