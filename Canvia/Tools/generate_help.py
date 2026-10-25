#!/usr/bin/env python3
"""Write the help topics and the What's new notes both phones show.

    tools/generate_help.py [path/to/ios/folder]

Writes core/src/main/resources/com/canvia/core/content/help.json and
whatsnew.json — and, given the iPhone's Canvia/Canvia/Content folder, the
same two files there, byte for byte (the iPhone's copy of this script is
Canvia/Tools/generate_help.py).

help.json is a JSON array of the topics added since the first nineteen,
each {"id", "title", "body", "keywords", "opens"}: the English title and
body exactly as the strings catalogue keys them (each phone looks them up
in its language as it reads them), the words people search for, and where
"Show me" goes — a target's name in lower camel case ("brand",
"a11yCheck", "chartData") or null for none. The first nineteen topics stay
in each phone's code, worded for that phone's own controls; these come
after them, in this order, the same on both phones.

whatsnew.json is a JSON array, newest first, of {"version", "items"}: a
version is dotted whole numbers ("1.36"), compared part by part, and each
item is {"id", "title", "body", "opens"}, "opens" one of the places Home
can open — "tools", "trash", "templates" — or null.

Nothing is random and nothing is downloaded: the output is the same on
every run.
"""
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
CONTENT = REPO / 'core/src/main/resources/com/canvia/core/content'

