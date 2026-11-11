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
import json, os, re

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

# ══════════════════════════════════════════════════════════════════
# ---- logo-less layout: config-nologo.jsonc ------------------------
# Not config-boxes with the art cut off: that one was laid out to sit beside
# the eye, so on its own it hugs column 1 and the name floats above a short
# box. This one is designed to stand alone: indented off the edge, the
# user@host set into the top border, and the space the art used to take
# spent on three grouped sections instead.
NL_W = 56                      # outer box width
NL_LEFT = 3                    # column of the left rail (2-col margin)
NL_RIGHT = NL_LEFT + NL_W - 1  # column of the right rail
NL_RAIL = f"\x1b[{NL_RIGHT}G│\x1b[{NL_LEFT}G│ "

nl = []


def nl_rule(left, right):
    nl.append({"type": "custom", "format":
               f"\x1b[{NL_LEFT}G{E(DRED)}{left}{'─' * (NL_W - 2)}{right}{E('0')}"})


def nl_row(mtype, name, label, **kw):
    nl.append({"type": mtype, "keyColor": DRED,
               "key": f"{NL_RAIL}{E(RED)}{icon(name)}  {E(WHITE)}{label.ljust(LABEL_W)}",
               **kw})


# Top border first, then jump back and write the name over its start, so the
# rule stays exactly NL_W wide whatever the user/host names are.
nl.append({"type": "title", "key": " ", "format":
           f"\x1b[{NL_LEFT}G{E(DRED)}╭{'─' * (NL_W - 2)}╮"
           f"\x1b[{NL_LEFT + 1}G─ {E('1;' + RED)}{{user-name}}{E(WHITE)}@{{host-name}} {E('0')}"})
nl_row("host", "host", "host", format="{family}")
nl_row("os", "os", "os", format="{pretty-name}")
nl_row("kernel", "kernel", "kernel", format="{release}")
nl_row("uptime", "uptime", "uptime")
nl_rule("├", "┤")
nl_row("wm", "wm", "wm", format="{pretty-name} {version} ({protocol-name})")
nl_row("terminal", "term", "term", format="{pretty-name} {version}")
nl_row("shell", "shell", "shell", format="{pretty-name} {version}")
nl_row("packages", "packages", "pkgs", format="{all}")
nl_rule("├", "┤")
nl_row("cpu", "cpu", "cpu", format="{name}")
nl_row("gpu", "gpu", "gpu", format="{name}")
nl_row("memory", "memory", "memory", format="{used} / {total}")
nl_row("disk", "disk", "disk", folders="/", format="{size-used} / {size-total}")
nl_rule("╰", "╯")

write("~/.config/fastfetch/config-nologo.jsonc",
      {"$schema": SCHEMA, "logo": {"type": "none"},
       "display": DISPLAY, "modules": ["break"] + nl},
      gutter=0)
