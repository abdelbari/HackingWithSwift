#!/usr/bin/env python3
"""Write the font combinations both phones offer in Add > Text.

    tools/generate_textcombos.py [path/to/ios/staging]

Writes core/src/main/resources/com/canvia/core/content/textcombos.json — and,
given a folder, the same bytes there as textcombos.json with textcombos.txt
saying what it holds, for the iOS twin to bundle — so a combination is the
same elements on both phones.

The file is a list of combinations, one a line:

    {"id", "name", "tags": [...], "category", "w": <width>, "elements": [...]}

the category one of Headline, Sale, Quote, Event, Wedding, Social, Retro,
Minimal, Badge, Kids and Animated, the chips Add > Text browses them by.
An Animated one's texts carry the design file's `animation` — {kind, delay,
duration} and `by` (letter, word or line) for a kind that moves units one
by one — and some an `exitAnimation`, every kind one ElementAnimation
knows; some of them, and twelve in the other categories, are bent by a
`warp` ({kind, amount}) or a curve.

each element in the iOS twin's JSON, as a design file has it, placed in a box
`w` wide from 0, 0 in a 1080-wide page's units — every one with its x, y, w
and h, and a text with its font, size, weight, alignment, line height,
spacing and colour written out, so neither phone falls back on a default of
its own. The box is as tall as its lowest element reaches. The first six
are the six font pairings the Text tab always had (Themes.pairings), each a
heading over a line of body text, 14 apart.
"""
import json
import math
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/textcombos.json'

INK = '#1f2430'
GREY = '#6B7280'


def num(v):
    """A whole number as one, anything else to two places — the file's
    numbers as both phones' decoders read them; None — a width the box
    fills in — as it is."""
    if v is None:
        return None
    r = round(v, 2)
    return int(r) if r == int(r) else r


def text(words, y, size, font, weight=400, x=0, w=None, color=INK, align='center', lh=1.2, ls=0, lines=None, h=None, **more):
    """A text box, as tall as its lines of type: the count of written lines
    unless [lines] says it wraps to more."""
    count = lines or words.count('\n') + 1
    el = {
        'type': 'text', 'text': words, 'x': num(x), 'y': num(y), 'w': num(w), 'h': num(h or math.ceil(size * lh * count)),
        'fontFamily': font, 'fontSize': num(size), 'fontWeight': weight, 'align': align,
        'lineHeight': lh, 'letterSpacing': num(ls), 'color': color,
    }
    el.update(more)
    return el


def shape(shape_id, x, y, w, h, fill, radius=0, **more):
    el = {'type': 'shape', 'shapeId': shape_id, 'x': num(x), 'y': num(y), 'w': num(w), 'h': num(h), 'fill': {'kind': 'solid', 'color': fill}, 'radius': num(radius)}
    el.update(more)
    return el


def line(x, y, w, thickness, color, dash='solid'):
    """A rule, its box as tall as the iPhone gives one: its thickness, never
    under 8."""
    return {'type': 'line', 'x': num(x), 'y': num(y), 'w': num(w), 'h': num(max(8, thickness)), 'thickness': num(thickness), 'color': color, 'dash': dash}


def gradient(angle, a, b):
    return {'kind': 'gradient', 'angle': angle, 'stops': [{'offset': 0, 'color': a}, {'offset': 1, 'color': b}]}


def spans(words, start, end, **look):
    """Words [start, end) of the box's text given a look of their own."""
    return {'spans': [dict({'start': start, 'end': end}, **look)], 'spansText': words}


def stacked(w, parts):
    """[parts] — (gap above, element maker taking its y) — one under the
    other, each full width unless it says otherwise."""
    out, y = [], 0
    for gap, make in parts:
        y += gap
        el = make(y)
        if el.get('w') is None:
            el['w'] = num(w)
        out.append(el)
        y = el['y'] + el['h']
    return out


CATEGORIES = ['Headline', 'Sale', 'Quote', 'Event', 'Wedding', 'Social', 'Retro', 'Minimal', 'Badge', 'Kids', 'Animated']

# The first thirty's categories; every one after names its own.
FIRST = {
    'editorial': 'Headline', 'poster': 'Headline', 'technical': 'Minimal', 'playful': 'Kids', 'luxury': 'Wedding',
    'minimal': 'Minimal', 'mega-sale': 'Sale', 'wedding-invitation': 'Wedding', 'quote': 'Quote', 'grand-opening': 'Event',
    'happy-birthday': 'Kids', 'webinar': 'Event', 'summer-vibes': 'Social', 'breaking-news': 'Headline', 'coffee-house': 'Badge',
    'thank-you': 'Social', 'neon-night': 'Retro', 'creative-workshop': 'Event', 'new-collection': 'Headline',
    'podcast-episode': 'Social', 'open-house': 'Event', 'train-harder': 'Social', 'black-friday': 'Sale', 'recipe-card': 'Headline',
    'merry-christmas': 'Event', 'explore-iceland': 'Social', 'baby-shower': 'Kids', 'dont-stop': 'Quote',
    'product-launch': 'Headline', 'halloween-party': 'Event',
}


def combo(cid, name, tags, w, elements, category=None):
    for el in elements:
        if el.get('w') is None:
            el['w'] = num(w)
    category = category or FIRST[cid]
    assert category in CATEGORIES, cid
    return {'id': cid, 'name': name, 'tags': tags, 'category': category, 'w': num(w), 'elements': elements}


def pairing(cid, name, tags, heading, body):
    """One of the six pairings: heading over body, as Add > Text set them —
    72% of a 1080 page wide, centred, 14 between."""
    w = 780
    hf, hw, hs, hl, ht = heading
    bf, bw, bs, bl, bt = body
    return combo(cid, name, tags, w, stacked(w, [
        (0, lambda y: text(ht, y, hs, hf, hw, ls=hl, lh=1.25)),
        (14, lambda y: text(bt, y, bs, bf, bw, ls=bl, lh=1.25)),
    ]))


def centred_on(box_x, box_w, w):
    return box_x + (box_w - w) / 2


