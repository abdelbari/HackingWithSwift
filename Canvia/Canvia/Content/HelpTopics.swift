// The help centre's contents: short, searchable, and each one a door into
// the feature it describes.
//
// Offline by construction — it is a Swift array — and deep-linked: a topic
// that explains the export sheet opens the export sheet. Reading about a
// button is worse than being taken to it.

import Foundation

struct HelpTopic: Identifiable, Equatable {
    var id: String
    var title: String
    var body: String
    var keywords: [String]
    /// The sheet this topic is about, opened by "Show me".
    var opens: EditorSheet?
}

enum HelpTopics {

    static let all: [HelpTopic] = [
        HelpTopic(id: "add", title: "Adding things to the page",
                  body: "Tap the + button. Templates, shapes, lines, text styles, photos, stickers and QR codes are all there, and the search box at the top searches every tab.",
                  keywords: ["insert", "plus", "shape", "sticker", "qr", "template"], opens: .insert),
        HelpTopic(id: "move", title: "Moving, resizing and rotating",
                  body: "Drag an element to move it. Drag a corner handle to resize (text scales its type too), an edge handle to stretch, and the handle below to rotate. Snap guides appear when edges or centres line up.",
                  keywords: ["drag", "handle", "rotate", "resize", "snap"], opens: nil),
        HelpTopic(id: "zoom", title: "Zooming and panning",
                  body: "Pinch anywhere to zoom, even over elements. Pan with two fingers, or one finger on the grey workspace. Double-tap to zoom in on a spot, and again to fit the page.",
                  keywords: ["pinch", "pan", "fit", "double tap"], opens: nil),
        HelpTopic(id: "select", title: "Selecting several elements",
                  body: "Drag from empty page to draw a band; everything it touches is selected. Or press and hold an element to add it to the selection. A multi-selection moves, resizes and rotates as one.",
                  keywords: ["marquee", "band", "multi", "group", "hold"], opens: nil),
        HelpTopic(id: "text", title: "Editing text",
                  body: "Double-tap a text element to edit it in place. The toolbar has font, size, colour, bold, italic, lists, indents, alignment, effects, spacing and a curve slider.",
                  keywords: ["font", "type", "edit", "curve", "list", "bullet"], opens: .fonts),
        HelpTopic(id: "inline", title: "Bold or italic words inside a text",
                  body: "Wrap words the way you would in a message: **two stars** for bold, *one star* or _underscores_ for italic, __two underscores__ to underline, ~~two tildes~~ to strike through. The markers disappear and the words take the style, on the canvas and in every export.",
                  keywords: ["bold", "italic", "underline", "strike", "markdown", "rich", "inline", "style"], opens: nil),
        HelpTopic(id: "photos", title: "Photos: crop, filters, frames, cut-out",
                  body: "Select a photo for Crop (zoom, focus, straighten, fit or fill), Filters (presets, duotone, adjustments), Frame (clip to any shape) and Cut out (remove the background).",
                  keywords: ["crop", "filter", "frame", "cutout", "background", "straighten"], opens: .crop),
        HelpTopic(id: "shadow", title: "Shadows and glows",
                  body: "Any element can cast a shadow or glow: pick a preset or set the colour, blur and offset yourself.",
                  keywords: ["glow", "drop", "effect"], opens: .shadow),
        HelpTopic(id: "layers", title: "Layer order",
                  body: "The Layers sheet lists everything on the page, top-most first. Drag to reorder, tap to select. The Position sheet moves an element forward or back one step.",
                  keywords: ["order", "front", "back", "arrange", "position"], opens: .layers),
        HelpTopic(id: "pages", title: "Pages",
                  body: "The bar at the bottom shows every page. Add, duplicate, reorder, copy and paste pages (even into another design), keep notes on a page, and open the organizer to manage many at once.",
                  keywords: ["page", "organizer", "notes", "duplicate", "reorder"], opens: nil),
        HelpTopic(id: "colors", title: "Colours and themes",
                  body: "Every colour picker offers recent colours, the document's colours, colours from the selected photo and harmonies of the current colour. The sparkles button reshuffles the page's palette; Document theme applies a palette and a type pairing to every page.",
                  keywords: ["palette", "theme", "harmony", "gradient", "shuffle"], opens: .theme),
        HelpTopic(id: "find", title: "Find and replace, spelling",
                  body: "Find and replace searches the text on every page and replaces in one undo step. Check spelling lists every word the dictionary does not know, with suggestions.",
                  keywords: ["search", "replace", "spell", "proofread"], opens: .find),
        HelpTopic(id: "undo", title: "Undo, redo and version history",
                  body: "Undo and redo are in the top bar. Version history keeps a copy of the design every couple of minutes while you edit; restoring one is itself undoable.",
                  keywords: ["history", "restore", "version", "mistake"], opens: .history),
        HelpTopic(id: "export", title: "Exporting and sharing",
                  body: "Export makes PNG, JPEG, PDF, SVG, MP4 and GIF at any size, saves straight to Photos, copies to the clipboard, or prints. Choose this page, every page, or just the selection.",
                  keywords: ["share", "png", "pdf", "video", "gif", "print", "save", "size"], opens: .export),
        HelpTopic(id: "resize", title: "Changing the design's size",
                  body: "Resize scales everything on every page to fit the new size, keeping it centred.",
                  keywords: ["size", "dimensions", "canvas"], opens: .resize),
        HelpTopic(id: "snap", title: "Snapping and the grid",
                  body: "Snapping to the page, to other elements and to a grid each have a switch under Snapping in the menu. The grid can be shown on the canvas; it is never exported.",
                  keywords: ["grid", "guide", "align"], opens: nil),
        HelpTopic(id: "keyboard", title: "Keyboard shortcuts",
                  body: "With a hardware keyboard: ⌘Z undo, ⇧⌘Z redo, ⌘C/⌘X/⌘V copy, cut, paste, ⌘D duplicate, ⌘A select all, ⌘G group, ⌘F find, ⌘E export.",
                  keywords: ["shortcut", "ipad", "command"], opens: nil),
        HelpTopic(id: "voiceover", title: "VoiceOver and accessibility",
                  body: "Every element on the canvas is named and can be moved, duplicated, deleted or reordered from the VoiceOver actions rotor. Reduce Motion, Increase Contrast and Differentiate Without Colour are honoured.",
                  keywords: ["accessibility", "voice", "motion", "contrast"], opens: nil),
    ]

    /// Topics matching a query, title matches first. An empty query is
    /// every topic.
    static func search(_ query: String) -> [HelpTopic] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        func hit(_ s: String) -> Bool { s.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        let byTitle = all.filter { hit($0.title) }
        let byRest = all.filter { t in !hit(t.title) && (t.keywords.contains(where: hit) || hit(t.body)) }
        return byTitle + byRest
    }
}
