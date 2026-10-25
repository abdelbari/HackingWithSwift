#!/usr/bin/env python3
"""Write round 34's templates: starts for the design types the catalogue
gained (templates/sizes.json), from the app's own content only.

    python3 tools/generate_design_types.py
    python3 tools/generate_templates.py

writes templates/round34-types.json:

  - six seamless carousels (Instagram and LinkedIn Carousel, 3240 x 1350,
    three 1080 x 1350 slides) whose circle, band, star and rule
    deliberately run across the seams, the words kept inside a slide each;
  - six each for the types of a size no template had — Twitch Panel,
    Discord Banner, Rack Card, Flyer (DL), T-Shirt Print and Tote Bag
    Print — and for Lesson Plan (A4);
  - reports as sets of four pages (three A4, three US Letter), proposals
    as sets of five, trifold brochures as two pages of three panels
    (outside and inside), and birthday and thank-you cards as two pages
    (front and inside).

Each carries its `topic` (the type it was made for) and `style`, the facets
the Filters sheet filters by. The layouts, colourways and font pairs are
round 33's (tools/generate_template_variants.py), so the new starts look
like the library they join; everything is seeded from each template's own
id (zlib.crc32), so the output is the same on every run. Nothing is
downloaded.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import generate_template_variants as gtv  # noqa: E402
from generate_templates import SIZES as PIXELS  # noqa: E402

OUT = os.path.join(gtv.SPEC_DIR, "round34-types.json")

# Every type's size in pixels, as the generator reads sizes.json.
gtv.SIZES.update({k: (int(w), int(h)) for k, (w, h) in PIXELS.items()})

STYLES = ["minimal", "bold", "elegant", "playful", "corporate"]


def look(tid, style=None, dark=None):
    """A template's colourway, dark or light, and font pair, from its id."""
    rng = gtv.seeded(tid)
    colours = gtv.PALETTES[rng.randrange(len(gtv.PALETTES))][1]
    style = style or STYLES[rng.randrange(len(STYLES))]
    pairs = gtv.PAIRS[style]
    pair = pairs[rng.randrange(len(pairs))]
    if dark is None:
        dark = rng.random() < 0.5
    return gtv.roles(colours, dark=dark), pair, style


def page_of(p, title=None):
    page = {"background": {"kind": "color", "color": p.pal["bg"]}, "elements": gtv.strip(p.els)}
    if title:
        page["title"] = title
    return page


# ------------------------------------------------------------ single pages

