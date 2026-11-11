#!/usr/bin/env python3
"""Generate the wallust template that paints Tux in the current wallpaper's colors.

Reads images/tux.png, samples it at twice the row count, and emits one line of
half-block characters per output row so each cell carries two pixels: the upper
half as the foreground color, the lower half as the background. That buys back
the vertical detail a 1:2 terminal cell would otherwise throw away, which is the
difference between Tux having eyes and Tux being a blob.

Every pixel is classified into a zone (body / belly / beak+feet) and each zone
maps to a wallust variable, so wallust re-renders the art on every wallpaper
change and the logo tracks the palette the same way waybar does.

Re-run this only to change the art itself -- size, character, or zone mapping.
The width matters: it feeds ART_COLS in gen_config.py, which sets the minimum
terminal width .zshrc requires before it drops to a logo-less layout.

    python3 ~/.config/fastfetch/gen_tux_template.py
"""

import subprocess
import sys
from pathlib import Path

CONFIG = Path.home() / ".config"
SRC = CONFIG / "fastfetch/images/tux.png"
OUT = CONFIG / "wallust/templates/logo-tux.txt"

COLS = 28
ROWS = 14          # sampled at COLS x ROWS*2; half-blocks fold the pairs back

UPPER, LOWER, FULL = "▀", "▄", "█"

# zone -> wallust color variable. The source is black body / white belly /
# yellow beak, and black inverts badly on a dark terminal, so the body takes a
# mid tone and the belly the brightest one to keep the silhouette readable.
#
# These three slots are picked for worst-case behaviour, not for how they look
# on any one wallpaper. Measured over the wallpaper set, every one of them stays
# at least 82 luminance above the background, so no zone can sink into it -- the
# failure that rules out the obvious warm choice for the beak, color11, which
# lands near-black on dark wallpapers. Slots 0-3 and 9-11 all go dark somewhere.
# Zone contrast is the thing being traded away: wallust's dark16 palettes are
# low-contrast enough that the best worst-case gap between any three safe slots
# is ~7 luminance, so on a flat wallpaper Tux reads as near-monochrome and the
# silhouette does the work.
ZONE_COLOR = {
    "body":  "color12",
    "belly": "color15",
    "beak":  "color5",
}


def sample(cols, rows):
    """Return a cols x rows grid of (r, g, b, a) sampled from the source PNG."""
    out = subprocess.run(
        ["magick", str(SRC), "-resize", f"{cols}x{rows}!", "-depth", "8", "txt:-"],
        capture_output=True, text=True, check=True,
    ).stdout

    grid = [[(0, 0, 0, 0)] * cols for _ in range(rows)]
    for line in out.splitlines()[1:]:
        pos, _, rest = line.partition(":")
        x, y = (int(v) for v in pos.split(","))
        vals = [int(float(v)) for v in
                rest[rest.index("(") + 1: rest.index(")")].split(",")]
        grid[y][x] = tuple(vals[:4]) if len(vals) > 3 else (*vals[:3], 255)
    return grid


def zone(px):
    """Classify one sampled pixel into a color zone, or None for transparent."""
    r, g, b, a = px
    if a < 110:
        return None
    # beak and feet are the only strongly warm region in the source art
    if r > 150 and g > 110 and b < 140 and (r - b) > 55:
        return "beak"
    # the eyes and belly are the light areas; everything else is the black body
    return "belly" if 0.299 * r + 0.587 * g + 0.114 * b > 150 else "body"


def var(zone_name, layer):
    """A truecolor SGR body for one zone: 38 paints foreground, 48 background."""
    v = ZONE_COLOR[zone_name]
    return "%d;2;{{%s | red}};{{%s | green}};{{%s | blue}}" % (layer, v, v, v)


def cell(top, bottom):
    """(char, sgr-parameters) for one output cell, or None if fully transparent."""
    if top and bottom:
        # identical halves are a full block, which needs no background color
        if top == bottom:
            return FULL, var(top, 38)
        return UPPER, var(top, 38) + ";" + var(bottom, 48)
    if top:
        return UPPER, var(top, 38)
    if bottom:
        return LOWER, var(bottom, 38)
    return None


def main():
    if not SRC.exists():
        sys.exit(f"missing source image: {SRC}")

    grid = sample(COLS, ROWS * 2)
    lines, widths = [], []

    for r in range(ROWS):
        top_row = [zone(px) for px in grid[r * 2]]
        bot_row = [zone(px) for px in grid[r * 2 + 1]]
        cells = [cell(t, b) for t, b in zip(top_row, bot_row)]
        while cells and cells[-1] is None:
            cells.pop()                      # trailing blanks are just width

        out, current = [], None
        for c in cells:
            sgr = c[1] if c else None
            if sgr != current:
                if current is not None:
                    out.append("\033[0m")
                if sgr is not None:
                    out.append("\033[" + sgr + "m")
                current = sgr
            out.append(c[0] if c else " ")
        if current is not None:
            out.append("\033[0m")

        lines.append("".join(out))
        widths.append(len(cells))

    while lines and not widths[0]:           # drop blank rows, top and bottom
        lines.pop(0), widths.pop(0)
    while lines and not widths[-1]:
        lines.pop(), widths.pop()

    OUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote {OUT} ({len(lines)} rows, {max(widths)} cols)")


if __name__ == "__main__":
    main()
