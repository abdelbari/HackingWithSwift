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
  replace-in-place (swap the picture, keep the frame, radius and filter),
  corner radius, borders
- Color: curated palettes, gradient presets, document colors, background
  editor, ✨ Shuffle (luminance-ranked palette remap)
- Pages: live-thumbnail strip, add / duplicate / reorder / delete
- Undo/redo with gesture coalescing (a whole drag is one step), autosave,
  lock, opacity, duplicate, align / distribute / flip / exact-position
  sheet, layers sheet with drag reorder
- Top-bar overflow menu: layers, page background, copy / cut / paste,
  select all, and group / ungroup (grouping is sticky multi-selection —
  selecting one member selects the group — deliberately not nested
  transforms)

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

## Verifying it

Xcode is macOS-only, so the project carries two levels of checking.

**`Tools/verify.js`** — a static gate that runs anywhere Node does. It
parses every source file with the real tree-sitter Swift grammar and
checks six things a compiler would otherwise have to tell you: that each
file parses; that every call into project code matches a declared
signature's argument labels; that every `.case` argument names a real
case of the parameter's enum; that every switch over a project enum is
exhaustive; that no `@ViewBuilder` block exceeds SwiftUI's ten-child
limit; and that no shorthand closure passed to a higher-order method
(`filter`, `map`, `sorted`, …) silently ignores the argument it must
take. It does not type-check — a clean run means the syntax and the
project's internal API surface are consistent, not that the app builds.

```
cd Tools && npm install && node verify.js ../Canvia ../Tests
```

**`.github/workflows/canvia-ios.yml`** — the real thing. A macOS runner
compiles the app with `xcodebuild` against the iOS Simulator SDK, prints
every compiler diagnostic to the job log, then boots a simulator,
installs and launches the app, and captures a screenshot of it running.
It fires on pushes that touch `Canvia/**` and can be started by hand from
the Actions tab.

`Tests/GeometryTests.swift` holds 17 assertions over the geometry core
(rotated-anchor resize, snapping, AABB union, hit-testing). It sits
outside the synchronized source folder, so it never joins the app target;
add it to a test target to run it.

The sibling web implementation lives in the `story` repo under
`canva-clone/` and shares the document schema and content library.