# The types made of one page, each from round 33's layouts in turn, with
# the copy it takes.
SINGLES = [
    ("discord-banner", "Social", "Banner", ["hero", "centered", "split"], [
        {"name": "Pixel Guild", "kicker": "Gaming community", "headline": "Welcome to Pixel Guild",
         "body": "Weekly raids, friendly people and no spoilers.", "cta": "Say hello", "detail": "Raids every Friday",
         "points": ["Weekly raids", "Art channel", "Voice chat"]},
        {"name": "Study Hall", "kicker": "Study together", "headline": "Study Hall Server",
         "body": "Quiet rooms, focus timers and homework help.", "cta": "Join a room", "detail": "Open around the clock",
         "points": ["Focus rooms", "Homework help", "Exam season tips"]},
        {"name": "Synth Club", "kicker": "Music makers", "headline": "Synth Club",
         "body": "Share a loop, get feedback, make something new.", "cta": "Post a track", "detail": "Monthly challenge",
         "points": ["Feedback threads", "Sample swaps", "Live sessions"]},
        {"name": "Book Nook", "kicker": "Reading club", "headline": "The Book Nook",
         "body": "One book a month and a long chat about it.", "cta": "Pick a book", "detail": "Next read: Circe",
         "points": ["Monthly pick", "Spoiler tags", "Author Q&A"]},
        {"name": "Indie Devs", "kicker": "Make games", "headline": "Indie Devs Hangout",
         "body": "Show your build, find a team, ship your game.", "cta": "Share a build", "detail": "Game jam in May",
         "points": ["Devlogs", "Team finder", "Game jams"]},
        {"name": "Plant Parents", "kicker": "Green thumbs", "headline": "Plant Parents",
         "body": "Cuttings, care tips and a lot of photos of leaves.", "cta": "Show your plants", "detail": "Swap meet Sunday",
         "points": ["Care tips", "Cutting swaps", "Pest help"]},
    ]),
    ("rack-card", "Travel", "Rack Card", ["split", "hero", "centered"], [
        {"name": "Harbour Tours", "kicker": "Boat trips daily", "headline": "See the Harbour From the Water",
         "body": "Ninety minutes past the lighthouse, the seals and the old fort.", "cta": "Book a seat",
         "detail": "Pier 3 · 10 am to 5 pm", "points": ["Seal colony", "Lighthouse", "Old fort"]},
        {"name": "Valley Winery", "kicker": "Tastings and tours", "headline": "Valley Winery",
         "body": "Walk the vines, taste five wines and stay for lunch.", "cta": "Reserve a tasting",
         "detail": "Open Thursday to Sunday", "points": ["Five-wine flight", "Vineyard walk", "Farm lunch"]},
        {"name": "Old Town Walk", "kicker": "Free walking tour", "headline": "Old Town Stories",
         "body": "Two hours of lanes, legends and the best pastry in town.", "cta": "Meet at the fountain",
         "detail": "Daily at 11 am", "points": ["Hidden lanes", "Local legends", "Pastry stop"]},
        {"name": "Kayak Hire", "kicker": "Paddle the river", "headline": "Kayaks for Hire",
         "body": "Singles, doubles and family boats, by the hour or the day.", "cta": "Hire a kayak",
         "detail": "Life jackets included", "points": ["By the hour", "Family boats", "No experience needed"]},
        {"name": "Science Museum", "kicker": "Hands-on fun", "headline": "Discover Science",
         "body": "Three floors of experiments to touch, build and launch.", "cta": "Plan your visit",
         "detail": "Children under 5 free", "points": ["Planetarium", "Robot lab", "Water play"]},
        {"name": "Farm Shop", "kicker": "Fresh every day", "headline": "Meadow Farm Shop",
         "body": "Eggs, bread, cheese and vegetables from up the lane.", "cta": "Visit the farm",
         "detail": "Open 8 am to 6 pm", "points": ["Free-range eggs", "Fresh bread", "Local cheese"]},
    ]),
    ("flyer-dl", "Marketing", "DL Flyer", ["split", "centered", "hero"], [
        {"name": "Yoga Classes", "kicker": "New term", "headline": "Yoga for Everyone",
         "body": "Gentle classes for every body, every level.", "cta": "First class free",
         "detail": "Mondays and Thursdays · 7 pm", "points": ["Beginners welcome", "Mats provided", "Small groups"]},
        {"name": "Window Cleaning", "kicker": "Local and reliable", "headline": "Sparkling Windows",
         "body": "Inside and out, frames and sills, every four weeks.", "cta": "Get a quote",
         "detail": "Fully insured", "points": ["Every four weeks", "Frames and sills", "Fully insured"]},
        {"name": "Pizza Menu", "kicker": "Order tonight", "headline": "Stone Oven Pizza",
         "body": "Hand-stretched dough, slow tomato and proper mozzarella.", "cta": "Order now",
         "detail": "Free delivery over 20", "points": ["Margherita", "Diavola", "Funghi"]},
        {"name": "Piano Lessons", "kicker": "All ages", "headline": "Learn the Piano",
         "body": "Friendly lessons at home or in the studio.", "cta": "Book a trial",
         "detail": "Grades 1 to 8", "points": ["Beginners", "Exam prep", "Adults welcome"]},
        {"name": "Community Fair", "kicker": "Free entry", "headline": "Spring Fair on the Green",
         "body": "Stalls, games, music and a cake competition.", "cta": "Bring the family",
         "detail": "Saturday 10 am to 4 pm", "points": ["Craft stalls", "Live music", "Cake contest"]},
        {"name": "Dog Walking", "kicker": "Happy dogs", "headline": "Daily Dog Walks",
         "body": "Hour-long walks in small groups, picked up from your door.", "cta": "Meet the walker",
         "detail": "Insured and trained", "points": ["Small groups", "Door pick-up", "Photo updates"]},
    ]),
    ("tshirt-print", "Personal", "Tee", ["centered", "hero", "centered"], [
        {"name": "Coffee First", "kicker": "But first", "headline": "Coffee",
         "body": "Then we can talk.", "cta": "Est. 6 am", "detail": "Brewed daily", "points": []},
        {"name": "Team Run", "kicker": "City 10K", "headline": "Run Club",
         "body": "We run for the post-race breakfast.", "cta": "Sunday crew", "detail": "Est. 2026", "points": []},
        {"name": "Plant Lady", "kicker": "Certified", "headline": "Plant Lady",
         "body": "Ask me about my monstera.", "cta": "Water me", "detail": "Grow slow", "points": []},
        {"name": "Family Reunion", "kicker": "The Garcia family", "headline": "Reunion 2026",
         "body": "Same family, louder every year.", "cta": "Lake Tahoe", "detail": "July 4 weekend", "points": []},
        {"name": "Good Vibes", "kicker": "Only", "headline": "Good Vibes",
         "body": "Sun, sea and a playlist.", "cta": "All summer", "detail": "Stay golden", "points": []},
        {"name": "Bake Club", "kicker": "Proudly", "headline": "Bake Club",
         "body": "Will bake for compliments.", "cta": "Since 2019", "detail": "Butter is love", "points": []},
    ]),
    ("tote-print", "Personal", "Tote", ["centered", "hero", "centered"], [
        {"name": "Farmers Market", "kicker": "Saturday", "headline": "Market Day",
         "body": "Fresh, local, in season.", "cta": "Carry it home", "detail": "Shop local", "points": []},
        {"name": "Library Bag", "kicker": "Property of", "headline": "Book Lover",
         "body": "One more chapter.", "cta": "Read more", "detail": "Overdue, probably", "points": []},
        {"name": "Beach Day", "kicker": "Packed for", "headline": "Beach Day",
         "body": "Towel, snacks, sunscreen.", "cta": "Salt air", "detail": "Low tide", "points": []},
        {"name": "Reusable", "kicker": "Say no to plastic", "headline": "Bag for Life",
         "body": "Use me again and again.", "cta": "Refill", "detail": "Reuse", "points": []},
        {"name": "Art School", "kicker": "Class of 2026", "headline": "Art School",
         "body": "Brushes, sketchbooks, big ideas.", "cta": "Make art", "detail": "Studio 4", "points": []},
        {"name": "Corner Cafe", "kicker": "The", "headline": "Corner Cafe",
         "body": "Good coffee, good company.", "cta": "Since 1998", "detail": "Main Street", "points": []},
    ]),
    ("lesson-plan-a4", "Education", "Lesson Plan", ["split", "split", "split"], [
        {"name": "Fractions", "kicker": "Maths · Year 4", "headline": "Adding Fractions",
         "body": "Pupils add fractions with the same denominator using pictures, then numbers.",
         "cta": "Exit ticket", "detail": "60 minutes · Room 12", "points": ["Warm-up: pizza slices", "Model on the board", "Pairs practice"]},
        {"name": "Water Cycle", "kicker": "Science · Year 5", "headline": "The Water Cycle",
         "body": "Pupils explain evaporation, condensation and precipitation with a bag experiment.",
         "cta": "Label the cycle", "detail": "50 minutes · Lab", "points": ["Hook: rain video", "Bag experiment", "Draw and label"]},
        {"name": "Persuasive Writing", "kicker": "English · Year 6", "headline": "Persuasive Letters",
         "body": "Pupils plan and write a letter that argues for a change at school.",
         "cta": "Peer review", "detail": "Two lessons", "points": ["Read an example", "Plan three reasons", "Draft and edit"]},
        {"name": "Ancient Egypt", "kicker": "History · Year 3", "headline": "Life on the Nile",
         "body": "Pupils find out why the Nile mattered to farmers, traders and pharaohs.",
         "cta": "Map quiz", "detail": "45 minutes", "points": ["Map the river", "Sort the jobs", "Share findings"]},
        {"name": "Coding Loops", "kicker": "Computing · Year 5", "headline": "Repeat With Loops",
         "body": "Pupils shorten a long program by spotting patterns and using a loop.",
         "cta": "Debug challenge", "detail": "Computer room", "points": ["Unplugged game", "Spot the pattern", "Write a loop"]},
        {"name": "French Greetings", "kicker": "French · Year 3", "headline": "Bonjour!",
         "body": "Pupils greet each other and say how they feel in French.",
         "cta": "Role play", "detail": "30 minutes", "points": ["Listen and repeat", "Feelings song", "Greet a partner"]},
    ]),
]


