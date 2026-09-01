# Canvia for iOS

A Canva-inspired design studio built natively in SwiftUI — zero third-party
dependencies, fully offline. See [PLAN.md](PLAN.md) for the design plan.

## Requirements

- **Xcode 16 or newer** (the project uses the modern synchronized-folder
  format), **iOS 17+** deployment target.

## Run it

Open `Canvia.xcodeproj` in Xcode, pick a simulator or device, and Run.
No packages to resolve, nothing to configure.

## What it does

**Home** — size presets (Instagram post/story, presentation, poster, A4,
business card, …), custom sizes, recent designs with thumbnails (rename /
duplicate / delete via long-press), and a template gallery.

**Editor**
- Direct manipulation: tap to select, drag to move with magenta snap
  guides (page edges/centers + sibling edges/centers), rotation-aware
  corner/edge resize handles (corners keep aspect; text corners scale the
  font), rotate handle with 45° snapping and live angle badge, long-press
  for multi-select, pinch to zoom, drag empty canvas to pan
- Content: 44 shapes (one SVG-path library parsed with full arc support),
  lines with caps and dashes, emoji stickers, 20 procedurally drawn
  photos, photo-library imports, 8 complete templates that apply into any
  canvas size
- Text: inline editing (double-tap), 12 font personalities mapped to fonts
  that ship with iOS (Didot, Rockwell, Futura Condensed ExtraBold, Menlo,
  Snell Roundhand, …), 8 text effects (shadow, lift, hollow, splice, neon,
  echo, highlight) drawn through one CoreText pipeline shared by canvas,
  thumbnails and export
- Images: Core Image filter presets, cover-crop zoom + focus point,
  corner radius, borders
- Color: curated palettes, gradient presets, document colors, background
  editor, ✨ Shuffle (luminance-ranked palette remap)
- Pages: live-thumbnail strip, add / duplicate / reorder / delete
- Undo/redo with gesture coalescing (a whole drag is one step), autosave,
  lock, opacity, duplicate, align / flip / exact-position sheet, layers
  sheet with drag reorder

**Export** — PNG / JPEG at 1–3× and multi-page PDF, rendered with
`ImageRenderer` from the very views the canvas shows, delivered through
the share sheet.

## Architecture

```
Models/    Design · Page · Element · Paint — Codable value types using the
           same JSON schema as the Canvia web app, so the validated
           template gallery ships verbatim in Content.json
Store/     DesignStore (@Observable; snapshot undo/redo — history is just
           [Design] thanks to value semantics), DesignLibrary (Documents)
Content/   shape library + SVG path parser (arcs → Béziers), procedural
           photo generators, fonts, text effects, CI filters, templates
Editor/    Geometry (rotated-anchor resize, snapping, AABB), CanvasView,
           ElementView (+ PageRenderView reused for thumbnails & export),
           SelectionOverlay
UI/        HomeView, EditorView, ContextToolbar, insert/export/color/font/
           effects/filters/crop/position/layers/resize sheets, PagesBar
```

The sibling web implementation lives in the `story` repo under
`canva-clone/` and shares the document schema and content library.