def build():
    combos = [
        pairing('editorial', 'Editorial', ['magazine', 'serif', 'classic', 'story', 'blog'],
                ('didone', 700, 88, -1, 'The Quiet Issue'), ('serif', 400, 28, 0, 'Stories worth lingering over, told in full.')),
        pairing('poster', 'Poster', ['event', 'concert', 'bold', 'night', 'gig'],
                ('impact', 800, 110, 2, 'LOUD & CLEAR'), ('condensed', 500, 30, 1, 'One night only. Doors open at eight.')),
        pairing('technical', 'Technical', ['tech', 'code', 'startup', 'software'],
                ('grotesk', 600, 72, 0, 'System Online'), ('mono', 400, 24, 0.5, 'Precision in every line of the build.')),
        pairing('playful', 'Playful', ['fun', 'party', 'kids', 'friendly'],
                ('rounded', 700, 84, 0, 'Hello, Sunshine!'), ('humanist', 400, 28, 0.25, 'Bring snacks, good vibes, and your best ideas.')),
        pairing('luxury', 'Luxury', ['elegant', 'gold', 'boutique', 'invitation'],
                ('elegant', 500, 80, 4, 'Maison Doree'), ('script', 400, 30, 0.5, 'An evening of rare and beautiful things.')),
        pairing('minimal', 'Minimal', ['simple', 'clean', 'modern'],
                ('sans', 300, 68, 6, 'less is more'), ('slab', 400, 24, 0.5, "Everything you need. Nothing you don't.")),
    ]

    # Sale: the second word in its own colour, an offer on a bar.
    w = 900
    els = [text('MEGA SALE', 0, 150, 'anton', 400, ls=4, lh=1.0, color='#E11D48', effect={'type': 'lift'}, **spans('MEGA SALE', 5, 9, color='#111827'))]
    els.append(shape('rect', 150, 174, 600, 84, '#FACC15', radius=42))
    els.append(text('UP TO 50% OFF', 174 + (84 - 53) / 2, 44, 'montserrat', 800, x=150, w=600, ls=3, color='#111827'))
    els.append(text('Online and in store this weekend', 282, 26, 'montserrat', 500, color='#374151'))
    combos.append(combo('mega-sale', 'Mega sale', ['sale', 'shop', 'discount', 'promo', 'offer'], w, els))

    w = 860
    combos.append(combo('wedding-invitation', 'Wedding invitation', ['wedding', 'invitation', 'love', 'marriage', 'save the date', 'elegant'], w, stacked(w, [
        (0, lambda y: text('Save the date', y, 28, 'montserrat', 300, ls=12, color=GREY, uppercase=True)),
        (12, lambda y: text('Emma & James', y, 140, 'sacramento', 400, color='#B45309', lh=1.1)),
        (8, lambda y: line(330, y, 200, 2, '#D1A054')),
        (16, lambda y: text('06 . 21 . 2027', y, 40, 'playfair-display', 500, ls=6)),
        (10, lambda y: text('The Grand Orangery, Bath', y, 26, 'lora', 400, color=GREY, italic=True)),
    ])))

    w = 860
    combos.append(combo('quote', 'Quote', ['quote', 'inspiration', 'words', 'testimonial'], w, stacked(w, [
        (0, lambda y: text('“', y, 220, 'playfair-display', 900, color='#F59E0B', lh=0.8)),
        (0, lambda y: text('Small steps every day add up to\nbig changes.', y, 46, 'lora', 400, lh=1.3, italic=True)),
        (24, lambda y: line(390, y, 80, 3, '#F59E0B')),
        (16, lambda y: text('AVA REYNOLDS', y, 22, 'montserrat', 600, ls=6, color=GREY)),
    ])))

    w = 820
    combos.append(combo('grand-opening', 'Grand opening', ['opening', 'launch', 'shop', 'store', 'event', 'new'], w, stacked(w, [
        (0, lambda y: text('GRAND', y, 64, 'oswald', 300, ls=40, color='#0F766E', lh=1.1)),
        (0, lambda y: text('OPENING', y, 150, 'oswald', 700, ls=2, color='#0F172A', lh=1.0)),
        (16, lambda y: line(0, y, 820, 3, '#0F766E')),
        (14, lambda y: text('Saturday 10 am · 12 Market Street', y, 30, 'oswald', 400, ls=2, color='#334155')),
    ])))

    w = 880
    combos.append(combo('happy-birthday', 'Happy birthday', ['birthday', 'party', 'celebration', 'invitation', 'kids'], w, stacked(w, [
        (0, lambda y: text('Happy', y, 110, 'pacifico', 400, color='#EC4899', lh=1.3, rotation=-4)),
        (0, lambda y: text('BIRTHDAY', y, 120, 'poppins', 900, ls=4, lh=1.05, color='#F97316', textFill=gradient(90, '#F97316', '#EC4899'))),
        (12, lambda y: text("Let's celebrate, Saturday at 4", y, 30, 'poppins', 500, color=GREY)),
    ])))

    # A label on a pill, then the title and when.
    w = 900
    els = [shape('rect', 300, 0, 300, 64, '#2563EB', radius=32)]
    els.append(text('LIVE WEBINAR', (64 - 32) / 2, 26, 'dm-sans', 700, x=300, w=300, ls=5, color='#FFFFFF', h=32))
    els += stacked(w, [
        (88, lambda y: text('Design systems\nthat scale', y, 84, 'dm-sans', 800, lh=1.05, color='#0F172A')),
        (16, lambda y: text('Thursday · 3 pm GMT · Free', y, 30, 'dm-sans', 400, color='#475569')),
    ])
    combos.append(combo('webinar', 'Webinar', ['webinar', 'business', 'online', 'event', 'tech', 'talk'], w, els))

    # The sun behind the curved word.
    w = 860
    els = [shape('circle', 330, 0, 200, 200, '#FDE68A')]
    els += stacked(w, [
        (60, lambda y: text('summer', y, 120, 'pacifico', 400, color='#F97316', lh=1.3, curve=40)),
        (0, lambda y: text('VIBES', y, 160, 'bebas-neue', 400, ls=18, lh=1.0, color='#F97316', textFill=gradient(90, '#F97316', '#DB2777'))),
        (12, lambda y: text('Sun, sea and good company', y, 28, 'poppins', 400, color=GREY)),
    ])
    combos.append(combo('summer-vibes', 'Summer vibes', ['summer', 'holiday', 'travel', 'beach', 'sun', 'vacation'], w, els))

    # Set from the left, under a red tab.
    w = 900
    els = [shape('rect', 0, 0, 260, 60, '#DC2626')]
    els.append(text('BREAKING', (60 - 36) / 2, 30, 'roboto', 900, w=260, ls=4, color='#FFFFFF', h=36))
    els += stacked(w, [
        (80, lambda y: text('Big news is coming', y, 82, 'roboto-slab', 800, align='left', lh=1.1, color='#111827')),
        (16, lambda y: line(0, y, 900, 4, '#DC2626')),
        (16, lambda y: text('Stay tuned for the full story on Friday', y, 32, 'roboto', 300, align='left', color='#374151')),
    ])
    combos.append(combo('breaking-news', 'Breaking news', ['news', 'announcement', 'alert', 'update'], w, els))

    w = 820
    combos.append(combo('coffee-house', 'Coffee house', ['menu', 'cafe', 'coffee', 'food', 'restaurant', 'shop'], w, stacked(w, [
        (0, lambda y: text('· FRESHLY ROASTED ·', y, 26, 'raleway', 600, w=520, x=150, ls=8, color='#92400E', curve=60, h=70)),
        (8, lambda y: text('Coffee House', y, 108, 'abril-fatface', 400, color='#451A03', lh=1.15)),
        (10, lambda y: line(310, y, 200, 2, '#92400E')),
        (14, lambda y: text('Open daily from 7 am', y, 30, 'raleway', 300, ls=2, color='#78350F')),
    ])))

    w = 820
    combos.append(combo('thank-you', 'Thank you', ['thanks', 'thank you', 'gratitude', 'card', 'order'], w, stacked(w, [
        (0, lambda y: text('Thank you', y, 140, 'dancing-script', 700, color='#0F766E', lh=1.15)),
        (6, lambda y: text('FOR YOUR ORDER', y, 28, 'raleway', 500, ls=14, color='#334155')),
        (18, lambda y: shape('heart', 390, y, 40, 36, '#F43F5E')),
    ])))

    # Neon on a dark panel.
    w = 860
    els = [shape('rect', 0, 0, 860, 360, '#0B1026', radius=28)]
    els.append(text('Night Club', 80, 110, 'righteous', 400, x=40, w=780, color='#F472B6', lh=1.2, effect={'type': 'neon'}))
    els.append(text('FRIDAY · 10 PM', 236, 30, 'space-mono', 700, x=40, w=780, ls=8, color='#67E8F9'))
    combos.append(combo('neon-night', 'Neon night', ['neon', 'party', 'night', 'club', 'music', 'dj'], w, els))

    w = 900
    combos.append(combo('creative-workshop', 'Creative workshop', ['workshop', 'class', 'education', 'learn', 'course', 'art'], w, stacked(w, [
        (0, lambda y: text('Creative', y, 96, 'dm-serif-display', 400, color='#7C3AED', lh=1.15, italic=True)),
        (0, lambda y: text('WORKSHOP', y, 110, 'montserrat', 900, ls=6, lh=1.1, effect={'type': 'outline'})),
        (14, lambda y: text('Learn the basics in one afternoon', y, 28, 'montserrat', 400, color='#4B5563')),
    ])))

    w = 860
    combos.append(combo('new-collection', 'New collection', ['fashion', 'collection', 'shop', 'new', 'style', 'autumn'], w, stacked(w, [
        (0, lambda y: text('New', y, 200, 'playfair-display', 900, lh=1.0, italic=True)),
        (4, lambda y: text('COLLECTION', y, 44, 'raleway', 300, ls=22)),
        (14, lambda y: text('Autumn / Winter 2027', y, 24, 'raleway', 500, ls=4, color=GREY)),
    ])))

    w = 880
    els = [shape('rect', 320, 0, 240, 56, '#111827', radius=28)]
    els.append(text('EPISODE 12', (56 - 29) / 2, 24, 'space-grotesk', 700, x=320, w=240, ls=4, color='#FFFFFF', h=29))
    els += stacked(w, [
        (76, lambda y: text('The Creative Hour', y, 84, 'space-grotesk', 600, lh=1.1, color='#111827')),
        (10, lambda y: text('with Sam Rivera', y, 34, 'space-grotesk', 300, color=GREY)),
    ])
    combos.append(combo('podcast-episode', 'Podcast episode', ['podcast', 'episode', 'audio', 'show', 'interview'], w, els))

    w = 860
    combos.append(combo('open-house', 'Open house', ['real estate', 'house', 'home', 'property', 'open house'], w, stacked(w, [
        (0, lambda y: text('OPEN HOUSE', y, 104, 'lato', 900, ls=2, lh=1.1, color='#1E3A8A')),
        (10, lambda y: line(0, y, 860, 3, '#F59E0B')),
        (16, lambda y: text('Sunday 1–4 pm', y, 40, 'lato', 300)),
        (8, lambda y: text('12 Maple Lane', y, 30, 'lato', 700, ls=3, color='#1E3A8A', uppercase=True)),
    ])))

    w = 820
    combos.append(combo('train-harder', 'Train harder', ['fitness', 'gym', 'sport', 'workout', 'health'], w, stacked(w, [
        (0, lambda y: text('TRAIN', y, 170, 'anton', 400, ls=6, lh=1.0, color='#111827', italic=True)),
        (0, lambda y: text('HARDER', y, 170, 'anton', 400, ls=6, lh=1.0, color='#EF4444', italic=True, effect={'type': 'splice'})),
        (16, lambda y: text('30-day challenge starts Monday', y, 32, 'oswald', 500, ls=2, color='#374151')),
    ])))

    # Gold letters on black.
    w = 860
    els = [shape('rect', 0, 0, 860, 440, '#000000')]
    els.append(text('BLACK', 40, 150, 'bebas-neue', 400, x=40, w=780, ls=12, lh=1.0, color='#FFFFFF'))
    els.append(text('FRIDAY', 190, 150, 'bebas-neue', 400, x=40, w=780, ls=12, lh=1.0, color='#FDE68A', textFill=gradient(180, '#FDE68A', '#D97706')))
    els.append(text('Deals end Monday at midnight', 362, 28, 'roboto', 500, x=40, w=780, color='#E5E7EB'))
    combos.append(combo('black-friday', 'Black Friday', ['sale', 'black friday', 'shop', 'deal', 'discount'], w, els))

    w = 860
    combos.append(combo('recipe-card', 'Recipe card', ['recipe', 'food', 'cooking', 'kitchen', 'menu'], w, stacked(w, [
        (0, lambda y: text("Grandma's", y, 72, 'caveat', 700, color='#B45309', lh=1.2, rotation=-4)),
        (0, lambda y: text('Apple Pie', y, 120, 'playfair-display', 900, lh=1.1, **spans('Apple Pie', 6, 9, color='#B91C1C'))),
        (12, lambda y: text('Serves 8 · 1 hour · Easy', y, 30, 'nunito', 600, color=GREY)),
    ])))

    # Two small stars beside the word.
    w = 860
    els = stacked(w, [
        (0, lambda y: text('Merry', y, 120, 'dancing-script', 700, color='#B91C1C', lh=1.15)),
        (0, lambda y: text('CHRISTMAS', y, 76, 'playfair-display', 600, ls=14, lh=1.2, color='#166534')),
        (12, lambda y: text('and a happy new year', y, 32, 'crimson-text', 400, color='#4B5563', italic=True)),
    ])
    star_y = els[1]['y'] + (els[1]['h'] - 50) / 2
    els += [shape('star-4', 40, star_y, 50, 50, '#CA8A04'), shape('star-4', 770, star_y, 50, 50, '#CA8A04')]
    combos.append(combo('merry-christmas', 'Merry Christmas', ['christmas', 'holiday', 'winter', 'season', 'card', 'greetings'], w, els))

    w = 900
    combos.append(combo('explore-iceland', 'Explore Iceland', ['travel', 'adventure', 'trip', 'explore', 'holiday'], w, stacked(w, [
        (0, lambda y: text('explore', y, 90, 'caveat', 400, color='#0EA5E9', lh=1.2, rotation=-6)),
        (0, lambda y: text('ICELAND', y, 150, 'montserrat', 900, ls=8, lh=1.05, color='#0EA5E9', textFill=gradient(90, '#0EA5E9', '#1E3A8A'))),
        (12, lambda y: text('7 days · 4 glaciers · 1 road trip', y, 26, 'montserrat', 500, ls=2, color='#475569')),
    ])))

    # Confetti dots round the words.
    w = 820
    els = stacked(w, [
        (0, lambda y: text('Oh baby!', y, 110, 'pacifico', 400, color='#F472B6', lh=1.3)),
        (6, lambda y: text('BABY SHOWER FOR EMMA', y, 34, 'nunito', 800, ls=6, color='#0F766E')),
        (10, lambda y: text('June 14 · 2 pm · Garden party', y, 28, 'nunito', 300, color=GREY)),
    ])
    els += [shape('circle', 60, 30, 28, 28, '#FDE68A'), shape('circle', 740, 96, 22, 22, '#A7F3D0'), shape('circle', 700, 10, 16, 16, '#F9A8D4')]
    combos.append(combo('baby-shower', 'Baby shower', ['baby', 'shower', 'party', 'celebration', 'invitation'], w, els))

    w = 860
    combos.append(combo('dont-stop', "Don't stop", ['motivation', 'quote', 'inspiration', 'monday', 'goals'], w, stacked(w, [
        (0, lambda y: text("DON'T STOP", y, 110, 'oswald', 600, ls=3, lh=1.15, color='#111827', effect={'type': 'highlight', 'color': '#FDE047'})),
        (4, lambda y: text("until you're proud", y, 80, 'dancing-script', 700, color='#7C3AED', lh=1.2, rotation=-3)),
        (12, lambda y: text('— Monday mood', y, 24, 'raleway', 500, ls=4, color=GREY)),
    ])))

    w = 880
    els = stacked(w, [
        (0, lambda y: text('Introducing', y, 44, 'poppins', 300, color=GREY)),
        (0, lambda y: text('Nova One', y, 128, 'poppins', 800, ls=-2, lh=1.1, color='#111827')),
    ])
    pill_y = els[-1]['y'] + els[-1]['h'] + 18
    els.append(shape('rect', 290, pill_y, 300, 64, '#111827', radius=32))
    els.append(text('Available now', pill_y + (64 - 32) / 2, 26, 'poppins', 600, x=290, w=300, ls=2, color='#FFFFFF', h=32))
    combos.append(combo('product-launch', 'Product launch', ['launch', 'product', 'tech', 'startup', 'announcement', 'new'], w, els))

    w = 880
    combos.append(combo('halloween-party', 'Halloween party', ['halloween', 'party', 'spooky', 'october', 'costume'], w, stacked(w, [
        (0, lambda y: text('HALLOWEEN', y, 100, 'alfa-slab-one', 400, lh=1.15, color='#EA580C', effect={'type': 'echo', 'color': '#7C2D12'})),
        (0, lambda y: text('PARTY', y, 90, 'bebas-neue', 400, ls=30, lh=1.05)),
        (10, lambda y: text('Costumes required', y, 34, 'permanent-marker', 400, color='#7C3AED')),
    ])))
    return combos + more() + shaped() + animated()