def singles():
    out = []
    for size_id, category, word, layouts, copies in SINGLES:
        for i, c in enumerate(copies):
            tid = f"{size_id}-{i + 1}"
            pal, pair, style = look(tid)
            # A shirt's or a bag's print is the picture on it: light ink on
            # nothing much, so the page is the palette's lightest.
            if size_id in ("tshirt-print", "tote-print"):
                pal, pair, style = look(tid, dark=False)
            p = gtv.laid_out(size_id, pal, pair, i % 2 == 1, layouts[i % len(layouts)], c, None)
            out.append({"id": tid, "name": f"{c['name']} {word}", "category": category, "sizeId": size_id,
                        "topic": size_id, "style": style, **page_of(p)})
    return out


# ------------------------------------------------------------ twitch panels

PANELS = ["About Me", "Schedule", "Donate", "Rules", "My Setup", "Socials"]


def twitch():
    """A Twitch panel: its title on a band, an accent edge and a star."""
    out = []
    for i, title in enumerate(PANELS):
        tid = f"twitch-panel-{i + 1}"
        pal, pair, style = look(tid, dark=True)
        p = gtv.Page("twitch-panel", pal, pair, False)
        p.shape("panel", "rect", 0, 0, 18, 160)
        p.shape("decor", "star", 252, 20, 48, 48, opacity=0.5)
        p.text("headline", title, 40, 52, 220, 40, face="head", upper=True, lh=1.1)
        p.line("rule", 40, 108, 90, 6)
        out.append({"id": tid, "name": f"{title} Twitch Panel", "category": "Social", "sizeId": "twitch-panel",
                    "topic": "twitch-panel", "style": style, **page_of(p)})
    return out