# id, title, body, keywords, opens
TOPICS = [
    ('crop-mode', 'Crop mode',
     'Double-tap a photo or a clip to crop it where it sits. Drag the picture, pinch it, pull the frame in, pick a shape such as 1:1 or 9:16, straighten it with the dial, turn it a quarter or flip it. Done keeps it.',
     ['crop', 'straighten', 'ratio', 'rotate', 'flip', 'trim'], 'crop'),
    ('brushes', 'Brushes: erase, restore and blur',
     'Edit on a photo has brushes that erase part of it, bring an erased part back, blur or pixelate where you paint. The size slider sets the brush, and Undo takes back a stroke.',
     ['brush', 'erase', 'restore', 'blur', 'pixelate', 'magic eraser', 'paint'], None),
    ('cutout', "Removing a photo's background",
     'Edit on a photo can take its background out: erase what you do not want with the brush, or remove a white background from a logo. The Restore brush brings back what was taken.',
     ['remove background', 'background remover', 'cut out', 'cutout', 'transparent'], None),
    ('effects', 'Photo effects and filters',
     'Filters set a look at any strength. Adjust has light, colour, curves and selective colour. Effects add blur, glow, duotone, shadows and more; hold Compare to see the photo without them.',
     ['filter', 'effect', 'adjust', 'duotone', 'glow', 'blur', 'retouch', 'look'], 'style'),
    ('timeline', 'Timeline and clips',
     'Turn on the timeline in the editor\'s menu to see each page\'s length, its clips and its sound. Drag a clip\'s ends to trim it, split it at the playhead, and set its speed and volume.',
     ['timeline', 'video', 'clip', 'trim', 'split', 'speed', 'duration'], 'timeline'),
    ('animate', 'Animation',
     'Animate gives a page or an element a way in and out, and text can come in word by word. Page transitions play between pages in Present and in videos.',
     ['animate', 'animation', 'motion', 'transition', 'effect'], None),
    ('audio', 'Music and sound',
     'Audio adds music from the library, your own songs and sound effects. Each track can be trimmed, faded, set louder or quieter and fitted to the beat.',
     ['music', 'audio', 'sound', 'song', 'beat', 'sfx', 'volume'], 'audio'),
    ('voiceover', 'Voice-over',
     'Record your voice over a page in Audio, or have a text read aloud as a track. Enhance voice cleans it up.',
     ['voice-over', 'voiceover', 'narration', 'record', 'microphone', 'text to speech', 'read aloud'], 'audio'),
    ('captions', 'Captions',
     'Captions write what is said in a clip or a voice-over as words on the page, made on the phone. Change their words, their style and where they sit, or bring them in from an SRT file.',
     ['captions', 'subtitles', 'srt', 'transcript', 'words'], 'captions'),
    ('present', 'Presenting',
     'Present shows the design full screen, page by page. Tap or swipe to move on, or use the arrow keys on a keyboard. Magic shortcuts play confetti, a drumroll and more.',
     ['present', 'slideshow', 'slides', 'full screen', 'keyboard', 'shortcuts', 'confetti'], 'present'),
    ('presenter', 'Presenter view and recording',
     'Presenter view shows your notes, the next page and a timer while the audience sees only the slides. Present and record keeps you, the slides and your voice as a video to share.',
     ['presenter', 'notes', 'timer', 'record', 'camera', 'talk', 'pointer', 'pen'], 'present'),
    ('print', 'Printing and paper layout',
     'Print sends pages to a printer, or several to a sheet of A4 or Letter. The print-ready PDF adds bleed and crop marks.',
     ['print', 'paper', 'a4', 'letter', 'bleed', 'crop marks', 'cmyk', 'duplex'], 'print'),
    ('versions', 'Version history',
     'Version history keeps how the design looked earlier. Preview a version page by page, restore it whole, make a copy of it, or bring back just one page.',
     ['version', 'history', 'restore', 'earlier', 'bring back', 'page', 'pin'], 'versions'),
    ('brand', 'Brand kits',
     'A brand kit keeps your colours, fonts, logos, photos and text styles for every design. Pick its colours from a logo, and make a brand guidelines page from it.',
     ['brand', 'kit', 'logo', 'colours', 'colors', 'fonts', 'guidelines'], 'brand'),
    ('templates', 'Templates',
     'Templates start a design from a finished one. Search them, filter by style and colour, or add one as a new page of the design you have open.',
     ['template', 'layout', 'start', 'design', 'style'], 'add'),
    ('own-templates', 'Your templates',
     'Save as template keeps a design to start from again. Your templates can be renamed, starred, sent to someone else and brought in from a file.',
     ['save as template', 'your templates', 'send template', 'template file', 'share template'], None),
    ('planner', 'Planning posts',
     'Plan a post sets a day and time to post a design, with its caption. The planner on Home shows them on a calendar and reminds you when it is time.',
     ['planner', 'schedule', 'post', 'calendar', 'reminder', 'social'], 'planner'),
    ('bulk', 'Bulk create',
     'Bulk create makes a page for each row of a table you type or paste, filling texts and photos from its columns.',
     ['bulk create', 'mail merge', 'spreadsheet', 'csv', 'rows', 'data'], 'bulk'),
    ('docs', 'Docs',
     'A Doc is a long page of headings, words, lists, tables and pictures that flows on as you type. Export it as a Word file or a PDF, or turn a design into a Doc.',
     ['doc', 'document', 'word', 'docx', 'heading', 'report'], None),
    ('whiteboards', 'Whiteboards',
     'A whiteboard is one page that grows as you add to it, for sticky notes, drawing, diagrams and ideas.',
     ['whiteboard', 'sticky notes', 'brainstorm', 'diagram', 'infinite'], None),
    ('draw', 'Drawing',
     'Draw has pens, a marker and a highlighter in any colour and size, and an eraser. Shape assist turns a rough circle or arrow into a neat one.',
     ['draw', 'pen', 'marker', 'highlighter', 'stylus', 'freehand', 'shape assist'], 'draw'),
    ('charts', 'Charts and their data',
     'Add a chart, then type its numbers in its table, paste them or import a CSV. Pick a kind — bar, line, pie, donut, scatter and more — and its colours and labels.',
     ['chart', 'graph', 'data', 'csv', 'pie', 'bar', 'line'], 'chartData'),
    ('tables', 'Tables',
     'A table can have rows and columns added and removed, cells merged, borders and colours of its own, and a design to start from.',
     ['table', 'rows', 'columns', 'cells', 'merge', 'borders'], 'table'),
    ('qr', 'QR codes and barcodes',
     'Add a QR code for a link, an email, a phone number or Wi-Fi, in your own colours, or a barcode. Canvia warns when a code may not scan.',
     ['qr', 'qr code', 'barcode', 'link', 'wifi', 'scan'], 'add'),
    ('a11y-check', 'Checking accessibility',
     'Check accessibility looks for small text, low contrast, pictures without alt text and clips without captions, and takes you to each.',
     ['accessibility', 'accessibility check', 'alt text', 'contrast', 'captions', 'reading order'], 'a11yCheck'),
    ('backup', 'Backing up',
     'Back up everything, in Settings, keeps your designs, uploads, templates and settings in one file that either phone can restore. Back up automatically writes one to a folder you choose.',
     ['backup', 'back up', 'restore', 'move phone', 'settings'], 'backup'),
    ('share-in', 'Sharing into Canvia',
     "Share photos, videos, PDFs or design files to Canvia from another app to start a design, or add them to the one that is open.",
     ['share', 'share into', 'open with', 'import', 'pdf', 'powerpoint'], None),
    ('folders', 'Folders and starred',
     'On Home, keep designs and uploads in folders and folders inside folders. Star a design or a folder to find it under Starred.',
     ['folder', 'starred', 'star', 'favourite', 'favorite', 'organise', 'organize'], None),
    ('uploads', 'Uploads and Recently deleted',
     'Uploads on Home lists the photos, videos, music and fonts you brought in. Deleted designs, uploads and folders wait in Recently deleted for 30 days, where they can be restored.',
     ['uploads', 'trash', 'recently deleted', 'restore', 'deleted', 'bin'], None),
    ('quick-tools', 'Quick file tools',
     'Tools on Home merge and split PDFs, turn a PDF into pictures and photos into a PDF, and resize, convert or compress a picture, without making a design.',
     ['merge pdf', 'split pdf', 'pdf to jpg', 'photos to pdf', 'resize image', 'convert', 'compress', 'tools'], None),
    ('export-more', 'Videos, GIFs and file types',
     'Share makes a video or a GIF of animated pages, a ZIP of every page, an SVG, a PowerPoint, a web page or a smaller PDF, and suggests the type that suits the design.',
     ['mp4', 'gif', 'zip', 'svg', 'pptx', 'powerpoint', 'html', 'compress'], 'export'),
]

