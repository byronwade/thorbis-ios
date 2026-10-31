#!/usr/bin/env python3
"""Contrast check for Theme.swift text tokens on the grounds they sit on (redesign 2026-10-31).

Reads the hex values straight out of Thorbis/Sources/Theme.swift, so it checks what ships.
Run: python3 scripts/tests/contrast.py  (exit 1 on any failure)
"""
import re, sys, pathlib

src = (pathlib.Path(__file__).resolve().parents[2] / "Thorbis/Sources/Theme.swift").read_text()
tokens = {}
for m in re.finditer(r"static let (\w+) = adaptive\(light: 0x(\w+), dark: 0x(\w+)(?:, highLight: 0x(\w+), highDark: 0x(\w+))?\)", src):
    name, l, d, hl, hd = m.groups()
    tokens[name] = {"light": l, "dark": d, "highLight": hl or l, "highDark": hd or d}
for m in re.finditer(r"static let (\w+) = (\w+)\n", src):
    if m.group(2) in tokens: tokens[m.group(1)] = tokens[m.group(2)]

def lum(h):
    c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.03928 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return 0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]

def ratio(a, b):
    la, lb = sorted([lum(a), lum(b)], reverse=True)
    return (la + 0.05) / (lb + 0.05)

grounds = ["background", "card", "fill"]
checks = {
    "foreground": grounds + ["selectedSegment", "brandSurface", "warningSurface", "successSurface", "destructiveSurface"],
    # The job's "Before you go in" banner sets its notes and caveat on the warning surface.
    "muted": grounds + ["selectedSegment", "warningSurface"],
    "subtle": grounds + ["warningSurface"],
    "brandText": grounds[:2] + ["brandSurface"],
    "success": grounds[:2] + ["successSurface"],
    "warning": grounds[:2] + ["warningSurface"],
    "destructive": grounds[:2] + ["destructiveSurface"],
    "statusScheduledText": grounds[:2] + ["statusScheduledSurface"],
    "statusInvoicedText": grounds[:2] + ["statusInvoicedSurface"],
    "onInk": ["foreground"],
}
fails = 0
for mode in ["light", "dark", "highLight", "highDark"]:
    print(f"== {mode}")
    for text, gs in checks.items():
        row = []
        for g in gs:
            r = ratio(tokens[text][mode], tokens[g][mode])
            ok = r >= 4.5
            fails += not ok
            row.append(f"{g} {r:.2f}{'' if ok else ' FAIL'}")
        print(f"  {text:22} " + " | ".join(row))
# Non-text (WCAG 1.4.11): each status glyph hue against the grounds it is drawn on: the screen,
# the well, and its own chip surface (unscheduled and cancelled chips sit on `fill`). 3:1, counted.
tokens["statusDispatched"] = {m: "2F6BFF" for m in ["light", "dark", "highLight", "highDark"]}  # = brand, Color(hex:)
glyphs = {
    "statusUnscheduled": "fill",
    "statusScheduled": "statusScheduledSurface",
    "statusDispatched": "brandSurface",
    "statusInProgress": "warningSurface",
    "statusDone": "successSurface",
    "statusAttention": "destructiveSurface",
    "statusInvoiced": "statusInvoicedSurface",
}
print("== status glyphs, non-text 3:1 (background | well | own chip surface)")
for mode in ["light", "dark"]:
    for n, surface in glyphs.items():
        row = []
        for g in ["background", "card", surface]:
            r = ratio(tokens[n][mode], tokens[g][mode])
            ok = r >= 3
            fails += not ok
            row.append(f"{g} {r:.2f}{'' if ok else ' FAIL'}")
        print(f"  {mode:5} {n:20} " + " | ".join(row))
# The dark toast capsule (ThorbisToast) and its words.
print("== toast")
for mode in ["light", "dark", "highLight", "highDark"]:
    for text in ["toastText", "toastMuted"]:
        r = ratio(tokens[text][mode], tokens["toastFill"][mode])
        ok = r >= 4.5
        fails += not ok
        print(f"  {mode:9} {text:10} toastFill {r:.2f}{'' if ok else ' FAIL'}")
print("FAILURES:", fails)
sys.exit(1 if fails else 0)