# ---------------------------------------------------------------- carousels

CAROUSELS = [
    {"name": "Five Habits", "kicker": "Swipe for more", "headline": "Five Habits of Calm People",
     "body": "Small routines that make a busy week feel lighter.", "points": ["Plan the night before", "Walk at lunch", "Phone off at nine"],
     "close": "Which one will you try?", "cta": "Save this post"},
    {"name": "Brand Launch", "kicker": "Introducing", "headline": "Meet Fieldnote",
     "body": "Notebooks made from recycled cotton, stitched by hand.", "points": ["Recycled cotton", "Lay-flat binding", "Made in Porto"],
     "close": "Out now, in six colours", "cta": "Shop the range"},
    {"name": "Recipe Steps", "kicker": "Easy dinner", "headline": "One-Pan Lemon Chicken",
     "body": "Thirty minutes, one pan and almost no washing up.", "points": ["Brown the chicken", "Add lemon and garlic", "Roast for 20 minutes"],
     "close": "Dinner is served", "cta": "Save for later"},
    {"name": "Hiring Now", "kicker": "We're hiring", "headline": "Join Our Design Team",
     "body": "We're looking for a product designer who loves detail.", "points": ["Remote friendly", "Four-day week", "Learning budget"],
     "close": "Apply by May 30", "cta": "See the role"},
    {"name": "Travel Guide", "kicker": "48 hours in", "headline": "Lisbon in a Weekend",
     "body": "Trams, tiles, custard tarts and a sunset over the river.", "points": ["Ride tram 28", "Eat pastel de nata", "Sunset at Graça"],
     "close": "Pack light, walk lots", "cta": "Follow for part 2"},
    {"name": "Study Tips", "kicker": "Exam season", "headline": "Study Smarter, Not Longer",
     "body": "Three methods that beat rereading your notes.", "points": ["Test yourself", "Space it out", "Teach a friend"],
     "close": "You've got this", "cta": "Share with a friend"},
]


