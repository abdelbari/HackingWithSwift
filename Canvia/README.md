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
  photos, photo-library imports, QR codes generated from a link or any
  text (regenerated from the document, so they stay editable and nothing
  is stored), 8 complete templates that apply into any canvas size
- Text: curved text on an arc from -180° to 180° (glyphs placed along one
  circle whose radius the line's own width fixes, so letters keep their
  size rather than being squashed to fit), inline editing (double-tap),
  12 font personalities mapped to fonts
  that ship with iOS (Didot, Rockwell, Futura Condensed ExtraBold, Menlo,
  Snell Roundhand, …), 8 text effects (shadow, lift, hollow, splice, neon,
  echo, highlight) drawn through one CoreText pipeline shared by canvas,
  thumbnails and export
- Photo frames: any library shape clips a photo — circle, star, blob,
  speech bubble — applying one squares the box about its centre, because
  the library's paths stretch onto the element and a circle on a 4:3 photo
  would otherwise be an ellipse
- Images: one-tap background removal on device (Vision's foreground
  segmenter — no account, no upload, no paywall), Core Image filter
  presets, duotone (a photo's luminance mapped onto two of your own
  colours, offered from the document's own palette first), plus six
  free-hand dials (brightness, contrast, saturation,
  warmth, sharpness, vignette) that compose on top of the preset rather
  than replacing it, cover-crop zoom + focus point, replace-in-place (swap the
  picture, keep the frame, radius and filter), corner radius, borders
- Color: recently used colours first, colour harmony derived from whatever
  is chosen (complementary, analogous, triadic, split, tetradic, and a
  tint/shade ramp), curated palettes, gradient presets, document colors,
  background editor, ✨ Shuffle (luminance-ranked palette remap)
- Pages: live-thumbnail strip, add / duplicate / reorder / delete (with a
  confirmation when the page is not empty), and per-page notes that are
  never drawn and so cannot reach an export
- Undo/redo with gesture coalescing (a whole drag is one step), autosave,
  lock, opacity, duplicate, align / distribute / flip / exact-position
  sheet, layers sheet with drag reorder
- Find and replace across every page, with a live match count and
  replace-all as a single undo step; and a spelling check across the
  document through the system dictionary, each mistake with its
  suggestions a tap away (acronyms, hashtags and addresses left alone)
- Bulleted, numbered and lettered lists with hanging indents, and up to
  four indent levels on any paragraph
- Gradient text: any gradient from the colour picker fills the letters,
  straight or curved, and survives into the SVG
- Copy style / paste style: the look of an element without its identity,
  position or content, and never across element kinds — pasting a text
  style onto a rectangle changes nothing about the rectangle
- A page organizer: every page as a list with drag handles, multi-select
  to duplicate or delete (never the last page), tap to jump. Pages copy
  and paste across designs and across launches through the system
  pasteboard, scaled to fit a differently sized design.
- The home screen searches designs (title, loosely; size, exactly) and
  templates, sorts by last edited, name or page count, and keeps deleted
  designs in a Recently deleted section for thirty days, with Restore
  and Delete forever. Their photos and version history wait with them.
- VoiceOver on the canvas: every element is named (what it is, and what
  it says if it is text), valued (where and how big, in percentages of
  the page, plus rotation and lock) and carries actions — move in four
  directions, duplicate, delete, layer order, edit text — so the whole
  page can be arranged without a drag.
- Photos import several at once (up to ten, landing as a cascade), keep
  their transparency when they have any — a PNG logo is stored as PNG,
  an opaque screenshot as the far smaller JPEG — and every colour picker
  offers "From the photo": the six most prominent colours of the selected
  picture or the page's background picture, read from its pixels.
- Document theme: pick a palette and a type pairing, see page one
  wearing them, apply to every page as one undo step — colours remapped
  by luminance rank, headings (32 px and up) and body text given the
  pairing's faces at their own sizes.
- Blend modes on any element — multiply, screen, overlay and the rest of
  the CSS set — honoured on the canvas, in every export, and in the SVG
  as mix-blend-mode.
- Rubber-band selection: drag from empty page and everything the band
  touches is selected, live, sticky groups included
- A multi-selection resizes and rotates as one unit from its box —
  corner handles only, because a uniform scale is the only one that
  keeps rotated members exact; text scales its type along with its box
- Snapping with switches: to the page, to other elements, and to a grid
  of 8/16/32/64 px that can be shown as hairlines on the canvas (never in
  an export). Remembered across launches.
- Version history: a copy of the design is kept at most every two
  minutes while editing, and whenever the editor is left, only when
  something changed, thirty deep. Restoring one is a single undo step
  and the current state is kept as a version first, so it is never a
  one-way door.
- An undo toast after the edits people regret — delete, delete page,
  replace all, restore — naming what just happened with an Undo button
  on it, gone after four seconds.
- Top-bar overflow menu: layers, page background, find and replace,
  version history, copy and paste style, copy / cut / paste,
  select all, and group / ungroup (grouping is sticky multi-selection —
  selecting one member selects the group — deliberately not nested
  transforms)

**Export** — PNG / JPEG at 1–3× or at an exact size: type the long edge
in pixels, or pick a preset (Instagram post, Story, Full HD, 4K, A4 and
Letter at 300 dpi) and the scale follows. The selection alone can be
exported, cropped to its bounds, and any raster can be copied to the
clipboard as PNG. A warning appears before the export when the output
would be under 1080 px on the long side or a photo would be stretched
past the pixels it has (this page or every page, one numbered
file each, with an optional transparent background that really removes
the page's own), multi-page PDF and SVG, rendered with
`ImageRenderer` from the very views the canvas shows, delivered through
the share sheet. PDF pages are written as vectors, not page-sized
bitmaps, and everything streams to disk rather than being assembled in
memory. The scale picker shows the pixel size it will actually produce,
including when a 32-megapixel cap is what decided it.

Every export shows how far along it is — a page at a time for rasters,
a frame at a time for the video — with a Cancel button that stops the
writer at the next frame and leaves no partial file behind.

**Save to Photos** — PNG (this page or the selected range) or the MP4
straight into the photo library with add-only permission, no share
sheet in the way.

**Print** — AirPrint, through the same vector PDF the export writes, so
what reaches the printer is the document rather than a picture of it.

**MP4 and animated GIF** — a multi-page design is already a sequence, so
it exports as one: each page holds for 2.5 seconds with a slow push in
and a cross-fade into the next (hold time, frame rate, push-in and fade
are settings saved with the design), written frame by frame with AVAssetWriter
(video) and ImageIO (GIF). No network, no account, no codec licence.

SVG keeps shapes and lines as paths and strokes, and converts text to
glyph outlines rather than `<text>` — the twelve font personalities map
to faces that ship with iOS and are not on the machine opening the file,
so `<text>` would silently substitute. Images and stickers embed as
bitmaps rendered through the very views the canvas draws, so crop,
filter, corner radius and emoji colour arrive exactly as they looked.

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

**`.github/workflows/canvia-ios.yml`** — the real thing. Two macOS legs
compile the app with `xcodebuild`, print every compiler diagnostic to the
job log, then boot a simulator, install and launch the app, confirm the
process is still alive, and capture a screenshot of it running:

| Leg | Runner | Xcode | Simulator |
| --- | --- | --- | --- |
| `baseline-ios18` | macos-15 | 16.4 | iPhone 16, iOS 18.6 |
| `latest-ios26` | macos-26 | 26.6 | iPhone 17 Pro, iOS 26.5 |

iOS 26.5 is the newest SDK Apple ships — Xcode 26.6 carries it. iOS 26.6 does
run on real devices, but Apple publishes no 26.6 SDK and no 26.6 simulator
runtime (the catalog goes 26.5, then 27.0), so 26.5 is the newest iOS testable
in a simulator; a phone on 26.6.x is only reachable by installing on it. The older leg is what
proves the iOS 17 deployment target still works on an earlier SDK. The
destination names a concrete OS and a preceding step asserts that runtime
exists, so a missing runtime fails the leg rather than letting `xcodebuild`
quietly build against a different version.

`.github/workflows/canvia-probe.yml` reports what each runner image actually
carries, so those versions can be re-checked rather than assumed.

`Tests/GeometryTests.swift` holds 17 assertions over the geometry core
(rotated-anchor resize, snapping, AABB union, hit-testing). It sits
outside the synchronized source folder, so it never joins the app target;
add it to a test target to run it.

### A note on the iOS 26 look

Linking against any iOS 26 SDK — which the `latest-ios26` leg and the TestFlight
archive both do — opts the app into the iOS 26 design system on iOS 26 devices.
There is no error and no warning; system-drawn controls simply restyle. Canvia
draws most of its own chrome, and the iOS 26.5 CI screenshot renders correctly,
so nothing is being done about it here.

If a future change does look wrong on iOS 26, `UIDesignRequiresCompatibility =
YES` in Info.plist restores the pre-26 appearance. Treat it as a stopgap, not a
fix: Apple describes it as a debugging aid, and an app built against the iOS 27
SDK ignores the key entirely.

## Installing on your own iPhone

Two routes. They are not alternatives so much as different speeds — use the
first to iterate, the second to keep the app on your phone.

### Straight from Xcode (fastest, no CI)

1. Open `Canvia.xcodeproj`, select the **Canvia** target → **Signing &
   Capabilities**.
2. Set **Team** to your Apple Developer team.
3. If `com.canvia.app` is not available to your team, change **Bundle
   Identifier** to something you own, e.g. `com.yourname.canvia`.
4. Plug the iPhone in, enable **Settings → Privacy & Security → Developer
   Mode** on it, pick it as the run destination, and press Run.

With a paid Apple Developer Program membership the provisioning profile is
good for a year, so the app keeps working between rebuilds. (On a *free*
Apple ID it would expire after 7 days.)

### TestFlight from CI (hands-off, installs like a real app)

`.github/workflows/canvia-testflight.yml` archives a Release build, signs it,
and uploads it to App Store Connect. It runs on demand from the Actions tab,
or on any `v*` tag. Builds reach TestFlight a few minutes after upload and
last 90 days.

Signing uses Xcode's automatic provisioning driven by an App Store Connect
API key, so there is no certificate to export, no `.p12`, and no temporary
keychain — Xcode creates and renews the distribution certificate and profile
itself.

**One-time setup.**

Four things have to exist before the first upload, and each one blocks it on
its own:

1. **Accept the current agreements** in App Store Connect → *Business*. Until
   the Account Holder signs, you cannot create an app at all.
2. **Register the App ID** at developer.apple.com → *Certificates, Identifiers &
   Profiles → Identifiers → + → App IDs*, explicit, matching the bundle
   identifier. Automatic signing does register it, but only during the archive —
   too late for step 3, which needs it first. App IDs are globally unique across
   *all* Apple accounts, so `com.canvia.app` may already belong to someone else;
   if so pick something you control, e.g. `io.github.yourname.canvia`, and set
   the `CANVIA_BUNDLE_ID` variable below.
3. **Create the app record**: App Store Connect → *Apps → +*, that bundle
   identifier, a globally unique app name, an SKU. An upload for a bundle
   identifier with no app record is rejected — the likeliest first-run failure.
4. **Create an Internal Testing group**: your app → *TestFlight → Internal
   Testing → +*, enable automatic distribution, and add yourself as a tester.
   Builds are invisible to anyone not in a group — the Account Holder included.
   Skipping this is what produces a processed build and an empty TestFlight app.

Then mint an API key. In [Users and Access → Integrations → App Store Connect
API](https://appstoreconnect.apple.com/access/integrations/api), create a **team
key** with the **Admin** role and download the `.p8` — Apple lets you download it
exactly once.

> The role must be **Admin**, not App Manager. `-allowProvisioningUpdates` uses
> cloud-managed distribution signing, and a non-Admin key is refused with
> *"You haven't been given access to cloud-managed distribution certificates"* —
> with no way to grant it after the fact. The failure lands in the archive step,
> not the upload.

Add four repository secrets under *Settings → Secrets and variables → Actions*:

| Secret | Where it comes from |
| --- | --- |
| `APP_STORE_CONNECT_KEY_ID` | the key's Key ID, e.g. `2X9R4HXF34` |
| `APP_STORE_CONNECT_ISSUER_ID` | the Issuer ID shown above the key list |
| `APP_STORE_CONNECT_PRIVATE_KEY` | the whole `.p8` file, `BEGIN`/`END` lines included |
| `APPLE_TEAM_ID` | your 10-character Team ID, from Membership details |

Optionally set the repository *variable* `CANVIA_BUNDLE_ID` if you changed the
bundle identifier. The first run registers the App ID under your team.

The build number is derived from the run number and the run attempt, because
App Store Connect rejects a build number it has already seen and `run_number`
does *not* change when you re-run a failed workflow. Export compliance is declared in
the project (`ITSAppUsesNonExemptEncryption = NO` — the app does no networking
at all), so uploads do not stall waiting for that question to be answered by
hand.

The sibling web implementation lives in the `story` repo under
`canva-clone/` and shares the document schema and content library.

> **These workflows live on this branch, not on `master`.** GitHub only offers a
> *Run workflow* button for a `workflow_dispatch` file that exists on the default
> branch, so until this branch is merged the TestFlight workflow can only be
> triggered by pushing a `v*` tag.