# How wide a letter of each face runs, in ems, roughly — enough to set a
# line's size so it stays one line in its box.
EM = {
    'anton': 0.47, 'bebas-neue': 0.4, 'oswald': 0.5, 'abril-fatface': 0.62, 'alfa-slab-one': 0.72, 'bungee': 0.82,
    'righteous': 0.62, 'pacifico': 0.62, 'sacramento': 0.42, 'dancing-script': 0.48, 'satisfy': 0.5, 'caveat': 0.45,
    'indie-flower': 0.55, 'shadows-into-light': 0.5, 'permanent-marker': 0.62, 'patrick-hand': 0.48,
    'space-mono': 0.62, 'roboto-mono': 0.6, 'jetbrains-mono': 0.6, 'ibm-plex-mono': 0.6, 'playfair-display': 0.56,
    'dm-serif-display': 0.55, 'libre-baskerville': 0.62, 'lora': 0.56, 'crimson-text': 0.5, 'pt-serif': 0.56,
    'roboto-slab': 0.6, 'montserrat': 0.64, 'poppins': 0.62, 'raleway': 0.58, 'nunito': 0.56, 'lato': 0.56,
    'dm-sans': 0.58, 'karla': 0.56, 'space-grotesk': 0.6, 'roboto': 0.56, 'open-sans': 0.58,
}


def fit(words, w, font, size, ls=0, caps=False):
    """[size], or less, so the longest line of [words] fits [w] — a little
    room spare, letter spacing counted."""
    n = max(len(line) for line in words.split('\n'))
    em = EM.get(font, 0.6) * (1.18 if caps or words == words.upper() else 1.0)
    most = (w * 0.9 - n * ls) / (n * em)
    return min(size, max(12, math.floor(most)))


def part(words, font, size, weight=400, color=INK, gap=0, ls=0, lh=None, w=None, x=0, **more):
    """One line of a stack: fitted to its width, [gap] under the one above."""
    def make(y, width):
        box = w or width
        sized = fit(words, box, font, size, ls, more.get('uppercase', False))
        return text(words, y, sized, font, weight, x=x, w=box, color=color, ls=ls, lh=lh or (1.1 if sized >= 80 else 1.2), **more)
    return gap, make


def rule(w, thickness, color, gap=14, x=None, width=None):
    def make(y, box):
        span = width or box * 0.25
        return line(x if x is not None else (box - span) / 2, y, span, thickness, color)
    return gap, make


def stack(w, parts):
    return stacked(w, [(gap, (lambda make: lambda y: make(y, w))(make)) for gap, make in parts])


def trio(cid, name, category, tags, w, parts):
    return combo(cid, name, tags, w, stack(w, parts), category)


def labelled(cid, name, category, tags, w, label, label_font, fill, ink, parts, pill=None):
    """A label on a pill over the words, as the webinar has."""
    pw = pill or min(w, 60 + len(label) * 20)
    els = [shape('rect', (w - pw) / 2, 0, pw, 60, fill, radius=30)]
    els.append(text(label, (60 - 30) / 2, 24, label_font, 700, x=(w - pw) / 2, w=pw, ls=4, color=ink, h=30))
    body = stack(w, parts)
    for el in body:
        el['y'] = num(el['y'] + 84)
    return combo(cid, name, tags, w, els + body, category)


def panel(cid, name, category, tags, w, fill, parts, radius=24, pad=48):
    """Words on a panel of colour, inset by [pad]."""
    inner = w - 2 * pad
    body = stack(inner, parts)
    for el in body:
        el['x'] = num(el['x'] + pad)
        el['y'] = num(el['y'] + pad)
    h = body[-1]['y'] + body[-1]['h'] + pad
    return combo(cid, name, tags, w, [shape('rect', 0, 0, w, num(h), fill, radius=radius)] + body, category)


def badge(cid, name, tags, d, fill, top, big, bottom, ink='#FFFFFF', ring=None):
    """A round badge [d] across: a small line, a big one and a small one,
    centred in it."""
    els = [shape('circle', 0, 0, d, d, fill)]
    if ring:
        els.append(shape('circle', d * 0.06, d * 0.06, d * 0.88, d * 0.88, fill, stroke=ring, strokeWidth=4))
    inner = d * 0.7
    body = stack(inner, [
        part(top[0], top[1], top[2], top[3], ink, ls=4),
        part(big[0], big[1], big[2], big[3], ink, gap=4),
        part(bottom[0], bottom[1], bottom[2], bottom[3], ink, gap=4, ls=3),
    ])
    tall = body[-1]['y'] + body[-1]['h']
    for el in body:
        el['x'] = num(el['x'] + (d - inner) / 2)
        el['y'] = num(el['y'] + (d - tall) / 2)
    return combo(cid, name, tags, d, els + body, 'Badge')


def anim(kind, by=None, delay=0, duration=0.8):
    """An element's `animation` (or `exitAnimation`), as ElementAnimation
    keeps it: {kind, delay, duration}, and `by` — letter, word or line —
    for a text kind that moves its units one by one."""
    out = {'kind': kind, 'delay': num(delay), 'duration': num(duration)}
    if by:
        out['by'] = by
    return out


def warp(kind, amount):
    """A text's `warp` preset (TextWarp): arch, bulge, flag, squeeze, rise
    or perspective, amount -100…100."""
    return {'kind': kind, 'amount': amount}