def carousels():
    """Three 1080 x 1350 slides on one 3240 wide page: the words kept
    inside a slide each, and the circle, the band, the star and the rule
    running across the seams, so the panorama carries on as you swipe."""
    out = []
    slide = 1080
    for i, c in enumerate(CAROUSELS):
        tid = f"carousel-{i + 1}"
        pal, pair, style = look(tid)
        p = gtv.Page("insta-carousel", pal, pair, False)
        m = 110
        p.shape("decor", "circle", slide - 420, 380, 840, 840, opacity=0.18)
        p.shape("panel", "rect", slide * 1.5, 960, slide * 1.1, 150, color="soft", radius=75)
        p.shape("decor", "star", slide * 2 - 70, 140, 140, 140)
        p.line("rule", m, 1220, slide * 3 - 2 * m, 10)
        w = slide - 2 * m
        y = p.text("kicker", c["kicker"], m, 220, w, 36, color="kicker", spacing=6, upper=True) + 30
        p.text("headline", c["headline"], m, y, w * 0.9, 112, face="head")
        x2 = slide + m
        y = p.text("body", c["body"], x2, 220, w, 48) + 50
        p.text("points", "\n".join(c["points"]), x2, y, w, 44, lh=1.6)
        x3 = slide * 2 + m
        y = p.text("headline", c["close"], x3, 300, w, 96, face="head") + 60
        p.pill(c["cta"], x3, y, 40)
        out.append({"id": tid, "name": f"{c['name']} Carousel", "category": "Social", "sizeId": "insta-carousel",
                    "topic": "carousel", "style": style, **page_of(p)})
    return out


# ------------------------------------------------------------ sets of pages

REPORTS = [
    ("Annual Report", "Northwind Retail", "2026 in review", "Revenue grew for the third year running, led by online sales.",
     ["Revenue up 14%", "40,000 new customers", "Two new stores"]),
    ("Impact Report", "Green Streets Trust", "Our year of planting", "Volunteers planted more trees than in our first five years together.",
     ["12,000 trees planted", "900 volunteers", "35 schools joined"]),
    ("Research Report", "City Transport Study", "How we travel", "Most short trips could be walked or cycled with safer routes.",
     ["62% of trips under 3 km", "Cycling up 18%", "Bus use steady"]),
    ("Market Report", "Coffee Market 2026", "Trends and outlook", "Specialty coffee keeps growing as drinkers trade up at home.",
     ["Home brewing up 22%", "Oat milk leads", "Cold brew all year"]),
    ("Progress Report", "Project Lighthouse", "Quarter three update", "The new app is in beta, on time and slightly under budget.",
     ["Beta with 400 users", "Budget 4% under", "Launch in March"]),
    ("School Report", "Riverside Academy", "Our year together", "Attendance and reading scores are the highest they have been.",
     ["Attendance 96%", "Reading up two levels", "New science lab"]),
]

