#!/usr/bin/env python3
"""Adds round 34's font combinations to textcombos.json: 36 that drop in
already moving, under the new category "Animated" — each text carrying the
`animation` (and, where it fits, `exitAnimation`) keys ElementAnimation
reads, {kind, delay, duration, by}, some with a neon, glitch or echo effect,
a curve or a warp — and 12 more curved or warped headlines in the existing
categories.

The first 120 combinations are the Android twin's tools/generate_textcombos.py
output, kept here exactly as they are: this script reads the file, drops any
entry with one of the ids below, and writes the 120 and then these, in the
same form — one entry a line, compact, UTF-8 — so running it twice changes
nothing. Run from anywhere:

  python3 Canvia/Tools/generate_textcombos_animated.py

It writes Canvia/Canvia/Content/textcombos.json, which both apps ship byte
for byte. Nothing is random and nothing is downloaded.
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(os.path.join(HERE, "..", "Canvia", "Content", "textcombos.json"))

ANIMATED = "Animated"

# The kinds every animation below uses: each one ElementAnimation knows
# (the test that reads the file holds them to it).
TEXT_KINDS = ["typewriter", "words", "letterPop", "lineRise", "baseline", "ascend", "shift", "merge",
              "block", "burst", "bounceIn", "roll", "skate", "spread", "clarify", "tumble", "writeOn"]
WHOLE_KINDS = ["fade", "rise", "pop", "slideLeft", "slideRight", "wipe", "breathe", "drift", "pulse",
               "wiggle", "bounce"]


def anim(kind, by=None, duration=0.8, delay=0.0):
    out = {"kind": kind, "delay": delay, "duration": duration}
    if by:
        out["by"] = by
    return out


def text(words, y, h, font, size, color, w=860, x=0, weight=400, align="center", line=1.2, spacing=0, **extra):
    el = {"type": "text", "text": words, "x": x, "y": y, "w": w, "h": h, "fontFamily": font,
          "fontSize": size, "fontWeight": weight, "align": align, "lineHeight": line,
          "letterSpacing": spacing, "color": color}
    el.update(extra)
    return el


def panel(w, h, color, radius=28):
    return {"type": "shape", "shapeId": "rect", "x": 0, "y": 0, "w": w, "h": h,
            "fill": {"kind": "solid", "color": color}, "radius": radius}


def combo(cid, name, tags, category, w, elements):
    return {"id": cid, "name": name, "tags": tags, "category": category, "w": w, "elements": elements}


def animated():
    """The 36 combinations of the Animated category."""
    out = []

    def add(cid, name, tags, elements, w=860):
        out.append(combo(cid, name, tags + ["animated", "moving"], ANIMATED, w, elements))

    add("type-it-out", "Type it out", ["typewriter", "type", "story", "intro"], [
        text("Once upon a time", 0, 106, "space-mono", 72, "#1f2430", weight=700,
             animation=anim("typewriter", "letter", 1.6)),
        text("a story, one key at a time", 124, 36, "space-mono", 30, "#6B7280",
             animation=anim("fade", duration=0.6, delay=1.6)),
    ])
    add("word-by-word", "Word by word", ["words", "message", "announcement"], [
        text("Big news is coming", 0, 120, "montserrat", 96, "#111827", weight=800,
             animation=anim("words", "word", 1.2)),
        text("Stay tuned", 136, 40, "montserrat", 32, "#6366F1", weight=600, spacing=4,
             animation=anim("rise", duration=0.6, delay=1.2)),
    ])
    add("letter-pop", "Letter pop", ["pop", "fun", "party", "kids"], [
        text("POP!", 0, 190, "bungee", 180, "#EC4899",
             animation=anim("letterPop", "letter", 1.0)),
        text("Something fun is on its way", 196, 36, "nunito", 30, "#6B7280", weight=700,
             animation=anim("fade", duration=0.5, delay=1.0)),
    ])
    add("rising-lines", "Rising lines", ["lines", "poem", "quote", "rise"], [
        text("Every line\nrises in turn", 0, 220, "playfair-display", 84, "#1f2430", weight=700, line=1.25,
             animation=anim("lineRise", "line", 1.2)),
    ])
    add("baseline-reveal", "Baseline reveal", ["reveal", "headline", "elegant"], [
        text("Reveal", 0, 150, "dm-serif-display", 140, "#0F172A",
             animation=anim("baseline", "line", 1.0)),
        text("NEW COLLECTION", 166, 34, "raleway", 28, "#64748B", weight=600, spacing=10,
             animation=anim("ascend", "word", 0.8, delay=0.8)),
    ])
    add("ascending", "Ascending", ["ascend", "launch", "growth"], [
        text("Going up", 0, 130, "poppins", 110, "#16A34A", weight=800,
             animation=anim("ascend", "letter", 1.0)),
        text("Our best quarter yet", 140, 38, "poppins", 32, "#4B5563",
             animation=anim("fade", duration=0.6, delay=1.0)),
    ])
    add("shift-in", "Shift in", ["shift", "modern", "tech"], [
        text("SHIFT", 0, 160, "space-grotesk", 150, "#0EA5E9", weight=700, spacing=6,
             animation=anim("shift", "letter", 1.0), exitAnimation=anim("fade", duration=0.5)),
        text("A new way to work", 168, 36, "space-grotesk", 30, "#334155",
             animation=anim("shift", "word", 0.8, delay=0.8)),
    ])
    add("merge-together", "Merge together", ["merge", "team", "together"], [
        text("Better together", 0, 112, "raleway", 92, "#7C3AED", weight=800,
             animation=anim("merge", "letter", 1.2)),
    ])
    add("block-reveal", "Block reveal", ["block", "bold", "news"], [
        panel(860, 300, "#111827", 0),
        text("BREAKING", 40, 60, "anton", 120, "#FACC15", w=780, spacing=4,
             animation=anim("block", "word", 1.0)),
        text("Read all about it", 40, 200, "oswald", 40, "#F9FAFB", w=780,
             animation=anim("block", "line", 0.8, delay=0.8)),
    ])
    add("burst-out", "Burst out", ["burst", "celebrate", "party"], [
        text("Hooray!", 0, 160, "righteous", 140, "#F97316",
             animation=anim("burst", "letter", 1.0), effect={"type": "echo", "color": "#FDBA74"}),
        text("We did it", 168, 40, "righteous", 34, "#7C2D12",
             animation=anim("pop", duration=0.5, delay=1.0)),
    ])
    add("bounce-in", "Bounce in", ["bounce", "kids", "play"], [
        text("Bounce!", 0, 150, "bungee", 130, "#22C55E",
             animation=anim("bounceIn", "letter", 1.2)),
        text("Playtime starts now", 156, 36, "nunito", 30, "#166534", weight=800,
             animation=anim("bounce", duration=0.8, delay=1.2)),
    ])
    add("roll-up", "Roll up", ["roll", "show", "circus"], [
        text("Roll up!", 0, 140, "alfa-slab-one", 120, "#DC2626",
             animation=anim("roll", "letter", 1.0), curve=24),
        text("THE SHOW BEGINS", 150, 34, "oswald", 30, "#991B1B", spacing=8,
             animation=anim("fade", duration=0.6, delay=1.0)),
    ])
    add("skate-across", "Skate across", ["skate", "sport", "street"], [
        text("Skate", 0, 170, "permanent-marker", 150, "#0F172A",
             animation=anim("skate", "letter", 1.0)),
        text("street session · saturday", 176, 36, "space-mono", 28, "#475569",
             animation=anim("slideLeft", duration=0.6, delay=1.0)),
    ])
    add("spread-out", "Spread out", ["spread", "wide", "open"], [
        text("OPEN", 0, 160, "bebas-neue", 170, "#0891B2", spacing=24,
             animation=anim("spread", "letter", 1.2)),
        text("doors at nine", 166, 36, "lato", 30, "#155E75",
             animation=anim("fade", duration=0.6, delay=1.2)),
    ])
    add("clarify", "Come into focus", ["clarify", "focus", "blur", "reveal"], [
        text("In focus", 0, 130, "lora", 110, "#1E293B", weight=700,
             animation=anim("clarify", "word", 1.4)),
        text("See the bigger picture", 140, 36, "lora", 30, "#64748B",
             animation=anim("clarify", "line", 1.0, delay=1.0)),
    ])
    add("tumble-in", "Tumble in", ["tumble", "fun", "playful"], [
        text("Tumble", 0, 150, "righteous", 130, "#9333EA",
             animation=anim("tumble", "letter", 1.2)),
    ])
    add("write-on", "Write on", ["write", "signature", "script", "handwriting"], [
        text("Thank you", 0, 170, "dancing-script", 140, "#BE185D", weight=700,
             animation=anim("writeOn", "letter", 1.8)),
        text("with love", 170, 40, "satisfy", 36, "#9D174D",
             animation=anim("fade", duration=0.6, delay=1.8)),
    ])
    add("neon-flicker", "Neon flicker", ["neon", "flicker", "night", "club"], [
        panel(860, 340, "#0B1026"),
        text("Open late", 40, 80, "righteous", 110, "#F472B6", w=780, effect={"type": "neon"},
             animation=anim("letterPop", "letter", 1.0), exitAnimation=anim("fade", duration=0.4)),
        text("bar · music · friends", 40, 236, "space-mono", 30, "#67E8F9", w=780,
             effect={"type": "neon"}, animation=anim("pulse", duration=1.2, delay=1.0)),
    ])
    add("neon-sign", "Neon sign", ["neon", "sign", "diner"], [
        panel(860, 320, "#111827"),
        text("EAT", 40, 50, "bungee", 150, "#FB7185", w=780, effect={"type": "neon"},
             animation=anim("typewriter", "letter", 0.9)),
        text("open 24 hours", 40, 220, "pacifico", 44, "#FDE68A", w=780, effect={"type": "neon"},
             animation=anim("fade", duration=0.8, delay=0.9)),
    ])
    add("glitch-in", "Glitch in", ["glitch", "tech", "gaming", "cyber"], [
        panel(860, 320, "#0A0A0A", 0),
        text("SYSTEM", 40, 60, "space-grotesk", 130, "#22D3EE", w=780, weight=700, spacing=4,
             effect={"type": "glitch"}, animation=anim("shift", "letter", 0.8),
             exitAnimation=anim("wipe", duration=0.4)),
        text("reboot complete", 40, 220, "roboto-mono", 32, "#A3E635", w=780,
             animation=anim("typewriter", "letter", 1.0, delay=0.8)),
    ])
    add("glitch-title", "Glitch title", ["glitch", "trailer", "film"], [
        text("ERROR 404", 0, 150, "anton", 130, "#E11D48", spacing=2, effect={"type": "glitch"},
             animation=anim("block", "letter", 0.8)),
        text("page not found", 158, 34, "space-mono", 30, "#334155",
             animation=anim("wiggle", duration=0.8, delay=0.8)),
    ])
    add("echo-rise", "Echo rise", ["echo", "retro", "rise"], [
        text("Echo", 0, 170, "abril-fatface", 160, "#2563EB", effect={"type": "echo", "color": "#93C5FD"},
             animation=anim("lineRise", "line", 1.0)),
        text("say it again", 176, 36, "raleway", 30, "#1E3A8A", weight=600,
             animation=anim("rise", duration=0.6, delay=1.0)),
    ])
    add("echo-words", "Echo words", ["echo", "music", "sound"], [
        text("Turn it up", 0, 130, "oswald", 120, "#F59E0B", effect={"type": "echo", "color": "#7C2D12"},
             animation=anim("words", "word", 1.0)),
    ])
    add("curved-pop", "Curved pop", ["curve", "badge", "sticker", "pop"], [
        text("fresh & local", 0, 140, "pacifico", 96, "#15803D", curve=45,
             animation=anim("letterPop", "letter", 1.0)),
        text("FARMERS MARKET", 150, 40, "oswald", 40, "#14532D", spacing=6,
             animation=anim("fade", duration=0.6, delay=1.0)),
    ])
    add("arch-rise", "Arch rise", ["arch", "warp", "retro", "headline"], [
        text("SUPER SALE", 0, 170, "bungee", 120, "#DC2626", warp={"kind": "arch", "amount": 50},
             animation=anim("ascend", "letter", 1.0), exitAnimation=anim("fade", duration=0.5)),
        text("this weekend only", 180, 36, "poppins", 30, "#7F1D1D",
             animation=anim("fade", duration=0.6, delay=1.0)),
    ])
    add("flag-wave", "Flag wave", ["flag", "warp", "wave", "summer"], [
        text("Summer", 0, 170, "righteous", 150, "#0EA5E9", warp={"kind": "flag", "amount": 40},
             animation=anim("drift", duration=1.2)),
        text("make waves", 176, 36, "caveat", 40, "#0369A1",
             animation=anim("words", "word", 0.8, delay=0.6)),
    ])
    add("bulge-bounce", "Bulge bounce", ["bulge", "warp", "fun", "kids"], [
        text("BIG FUN", 0, 180, "bungee", 140, "#A21CAF", warp={"kind": "bulge", "amount": 45},
             animation=anim("bounceIn", "letter", 1.0)),
    ])
    add("rise-warp", "Rising star", ["rise", "warp", "star", "award"], [
        text("Rising Star", 0, 150, "abril-fatface", 120, "#B45309", warp={"kind": "rise", "amount": 40},
             animation=anim("lineRise", "line", 1.0)),
        text("AWARD 2026", 160, 36, "raleway", 30, "#78350F", weight=700, spacing=10,
             animation=anim("spread", "letter", 0.8, delay=1.0)),
    ])
    add("perspective-roll", "Perspective", ["perspective", "warp", "cinema", "epic"], [
        text("EPIC", 0, 180, "anton", 170, "#1F2937", warp={"kind": "perspective", "amount": 35},
             animation=anim("roll", "letter", 1.0)),
        text("coming this winter", 186, 36, "oswald", 32, "#4B5563", spacing=4,
             animation=anim("fade", duration=0.8, delay=1.0)),
    ])
    add("squeeze-merge", "Squeeze", ["squeeze", "warp", "juice", "drink"], [
        text("Squeeze", 0, 170, "righteous", 140, "#EA580C", warp={"kind": "squeeze", "amount": 40},
             animation=anim("merge", "letter", 1.0)),
        text("fresh juice bar", 176, 36, "nunito", 32, "#9A3412", weight=800,
             animation=anim("pop", duration=0.5, delay=1.0)),
    ])
    add("slide-sale", "Slide sale", ["sale", "slide", "discount"], [
        panel(860, 300, "#FEE2E2"),
        text("50% OFF", 40, 50, "anton", 140, "#B91C1C", w=780, spacing=2,
             animation=anim("slideRight", duration=0.7)),
        text("everything must go", 40, 206, "poppins", 34, "#7F1D1D", w=780, weight=600,
             animation=anim("slideLeft", duration=0.7, delay=0.4)),
    ])
    add("wipe-title", "Wipe title", ["wipe", "film", "title", "reveal"], [
        text("CHAPTER ONE", 0, 130, "playfair-display", 100, "#111827", weight=700, spacing=4,
             animation=anim("wipe", duration=1.0), exitAnimation=anim("wipe", duration=0.6)),
        text("The beginning", 140, 40, "playfair-display", 36, "#6B7280", italic=True,
             animation=anim("fade", duration=0.8, delay=1.0)),
    ])
    add("breathe-quote", "Breathe", ["breathe", "calm", "wellness", "yoga"], [
        text("breathe in\nbreathe out", 0, 230, "raleway", 90, "#0F766E", weight=300, line=1.25,
             animation=anim("breathe", duration=3.0)),
    ])
    add("pulse-live", "Live now", ["live", "pulse", "stream"], [
        panel(860, 260, "#DC2626", 130),
        text("● LIVE NOW", 40, 70, "montserrat", 96, "#FFFFFF", w=780, weight=800, spacing=4,
             animation=anim("pulse", duration=1.2)),
    ])
    add("wiggle-hello", "Wiggle hello", ["hello", "wiggle", "greeting", "kids"], [
        text("hello!", 0, 170, "pacifico", 150, "#F59E0B", curve=-30,
             animation=anim("wiggle", duration=1.0)),
        text("nice to see you", 176, 40, "patrick-hand", 40, "#92400E",
             animation=anim("typewriter", "letter", 1.0, delay=0.6)),
    ])
    add("countdown", "Countdown", ["countdown", "new year", "event", "timer"], [
        text("3 · 2 · 1", 0, 150, "bebas-neue", 160, "#4F46E5", spacing=10,
             animation=anim("words", "word", 1.5)),
        text("HAPPY NEW YEAR", 160, 44, "montserrat", 40, "#312E81", weight=800, spacing=8,
             animation=anim("burst", "letter", 1.0, delay=1.5), effect={"type": "neon"}),
    ])
    return out


def curved():
    """12 more curved or warped headlines in the existing categories."""
    return [
        combo("arched-headline", "Arched headline", ["arch", "warp", "headline", "bold"], "Headline", 860, [
            text("HEADLINE", 0, 170, "anton", 150, "#111827", spacing=4, warp={"kind": "arch", "amount": 40}),
            text("a story worth the top of the page", 180, 34, "lora", 30, "#4B5563"),
        ]),
        combo("bulging-news", "Bulging news", ["bulge", "warp", "news", "headline"], "Headline", 860, [
            text("HOT NEWS", 0, 170, "bungee", 130, "#DC2626", warp={"kind": "bulge", "amount": 35}),
        ]),
        combo("curved-sale", "Curved sale", ["curve", "sale", "offer"], "Sale", 860, [
            text("limited offer", 0, 150, "pacifico", 100, "#DB2777", curve=50),
            text("UP TO 70% OFF", 160, 60, "anton", 64, "#831843", spacing=4),
        ]),
        combo("flag-sale", "Waving sale", ["flag", "warp", "sale", "summer"], "Sale", 860, [
            text("SUMMER SALE", 0, 170, "bebas-neue", 150, "#0284C7", spacing=6, warp={"kind": "flag", "amount": 45}),
        ]),
        combo("arched-quote", "Arched quote", ["curve", "quote", "inspiration"], "Quote", 860, [
            text("dream big", 0, 160, "dancing-script", 130, "#7C3AED", weight=700, curve=35),
            text("and start small", 170, 40, "raleway", 34, "#4C1D95", weight=500),
        ]),
        combo("curved-invite", "Curved invite", ["curve", "event", "invite", "party"], "Event", 860, [
            text("you're invited", 0, 150, "satisfy", 110, "#B45309", curve=40),
            text("SATURDAY · 7 PM", 160, 40, "montserrat", 34, "#78350F", weight=700, spacing=6),
        ]),
        combo("arched-vows", "Arched vows", ["curve", "wedding", "love"], "Wedding", 860, [
            text("forever & always", 0, 150, "sacramento", 110, "#9F1239", curve=45),
            text("ANNA & JAMES", 160, 40, "playfair-display", 34, "#4C0519", spacing=8),
        ]),
        combo("rising-social", "Rising post", ["rise", "warp", "social", "post"], "Social", 860, [
            text("NEW POST", 0, 160, "montserrat", 130, "#2563EB", weight=900, warp={"kind": "rise", "amount": 40}),
            text("link in bio", 170, 40, "poppins", 34, "#1E40AF", weight=600),
        ]),
        combo("retro-arch", "Retro arch", ["arch", "warp", "retro", "70s"], "Retro", 880, [
            text("FAR OUT", 0, 180, "righteous", 150, "#EA580C", warp={"kind": "arch", "amount": 55},
                 textFill={"kind": "gradient", "angle": 90, "stops": [{"offset": 0, "color": "#F59E0B"},
                                                                     {"offset": 1, "color": "#DB2777"}]}),
        ]),
        combo("minimal-curve", "Minimal curve", ["curve", "minimal", "clean"], "Minimal", 860, [
            text("less is more", 0, 120, "dm-sans", 90, "#111827", weight=500, curve=20),
        ]),
        combo("badge-ring", "Ring badge", ["curve", "badge", "circle", "stamp"], "Badge", 860, [
            {"type": "shape", "shapeId": "circle", "x": 280, "y": 0, "w": 300, "h": 300,
             "fill": {"kind": "solid", "color": "#FEF3C7"}, "radius": 0},
            text("HANDMADE WITH CARE", 0, 20, "oswald", 44, "#92400E", spacing=6, curve=160),
            text("est. 2026", 0, 130, "dancing-script", 56, "#78350F", weight=700),
        ]),
        combo("kids-squeeze", "Squeezy fun", ["squeeze", "warp", "kids", "fun"], "Kids", 860, [
            text("SILLY TIME", 0, 170, "bungee", 130, "#16A34A", warp={"kind": "squeeze", "amount": 35}),
            text("games · snacks · giggles", 176, 40, "nunito", 34, "#14532D", weight=800),
        ]),
    ]


def main():
    with open(OUT, encoding="utf-8") as f:
        existing = json.load(f)
    added = animated() + curved()
    ids = {c["id"] for c in added}
    assert len(ids) == len(added), "an id twice"
    kept = [c for c in existing if c["id"] not in ids]
    assert not ids & {c["id"] for c in kept}
    for c in added:
        for el in c["elements"]:
            for key in ("animation", "exitAnimation"):
                if key in el:
                    assert el[key]["kind"] in TEXT_KINDS + WHOLE_KINDS, el[key]["kind"]
    entries = kept + added
    body = "[\n" + ",\n".join(json.dumps(c, separators=(",", ":"), ensure_ascii=False) for c in entries) + "\n]\n"
    with open(OUT, "w", encoding="utf-8") as f:
        f.write(body)
    print(f"{len(entries)} combinations, {len(added)} from this round, to {OUT}")


if __name__ == "__main__":
    main()
