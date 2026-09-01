# Canvia for iOS — a Canva-inspired design studio (plan)

A native SwiftUI iPhone/iPad app strongly inspired by Canva: a home screen
with size presets, recent designs and a template gallery; a full
direct-manipulation editor (drag, resize, rotate, snap, inline text, layers,
multi-page); and real export (PNG / JPEG / multi-page PDF) through the share
sheet. Pure Swift + SwiftUI, zero third-party dependencies, fully offline.

This is the iOS sibling of the web plan in `story/canva-clone/PLAN.md` —
same document schema, same content library (templates, shapes, palettes were
generated and validated once and are bundled here as JSON/data), adapted to
touch idioms and Apple frameworks.

## Targets & constraints

- **iOS 17+, Xcode 16+** (uses `@Observable`, `ImageRenderer`, modern
  project format with synchronized folders — no per-file pbxproj entries).
- **Zero dependencies, fully offline.** "Photos" are procedurally drawn
  (mesh gradients, waves, stripes, scenes) into `UIImage`s; fonts map to
  fonts that ship with iOS (Didot, Rockwell, Futura, Menlo, Snell
  Roundhand, Avenir Next Condensed, …).
- **Document schema = the web schema** (same JSON keys), so the validated
  template gallery ports verbatim and designs could round-trip.

## Architecture

```
Canvia/
  Canvia.xcodeproj            Xcode 16 project (synchronized folder)
  Canvia/
    CanviaApp.swift           entry, routing home ⇄ editor
    Models/                   Design / Page / Element / Paint (Codable, value types)
    Store/                    DesignStore (@Observable, snapshot undo/redo with
                              gesture coalescing), DesignLibrary (Documents-dir
                              persistence + thumbnails + recents index)
    Content/                  ShapeLibrary (SVG paths + parser with arc support),
                              PhotoLibrary (procedural UIImages), Palettes,
                              FontLibrary, TextEffects, ImageFilters, Stickers,
                              TemplateLibrary + Templates.json (ported, validated)
    Editor/                   Geometry (rotated-anchor resize, snapping, SAT),
                              EditorView, CanvasView, ElementView,
                              SelectionOverlay, gesture handling
    UI/                       HomeView, ContextToolbar, sheets (colors, fonts,
                              effects, filters, position, layers, export), PagesBar
```

**Value-type documents.** `Design` is a struct; undo/redo is a plain
`[Design]` history with begin/commit gesture coalescing (one drag = one undo
step) — Swift value semantics make the snapshot store trivial and safe.

**Rendering.** Each element is a SwiftUI view positioned in page
coordinates inside a scaled canvas; the same `PageRenderView` renders
export frames through `ImageRenderer` at 1–3×, and `UIGraphicsPDFRenderer`
stitches pages into a PDF. Shapes come from one SVG-path library (parsed to
`Path`, arcs converted to Béziers) shared by the sidebar, canvas and export.

**Touch interaction.** Tap to select, drag to move with magenta snap
guides (page edges/centers + sibling edges/centers, zoom-aware threshold),
corner/edge handles for rotation-aware resize (corners proportional), a
rotate handle with 45° snapping and angle badge, double-tap for inline text
editing, pinch to zoom the canvas, long-press for multi-select, Layers
sheet for z-order, Position sheet for align/flip/exact values.

## Feature set (mirrors the web plan, mobile-shaped)

- Home: size presets, recents grid with thumbnails (rename/duplicate/
  delete), template gallery, start-from-template
- Elements: 44 shapes, lines with caps/dashes, emoji stickers, 20
  procedural photos, photo-library imports (PhotosPicker)
- Text: heading/sub/body inserts, 12 font personalities, size/weight/
  italic/underline/align/spacing, 8 effects (shadow, lift, hollow, splice,
  neon, echo, highlight)
- Images: filter presets (CIFilter), cover-crop zoom + focus, replace,
  corner radius, border
- Color system: curated palettes, gradients, document colors, background
  editor, ✨ Shuffle (luminance-ranked palette remap)
- Pages: strip with live thumbnails, add/duplicate/delete/reorder
- Undo/redo, autosave, lock, opacity, duplicate, align/distribute, flip
- Export: PNG / JPEG (1–3×) / multi-page PDF via the share sheet

## Deliberate iOS adaptations

- Contextual controls live in a bottom toolbar + sheets (thumb-reachable),
  not a desktop top toolbar
- Multi-select via long-press (not marquee); no hover states
- Uploads use PhotosPicker; exports go through the share sheet
- Same deliberate cuts as the web plan: no nested group transforms, no
  spacing guides, fixed-strength filters

## Verification

No Xcode is available in this build environment, so in place of a compile:
an adversarial multi-agent review pass (compile-correctness, SwiftUI/API
misuse, logic parity with the tested web geometry, Codable/JSON parity
against the bundled templates) with skeptic verification, findings fixed
before ship. The geometry math is a direct port of the web module that
passes 73 unit checks; the template JSON is the validated gallery.