def animated():
    """The thirty-six of the Animated category: each text arrives moving —
    typed, word by word, popped, risen, burst — some with a neon, glitch or
    echo effect, a curve or a warp, a few looping, a few leaving as they
    came. Every kind is one ElementAnimation knows."""
    out = []
    add = out.append
    A = 'Animated'
    add(trio('typed-hello', 'Typed hello', A, ['typewriter', 'typing', 'hello', 'animated', 'intro'], 840, [
        part('Hello, world', 'space-mono', 110, 700, '#111827', animation=anim('typewriter', 'letter', 0, 1.6)),
        part('a story begins here', 'space-mono', 34, 400, GREY, gap=12, animation=anim('fade', None, 1.6, 0.6)),
    ]))
    add(trio('word-by-word', 'Word by word', A, ['words', 'reveal', 'animated', 'message'], 860, [
        part('Words that land', 'poppins', 110, 800, '#111827', animation=anim('words', 'word', 0, 1.2)),
        part('one at a time', 'poppins', 36, 400, GREY, gap=12, animation=anim('rise', None, 1.0, 0.6)),
    ]))
    add(trio('letter-pop-party', 'Party pop', A, ['party', 'pop', 'celebrate', 'animated', 'fun'], 840, [
        part('PARTY!', 'bungee', 170, 400, '#DB2777', ls=4, lh=1.0, animation=anim('letterPop', 'letter', 0, 1.0)),
        part('Tonight from 9 pm', 'nunito', 40, 700, '#4B5563', gap=12, animation=anim('rise', None, 0.8, 0.6)),
    ]))
    add(trio('line-by-line', 'Line by line', A, ['lines', 'story', 'rise', 'animated', 'poem'], 820, [
        part('Slow mornings\nwarm coffee\nlong walks', 'lora', 70, 400, '#1F2937', lh=1.25, animation=anim('lineRise', 'line', 0, 1.4)),
    ]))
    add(trio('ascending-title', 'Ascending title', A, ['ascend', 'title', 'rise', 'animated', 'headline'], 880, [
        part('ASCEND', 'oswald', 170, 700, '#0F172A', ls=10, lh=1.0, animation=anim('ascend', 'letter', 0, 1.0)),
        part('new heights this season', 'raleway', 32, 500, GREY, gap=14, ls=4, animation=anim('fade', None, 0.9, 0.6)),
    ]))
    add(trio('shift-in', 'Shift in', A, ['shift', 'slide', 'modern', 'animated'], 860, [
        part('Shift your thinking', 'space-grotesk', 92, 700, '#1D4ED8', ls=-1, animation=anim('shift', 'word', 0, 1.0)),
    ]))
    add(trio('merge-logo', 'Merge', A, ['merge', 'logo', 'brand', 'animated', 'intro'], 820, [
        part('STUDIO', 'montserrat', 140, 900, '#111827', ls=14, lh=1.0, animation=anim('merge', 'letter', 0, 1.2)),
        part('design & motion', 'montserrat', 30, 500, '#6366F1', gap=14, ls=6, animation=anim('fade', None, 1.1, 0.6)),
    ]))
    add(trio('block-reveal', 'Block reveal', A, ['block', 'reveal', 'bold', 'animated', 'news'], 880, [
        part('BIG NEWS', 'anton', 170, 400, '#E11D48', ls=4, lh=1.0, animation=anim('block', 'word', 0, 1.0)),
        part('read all about it', 'oswald', 40, 500, '#374151', gap=12, ls=3, animation=anim('rise', None, 0.9, 0.6)),
    ]))
    add(trio('burst-boom', 'Boom', A, ['burst', 'boom', 'comic', 'animated', 'loud'], 820, [
        part('BOOM!', 'bungee', 190, 400, '#F59E0B', lh=1.0, effect={'type': 'echo', 'color': '#B45309'}, animation=anim('burst', 'letter', 0, 0.9)),
    ]))
    add(trio('bouncy-hello', 'Bouncy hello', A, ['bounce', 'kids', 'hello', 'animated', 'playful'], 820, [
        part('hi there!', 'pacifico', 130, 400, '#22C55E', lh=1.3, animation=anim('bounceIn', 'letter', 0, 1.1)),
        part('so glad you came', 'nunito', 38, 700, '#4B5563', gap=6, animation=anim('fade', None, 1.0, 0.6)),
    ]))
    add(trio('roll-credits', 'Roll credits', A, ['credits', 'film', 'roll', 'animated', 'movie'], 820, [
        part('Directed by\nJo Park', 'playfair-display', 64, 700, '#111827', lh=1.25, animation=anim('roll', 'line', 0, 1.2)),
        part('A NIGHT AT THE PICTURES', 'raleway', 26, 600, GREY, gap=16, ls=8, animation=anim('fade', None, 1.2, 0.6)),
    ]))
    add(trio('skate-in', 'Skate in', A, ['skate', 'slide', 'street', 'animated', 'sport'], 860, [
        part('Skate park', 'permanent-marker', 120, 400, '#7C3AED', rotation=-3, animation=anim('skate', 'word', 0, 1.0)),
        part('open every weekend', 'karla', 34, 700, '#374151', gap=10, animation=anim('rise', None, 0.9, 0.6)),
    ]))
    add(trio('spread-wide', 'Spread wide', A, ['spread', 'wide', 'minimal', 'animated', 'luxury'], 880, [
        part('HORIZON', 'raleway', 120, 300, '#0F172A', ls=24, lh=1.0, animation=anim('spread', 'letter', 0, 1.4)),
    ]))
    add(trio('clarify-focus', 'Into focus', A, ['focus', 'clarify', 'blur', 'animated', 'photography'], 860, [
        part('Into focus', 'dm-serif-display', 120, 400, '#1F2937', animation=anim('clarify', 'word', 0, 1.2)),
        part('a photography workshop', 'karla', 32, 500, GREY, gap=12, animation=anim('fade', None, 1.1, 0.6)),
    ]))
    add(trio('tumble-fun', 'Tumble', A, ['tumble', 'fun', 'kids', 'animated', 'playful'], 840, [
        part('TUMBLE', 'alfa-slab-one', 150, 400, '#F97316', ls=4, lh=1.0, animation=anim('tumble', 'letter', 0, 1.2)),
        part('gym club for little ones', 'patrick-hand', 42, 400, '#4B5563', gap=8, animation=anim('rise', None, 1.0, 0.6)),
    ]))
    add(trio('signature-write', 'Signature', A, ['signature', 'handwriting', 'write', 'animated', 'thank you'], 820, [
        part('With love,', 'dancing-script', 70, 700, '#6B7280', animation=anim('fade', None, 0, 0.6)),
        part('Amelia', 'satisfy', 150, 400, '#9D174D', lh=1.3, animation=anim('writeOn', 'letter', 0.5, 1.6)),
    ]))
    add(trio('neon-flicker', 'Neon flicker', A, ['neon', 'flicker', 'night', 'animated', 'bar'], 860, [
        part('OPEN LATE', 'righteous', 130, 400, '#F472B6', ls=6, lh=1.1, effect={'type': 'neon'}, animation=anim('pulse', None, 0, 1.2)),
        part('cocktails · music · dancing', 'righteous', 32, 400, '#67E8F9', gap=12, effect={'type': 'neon'}, animation=anim('fade', None, 0.4, 0.8)),
    ]))
    add(trio('glitch-title', 'Glitch', A, ['glitch', 'tech', 'game', 'animated', 'digital'], 880, [
        part('SYSTEM ERROR', 'space-mono', 100, 700, '#111827', ls=4, lh=1.1, effect={'type': 'glitch'}, animation=anim('shift', 'letter', 0, 0.9)),
        part('reboot at midnight', 'space-mono', 30, 400, GREY, gap=12, animation=anim('typewriter', 'letter', 0.9, 1.0)),
    ]))
    add(trio('echo-drop', 'Echo drop', A, ['echo', 'drop', 'music', 'animated', 'bass'], 860, [
        part('DROP', 'anton', 220, 400, '#2563EB', ls=6, lh=1.0, effect={'type': 'echo', 'color': '#93C5FD'}, animation=anim('baseline', 'line', 0, 0.8)),
        part('the new single, out now', 'oswald', 36, 500, '#1E3A8A', gap=10, ls=2, animation=anim('rise', None, 0.8, 0.6)),
    ]))
    add(trio('neon-breathe', 'Neon sign', A, ['neon', 'sign', 'glow', 'animated', 'diner'], 820, [
        part('Eat here', 'satisfy', 150, 400, '#FB923C', lh=1.3, effect={'type': 'neon'}, animation=anim('breathe', None, 0, 2.0)),
    ]))
    add(trio('curved-hello', 'Curved hello', A, ['curve', 'arc', 'hello', 'animated', 'summer'], 860, [
        part('hello summer', 'pacifico', 110, 400, '#F59E0B', lh=1.3, curve=45, animation=anim('letterPop', 'letter', 0, 1.2)),
        part('long days ahead', 'nunito', 34, 700, '#4B5563', gap=6, animation=anim('fade', None, 1.1, 0.6)),
    ]))
    add(trio('arch-rise', 'Arched rise', A, ['arch', 'warp', 'rise', 'animated', 'title'], 880, [
        part('GRAND OPENING', 'bebas-neue', 140, 400, '#0F766E', ls=6, lh=1.0, warp=warp('arch', 50), animation=anim('rise', None, 0, 0.8)),
        part('Saturday 10 am', 'montserrat', 34, 600, '#374151', gap=14, animation=anim('fade', None, 0.7, 0.6)),
    ]))
    add(trio('flag-wave', 'Waving flag', A, ['flag', 'wave', 'warp', 'animated', 'festival'], 860, [
        part('FESTIVAL', 'alfa-slab-one', 140, 400, '#B91C1C', ls=4, lh=1.0, warp=warp('flag', 40), animation=anim('wiggle', None, 0, 1.2)),
        part('three days of music', 'nunito', 36, 700, '#4B5563', gap=12, animation=anim('rise', None, 0.4, 0.6)),
    ]))
    add(trio('bulge-pop', 'Bulge pop', A, ['bulge', 'pop', 'warp', 'animated', 'sale'], 840, [
        part('WOW', 'bungee', 220, 400, '#7C3AED', lh=1.0, warp=warp('bulge', 45), animation=anim('pop', None, 0, 0.7)),
        part('prices you will love', 'poppins', 36, 600, '#374151', gap=10, animation=anim('rise', None, 0.6, 0.6)),
    ]))
    add(trio('countdown', 'Countdown', A, ['countdown', 'launch', 'numbers', 'animated', 'event'], 860, [
        part('3 · 2 · 1', 'anton', 170, 400, '#111827', ls=6, lh=1.0, animation=anim('words', 'word', 0, 1.5), exitAnimation=anim('fade', None, 0, 0.5)),
        part('WE ARE LIVE', 'montserrat', 44, 800, '#DC2626', gap=12, ls=8, animation=anim('pop', None, 1.5, 0.5)),
    ]))
    add(trio('breaking-wipe', 'Breaking wipe', A, ['breaking', 'news', 'wipe', 'animated', 'headline'], 900, [
        part('BREAKING', 'oswald', 150, 700, '#DC2626', ls=6, lh=1.0, animation=anim('wipe', None, 0, 0.7), exitAnimation=anim('slideLeft', None, 0, 0.6)),
        part('Live updates as they happen', 'oswald', 36, 400, '#111827', gap=10, animation=anim('rise', None, 0.6, 0.6), exitAnimation=anim('fade', None, 0, 0.5)),
    ]))
    add(trio('sale-ends', 'Sale ends', A, ['sale', 'last chance', 'ends', 'animated', 'discount'], 860, [
        part('LAST CHANCE', 'bebas-neue', 150, 400, '#E11D48', ls=6, lh=1.0, animation=anim('letterPop', 'letter', 0, 1.0), exitAnimation=anim('pop', None, 0, 0.5)),
        part('sale ends at midnight', 'montserrat', 34, 600, '#374151', gap=12, animation=anim('fade', None, 0.9, 0.6)),
    ]))
    add(trio('swipe-up-bounce', 'Swipe up bounce', A, ['swipe', 'social', 'story', 'animated', 'link'], 760, [
        part('SWIPE UP', 'montserrat', 90, 900, '#111827', ls=8, lh=1.1, animation=anim('bounce', None, 0, 1.2)),
        part('for the full look', 'poppins', 34, 500, GREY, gap=10, animation=anim('fade', None, 0.3, 0.6)),
    ]))
    add(trio('coming-soon-typed', 'Coming soon', A, ['coming soon', 'launch', 'teaser', 'animated', 'typewriter'], 860, [
        part('coming soon', 'jetbrains-mono', 110, 700, '#0F172A', animation=anim('typewriter', 'letter', 0, 1.4), exitAnimation=anim('fade', None, 0, 0.6)),
        part('stay tuned', 'jetbrains-mono', 32, 400, '#2563EB', gap=12, ls=4, animation=anim('fade', None, 1.4, 0.6)),
    ]))
    add(trio('thank-you-written', 'Thank you, written', A, ['thank you', 'thanks', 'handwriting', 'animated', 'card'], 820, [
        part('Thank you', 'dancing-script', 140, 700, '#BE185D', lh=1.3, animation=anim('writeOn', 'letter', 0, 1.6), exitAnimation=anim('writeOn', 'letter', 0, 1.0)),
    ]))
    add(trio('new-drop', 'New drop', A, ['drop', 'streetwear', 'release', 'animated', 'fashion'], 860, [
        part('NEW DROP', 'anton', 180, 400, '#111827', ls=6, lh=1.0, animation=anim('block', 'letter', 0, 1.0), exitAnimation=anim('block', 'letter', 0, 0.8)),
        part('friday · 6 pm · online', 'space-mono', 30, 700, '#6B7280', gap=12, ls=2, animation=anim('rise', None, 0.9, 0.6)),
    ]))
    add(trio('live-now', 'Live now', A, ['live', 'stream', 'now', 'animated', 'pulse'], 760, [
        part('LIVE NOW', 'bungee', 130, 400, '#DC2626', ls=6, lh=1.0, animation=anim('pulse', None, 0, 1.2)),
        part('join the stream', 'nunito', 36, 800, '#374151', gap=10, animation=anim('fade', None, 0.2, 0.6)),
    ]))
    add(trio('drifting-dream', 'Drifting', A, ['drift', 'dream', 'calm', 'animated', 'soft'], 840, [
        part('daydream', 'playfair-display', 130, 400, '#6D28D9', italic=True, animation=anim('drift', None, 0, 2.0)),
        part('a playlist for slow afternoons', 'lora', 32, 400, GREY, gap=10, animation=anim('fade', None, 0.6, 1.0)),
    ]))
    add(trio('big-reveal', 'Big reveal', A, ['reveal', 'baseline', 'launch', 'animated', 'product'], 880, [
        part('The reveal', 'space-grotesk', 140, 700, '#0F172A', ls=-2, animation=anim('baseline', 'line', 0, 0.9)),
        part('meet the new Model One', 'space-grotesk', 36, 400, '#475569', gap=12, animation=anim('baseline', 'line', 0.5, 0.9)),
    ]))
    add(trio('quote-reveal', 'Quote reveal', A, ['quote', 'words', 'inspiration', 'animated', 'motivation'], 860, [
        part('“Start where you are.”', 'playfair-display', 84, 400, '#1F2937', italic=True, lh=1.2, animation=anim('words', 'word', 0, 1.6)),
        part('— Arthur Ashe', 'raleway', 30, 600, GREY, gap=14, ls=4, animation=anim('fade', None, 1.6, 0.6)),
    ]))
    add(trio('new-year-burst', 'New year burst', A, ['new year', 'party', 'burst', 'animated', 'celebration'], 880, [
        part('HAPPY', 'bebas-neue', 90, 400, '#CA8A04', ls=14, lh=1.0, curve=30, animation=anim('fade', None, 0, 0.6)),
        part('NEW YEAR', 'bebas-neue', 180, 400, '#111827', ls=6, lh=1.0, animation=anim('burst', 'letter', 0.4, 1.0)),
    ]))
    return out


