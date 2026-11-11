#!/usr/bin/env python3
"""
Generate the fastfetch configs — red/white eye palette, one aligned box.

The layout is fixed-width, so it needs a window wide enough to hold it. Rather
than let it wrap, .zshrc picks one of these by $COLUMNS; each is a rung the
layout can step down to. Widths are the minimum the file needs.

  config.jsonc            78  eye + box
  config-ascii.jsonc      78  same file, named for .zshrc's non-kitty branch
  config-boxes.jsonc      49  the box alone — the logo is what stops fitting first
  config-logo.jsonc       25  eye PNG alone, for tiles too narrow for a box
  config-logo-ascii.jsonc 30  eye alone

Re-run after editing:  python3 ~/.config/fastfetch/gen_config.py
"""
import hashlib, json, os, re, sys

# ---- skip when nothing changed ------------------------------------
# wallust re-runs on the same wallpaper (login, dark/light toggle, game mode,
# terminal theme pickers) rewrite wallust-palette.json with identical colours,
# which bumps its mtime and used to make .zshrc rebuild everything. The output
# depends only on the palette, the wallpaper image and this script, so hash
# those; same hash -> just touch config-nologo.jsonc (what .zshrc compares
# against) and stop. --force rebuilds regardless.
_KEY_FILE = os.path.expanduser("~/.cache/fastfetch-gen.key")
_STAMP = os.path.expanduser("~/.config/fastfetch/config-nologo.jsonc")


def _inputs_key():
    h = hashlib.sha1()
    for f in (os.path.expanduser("~/.config/fastfetch/wallust-palette.json"),
              os.path.expanduser("~/.config/hypr/wallpaper_effects/.wallpaper_current"),
              os.path.abspath(__file__)):
        try:
            with open(f, "rb") as fh:
                h.update(fh.read())
        except OSError:
            h.update(b"<missing>")
        h.update(b"\0")
    return h.hexdigest()


_KEY = _inputs_key()
if "--force" not in sys.argv and os.path.exists(_STAMP):
    try:
        if open(_KEY_FILE).read().strip() == _KEY:
            os.utime(_STAMP)
            sys.exit(0)
    except OSError:
        pass

E = lambda c: "\x1b[" + c + "m"

# ---- the eye's palette ----
# Sampled straight from the quantizer that drew the art: the logo only ever
# paints these, so the panel beside it is built from the same three and nothing
# else. (This replaced a Catppuccin Mocha scheme -- the art is fixed red/white,
# so a themed panel next to it always read as two unrelated things.)
RED = "38;2;222;0;0"        # the iris/rim red
DRED = "38;2;130;0;0"       # its shaded red — the frame, so it recedes
WHITE = "38;2;235;235;235"  # the sclera; slightly off #fff so it is not harsh

# Nerd Font icons, by codepoint. Written as chr() rather than as literal
# characters on purpose: literal U+E000-U+F8FF chars do not reliably survive
# every editor/pipeline, and a silently dropped glyph misaligns one row only,
# which is maddening to spot. All of these are verified present in
# FantasqueSansM Nerd Font Mono.
I = {                        # glyph name in the font, for reference
    "user":     0xF0004,     # md-account
    "os":       0xF306,      # linux-debian
    "kernel":   0xF17C,      # fa-linux
    "packages": 0xF03D6,     # md-package_variant
    "shell":    0xF018D,     # md-console
    "uptime":   0xF0150,     # md-clock_outline
    "wm":       0xF2D0,      # fa-window_maximize
    "term":     0xF489,      # oct-terminal
    "theme":    0xF03D8,     # md-palette
    "icons":    0xF003B,     # md-apps
    "cursor":   0xF01C0,     # md-cursor_default
    "host":     0xF0322,     # md-laptop
    "cpu":      0xF061A,     # md-chip
    "gpu":      0xF08AE,     # md-expansion_card
    "memory":   0xF035B,     # md-memory
    "disk":     0xF02CA,     # md-harddisk
    "display":  0xF0379,     # md-monitor
    "battery":  0xF0079,     # md-battery
    "wifi":     0xF0928,     # md-wifi_strength_4
    "ip":       0xF0A5F,     # md-ip
}
icon = lambda n: chr(I[n])

