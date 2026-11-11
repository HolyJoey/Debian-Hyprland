#!/usr/bin/env python3
"""Replay fastfetch output as a cursor and report the rightmost column each line reaches."""
import re, subprocess, sys, unicodedata

RIGHT = int(sys.argv[2]) if len(sys.argv) > 2 else 85
out = subprocess.run(["fastfetch", "--config", sys.argv[1]],
                     capture_output=True, text=True).stdout

def cw(ch):
    if unicodedata.combining(ch):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in "WF" or 0xF0000 <= ord(ch) <= 0xFFFFD \
        or 0xE000 <= ord(ch) <= 0xF8FF else 1

tok = re.compile(r"\x1b\[([0-9;]*)([A-Za-z])")
for raw in out.split("\n"):
    col, maxcol, i = 1, 0, 0
    while i < len(raw):
        m = tok.match(raw, i)
        if m:
            n, verb = m.group(1), m.group(2)
            if verb == "G":
                col = int(n or 1)
            elif verb == "C":
                col += int(n or 1)
            i = m.end()
            continue
        col += cw(raw[i])
        maxcol = max(maxcol, col - 1)
        i += 1
    if maxcol > 0:
        flag = "  <-- OVERFLOW" if maxcol > RIGHT else ""
        print(f"{maxcol:4}  {re.sub(chr(27)+r'\[[0-9;]*[A-Za-z]', '', raw)[:70]}{flag}")