def shaped():
    """Twelve more for the other categories, their headlines bent: a warp
    (arch, bulge, flag, squeeze, rise or perspective) or a curve."""
    out = []
    add = out.append
    add(trio('arched-title', 'Arched title', 'Headline', ['arch', 'warp', 'title', 'headline', 'curved'], 880, [
        part('THE ARCHIVE', 'oswald', 150, 700, '#0F172A', ls=8, lh=1.0, warp=warp('arch', 45)),
        part('stories from the vault', 'lora', 34, 400, GREY, gap=16, italic=True),
    ]))
    add(trio('perspective-news', 'Perspective', 'Headline', ['perspective', 'warp', 'news', 'headline', 'dramatic'], 900, [
        part('BREAKTHROUGH', 'anton', 140, 400, '#1D4ED8', ls=4, lh=1.0, warp=warp('perspective', 50)),
        part('the science story of the year', 'karla', 32, 600, '#475569', gap=14),
    ]))
    add(trio('bulge-sale', 'Bulging sale', 'Sale', ['sale', 'bulge', 'warp', 'discount', 'bold'], 860, [
        part('SALE', 'bungee', 220, 400, '#E11D48', lh=1.0, warp=warp('bulge', 50)),
        part('everything must go', 'montserrat', 36, 700, '#374151', gap=10, ls=2),
    ]))
    add(trio('curved-quote', 'Curved quote', 'Quote', ['quote', 'curve', 'arc', 'inspiration'], 860, [
        part('dream big', 'pacifico', 130, 400, '#7C3AED', lh=1.3, curve=40),
        part('and work for it', 'poppins', 36, 500, GREY, gap=8),
    ]))
    add(trio('flag-festival', 'Festival flag', 'Event', ['festival', 'flag', 'warp', 'music', 'event'], 880, [
        part('FOLK FEST', 'alfa-slab-one', 130, 400, '#B45309', ls=4, lh=1.0, warp=warp('flag', 35)),
        part('July 12–14 · Riverside', 'nunito', 36, 700, '#4B5563', gap=12),
    ]))
    add(trio('curved-concert', 'Concert arc', 'Event', ['concert', 'curve', 'music', 'event', 'tour'], 880, [
        part('WORLD TOUR', 'bebas-neue', 120, 400, '#DC2626', ls=10, lh=1.0, curve=35),
        part('one night in your city', 'oswald', 36, 500, '#111827', gap=10, ls=2),
    ]))
    add(trio('arched-names', 'Arched names', 'Wedding', ['wedding', 'names', 'curve', 'elegant', 'love'], 860, [
        part('Ella & Theo', 'dancing-script', 120, 700, '#9D174D', lh=1.3, curve=35),
        part('JUNE 21 · LAKE COMO', 'raleway', 28, 500, '#6B7280', gap=12, ls=8),
    ]))
    add(trio('rise-follow', 'Rising follow', 'Social', ['follow', 'social', 'warp', 'rise', 'instagram'], 820, [
        part('FOLLOW US', 'montserrat', 110, 900, '#0EA5E9', ls=6, lh=1.0, warp=warp('rise', 40)),
        part('@canvia.studio', 'poppins', 40, 600, '#374151', gap=12),
    ]))
    add(trio('perspective-retro', 'Retro perspective', 'Retro', ['retro', 'perspective', 'warp', 'eighties', 'arcade'], 880, [
        part('RETRO', 'righteous', 190, 400, '#DB2777', ls=8, lh=1.0, warp=warp('perspective', -45), textFill=gradient(90, '#F59E0B', '#DB2777')),
        part('arcade night', 'space-mono', 36, 700, '#4C1D95', gap=12, ls=6),
    ]))
    add(trio('squeeze-minimal', 'Squeezed', 'Minimal', ['minimal', 'squeeze', 'warp', 'modern', 'clean'], 820, [
        part('less', 'space-grotesk', 200, 300, '#111827', lh=1.0, warp=warp('squeeze', 40)),
        part('is more', 'space-grotesk', 40, 400, GREY, gap=10),
    ]))
    add(trio('curved-badge', 'Curved stamp', 'Badge', ['badge', 'stamp', 'curve', 'quality', 'seal'], 760, [
        part('· HAND MADE ·', 'raleway', 40, 700, '#92400E', ls=8, curve=70, h=110),
        part('SMALL BATCH', 'alfa-slab-one', 80, 400, '#92400E', gap=6, lh=1.0),
    ]))
    add(trio('bouncy-arch', 'Bouncy arch', 'Kids', ['kids', 'arch', 'warp', 'fun', 'playground'], 840, [
        part('PLAYTIME', 'bungee', 140, 400, '#16A34A', ls=4, lh=1.0, warp=warp('arch', 60)),
        part('slides · swings · sandpit', 'patrick-hand', 42, 400, '#4B5563', gap=10),
    ]))
    return out