PROPOSALS = [
    ("Website Proposal", "A New Website for Bloom Florists", "Online orders are 10% of sales; customers want to order from their phones.",
     "A fast shop with same-day delivery booking.", ["Discovery workshop", "Design and build", "Launch and training"], "6 weeks · 8,400"),
    ("Marketing Proposal", "Spring Campaign for Hearth Bakery", "The new store opens in April and few people nearby know the name.",
     "A neighbourhood campaign online and on the street.", ["Launch posters", "Social ads", "Opening day event"], "4 weeks · 3,200"),
    ("Event Proposal", "The Summer Gala at Linden Hall", "Last year's gala sold out in a week and turned many guests away.",
     "A bigger venue, a garden stage and timed tickets.", ["Venue and stage", "Catering for 400", "Ticketing"], "3 months · 22,000"),
    ("Research Proposal", "Sleep and Screen Time in Teens", "We know little about how late-night phone use changes sleep at 14.",
     "A twelve-week study with 200 volunteers and sleep trackers.", ["Recruit and consent", "Twelve-week study", "Analysis and paper"], "1 year · 48,000"),
    ("Partnership Proposal", "Partnering With Trailhead Outfitters", "Both of us serve hikers, but we reach them at different moments.",
     "Joint guided walks with gear to try on the trail.", ["Monthly walks", "Shared newsletter", "Member discount"], "Pilot · 6 months"),
    ("Consulting Proposal", "Faster Onboarding at Kite Labs", "New hires take eight weeks to ship their first change.",
     "A clear first month with a buddy, docs and a starter task.", ["Interview new hires", "Write the playbook", "Run two cohorts"], "8 weeks · 12,500"),
]

TRIFOLDS = [
    ("Dental Clinic", "Smile Bright Dental", "Gentle care for the whole family",
     [("Our services", "Check-ups, cleaning, fillings and whitening, all under one roof."),
      ("Meet the team", "Four dentists and a hygienist who take time to explain."),
      ("New patients", "Book online and get your first check-up free.")]),
    ("Garden Centre", "Willow Garden Centre", "Plants, pots and good advice",
     [("Plants", "Seasonal bedding, shrubs and trees, grown on site."),
      ("Workshops", "Saturday sessions on pruning, planting and wreaths."),
      ("Cafe", "Cake and coffee among the greenhouses.")]),
    ("Yoga Retreat", "Stillwater Retreat", "A weekend to slow down",
     [("The weekend", "Morning yoga, forest walks and long, unhurried meals."),
      ("Where you stay", "Twelve cabins by the lake, each with a wood stove."),
      ("Book a place", "Spring and autumn retreats, from Friday to Sunday.")]),
    ("Charity", "Hope Kitchen", "Hot meals, warm welcome",
     [("What we do", "We serve 300 meals a week to anyone who needs one."),
      ("How to help", "Volunteer a shift, donate food or give monthly."),
      ("Our impact", "Last year we served 15,000 meals with 120 volunteers.")]),
    ("Real Estate", "Harbour & Hill Homes", "Find the home that fits",
     [("Buying", "Viewings, valuations and a team that knows every street."),
      ("Selling", "Professional photos, floor plans and honest advice."),
      ("Letting", "Tenants found, references checked, rent collected.")]),
    ("Museum", "City History Museum", "Five thousand years in one building",
     [("Galleries", "From Roman coins to the first city tram."),
      ("Families", "Trails, dressing up and a hands-on discovery room."),
      ("Visit", "Open every day but Monday. Entry is free.")]),
]