BOX_W = 48     # outer width of a section box, in columns
LABEL_W = 7    # value-column alignment ("kernel" is the longest label)

# Values start LEFT + 1(│) + 1(space) + 2(icon) + 2(gap) + LABEL_W columns in and
# must stop before the right rail, so this is the room a value has. Nothing pads
# or truncates for you: a longer value simply paints over the rail and past it.
# check_width.py replays a real run and flags any row that does.
VALUE_W = BOX_W - 6 - LABEL_W                                            # 35

# fastfetch can pad keys but not values, so the right-hand rail cannot be laid
# out by counting characters — value widths vary per machine and per boot.
# Instead every row starts by jumping the cursor to an absolute column, drawing
# │ there, and jumping back to the box's left edge. The two columns depend on
# how many columns the logo reserves, so they stay as placeholders until write()
# knows which config (kitty logo vs ASCII logo) is being emitted.
RAIL = "\x1b[{RIGHT}G│\x1b[{LEFT}G│ "

# The art is the taller of the two columns, so it decides where the box starts:
# see LEAD below. Read here rather than hardcoded, so re-rendering the eye at a
# different size re-centres the panel without anyone remembering to.
ART_SRC = "~/.config/fastfetch/logo-eye-26.txt"
ART_PAD_TOP = 1
ART_ROWS = sum(1 for l in open(os.path.expanduser(ART_SRC)) if l.strip())

mods = []


def box_top(label=None, color=None):
    # No icon here on purpose: box-drawing + ASCII only, so the top border
    # width is exact regardless of how the terminal measures Nerd Font glyphs.
    if label is None:                           # unlabelled: one plain rule
        mods.append({"type": "custom", "format":
                     E(DRED) + "╭" + "─" * (BOX_W - 2) + "╮" + E("0")})
        return
    head_cols = 1 + 2 + len(label) + 1          # ╭ + "─ " + label + " "
    mods.append({"type": "custom", "format":
                 f"{E(DRED)}╭─ {E(color or RED)}{label}{E(DRED)} "
                 + "─" * (BOX_W - head_cols - 1) + "╮" + E("0")})


def box_bottom():
    mods.append({"type": "custom",
                 "format": E(DRED) + "╰" + "─" * (BOX_W - 2) + "╯" + E("0")})


def row(mtype, name, label, **kw):
    """Dim rails, a red icon, then a white label — the eye's three colours."""
    mods.append({"type": mtype, "keyColor": DRED,
                 "key": f"{RAIL}{E(RED)}{icon(name)}  {E(WHITE)}{label.ljust(LABEL_W)}",
                 **kw})


gap = lambda: mods.append("break")

# ══════════════════════════════════════════════════════════════════
# ---- user@host ---------------------------------------------------
# The heading rather than a row: no rails, no icon, no label column, so it
# reads as a name over the box instead of the first entry inside it. Red name,
# then white for "@host" — the eye's palette in one line, the colour break
# falling on the username rather than on the separator.
# Not DRED for the @: DRED is picked to recede as a frame, which is exactly
# wrong for a glyph you have to read.
# Bold is set once up front and never re-sent: the escapes after it only change
# the foreground colour, so the weight carries through to the closing reset.
# The key is " " and not "": an empty key falls back to the module's default
# ("Title"), a blank one is dropped, and the separator is "" globally.
mods.append({"type": "title", "key": " ",
             "format": f"{E('1;' + RED)}{{user-name}}{E(WHITE)}@{{host-name}}{E('0')}"})

# ---- the box -----------------------------------------------------
# One unlabelled box: with six rows a section header is more chrome than
# signal. Ordered bottom-up through the stack — the machine, then the distro
# and kernel on it, then the session, terminal and shell you are typing into.
box_top()
row("host", "host", "host", format="{family}")
# pretty-name already carries the version and codename; arch is dropped because
# the kernel release right below it ends in -amd64 anyway.
row("os", "os", "os", format="{pretty-name}")
row("kernel", "kernel", "kernel", format="{release}")
row("wm", "wm", "wm", format="{pretty-name} {version} ({protocol-name})")
row("terminal", "term", "term", format="{pretty-name} {version}")
row("shell", "shell", "shell", format="{pretty-name} {version}")
box_bottom()