def more():
    """The ninety after the first thirty, ten categories' worth."""
    out = []
    add = out.append

    # Headline
    add(trio('big-announcement', 'Big announcement', 'Headline', ['announcement', 'news', 'headline', 'bold'], 900, [
        part('WE HAVE NEWS', 'montserrat', 30, 600, GREY, ls=10),
        part('Something big\nis coming', 'poppins', 96, 800, gap=10, lh=1.05),
        part('Mark your calendar for 1 March', 'poppins', 30, 400, '#475569', gap=16),
    ]))
    add(trio('magazine-cover', 'Magazine cover', 'Headline', ['magazine', 'cover', 'fashion', 'editorial'], 860, [
        part('VOGUE', 'playfair-display', 180, 900, '#111827', ls=8, lh=1.0),
        part('The spring issue', 'playfair-display', 44, 400, '#9F1239', gap=6, italic=True),
        rule(860, 2, '#111827'),
        part('Twelve looks for the new season', 'raleway', 26, 500, GREY, gap=14, ls=2),
    ]))
    add(trio('chapter-one', 'Chapter one', 'Headline', ['book', 'chapter', 'story', 'title', 'serif'], 820, [
        part('CHAPTER ONE', 'libre-baskerville', 26, 400, '#92400E', ls=12),
        part('The Long Way Home', 'libre-baskerville', 80, 700, gap=12),
        rule(820, 2, '#92400E'),
        part('In which everything begins', 'libre-baskerville', 28, 400, GREY, gap=14, italic=True),
    ]))
    add(trio('tech-keynote', 'Tech keynote', 'Headline', ['tech', 'keynote', 'conference', 'startup', 'presentation'], 900, [
        part('KEYNOTE 2027', 'jetbrains-mono', 28, 700, '#2563EB', ls=6),
        part('Build the future', 'space-grotesk', 104, 700, '#0F172A', gap=10, ls=-2),
        part('Live from the main stage', 'space-grotesk', 32, 400, '#475569', gap=12),
    ]))
    add(trio('photo-essay', 'Photo essay', 'Headline', ['photography', 'essay', 'gallery', 'story'], 860, [
        part('Light & Shadow', 'dm-serif-display', 110, 400, '#1F2937'),
        part('A PHOTO ESSAY BY MIA CHEN', 'karla', 26, 700, GREY, gap=14, ls=8),
    ]))
    add(trio('city-guide', 'City guide', 'Headline', ['travel', 'city', 'guide', 'lisbon'], 880, [
        part('The Weekend Guide to', 'lora', 40, 400, '#0F766E', italic=True),
        part('LISBON', 'oswald', 190, 700, '#0F172A', ls=10, lh=1.0),
        part('Where to eat, stay and wander', 'lora', 30, 400, GREY, gap=14),
    ]))

    # Sale
    add(trio('flash-sale', 'Flash sale', 'Sale', ['sale', 'flash', 'discount', 'limited', 'offer'], 880, [
        part('FLASH', 'bebas-neue', 200, 400, '#F59E0B', ls=10, lh=1.0, effect={'type': 'lift'}),
        part('SALE', 'bebas-neue', 200, 400, '#111827', ls=10, lh=1.0),
        part('24 hours only · up to 70% off', 'montserrat', 30, 600, '#374151', gap=14),
    ]))
    add(labelled('half-price', 'Half price', 'Sale', ['sale', 'half price', 'discount', 'offer', 'shop'], 860, 'THIS WEEK', 'montserrat', '#DC2626', '#FFFFFF', [
        part('50% OFF', 'anton', 190, 400, '#DC2626', ls=4, lh=1.0),
        part('Everything in store', 'montserrat', 34, 500, '#111827', gap=12),
    ]))
    add(panel('clearance', 'Clearance', 'Sale', ['sale', 'clearance', 'discount', 'final'], 860, '#FACC15', [
        part('FINAL', 'oswald', 60, 300, '#111827', ls=30),
        part('CLEARANCE', 'oswald', 140, 700, '#111827', lh=1.0),
        part('Last chance to buy', 'oswald', 30, 400, '#111827', gap=12, ls=3),
    ], radius=0))
    add(trio('buy-one-get-one', 'Buy one get one', 'Sale', ['sale', 'bogo', 'offer', 'deal', 'shop'], 880, [
        part('Buy one', 'pacifico', 90, 400, '#DB2777', lh=1.3),
        part('GET ONE FREE', 'poppins', 92, 900, '#111827', gap=2, ls=2),
        part('While stocks last', 'poppins', 28, 400, GREY, gap=12),
    ]))
    add(panel('cyber-monday', 'Cyber Monday', 'Sale', ['sale', 'cyber monday', 'tech', 'deal', 'discount'], 900, '#0F172A', [
        part('CYBER', 'space-mono', 120, 700, '#22D3EE', ls=10, lh=1.0, effect={'type': 'neon'}),
        part('MONDAY', 'space-mono', 120, 700, '#E879F9', ls=10, lh=1.0),
        part('Deals online all day', 'space-grotesk', 30, 400, '#CBD5E1', gap=16),
    ]))
    add(trio('summer-sale', 'Summer sale', 'Sale', ['sale', 'summer', 'discount', 'season', 'shop'], 880, [
        part('Summer', 'satisfy', 120, 400, '#F97316', lh=1.3),
        part('SALE', 'montserrat', 170, 900, '#0EA5E9', ls=12, lh=1.0, textFill=gradient(90, '#0EA5E9', '#14B8A6')),
        part('Up to 40% off swimwear', 'montserrat', 30, 500, '#475569', gap=12),
    ]))
    add(trio('new-arrivals', 'New arrivals', 'Sale', ['new', 'arrivals', 'shop', 'fashion', 'store'], 860, [
        part('JUST LANDED', 'raleway', 28, 600, GREY, ls=14),
        part('New Arrivals', 'abril-fatface', 120, 400, '#111827', gap=8),
        part('Shop the collection', 'raleway', 30, 400, '#9F1239', gap=10, italic=True),
    ]))
    add(trio('free-shipping', 'Free shipping', 'Sale', ['shipping', 'delivery', 'free', 'shop', 'online'], 880, [
        part('FREE', 'anton', 210, 400, '#16A34A', ls=6, lh=1.0),
        part('SHIPPING', 'anton', 120, 400, '#111827', ls=14, lh=1.0),
        part('On every order over £30', 'roboto', 32, 500, '#374151', gap=14),
    ]))
    add(labelled('limited-offer', 'Limited offer', 'Sale', ['offer', 'limited', 'promo', 'code', 'discount'], 860, 'CODE: SPRING20', 'roboto-mono', '#111827', '#FFFFFF', [
        part('20% off', 'playfair-display', 150, 900, '#7C3AED', lh=1.05),
        part('Use it at checkout before Sunday', 'lato', 30, 400, '#4B5563', gap=12),
    ], pill=420))
    add(trio('price-drop', 'Price drop', 'Sale', ['price', 'drop', 'deal', 'sale', 'discount'], 860, [
        part('PRICE DROP', 'bungee', 96, 400, '#E11D48', ls=2, effect={'type': 'echo', 'color': '#FDA4AF'}),
        part('Was £80  ·  Now £49', 'roboto-slab', 52, 700, '#111827', gap=14, **spans('Was £80  ·  Now £49', 0, 7, color='#9CA3AF')),
    ]))

    # Quote
    add(trio('wise-words', 'Wise words', 'Quote', ['quote', 'wisdom', 'words', 'inspiration'], 860, [
        part('“The best time to plant a tree\nwas twenty years ago.\nThe second best time is now.”', 'crimson-text', 50, 400, '#1F2937', lh=1.3, italic=True),
        rule(860, 2, '#B45309', gap=22),
        part('CHINESE PROVERB', 'raleway', 22, 600, GREY, gap=16, ls=8),
    ]))
    add(trio('bold-quote', 'Bold quote', 'Quote', ['quote', 'bold', 'motivation', 'statement'], 880, [
        part('DO MORE', 'anton', 170, 400, '#111827', ls=4, lh=1.0),
        part('of what makes you', 'dancing-script', 76, 700, '#DB2777', lh=1.2),
        part('HAPPY', 'anton', 170, 400, '#111827', ls=4, lh=1.0, effect={'type': 'highlight', 'color': '#FDE047'}),
    ]))
    add(trio('testimonial', 'Testimonial', 'Quote', ['testimonial', 'review', 'customer', 'quote', 'business'], 860, [
        part('★★★★★', 'roboto', 50, 400, '#F59E0B', ls=6),
        part('“Fast, friendly and the best\ncoffee in town.”', 'lora', 50, 500, '#111827', gap=14, lh=1.3),
        part('— Priya, regular since 2021', 'lora', 28, 400, GREY, gap=16, italic=True),
    ]))
    add(trio('handwritten-note', 'Handwritten note', 'Quote', ['note', 'handwritten', 'quote', 'personal', 'love'], 820, [
        part('you are\nmy sunshine', 'caveat', 120, 700, '#1D4ED8', lh=1.0, rotation=-3),
        part('xo, Mum', 'caveat', 50, 400, '#DB2777', gap=10),
    ]))
    add(trio('book-quote', 'Book quote', 'Quote', ['book', 'reading', 'literature', 'quote'], 860, [
        part('“', 'libre-baskerville', 160, 700, '#B91C1C', lh=0.8),
        part('So we beat on, boats against\nthe current.', 'libre-baskerville', 46, 400, '#1F2937', lh=1.35, italic=True),
        part('F. SCOTT FITZGERALD', 'libre-baskerville', 22, 700, GREY, gap=20, ls=6),
    ]))
    add(trio('daily-mantra', 'Daily mantra', 'Quote', ['mantra', 'mindfulness', 'calm', 'wellness', 'quote'], 840, [
        part('TODAY I WILL', 'karla', 26, 500, '#0F766E', ls=12),
        part('breathe deeply\nand begin again', 'playfair-display', 74, 400, '#134E4A', gap=12, lh=1.15, italic=True),
    ]))
    add(trio('fun-fact', 'Fun fact', 'Quote', ['fact', 'trivia', 'learn', 'social', 'education'], 860, [
        part('DID YOU KNOW?', 'bungee', 60, 400, '#7C3AED', ls=2),
        part('Octopuses have three hearts\nand blue blood.', 'nunito', 50, 700, '#111827', gap=16, lh=1.25),
    ]))
    add(trio('tweet-quote', 'Tweet quote', 'Quote', ['tweet', 'post', 'social', 'quote', 'thought'], 860, [
        part('Hot take:', 'space-grotesk', 40, 700, '#1D9BF0', align='left'),
        part('Every meeting could have\nbeen a walk.', 'space-grotesk', 64, 500, '#0F172A', gap=10, lh=1.15, align='left'),
        part('@studio.ana', 'space-grotesk', 28, 400, GREY, gap=16, align='left'),
    ]))
    add(trio('poem-line', 'Poem line', 'Quote', ['poem', 'poetry', 'verse', 'words'], 820, [
        part('and the sea\nkept every secret\nwe gave it', 'sacramento', 96, 400, '#0E7490', lh=1.0),
        rule(820, 1, '#0E7490', gap=18),
        part('from Tidelines', 'crimson-text', 30, 400, GREY, gap=14, italic=True),
    ]))
    add(trio('team-motto', 'Team motto', 'Quote', ['team', 'motto', 'work', 'motivation', 'business'], 880, [
        part('TOGETHER', 'oswald', 140, 700, '#1E3A8A', ls=6, lh=1.0),
        part('we go further', 'oswald', 60, 300, '#F59E0B', gap=6, ls=12),
    ]))

    # Event
    add(trio('live-music', 'Live music', 'Event', ['music', 'concert', 'gig', 'live', 'band'], 880, [
        part('LIVE', 'bungee', 150, 400, '#E11D48', ls=6, lh=1.0, effect={'type': 'splice'}),
        part('MUSIC', 'bungee', 110, 400, '#111827', ls=10, lh=1.0),
        part('Every Thursday · The Old Mill', 'oswald', 32, 400, '#374151', gap=14, ls=2),
    ]))
    add(trio('save-our-seat', 'Conference', 'Event', ['conference', 'summit', 'business', 'event', 'talk'], 900, [
        part('DESIGN SUMMIT', 'montserrat', 34, 700, '#7C3AED', ls=12),
        part('Ideas worth\nmaking', 'montserrat', 110, 900, '#111827', gap=10, lh=1.0),
        rule(900, 4, '#7C3AED', gap=18),
        part('12–13 May · Manchester', 'montserrat', 32, 400, '#374151', gap=16),
    ]))
    add(trio('farmers-market', 'Farmers market', 'Event', ['market', 'farmers', 'food', 'local', 'weekend'], 860, [
        part('Saturday', 'caveat', 70, 700, '#65A30D', rotation=-4),
        part('FARMERS MARKET', 'roboto-slab', 76, 800, '#3F6212', ls=2),
        part('Fresh, local and seasonal · 8 am–1 pm', 'roboto-slab', 28, 400, '#4B5563', gap=12),
    ]))
    add(labelled('charity-run', 'Charity run', 'Event', ['run', 'charity', 'race', 'fundraiser', 'sport'], 880, '5K FUN RUN', 'montserrat', '#16A34A', '#FFFFFF', [
        part('Run for a reason', 'montserrat', 84, 800, '#14532D', lh=1.05),
        part('Sunday 9 am · Riverside Park', 'montserrat', 30, 400, '#4B5563', gap=12),
    ]))
    add(panel('movie-night', 'Movie night', 'Event', ['movie', 'cinema', 'film', 'night', 'party'], 860, '#111827', [
        part('MOVIE', 'bebas-neue', 170, 400, '#FBBF24', ls=16, lh=1.0),
        part('NIGHT', 'bebas-neue', 170, 400, '#FFFFFF', ls=16, lh=1.0),
        part('Popcorn at 7 · Film at 7:30', 'raleway', 30, 500, '#D1D5DB', gap=14),
    ], radius=12))
    add(trio('new-year-party', 'New Year party', 'Event', ['new year', 'party', 'countdown', 'celebration', 'december'], 880, [
        part('Happy New Year', 'dancing-script', 110, 700, '#CA8A04', textFill=gradient(90, '#FDE68A', '#CA8A04')),
        part('2027', 'playfair-display', 170, 900, '#111827', ls=10, lh=1.0),
        part('Countdown from 11 pm', 'raleway', 30, 500, GREY, gap=12, ls=4),
    ]))

    # Wedding
    add(trio('we-said-yes', 'We said yes', 'Wedding', ['wedding', 'engagement', 'love', 'announcement'], 840, [
        part('We said', 'sacramento', 110, 400, '#9F1239'),
        part('YES', 'playfair-display', 170, 700, '#111827', ls=20, lh=1.0),
        part('Olivia & Noah · Engaged', 'lora', 30, 400, GREY, gap=12, italic=True),
    ]))
    add(trio('wedding-menu', 'Wedding menu', 'Wedding', ['wedding', 'menu', 'dinner', 'reception'], 820, [
        part('Menu', 'satisfy', 130, 400, '#854D0E', lh=1.3),
        rule(820, 1, '#CA8A04', gap=4),
        part('Starter · Main · Dessert', 'crimson-text', 34, 400, '#44403C', gap=16, ls=3),
    ]))
    add(trio('reception', 'Reception', 'Wedding', ['wedding', 'reception', 'party', 'invitation', 'dinner'], 860, [
        part('JOIN US FOR THE', 'montserrat', 24, 300, GREY, ls=14),
        part('Reception', 'dm-serif-display', 120, 400, '#1E293B', gap=8),
        part('7 pm onwards · The Barn, Ashford', 'montserrat', 26, 400, '#64748B', gap=10, ls=2),
    ]))
    add(trio('mr-and-mrs', 'Mr & Mrs', 'Wedding', ['wedding', 'mr and mrs', 'married', 'love', 'couple'], 840, [
        part('Mr & Mrs', 'dancing-script', 150, 700, '#B45309', lh=1.15),
        part('THE HARPERS', 'raleway', 40, 300, '#1C1917', gap=6, ls=20),
    ]))
    add(trio('bridal-shower', 'Bridal shower', 'Wedding', ['bridal', 'shower', 'bride', 'party', 'wedding'], 860, [
        part('Bridal', 'pacifico', 110, 400, '#DB2777', lh=1.3),
        part('SHOWER', 'playfair-display', 90, 500, '#831843', ls=24, lh=1.1),
        part('Brunch for Sophie · 3 May', 'lora', 30, 400, GREY, gap=12, italic=True),
    ]))
    add(trio('anniversary', 'Anniversary', 'Wedding', ['anniversary', 'love', 'years', 'celebration', 'couple'], 840, [
        part('25', 'abril-fatface', 220, 400, '#A16207', lh=1.0, textFill=gradient(180, '#FDE68A', '#A16207')),
        part('Years of love', 'sacramento', 90, 400, '#1C1917'),
        part('1 June 2002 – 1 June 2027', 'crimson-text', 28, 400, GREY, gap=10, ls=2),
    ]))
    add(trio('rsvp-card', 'RSVP card', 'Wedding', ['rsvp', 'wedding', 'reply', 'invitation', 'card'], 820, [
        part('RSVP', 'libre-baskerville', 120, 700, '#1E3A8A', ls=16, lh=1.0),
        rule(820, 1, '#1E3A8A', gap=14),
        part('Kindly reply by 1 May', 'libre-baskerville', 32, 400, '#475569', gap=14, italic=True),
    ]))
    add(trio('save-the-date-script', 'Save the date', 'Wedding', ['save the date', 'wedding', 'date', 'love', 'elegant'], 860, [
        part('Save', 'sacramento', 140, 400, '#0F766E'),
        part('THE DATE', 'raleway', 60, 300, '#134E4A', ls=26),
        part('09 · 09 · 2027', 'raleway', 40, 600, '#0F766E', gap=14, ls=8),
    ]))
    add(trio('love-story', 'Love story', 'Wedding', ['love', 'story', 'romance', 'couple', 'valentine'], 840, [
        part('a love story', 'satisfy', 96, 400, '#BE123C'),
        part('ANNA + LEO', 'montserrat', 46, 500, '#1F2937', gap=8, ls=14),
    ]))
    add(trio('ceremony-order', 'Order of service', 'Wedding', ['ceremony', 'order of service', 'wedding', 'church'], 820, [
        part('ORDER OF', 'crimson-text', 36, 400, GREY, ls=16),
        part('Service', 'dancing-script', 140, 700, '#713F12', lh=1.15),
        part('St Mary\u2019s Church · 2 pm', 'crimson-text', 30, 400, '#44403C', gap=8),
    ]))

    # Social
    add(trio('new-post', 'New post', 'Social', ['post', 'blog', 'social', 'new', 'announcement'], 860, [
        part('NEW POST', 'space-grotesk', 30, 700, '#DB2777', ls=10),
        part('10 tiny habits\nthat changed my year', 'space-grotesk', 74, 700, '#111827', gap=12, lh=1.1),
        part('Link in bio', 'space-grotesk', 30, 400, GREY, gap=14),
    ]))
    add(labelled('giveaway', 'Giveaway', 'Social', ['giveaway', 'contest', 'win', 'social', 'prize'], 880, 'WIN!', 'poppins', '#F43F5E', '#FFFFFF', [
        part('GIVEAWAY', 'poppins', 130, 900, '#111827', ls=4, lh=1.0, textFill=gradient(90, '#F43F5E', '#8B5CF6')),
        part('Like, share and tag a friend', 'poppins', 30, 500, '#4B5563', gap=12),
    ], pill=180))
    add(trio('swipe-up', 'Swipe for more', 'Social', ['carousel', 'swipe', 'tips', 'social', 'story'], 860, [
        part('5 tips for', 'dm-sans', 56, 400, '#475569'),
        part('Better Sleep', 'dm-sans', 116, 800, '#0F172A', ls=-2),
        part('Swipe for more →', 'dm-sans', 32, 700, '#2563EB', gap=12),
    ]))
    add(trio('good-morning', 'Good morning', 'Social', ['morning', 'greeting', 'coffee', 'social', 'story'], 840, [
        part('good', 'shadows-into-light', 110, 400, '#F59E0B'),
        part('MORNING', 'montserrat', 110, 900, '#78350F', ls=4, lh=1.0),
        part('coffee first, then the world', 'shadows-into-light', 40, 400, '#92400E', gap=10),
    ]))
    add(trio('milestone', 'Milestone', 'Social', ['milestone', 'followers', 'thanks', 'celebrate', 'social'], 860, [
        part('10K', 'anton', 250, 400, '#7C3AED', lh=1.0, effect={'type': 'lift'}),
        part('THANK YOU FOR FOLLOWING', 'montserrat', 34, 700, '#111827', gap=10, ls=4),
    ]))
    add(trio('weekend-plans', 'Weekend plans', 'Social', ['weekend', 'plans', 'friday', 'fun', 'social'], 860, [
        part('hello', 'indie-flower', 90, 400, '#0EA5E9'),
        part('WEEKEND', 'bebas-neue', 190, 400, '#0F172A', ls=14, lh=1.0),
        part('pancakes · park · repeat', 'indie-flower', 40, 400, '#475569', gap=10),
    ]))
    add(trio('behind-the-scenes', 'Behind the scenes', 'Social', ['behind the scenes', 'studio', 'making', 'social', 'story'], 880, [
        part('BEHIND', 'oswald', 120, 700, '#111827', ls=16, lh=1.0),
        part('the scenes', 'permanent-marker', 80, 400, '#EF4444', rotation=-3),
        part('A day in our studio', 'oswald', 30, 300, GREY, gap=10, ls=4),
    ]))

    # Retro
    add(trio('retro-diner', 'Retro diner', 'Retro', ['retro', 'diner', '50s', 'food', 'vintage'], 880, [
        part('Eat at', 'pacifico', 80, 400, '#0D9488', lh=1.3),
        part("MEL'S DINER", 'alfa-slab-one', 100, 400, '#DC2626', ls=2, effect={'type': 'echo', 'color': '#FCA5A5'}),
        part('Burgers · Shakes · Fries', 'righteous', 34, 400, '#0D9488', gap=12, ls=3),
    ]))
    add(panel('arcade', 'Arcade', 'Retro', ['arcade', 'game', '80s', 'retro', 'pixel'], 880, '#1E1B4B', [
        part('GAME', 'bungee', 140, 400, '#F472B6', ls=6, lh=1.0, effect={'type': 'neon'}),
        part('OVER', 'bungee', 140, 400, '#67E8F9', ls=6, lh=1.0, effect={'type': 'neon'}),
        part('Press start to continue', 'space-mono', 28, 400, '#E0E7FF', gap=16),
    ], radius=0))
    add(trio('groovy', 'Groovy', 'Retro', ['70s', 'groovy', 'retro', 'disco', 'funky'], 880, [
        part('Groovy', 'righteous', 160, 400, '#EA580C', lh=1.1, curve=30, textFill=gradient(90, '#F59E0B', '#DB2777')),
        part('· SEVENTIES NIGHT ·', 'righteous', 36, 400, '#7C2D12', gap=8, ls=6),
    ]))
    add(trio('vintage-label', 'Vintage label', 'Retro', ['vintage', 'label', 'brewery', 'established', 'craft'], 840, [
        part('ESTABLISHED 1924', 'roboto-slab', 26, 700, '#78350F', ls=10),
        rule(840, 3, '#78350F', gap=10),
        part('Old Town', 'abril-fatface', 120, 400, '#451A03', gap=10),
        part('Brewing Co.', 'dancing-script', 70, 700, '#B45309', lh=1.1),
    ]))
    add(trio('synthwave', 'Synthwave', 'Retro', ['synthwave', '80s', 'neon', 'music', 'retro'], 880, [
        part('MIDNIGHT', 'righteous', 130, 400, '#F472B6', ls=6, lh=1.0, textFill=gradient(180, '#FDE68A', '#DB2777')),
        part('drive', 'satisfy', 110, 400, '#22D3EE', rotation=-6, effect={'type': 'neon'}),
    ]))
    add(trio('typewriter', 'Typewriter', 'Retro', ['typewriter', 'letter', 'vintage', 'mono', 'note'], 860, [
        part('Dear reader,', 'space-mono', 60, 400, '#1C1917', align='left'),
        part('this story is true,\nmore or less.', 'space-mono', 40, 400, '#57534E', gap=14, lh=1.4, align='left'),
    ]))
    add(trio('roller-disco', 'Roller disco', 'Retro', ['disco', 'roller', 'skate', 'party', '80s'], 880, [
        part('ROLLER', 'bungee', 110, 400, '#A855F7', ls=4, lh=1.0),
        part('Disco', 'pacifico', 130, 400, '#F43F5E', lh=1.3, effect={'type': 'lift'}),
        part('Saturday · 8 pm till late', 'righteous', 30, 400, '#4C1D95', gap=8, ls=2),
    ]))
    add(trio('old-cinema', 'Old cinema', 'Retro', ['cinema', 'film', 'vintage', 'premiere', 'classic'], 880, [
        part('NOW SHOWING', 'oswald', 34, 500, '#B91C1C', ls=14),
        part('The Silver Screen', 'abril-fatface', 96, 400, '#111827', gap=8),
        part('One night only', 'playfair-display', 36, 400, '#B91C1C', gap=10, italic=True),
    ]))
    add(trio('retro-surf', 'Retro surf', 'Retro', ['surf', 'beach', 'retro', 'summer', 'california'], 880, [
        part('SURF', 'alfa-slab-one', 190, 400, '#0EA5E9', ls=8, lh=1.0, effect={'type': 'echo', 'color': '#F97316'}),
        part('club', 'pacifico', 90, 400, '#F97316', lh=1.3, rotation=-5),
        part('EST. 1969 · CALIFORNIA', 'righteous', 28, 400, '#0369A1', gap=6, ls=6),
    ]))
    add(trio('pop-art', 'Pop art', 'Retro', ['pop art', 'comic', 'retro', 'bold', 'wow'], 860, [
        part('POW!', 'bungee', 220, 400, '#FACC15', lh=1.0, effect={'type': 'outlined', 'color': '#111827'}),
        part('It all happens here', 'permanent-marker', 44, 400, '#DC2626', gap=6),
    ]))
    add(trio('record-store', 'Record store', 'Retro', ['record', 'vinyl', 'music', 'shop', 'vintage'], 860, [
        part('Vinyl', 'dm-serif-display', 150, 400, '#111827', italic=True),
        part('RECORD STORE', 'space-mono', 40, 700, '#D97706', gap=6, ls=10),
        part('Crate digging since 1988', 'space-mono', 26, 400, GREY, gap=12),
    ]))

    # Minimal
    add(trio('just-words', 'Just words', 'Minimal', ['minimal', 'simple', 'clean', 'quiet'], 820, [
        part('Less, but better.', 'dm-sans', 76, 500, '#111827'),
        part('dieter rams', 'dm-sans', 26, 400, '#9CA3AF', gap=16, ls=6),
    ]))
    add(trio('thin-caps', 'Thin capitals', 'Minimal', ['minimal', 'caps', 'thin', 'modern', 'fashion'], 880, [
        part('STUDIO', 'raleway', 120, 300, '#111827', ls=40, lh=1.0),
        rule(880, 1, '#111827', gap=20),
        part('Architecture & interiors', 'raleway', 26, 400, GREY, gap=20, ls=6),
    ]))
    add(trio('mono-label', 'Mono label', 'Minimal', ['mono', 'code', 'label', 'minimal', 'tech'], 820, [
        part('index.html', 'ibm-plex-mono', 80, 500, '#111827'),
        part('// a portfolio, nothing more', 'ibm-plex-mono', 28, 400, '#6B7280', gap=12),
    ]))
    add(trio('serif-whisper', 'Serif whisper', 'Minimal', ['serif', 'minimal', 'elegant', 'quiet', 'title'], 820, [
        part('Stillness', 'lora', 110, 400, '#1F2937', italic=True),
        part('A collection of quiet rooms', 'lora', 28, 400, '#6B7280', gap=10),
    ]))
    add(trio('numbered', 'Numbered', 'Minimal', ['number', 'section', 'minimal', 'presentation', 'slide'], 860, [
        part('01', 'space-grotesk', 150, 300, '#D1D5DB', align='left', lh=1.0),
        part('Introduction', 'space-grotesk', 80, 600, '#111827', align='left'),
        part('Where we are and where we are going', 'space-grotesk', 28, 400, GREY, gap=10, align='left'),
    ]))
    add(trio('left-aligned', 'Left aligned', 'Minimal', ['left', 'minimal', 'heading', 'report', 'clean'], 860, [
        part('Annual Report', 'karla', 96, 700, '#0F172A', align='left'),
        rule(860, 4, '#2563EB', gap=12, x=0, width=120),
        part('2026 in numbers', 'karla', 34, 400, '#475569', gap=16, align='left'),
    ]))
    add(trio('lowercase', 'Lowercase', 'Minimal', ['lowercase', 'minimal', 'brand', 'modern', 'soft'], 820, [
        part('hello, studio', 'nunito', 96, 300, '#111827'),
        part('design · type · code', 'nunito', 30, 600, '#A3A3A3', gap=10, ls=4),
    ]))
    add(trio('big-number', 'Big number', 'Minimal', ['number', 'stat', 'data', 'minimal', 'report'], 820, [
        part('87%', 'dm-sans', 220, 700, '#111827', lh=1.0, ls=-6),
        part('of readers finish the first page', 'dm-sans', 30, 400, GREY, gap=10),
    ]))
    add(trio('one-line', 'One line', 'Minimal', ['line', 'minimal', 'caption', 'simple'], 860, [
        rule(860, 1, '#9CA3AF', gap=0, x=0, width=860),
        part('the shape of things to come', 'crimson-text', 50, 400, '#374151', gap=18, italic=True),
        rule(860, 1, '#9CA3AF', gap=18, x=0, width=860),
    ]))
    add(trio('contact-card', 'Contact card', 'Minimal', ['contact', 'business card', 'name', 'minimal', 'work'], 820, [
        part('Jordan Lee', 'montserrat', 70, 600, '#111827', align='left'),
        part('Product Designer', 'montserrat', 30, 400, '#6B7280', gap=6, align='left'),
        part('hello@jordanlee.design', 'roboto-mono', 26, 400, '#2563EB', gap=20, align='left'),
    ]))

    # Badge
    add(badge('best-seller', 'Best seller', ['badge', 'best seller', 'shop', 'label', 'product'], 420, '#DC2626',
              ('THE', 'montserrat', 30, 600), ('BEST', 'anton', 120, 400), ('SELLER', 'montserrat', 36, 700), ring='#FFFFFF'))
    add(badge('new-badge', 'New badge', ['badge', 'new', 'label', 'sticker', 'product'], 360, '#16A34A',
              ('BRAND', 'poppins', 28, 600), ('NEW', 'poppins', 120, 900), ('IN STORE', 'poppins', 26, 600)))
    add(badge('handmade', 'Handmade', ['badge', 'handmade', 'craft', 'artisan', 'label'], 420, '#78350F',
              ('MADE WITH LOVE', 'raleway', 24, 600), ('Handmade', 'dancing-script', 90, 700), ('SINCE 2019', 'raleway', 24, 600), ink='#FEF3C7', ring='#FEF3C7'))
    add(badge('organic', 'Organic', ['badge', 'organic', 'natural', 'eco', 'food'], 400, '#65A30D',
              ('100%', 'montserrat', 40, 800), ('ORGANIC', 'oswald', 90, 700), ('FARM FRESH', 'montserrat', 24, 600)))
    add(badge('percent-off', 'Percent off', ['badge', 'discount', 'sale', 'sticker', 'offer'], 380, '#FACC15',
              ('SAVE', 'anton', 44, 400), ('30%', 'anton', 140, 400), ('TODAY', 'anton', 44, 400), ink='#111827'))
    add(badge('award-winner', 'Award winner', ['badge', 'award', 'winner', 'prize', 'gold'], 420, '#CA8A04',
              ('2027', 'playfair-display', 34, 700), ('WINNER', 'playfair-display', 80, 900), ('BEST CAFÉ', 'playfair-display', 28, 500), ring='#FEF9C3'))
    add(badge('vegan', 'Vegan', ['badge', 'vegan', 'plant based', 'food', 'label'], 360, '#15803D',
              ('PLANT', 'nunito', 30, 800), ('vegan', 'pacifico', 90, 400), ('FRIENDLY', 'nunito', 30, 800)))
    add(badge('limited-edition', 'Limited edition', ['badge', 'limited', 'edition', 'collector', 'product'], 420, '#111827',
              ('LIMITED', 'bebas-neue', 50, 400), ('EDITION', 'bebas-neue', 110, 400), ('NO. 001/500', 'space-mono', 24, 700), ink='#FDE68A', ring='#FDE68A'))
    add(badge('free-gift', 'Free gift', ['badge', 'gift', 'free', 'offer', 'sticker'], 360, '#DB2777',
              ('EVERY ORDER', 'poppins', 24, 600), ('FREE', 'poppins', 110, 900), ('GIFT', 'poppins', 50, 800)))
    add(badge('local', 'Shop local', ['badge', 'local', 'shop', 'community', 'small business'], 400, '#1D4ED8',
              ('SUPPORT', 'oswald', 34, 500), ('LOCAL', 'oswald', 110, 700), ('BUSINESS', 'oswald', 34, 500), ring='#BFDBFE'))
    add(badge('guarantee', 'Guarantee', ['badge', 'guarantee', 'quality', 'trust', 'promise'], 420, '#0F766E',
              ('MONEY BACK', 'montserrat', 26, 700), ('100%', 'montserrat', 110, 900), ('GUARANTEE', 'montserrat', 30, 700), ring='#99F6E4'))

    # Kids
    add(trio('first-birthday', 'First birthday', 'Kids', ['birthday', 'first', 'baby', 'kids', 'party'], 840, [
        part("I'm", 'patrick-hand', 70, 400, '#0EA5E9'),
        part('ONE!', 'bungee', 200, 400, '#F59E0B', lh=1.0, effect={'type': 'lift'}),
        part("Come party with Leo", 'patrick-hand', 44, 400, '#475569', gap=8),
    ]))
    add(trio('back-to-school', 'Back to school', 'Kids', ['school', 'back to school', 'kids', 'education', 'september'], 880, [
        part('back to', 'indie-flower', 90, 400, '#DC2626'),
        part('SCHOOL', 'alfa-slab-one', 150, 400, '#1D4ED8', ls=4, lh=1.0),
        part('pencils sharpened · bags packed', 'indie-flower', 40, 400, '#4B5563', gap=10),
    ]))
    add(trio('story-time', 'Story time', 'Kids', ['story', 'reading', 'library', 'kids', 'books'], 840, [
        part('Story', 'pacifico', 120, 400, '#7C3AED', lh=1.3),
        part('TIME', 'nunito', 110, 900, '#F97316', ls=12, lh=1.0),
        part('Saturdays at 10 in the library', 'nunito', 30, 600, GREY, gap=12),
    ]))
    add(trio('its-a-boy', "It's a boy", 'Kids', ['baby', 'boy', 'announcement', 'birth', 'kids'], 820, [
        part("it's a", 'dancing-script', 90, 700, '#64748B'),
        part('BOY', 'nunito', 190, 900, '#38BDF8', ls=14, lh=1.0),
        part('Welcome, little Sam', 'nunito', 34, 600, '#64748B', gap=10),
    ]))
    add(trio('its-a-girl', "It's a girl", 'Kids', ['baby', 'girl', 'announcement', 'birth', 'kids'], 820, [
        part("it's a", 'dancing-script', 90, 700, '#64748B'),
        part('GIRL', 'nunito', 190, 900, '#F472B6', ls=14, lh=1.0),
        part('Welcome, little Mae', 'nunito', 34, 600, '#64748B', gap=10),
    ]))
    add(trio('play-date', 'Play date', 'Kids', ['play', 'kids', 'party', 'fun', 'playground'], 860, [
        part("LET'S", 'bungee', 70, 400, '#22C55E', ls=4),
        part('play!', 'pacifico', 150, 400, '#F97316', lh=1.3, rotation=-4),
        part('Sunday at the big park', 'patrick-hand', 40, 400, '#475569', gap=4),
    ]))
    add(trio('dino-party', 'Dino party', 'Kids', ['dinosaur', 'party', 'birthday', 'kids', 'roar'], 880, [
        part('ROAR!', 'bungee', 170, 400, '#16A34A', lh=1.0, effect={'type': 'echo', 'color': '#BBF7D0'}),
        part("Max is turning 5", 'patrick-hand', 60, 400, '#14532D', gap=10),
        part('Dino dig party · 2 pm', 'nunito', 30, 700, '#4B5563', gap=8, ls=2),
    ]))
    add(trio('star-pupil', 'Star pupil', 'Kids', ['award', 'school', 'kids', 'star', 'certificate'], 860, [
        part('STAR', 'alfa-slab-one', 150, 400, '#EAB308', ls=6, lh=1.0),
        part('of the week', 'caveat', 80, 700, '#1D4ED8'),
        part('Well done, Ava!', 'nunito', 40, 800, '#111827', gap=8),
    ]))
    add(trio('summer-camp', 'Summer camp', 'Kids', ['camp', 'summer', 'kids', 'outdoors', 'holiday'], 880, [
        part('SUMMER', 'alfa-slab-one', 120, 400, '#EA580C', ls=4, lh=1.0),
        part('camp', 'permanent-marker', 120, 400, '#15803D', rotation=-4),
        part('Five days of fun outdoors', 'nunito', 32, 600, '#4B5563', gap=6),
    ]))
    return out