WHATS_NEW = [
    ('1.36', [
        ('quick-tools', 'Quick file tools',
         'Merge or split PDFs, turn pictures into a PDF and resize, convert or compress a picture, all from Tools on Home.', 'tools'),
        ('trash', 'Restore uploads and folders',
         'Deleted uploads and folders now wait in Recently deleted for 30 days, as designs do.', 'trash'),
        ('version-page', 'Bring back one page',
         'In Version history, bring back a single page from an earlier version without losing later work.', None),
        ('template-files', 'Send your templates',
         'Send one of your templates as a file. Whoever opens it can add it to their templates.', 'templates'),
    ]),
    ('1.35', [
        ('diagrams', 'Diagrams',
         'Add a Venn diagram, a cycle, a timeline or an org chart from Add, and edit its items as a list.', None),
        ('present-pen', 'Pointer and pen in Present',
         'Point at a slide or write on it while you present.', None),
    ]),
]


def topics():
    return [{'id': i, 'title': t, 'body': b, 'keywords': k, 'opens': o} for i, t, b, k, o in TOPICS]


def whats_new():
    return [{'version': v, 'items': [{'id': i, 'title': t, 'body': b, 'opens': o} for i, t, b, o in items]} for v, items in WHATS_NEW]


def dump(value):
    return json.dumps(value, ensure_ascii=False, indent=2) + '\n'


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    ios = pathlib.Path(sys.argv[1]) if len(sys.argv) == 2 else None
    ids = [t[0] for t in TOPICS]
    assert len(ids) == len(set(ids)), 'topic ids repeat'
    outputs = {'help.json': dump(topics()), 'whatsnew.json': dump(whats_new())}
    for name, text in outputs.items():
        (CONTENT / name).write_text(text, encoding='utf-8')
        if ios:
            (ios / name).write_text(text, encoding='utf-8')
    print('%d topics, %d What\'s new versions' % (len(TOPICS), len(WHATS_NEW)))


if __name__ == '__main__':
    main()