CARDS = {
    "birthday-card": ("Birthday Card", "Personal", [
        ("Happy Birthday", "Hip hip hooray", "Happy Birthday", "Wishing you a year of good things", "Have the best day, and save me some cake!"),
        ("Party Animal", "Let's celebrate", "Another Lap Around the Sun", "Here's to you", "May your year be full of adventures and naps."),
        ("Thirty Flirty", "Cheers to thirty", "Thirty and Thriving", "Raise a glass", "Thirty looks good on you. Let's celebrate properly."),
        ("Little One", "You're one!", "Happy First Birthday", "Big wishes for a little person", "One year of smiles, giggles and messy dinners."),
        ("Golden Years", "Happy 80th", "Eighty Years Young", "With love from us all", "Thank you for every story, every lesson and every laugh."),
        ("Birthday Wishes", "Make a wish", "Happy Birthday to You", "Sending love your way", "I hope today is as wonderful as you are."),
    ]),
    "thank-you-card": ("Thank You Card", "Personal", [
        ("Thank You", "From the heart", "Thank You", "You made a difference", "Thank you for your kindness and your help this year."),
        ("Teacher Thanks", "To the best teacher", "Thank You, Teacher", "For every lesson", "Thank you for making every day in class an adventure."),
        ("Wedding Thanks", "With love", "Thank You for Coming", "Our wedding day", "Having you there made the day complete. Thank you for the lovely gift."),
        ("Big Thanks", "Thanks a million", "You're the Best", "Seriously, thank you", "I couldn't have done it without you. Coffee is on me."),
        ("Customer Thanks", "Thank you for your order", "We Appreciate You", "From our small shop", "Every order helps our small team keep making things we love."),
        ("Nurse Thanks", "With gratitude", "Thank You for Caring", "For your care and patience", "Thank you for looking after us so kindly. We won't forget it."),
    ]),
}


def report_pages(size_id, c, tid):
    name, org, kicker, finding, points = c
    pal, pair, style = look(tid, style="corporate")
    dark, _, _ = look(tid, style="corporate", dark=True)
    copy = {"name": name, "kicker": kicker, "headline": f"{org} {name}", "body": finding, "cta": "Read the summary",
            "detail": org, "points": points}
    pages = [page_of(gtv.laid_out(size_id, dark, pair, False, "hero", copy, None), "Cover")]
    sections = [("Summary", "At a glance", finding), ("Results", "What we found", "The numbers behind the year, and what drove them."),
                ("Next steps", "Looking ahead", "Three priorities for the year ahead, each with an owner.")]
    for k, (title, kick, body) in enumerate(sections):
        c2 = {**copy, "kicker": kick, "headline": title, "body": body}
        layout = "centered" if k == 2 else "split"
        pages.append(page_of(gtv.laid_out(size_id, pal, pair, k == 1, layout, c2, None), title))
    return pages, style


def proposal_pages(c, tid):
    name, title, problem, answer, steps, cost = c
    pal, pair, style = look(tid, style="corporate", dark=False)
    dark, _, _ = look(tid, style="corporate", dark=True)
    base = {"name": name, "kicker": name, "headline": title, "body": "Prepared by Canvia Studio for your review.",
            "cta": "Let's talk", "detail": cost, "points": steps}
    pages = [page_of(gtv.laid_out("proposal", dark, pair, False, "hero", base, None), "Cover")]
    sections = [("The challenge", problem, "split"), ("Our approach", answer, "split"),
                ("Timeline and cost", f"Three stages, {cost}.", "split"), ("Next steps", "Sign below and we can start next week.", "centered")]
    for k, (head, body, layout) in enumerate(sections):
        c2 = {**base, "kicker": name, "headline": head, "body": body}
        pages.append(page_of(gtv.laid_out("proposal", pal, pair, k % 2 == 1, layout, c2, None), head))
    return pages, style