# The 16-colour palette strip that used to sit here is gone: it is the one
# element that cannot be red/white, and dropping it lets the box centre against
# the art with clean space above and below instead of hanging past its bottom.

# Blank lines above the box, so its middle lands on the middle of the art.
# ART_PAD_TOP is where the art starts; the halved difference is the offset.
LEAD = ART_PAD_TOP + max(0, (ART_ROWS - len(mods)) // 2)


def stack(lead):
    """The module list with `lead` blank lines in front of it."""
    return ["break"] * lead + mods

DISPLAY = {
    "separator": "",
    # Values are the sclera white; the rails they sit between are the dim red.
    "color": {"output": WHITE, "separator": DRED},
    # 11 = colored number + single-colour bar (not the rainbow gradient bar).
    # Nothing in the current layout draws a bar, but a re-added memory/battery
    # row would, so the thresholds stay rather than being rediscovered later --
    # ramped white → red → dark red so they land on the palette if they return.
    "percent": {
        "type": 11, "green": 50, "yellow": 80,
        "color": {"green": WHITE, "yellow": RED, "red": DRED},
    },
    # heavier glyph for the filled part, lighter for the rest
    "bar": {"charElapsed": "━", "charTotal": "─",
            "borderLeft": "", "borderRight": "", "width": 12},
}

SCHEMA = "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json"


def write(path, cfg, gutter):
    """gutter = columns fastfetch reserves for the logo, i.e. how far every
    module line is indented. The box therefore opens at column gutter+1 and
    closes at column gutter+BOX_W (both 1-indexed, as CHA wants them)."""
    p = os.path.expanduser(path)
    with open(p, "w") as f:
        # ensure_ascii escapes every icon to \uXXXX in the JSON, so the written
        # config is pure ASCII and cannot lose a glyph in transit.
        f.write(json.dumps(cfg, indent=2, ensure_ascii=True)
                .replace("{RIGHT}", str(gutter + BOX_W))
                .replace("{LEFT}", str(gutter + 1)) + "\n")
    print("wrote", p)


def logo_cols(path):
    """Visible width of the widest line of an ASCII logo, ignoring its colors."""
    art = open(os.path.expanduser(path)).read()
    return max(len(re.sub(r"\x1b\[[0-9;]*m", "", l)) for l in art.split("\n"))


# The PNG is 256x256 with the corners transparent, same eye as the text art.
# At roughly a 1:2 terminal cell, 20x10 cells keeps it from being stretched;
# fastfetch letterboxes inside the box either way.
IMAGE = {
    "type": "kitty-direct",
    "source": "~/.config/fastfetch/images/eye.png",
    "width": 20, "height": 10,
    "padding": {"top": 2, "left": 2, "right": 3},
}
IMAGE_COLS = 2 + 20 + 3          # padding-left + width + padding-right

# Half-block eye, traced from the source art and quantized to black/white/red.
# Being text rather than a graphics-protocol image it renders in any terminal,
# so it is the logo for the full layout everywhere. Unlike the old Tux it has a
# fixed palette and does NOT follow wallust -- the red is the point. The circle
# is masked to the terminal background, so the corners stay transparent.
# (logo-tux.txt is left in place; wallust still rewrites it, nothing reads it.)
# 26 columns, near enough to the 25 Tux used that the layout keeps its old
# minimum width. logo-eye.txt is the same art at 40 -- more of the dithered
# iris survives, but it costs 15 more columns, so it is not wired up.
ART = {
    "type": "file-raw",   # raw: the art is pre-colored with SGR escapes, which
    "source": ART_SRC,    # the colorising loader eats
    "padding": {"top": ART_PAD_TOP, "left": 1, "right": 3},
}
ART_COLS = 1 + logo_cols(ART["source"]) + 3

write("~/.config/fastfetch/config.jsonc",
      {"$schema": SCHEMA, "logo": ART, "display": DISPLAY, "modules": stack(LEAD)},
      gutter=ART_COLS)

# Kept so .zshrc's non-kitty branch has a file to name; the art is already
# plain text, so this is the same layout rather than a degraded one.
write("~/.config/fastfetch/config-ascii.jsonc",
      {"$schema": SCHEMA, "logo": ART, "display": DISPLAY, "modules": stack(LEAD)},
      gutter=ART_COLS)

# The logo is the first thing that stops fitting — it costs 30 columns and the
# box only needs 48. Dropping it buys back a whole tier of window sizes. With no
# art to centre against, the lead-in drops to a single blank line.
write("~/.config/fastfetch/config-boxes.jsonc",
      {"$schema": SCHEMA, "logo": {"type": "none"},
       "display": DISPLAY, "modules": stack(1)},
      gutter=0)

# Narrower than one box: no layout survives, so show the logo and nothing else.
# fastfetch still emits the cursor-up/newline pair that follows a logo, so the
# prompt lands below the art rather than on top of it.
for name, logo in (("config-logo.jsonc", IMAGE), ("config-logo-ascii.jsonc", ART)):
    write("~/.config/fastfetch/" + name,
          {"$schema": SCHEMA, "logo": logo, "modules": []}, gutter=0)


# ---- accent colours from the wallpaper ---------------------------
# wallust writes the wallpaper's palette to wallust-palette.json (template
# ~/.config/wallust/templates/colors-fastfetch.json) on every wallpaper change,
# and .zshrc re-runs this script when that file is newer than the configs.
# Same roles as the eye's red/white: ACC for icons and the name, FRM for the
# frame (the accent sunk toward the background so it recedes), TXT for values.
# No palette file -> the original red/white.
import colorsys

PALETTE = os.path.expanduser("~/.config/fastfetch/wallust-palette.json")


def _rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _sgr(rgb):
    return "38;2;%d;%d;%d" % rgb


TERM_BG = (19, 19, 19)   # kitty Brogrammer background: the frame mixes toward it
WALLPAPER = os.path.expanduser("~/.config/hypr/wallpaper_effects/.wallpaper_current")


def _chroma(c):
    return (max(c) - min(c)) / 255


def _from_image(path):
    """The wallpaper's most vivid colour that covers a real part of it.
    Read from the image itself: wallust's dark16/labmixed palette blends and
    lightens, so e.g. the dedsec wallpaper's pure red came out as pale peach."""
    import re, subprocess
    try:
        out = subprocess.run(["magick", path + "[0]", "-resize", "200x200", "-colors", "24",
                              "-format", "%c", "histogram:info:-"],
                             capture_output=True, text=True, timeout=10).stdout
    except (OSError, subprocess.SubprocessError):
        return None
    cols = []
    for line in out.splitlines():
        m = re.match(r"\s*(\d+):.*#([0-9A-Fa-f]{6})", line)
        if m:
            cols.append((int(m.group(1)), _rgb(m.group(2))))
    total = sum(n for n, _ in cols) or 1
    best, best_score = None, 0.0
    for n, c in cols:
        share = n / total
        light = colorsys.rgb_to_hls(*(v / 255 for v in c))[1]
        if share < 0.01 or light < 0.2:   # specks and near-black do not count
            continue
        score = _chroma(c) * share ** 0.35   # vivid first, but it must be present
        if score > best_score:
            best, best_score = c, score
    # None when nothing has any colour (a grey wallpaper): wallust's palette decides
    return best


def _from_wallust():
    """Fallback: the most vivid readable colour of wallust's palette."""
    try:
        pal = json.load(open(PALETTE))
        cands = [_rgb(pal[f"color{i}"]) for i in (1, 2, 3, 4, 5, 6, 9, 10, 11, 12, 13, 14)]
    except (OSError, ValueError, KeyError):
        return None
    ok = [c for c in cands if colorsys.rgb_to_hls(*(v / 255 for v in c))[1] >= 0.45]
    return max(ok or cands, key=_chroma)


def for_dark_bg(c, ratio=4.0):
    """Lighten c toward white until it reads on the terminal background."""
    bg = _lum(TERM_BG)
    for i in range(51):
        f = i / 50
        d = tuple(round(v + (255 - v) * f) for v in c)
        if (_lum(d) + 0.05) / (bg + 0.05) >= ratio:
            return d
    return (235, 235, 235)


def wallust_accents():
    acc = (_from_image(WALLPAPER) if os.path.exists(WALLPAPER) else None) or _from_wallust()
    if not acc:
        return None
    acc = for_dark_bg(acc)
    frm = tuple(round(a * 0.55 + b * 0.45) for a, b in zip(acc, TERM_BG))
    return acc, frm


def _lum(c):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = map(ch, c)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def for_white_text(c, ratio=4.5):
    """Darken c until white-ish text on it reaches `ratio` contrast."""
    white = _lum((235, 235, 235))
    f = 1.0
    while f > 0.1:
        d = tuple(round(v * f) for v in c)
        if (white + 0.05) / (_lum(d) + 0.05) >= ratio:
            return d
        f -= 0.02
    return tuple(round(v * 0.1) for v in c)


# The zsh prompt (agnosterzak theme) uses the accent as segment BACKGROUNDS with
# white text on top, so it gets its own darkened pair: time segment, then the
# dir segment a step darker (the same 130/222 ratio as the original reds).
PROMPT_ACCENT = os.path.expanduser("~/.cache/prompt-accent.zsh")

_acc = wallust_accents()
if _acc:
    ACC, FRM, TXT = _sgr(_acc[0]), _sgr(_acc[1]), WHITE
    _p1 = for_white_text(_acc[0])
    _p2 = tuple(round(v * 130 / 222) for v in _p1)
    os.makedirs(os.path.dirname(PROMPT_ACCENT), exist_ok=True)
    with open(PROMPT_ACCENT, "w") as f:
        f.write("# generated by ~/.config/fastfetch/gen_config.py from the wallpaper\n"
                "ZAK_RED='#%02x%02x%02x'\nZAK_DRED='#%02x%02x%02x'\n" % (_p1 + _p2))
else:
    ACC, FRM, TXT = RED, DRED, WHITE
    if os.path.exists(PROMPT_ACCENT):
        os.remove(PROMPT_ACCENT)   # theme falls back to its own reds

# ---- Waybar clock calendar ------------------------------------------
# The clock's calendar tooltip takes the same accent: weekday names in the
# accent, today as a block in the prompt's darkened accent with white text.
# Waybar can't read colours into a tooltip from CSS, so the whole clock module
# lives in this generated include (listed in waybar/configs/TOP-Everforest).
# Waybar only reads tooltip formats at load, so it is reloaded (SIGUSR2) when
# the file actually changes.
WAYBAR_CLOCK = os.path.expanduser("~/.config/waybar/wallust/clock-calendar.jsonc")


def _hex(c):
    return "#%02x%02x%02x" % tuple(c)


_cal_acc = _acc[0] if _acc else (222, 0, 0)
_cal_today = for_white_text(_cal_acc)
_clock = {"clock#forest": {
    "format": "{:L%A %d.%m.%Y - %H:%M}",
    "tooltip-format": "<tt>{calendar}</tt>",
    "calendar": {
        "mode": "month",
        "on-scroll": 1,
        "format": {
            "months": "<span color='#ebebeb'><b>{}</b></span>",
            "days": "<span color='#cfcfcf'>{}</span>",
            "weekdays": "<span color='%s'><b>{}</b></span>" % _hex(_cal_acc),
            "today": "<span background='%s' color='#ebebeb'><b>{}</b></span>" % _hex(_cal_today),
        },
    },
    "actions": {"on-scroll-up": "shift_up", "on-scroll-down": "shift_down",
                "on-click-right": "shift_reset"},
}}
_clock_txt = ("// generated by ~/.config/fastfetch/gen_config.py from the wallpaper\n"
              + json.dumps(_clock, indent=2) + "\n")
try:
    _old_clock = open(WAYBAR_CLOCK).read()
except OSError:
    _old_clock = None
if _old_clock != _clock_txt:
    os.makedirs(os.path.dirname(WAYBAR_CLOCK), exist_ok=True)
    with open(WAYBAR_CLOCK, "w") as f:
        f.write(_clock_txt)
    if _old_clock is not None:
        import subprocess
        subprocess.run(["pkill", "-USR2", "-x", "waybar"], stderr=subprocess.DEVNULL)

# ══════════════════════════════════════════════════════════════════
# ---- logo-less layout: config-nologo.jsonc ------------------------
# The default .zshrc runs. Tuned to read cleanly without a logo beside it:
#  - every value trimmed to its short form, so the box can be narrow and the
#    right rail does not float far away from the text;
#  - brightColor off: fastfetch bolds keys by default, which made the vertical
#    rails heavier than the horizontal rules;
#  - sizes to one decimal, uptime as 2d 4h 56m, no package count.
# Three widths, each a rung .zshrc steps down to as the window narrows:
#   config-nologo.jsonc   46 cols  full box, icon + label + value
#   config-compact-nologo 31 cols  box, icon + value only (labels dropped)
#   config-mini-nologo    24 cols  no frame, the five shortest rows
CPU_CMD = ("awk -F': ' '/model name/{print $2; exit}' /proc/cpuinfo"
           " | sed -E 's/\\((R|TM)\\)//g; s/^[0-9]+th Gen //; s/ Core / /; s/ +/ /g'")

# (module, icon, label, extra fastfetch options). None = section divider.
ROWS = [
    ("host", "host", "host", {"format": "{family}"}),
    ("os", "os", "os", {"format": "Debian {version-id} {codename}"}),
    ("kernel", "kernel", "kernel", {"format": "{release}"}),
    None,
    ("wm", "wm", "wm", {"format": "{pretty-name} {version}"}),
    ("terminal", "term", "term", {"format": "{pretty-name}"}),
    ("shell", "shell", "shell", {"format": "{pretty-name} {version}"}),
    None,
    ("command", "cpu", "cpu", {"text": CPU_CMD}),
    ("gpu", "gpu", "gpu", {"format": "{vendor} {name}"}),
    ("memory", "memory", "memory", {"format": "{used} / {total}"}),
    ("disk", "disk", "disk", {"folders": "/", "format": "{size-used} / {size-total}"}),
]
MINI = {"os", "kernel", "memory", "shell"}


def boxed(width, left, labels):
    """Box `width` columns wide whose left rail is at column `left`."""
    right = left + width - 1
    rail = f"\x1b[{right}G│\x1b[{left}G│ "
    rule = lambda l, r: {"type": "custom", "format":
                         f"\x1b[{left}G{E(FRM)}{l}{'─' * (width - 2)}{r}{E('0')}"}
    # Top border first, then jump back and write the name over its start, so
    # the rule stays exactly `width` wide whatever the user/host names are.
    out = [{"type": "title", "key": " ", "format":
            f"\x1b[{left}G{E(FRM)}╭{'─' * (width - 2)}╮"
            f"\x1b[{left + 1}G─ {E('1;' + ACC)}{{user-name}}{E(TXT)}@{{host-name}} {E('0')}"}]
    for r in ROWS:
        if r is None:
            out.append(rule("├", "┤"))
            continue
        mtype, name, label, kw = r
        lbl = f"{E(TXT)}{label.ljust(LABEL_W)}" if labels else ""
        out.append({"type": mtype, "keyColor": FRM,
                    "key": f"{rail}{E(ACC)}{icon(name)}  {lbl}", **kw})
    out.append(rule("╰", "╯"))
    return out


def mini():
    out = [{"type": "title", "key": " ",
            "format": f" {E('1;' + ACC)}{{user-name}}{E(TXT)}@{{host-name}}{E('0')}"}]
    for r in ROWS:
        if r is not None and r[1] in MINI:
            mtype, name, label, kw = r
            out.append({"type": mtype, "keyColor": ACC,
                        "key": f" {icon(name)}  ", **kw})
    return out


# brightColor off: fastfetch bolds keys by default, which made the vertical
# rails heavier than the horizontal rules. Sizes to one decimal.
NL_DISPLAY = {**DISPLAY, "brightColor": False, "size": {"ndigits": 1},
              "color": {"output": TXT, "separator": FRM},
              "percent": {**DISPLAY["percent"],
                          "color": {"green": TXT, "yellow": ACC, "red": FRM}}}

for name, mods_ in (("config-nologo.jsonc", boxed(44, 3, True)),
                    ("config-compact-nologo.jsonc", boxed(30, 2, False)),
                    ("config-mini-nologo.jsonc", mini())):
    write("~/.config/fastfetch/" + name,
          {"$schema": SCHEMA, "logo": {"type": "none"},
           "display": NL_DISPLAY, "modules": ["break"] + mods_ + ["break"]},
          gutter=0)

# Record what this build was made from (see "skip when nothing changed").
os.makedirs(os.path.dirname(_KEY_FILE), exist_ok=True)
with open(_KEY_FILE, "w") as f:
    f.write(_KEY + "\n")