def main():
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    combos = build()
    ids = [c['id'] for c in combos]
    if len(set(ids)) != len(ids):
        sys.exit('an id is listed twice')
    lines = [json.dumps(c, ensure_ascii=False, separators=(',', ':')) for c in combos]
    text_out = '[\n' + ',\n'.join(lines) + '\n]\n'
    json.loads(text_out)
    RESOURCE.write_text(text_out, encoding='utf-8')
    print(f'{len(combos)} combinations written to {RESOURCE}')
    if len(sys.argv) == 2:
        staging = pathlib.Path(sys.argv[1])
        staging.mkdir(parents=True, exist_ok=True)
        (staging / 'textcombos.json').write_text(text_out, encoding='utf-8')
        (staging / 'textcombos.txt').write_text(ios_readme(combos), encoding='utf-8')
        print(f'textcombos.json and textcombos.txt written to {staging}')


def ios_readme(combos):
    lines = [
        'textcombos.json: the font combinations in Add > Text, written by the Android',
        'repo\'s tools/generate_textcombos.py. Bundle it as it is; the Android app reads',
        'the same bytes from core/src/main/resources/com/canvia/core/content/.',
        '',
        'Shape',
        '-----',
        '[{"id","name","tags":[…],"category","w":<box width>,"elements":[<Element, the iOS JSON>…]}, …]',
        'category is one of Headline, Sale, Quote, Event, Wedding, Social, Retro, Minimal,',
        'Badge, Kids, Animated, in that order the chips list them.',
        'Each element sits in a box w wide from 0, 0, in a 1080-wide page\'s units, with',
        'its x, y, w and h, and a text with fontFamily, fontSize, fontWeight, align,',
        'lineHeight, letterSpacing and color written out; no ids. The fields used are',
        'the design file\'s own: italic, rotation, effect, curve, warp, uppercase, spans',
        'with spansText, textFill, animation and exitAnimation ({kind, delay, duration,',
        'by?}), shapes ("rect", "circle", "heart", "star-4") and lines.',
        'The box\'s height is the lowest bottom (y + h) of its elements.',
        '',
        'As Android does it (TextCombos in :core, addTextCombo in the editor)',
        '------------------',
        'Text tab: the role inserts and "Add a page number", then "Font combinations":',
        'category chips (All, then the ten), a "Recently used" row (this phone\'s last 8',
        'ids, newest first), a "From your brand" row when the kit in use sets a title,',
        'heading or body face — each combination\'s texts re-set by size rank, largest',
        'the title\'s face (else the heading\'s), the next the subheading\'s, the rest',
        'the body\'s (BrandRoles.fontFor), family and weight, sizes kept — and a',
        '2-column grid of thumbnails drawn by the page renderer, cached, each named',
        'under it and for a screen reader "<name> font combination". The Add panel\'s',
        'field, "Search font combinations", keeps the combinations whose name, a tag',
        'or category contains the query (case and accents aside, as the font picker',
        'searches), in file order, and hides the inserts above; none: "No font',
        'combinations match “<query>”." The six pairings are the first six entries.',
        'A tap: scale s = pageWidth * 0.72 / w; the box goes s times as big, centred',
        'on the page both ways (left = (pageWidth - w*s) / 2, top = (pageHeight - h*s) / 2,',
        'nothing rounded); each element x = left + x*s, y = top + y*s, its w, h,',
        'fontSize, letterSpacing, radius, strokeWidth and corners times s, a line\'s',
        'thickness max(1, thickness * s); effects, curves and spans are relative and',
        'stay. Every element gets a fresh id, all one fresh group id; each text then',
        'takes its measured height, its top kept. Added on top of the page, selected',
        'as the group, as one undo step. Brand colours are not applied.',
        '',
        'Combinations (id, element count, name)',
        '------------',
    ]
    for c in combos:
        lines.append(f"{c['id'].ljust(22)}{str(len(c['elements'])).ljust(4)}{c['name']}")
    lines.append('')
    return '\n'.join(lines)


if __name__ == '__main__':
    main()