def trifold_pages(c, tid):
    """Two pages of three 1100 wide panels: the outside — the inside flap,
    the back and the cover, left to right, as it folds — and the inside."""
    kind, org, line, panels = c
    pal, pair, style = look(tid)
    panel = 1100
    m = 110
    w = panel - 2 * m

    outside = gtv.Page("trifold-letter", pal, pair, False)
    outside.shape("panel", "rect", panel * 2, 0, panel, 2550)
    outside.text("headline", org, panel * 2 + m, 700, w, 120, face="head", color="on")
    outside.text("kicker", line, panel * 2 + m, 1300, w, 44, color="on", spacing=4, upper=True)
    title, body = panels[0]
    y = outside.text("headline", title, m, 300, w, 80, face="head") + 40
    outside.text("body", body, m, y, w, 44)
    outside.line("rule", panel + m, 1100, w * 0.4, 8)
    outside.text("detail", f"{org}\nhello@example.com", panel + m, 1180, w, 40, align="left")

    inside = gtv.Page("trifold-letter", pal, pair, False)
    for k, (title, body) in enumerate(panels):
        x = panel * k + m
        inside.shape("decor", "circle", x, 260, 160, 160, opacity=0.8)
        y = inside.text("headline", title, x, 500, w, 80, face="head") + 40
        inside.text("body", body, x, y, w, 44)
    inside.line("rule", m, 2300, panel * 3 - 2 * m, 6)
    return [page_of(outside, "Outside"), page_of(inside, "Inside")], style


def card_pages(size_id, c, tid):
    name, kicker, headline, sub, message = c
    pal, pair, style = look(tid, style="playful" if size_id == "birthday-card" else "elegant")
    front = {"name": name, "kicker": kicker, "headline": headline, "body": sub, "cta": "", "detail": "", "points": []}
    inside = {"name": name, "kicker": "", "headline": "", "body": message, "cta": "", "detail": "With love", "points": []}
    p1 = gtv.laid_out(size_id, pal, pair, False, "centered", {**front, "detail": "★"}, None)
    p2 = gtv.Page(size_id, pal, pair, False)
    u, m = p2.u, p2.m
    p2.shape("decor", "heart" if size_id == "birthday-card" else "star", (p2.w - u * 0.12) / 2, m * 2, u * 0.12, u * 0.12)
    y = p2.text("body", inside["body"], m * 1.5, p2.h * 0.35, p2.w - 3 * m, u * 0.06, align="center", lh=1.4) + u * 0.08
    p2.text("detail", inside["detail"], m * 1.5, y, p2.w - 3 * m, u * 0.05, face="head", align="center", color="kicker")
    return [page_of(p1, "Front"), page_of(p2, "Inside")], style


def sets():
    out = []
    for i, c in enumerate(REPORTS):
        size_id = "report-a4" if i < 3 else "report-letter"
        tid = f"{size_id}-{i % 3 + 1}"
        pages, style = report_pages(size_id, c, tid)
        out.append({"id": tid, "name": f"{c[1]} {c[0]}", "category": "Business", "sizeId": size_id,
                    "topic": "report", "style": style, "pages": pages})
    for i, c in enumerate(PROPOSALS):
        tid = f"proposal-{i + 1}"
        pages, style = proposal_pages(c, tid)
        out.append({"id": tid, "name": c[0], "category": "Business", "sizeId": "proposal",
                    "topic": "proposal", "style": style, "pages": pages})
    for i, c in enumerate(TRIFOLDS):
        tid = f"trifold-letter-{i + 1}"
        pages, style = trifold_pages(c, tid)
        out.append({"id": tid, "name": f"{c[0]} Trifold", "category": "Marketing", "sizeId": "trifold-letter",
                    "topic": "trifold-letter", "style": style, "pages": pages})
    for size_id, (word, category, copies) in CARDS.items():
        for i, c in enumerate(copies):
            tid = f"{size_id}-{i + 1}"
            pages, style = card_pages(size_id, c, tid)
            out.append({"id": tid, "name": f"{c[0]} {word}", "category": category, "sizeId": size_id,
                        "topic": size_id, "style": style, "pages": pages})
    return out


def main():
    gtv.write(OUT, carousels() + twitch() + singles() + sets())


if __name__ == "__main__":
    main()
