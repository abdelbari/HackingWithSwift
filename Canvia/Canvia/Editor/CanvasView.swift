// Interactive canvas: the page rendered in page-pixel coordinates, inside a
// scroll view that owns zoom and pan (see ZoomableCanvas), with a gesture
// layer for select/move and a selection overlay for handles. All gesture math
// runs in the "page" coordinate space so zoom never affects it.
//
// Scrolling through pages (PageColumn, on unless turned off in the More
// menu), the scroll view holds every page down one column instead: the page
// being worked is this same interactive page, scaled into its place, and the
// others are drawn around it under their headers.

import Observation
import SwiftUI
import UIKit

struct CanvasView: View {
    @Bindable var store: DesignStore
    @State private var gesture = GestureState()
    /// The stroke being drawn, in page units, while the pen is on.
    @State private var strokePoints: [CGPoint] = []
    /// Where the stroke under way began. A drag the canvas's two-finger pan
    /// cancels never ends, so a new touch — a new start — begins a stroke
    /// afresh rather than joining the one cut short with a straight jump.
    @State private var strokeStart: CGPoint?
    @State private var dropTargeted = false
    /// When a tap on the photo in crop mode last landed, for the double tap
    /// that finishes it.
    @State private var lastCropTap: Date?
    /// The guide a long press is offering Position… and Remove for.
    @State private var guideMenu: Guide?
    /// The guide Position… is asking a place for, and what is typed.
    @State private var positioningGuide: Guide?
    @State private var guidePositionText = ""
    /// Scroll through pages, from the More menu: on unless turned off.
    @AppStorage(PageColumn.key) private var pageScroll = true
    /// Play in the editor: animated pictures play on the canvas.
    @AppStorage(AnimStore.playKey) private var playAnimated = false
    /// The canvas's width, which the column of pages is fitted to.
    @State private var canvasWidth = 0.0
    /// A page the column itself made the one worked — scrolled to, tapped
    /// on, or something let go over — which it then does not scroll to.
    @State private var pageFromColumn: Int?
    /// The pages near enough to the part of the column on screen to draw
    /// live (PageColumn.livePages); the others show a thumbnail.
    @State private var livePages: Set<Int> = []
    /// The part of the column on screen, kept without redrawing the canvas
    /// on every frame of a scroll.
    @State private var seen = ColumnSeen()
    /// A page header's Delete asking first, and its Notes.
    @State private var confirmingPageDelete = false
    @State private var editingPageNotes = false
    /// The bleed band's "Bleed" label, shown for its first few seconds.
    @State private var bleedLabel = false
    /// Rulers, from the More menu: off unless turned on (RulersView).
    @AppStorage(Guides.rulersKey) private var rulers = false

    /// Where the view is in the column, written as it scrolls, the zoom
    /// that fits it, and whether a finger set it moving; read when it comes
    /// to rest, or when the page worked changes under a view standing still.
    /// Only `across` is watched: the header rows, cut to it, redraw on their
    /// own as the view pans across (ColumnRow).
    @Observable
    final class ColumnSeen {
        @ObservationIgnored var visible: CGRect = .zero
        @ObservationIgnored var fit = 0.0
        @ObservationIgnored var moved = false
        /// The column's left and right edges on screen, in column units;
        /// nil until the canvas has said.
        var across: ClosedRange<Double>?
    }

    /// Inverse zoom: ornaments are drawn in page units but should
    /// stay a constant size on screen.
    private var iz: Double { 1 / max(store.zoom, 0.01) }

    /// The design's print bleed, in page units; 0 when none is shown, and
    /// while the page plays, which cuts it at its trim as Present does, as
    /// on the Android twin.
    private var bleed: Double { store.previewTime == nil ? Bleed.of(store.design) : 0 }

    struct GestureState {
        var dragOriginals: [String: CGPoint] = [:]
        var dragActive = false
        // Siblings don't move during a drag, so their snap lines are computed
        // once at grab time rather than rebuilt every frame.
        var snapX: [Double] = []
        var snapY: [Double] = []
        /// The same lines with where each comes from, to name the guide.
        var snapTagsX: [Geometry.SnapLine] = []
        var snapTagsY: [Geometry.SnapLine] = []
        /// The moving selection's box as it is now, while a move is under way.
        var movedBox: CGRect?
        /// Whether the finger has gone far enough for the ghost of where the
        /// move began to show.
        var ghost = false
        /// Union of the dragged elements' bounding boxes as they were at grab
        /// time. Moving does not change any element's size or rotation, so the
        /// union per frame is just this one translated — no need to look the
        /// elements up and re-derive their boxes on every touch move.
        var dragUnion: CGRect = .zero
        /// Sibling boxes at grab time, for equal-spacing hints.
        var siblingBoxes: [CGRect] = []
        /// The photo being moved, when it is one photo or clip that can go
        /// into a frame (PhotoFrames.canDrop).
        var framePhoto: String?
        /// The frame under the finger it would go into, lit up while it is.
        var frameTarget: String?
        var resizeOriginal: Element?
        /// The picture's size in pixels when a photo's side is grabbed, so
        /// the side trims the frame across a picture that stays put.
        var resizeImage: CGSize?
        var rotateCenter: CGPoint?
        var rotateOffset: Double = 0
        /// A multi-selection being resized or rotated as one: the members
        /// and their union as they were when the handle was grabbed.
        var groupOriginals: [Element] = []
        var groupBox: CGRect = .zero
        /// The rubber band, in page units, while one is being drawn.
        var marquee: CGRect?
        /// Whether a hold on the empty page has taken, so a band is being
        /// held out.
        var banding = false
        /// What a finger in crop mode is working, from when it lands.
        var crop: CropTouch?
        /// A crop-mode pinch's magnification when last applied.
        var cropPinch = 1.0
        /// The page in the column a move is over, other than its own: let
        /// go there, what moves goes to that page.
        var dropPage: Int?
        /// What a drag from another page of the column is moving, once it
        /// has made that page the one worked.
        var columnDrag: String?
    }

    /// What a touch in crop mode landed on: one of the frame's brackets (the
    /// photo as grabbed, and how far the finger is from the bracket, so the
    /// edge does not jump to it), the picture, or anywhere else.
    enum CropTouch {
        case picture(last: CGPoint)
        case frame(Handle, start: Element, grab: CGPoint)
        case outside

        var handle: Handle? {
            if case .frame(let handle, _, _) = self { return handle }
            return nil
        }

        var isWorking: Bool {
            if case .outside = self { return false }
            return true
        }
    }

    var body: some View {
        columnAware
        .ignoresSafeArea(.keyboard)
        .confirmationDialog(guideMenu.map { guideTitle($0) } ?? "Guide",
                            isPresented: Binding(get: { guideMenu != nil }, set: { if !$0 { guideMenu = nil } }),
                            titleVisibility: .visible, presenting: guideMenu) { guide in
            Button("Position…") { askPosition(guide) }
            Button("Remove guide", role: .destructive) { store.removeGuide(guide.id) }
            Button("Cancel", role: .cancel) {}
        }
        // Worded as Android's Position… dialog words it.
        .alert(positioningGuide?.vertical == false ? "Horizontal guide" : "Vertical guide",
               isPresented: Binding(get: { positioningGuide != nil },
                                    set: { if !$0 { positioningGuide = nil } }),
               presenting: positioningGuide) { guide in
            TextField(guide.vertical ? "From the left (px)" : "From the top (px)", text: $guidePositionText)
                .keyboardType(.decimalPad)
            Button("Move") {
                let limit = guide.vertical ? store.pageWidth : store.pageHeight
                if let position = Guides.typedPosition(guidePositionText, limit: limit) {
                    store.setGuidePosition(guide.id, to: position)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { guide in
            Text("From 0 to \(Int((guide.vertical ? store.pageWidth : store.pageHeight).rounded())) px")
        }
        // Typing in place stays above the keyboard: when it starts, when the
        // keyboard arrives or changes, and as the box grows line by line.
        .onChange(of: typingBox) { _, _ in revealTyping() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            revealTyping()
        }
    }

    /// Zoom and pan live in a UIScrollView rather than in SwiftUI gestures.
    /// See ZoomableCanvas for why: a MagnifyGesture on this stack can never
    /// outrank the per-element DragGestures inside it, which is what made
    /// pinching impossible once elements covered the page.
    private var zoomable: some View {
        let slot = columnSlot
        return ZoomableCanvas(
            contentSize: slot == nil ? CGSize(width: store.pageWidth, height: store.pageHeight) : columnSize,
            zoom: slot.map { columnZoom($0.scale) } ?? $store.zoom,
            fitToken: slot == nil ? "\(store.design.id)-\(store.pageWidth)x\(store.pageHeight)" : "\(store.design.id)-column",
            onBackgroundTap: { point in backgroundTap(at: point) },
            onPencilTap: { store.toggleDrawing() },
            pinchZooms: store.cropping == nil,
            claimsDoubleTap: { point in claimsDoubleTap(at: point) },
            pansFromPage: { point in pansFromPage(at: point) },
            holdsPage: { point in holdsWorkedPage(at: point) },
            request: canvasRequest(in: slot),
            column: slot.map { canvasColumn($0) },
            isControl: { point in isColumnControl(point) },
            movesOtherPage: { point in otherPageHit(at: point) != nil },
            onOtherPageDrag: { phase, start, now in otherPageDrag(phase, from: start, to: now) },
            onOtherPageDoubleTap: { point in otherPageDoubleTap(at: point) },
            onViewport: { visible, fit in viewportChanged(visible, fit: fit) },
            onMotion: { moving in motionChanged(moving) }
        ) {
            if let slot {
                columnContent(slot)
            } else {
                pageContent
                    .coordinateSpace(name: "page")
                    .frame(width: store.pageWidth, height: store.pageHeight)
            }
        }
    }

    /// The canvas, and what the column of pages answers: the width it is
    /// fitted to, a page made current from elsewhere scrolled to, and a
    /// header's questions.
    private var columnAware: some View {
        zoomable
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { canvasWidth = Double(proxy.size.width) }
                        .onChange(of: proxy.size.width) { _, width in canvasWidth = Double(width) }
                }
            }
            .onChange(of: store.pageIndex) { _, index in followPage(index) }
            .onChange(of: columnSlot) { _, _ in republishViewport() }
            .onChange(of: columnSlot?.scale) { old, new in rescaleZoom(from: old, to: new) }
            .asksBeforeDeletingPage($confirmingPageDelete, store: store)
            .sheet(isPresented: $editingPageNotes) { PageNotesSheet(store: store) }
            .task(id: Bleed.shown(store.design)) {
                // The bleed band says what it is for its first few seconds.
                bleedLabel = Bleed.shown(store.design)
                guard bleedLabel else { return }
                try? await Task.sleep(for: .seconds(Bleed.labelSeconds))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.3)) { bleedLabel = false }
            }
    }

    /// The box being typed in, as it is now.
    private var typingBox: CGRect? {
        store.editingTextId.flatMap { store.element($0) }.map(Geometry.aabb)
    }

    private func revealTyping() {
        guard let box = typingBox else { return }
        store.requestCanvas(.reveal(box, typing: true))
    }

    // MARK: page + overlay

    private var pageContent: some View {
        ZStack {
            // The shadow casts from a plain rectangle, not from the page
            // content. A .shadow() on PageRenderView made the blur's source a
            // tree that changes on every frame of a drag, and whose radius
            // changes on every frame of a pinch — so Core Animation had to
            // re-render the blur continuously and could cache nothing. The
            // page is an opaque rectangle of exactly these bounds, so a
            // constant rect casts an identical shadow for free.
            Rectangle()
                .fill(Color.white)
                .frame(width: store.pageWidth, height: store.pageHeight)
                // Divided by zoom like every other ornament: this lives inside
                // the scroll view's zoomed subview, so a fixed radius was 4pt
                // of blur at fit zoom — the page looked pasted flat onto the
                // workspace — and a 42pt black halo at 3x. With a bleed shown
                // the band casts it instead, from its own edge.
                .shadow(color: .black.opacity(bleed > 0 ? 0 : 0.16), radius: 12 * iz, y: 3 * iz)

            // Deselect (and commit any inline text edit) on the page surface
            // itself: the workspace-background tap can't fire here because
            // the opaque page sits above it in the ZStack.
            PageRenderView(design: store.design, page: shownPage)
                .environment(\.animationTime, store.previewTime.map { ($0, store.pageHold) })
                // While Play runs, a clip shows the frames decoded so far
                // rather than holding up the canvas for each one.
                .environment(\.liveVideo, store.previewTime != nil)
                // A photo's subject is found for focus off the main thread.
                .environment(\.onScreen, true)
                .environment(\.playsPictures, playAnimated)
                // Carries the document edge in dark mode, where a shadow on a
                // dark workspace is invisible.
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * iz))
                .contentShape(Rectangle())
                .onTapGesture {
                    commitTextEditIfAny()
                    // Select multiple keeps what it has built.
                    if !store.selectingMultiple { store.select(nil) }
                }
                // Held still on the empty page, a drag draws a rubber band;
                // a drag from there straight away moves the view instead
                // (see pansFromPage and ZoomableCanvas).
                .gesture(marqueeGesture)

            Group {
                if bleed > 0 { TrimLine(size: store.pageSize, unit: iz) }
                if store.snapping.showGrid { gridOverlay }
                if store.snapping.marginEnabled && store.snapping.showMargins { marginOverlay }
                ForEach(store.design.guides) { guide in guideLine(guide) }
                if store.showsReadingOrder { readingOrderOverlay }
            }

            if store.page.elements.isEmpty {
                emptyPageHint
            }

            // Hit layer: one transparent overlay per element for taps/drags,
            // announced in reading order rather than stacking order. A hidden
            // element has none: it is picked from Layers.
            let order = CanvasAccessibility.readingOrder(store.page.elements, pageHeight: store.pageHeight)
            ForEach(store.page.elements.filter { !$0.isHidden }) { el in
                elementHitArea(el)
                    .accessibilitySortPriority(Double(order.count - (order.firstIndex(of: el.id) ?? 0)))
            }

            if let moved = gesture.movedBox, store.cropping == nil, store.previewTime == nil {
                moveFurniture(moved)
            }

            if store.cropping == nil {
                SelectionOverlay(store: store,
                                 onHandleDrag: handleDrag,
                                 onHandleEnd: { store.commit(); clearTransient() },
                                 onRotateDrag: rotateDrag,
                                 onRotateEnd: { store.commit(); clearTransient(); store.tipEvent = .rotated })
            }

            // The band being drawn, and the letters of the match Find and
            // replace is showing.
            Group {
                if let band = gesture.marquee { marqueeView(band) }
                if let match = store.findHighlight, match.pageIndex == store.pageIndex,
                   let el = store.element(match.elementId), store.editingTextId != el.id {
                    findMark(el, match)
                }
            }

            if let id = store.editingTextId, let el = store.element(id) {
                if el.type == .shape { shapeTextEditor(el) } else { inlineTextEditor(el) }
            }

            // The modes that take the whole page's touches, over everything.
            Group {
                if let tool = store.drawing { drawingLayer(tool) }
                if store.erasing != nil { eraserLayer }
                if let crop = store.cropping, let photo = store.cropElement { cropLayer(photo, crop) }
            }
        }
        // The print bleed round the page, when the design shows one: behind
        // the page, and as big again as the bleed all round.
        .background {
            if bleed > 0 {
                BleedBand(design: store.design, page: shownPage, bleed: bleed, unit: iz, labelled: bleedLabel)
            }
        }
        // Pictures, text and links from other apps land where they are let go.
        .onDrop(of: CanvasDrop.types, isTargeted: $dropTargeted) { providers, location in
            CanvasDrop.handle(providers, at: location, store: store)
        }
        .overlay {
            if dropTargeted {
                Rectangle().stroke(Theme.accent, lineWidth: 4 * iz).allowsHitTesting(false)
            }
        }
    }

    // MARK: move

    /// While a selection moves: a faint dashed box where it started, once
    /// the finger has travelled far enough for that to be somewhere else,
    /// and every page edge it has crossed lit up — moving things off the
    /// page is allowed, a bleed is a real choice, but it should never happen
    /// unnoticed. A photo over a frame lights the frame up, as the place it
    /// will go if let go. None of it is ever part of the design.
    private func moveFurniture(_ moved: CGRect) -> some View {
        let start = gesture.dragUnion
        let w = store.pageWidth, h = store.pageHeight
        let showGhost = gesture.ghost
        let edgeWidth = 2 * iz
        let dash: [CGFloat] = [6 * iz, 6 * iz]
        let ghostWidth = 1.4 * iz
        let frame = gesture.frameTarget.flatMap { store.element($0) }.map(Self.outline)
        let frameWidth = 3 * iz
        return Canvas { context, _ in
            if let frame {
                context.fill(frame, with: .color(Theme.accent.opacity(0.14)))
                context.stroke(frame, with: .color(Theme.accent), lineWidth: frameWidth)
            }
            if showGhost {
                context.stroke(Path(start), with: .color(.black.opacity(0.2)),
                               style: StrokeStyle(lineWidth: ghostWidth, dash: dash))
            }
            var edges = Path()
            if moved.minX < 0 { edges.move(to: CGPoint(x: 0, y: 0)); edges.addLine(to: CGPoint(x: 0, y: h)) }
            if moved.maxX > w { edges.move(to: CGPoint(x: w, y: 0)); edges.addLine(to: CGPoint(x: w, y: h)) }
            if moved.minY < 0 { edges.move(to: CGPoint(x: 0, y: 0)); edges.addLine(to: CGPoint(x: w, y: 0)) }
            if moved.maxY > h { edges.move(to: CGPoint(x: 0, y: h)); edges.addLine(to: CGPoint(x: w, y: h)) }
            context.stroke(edges, with: .color(Theme.guide.opacity(0.6)), lineWidth: edgeWidth)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    /// An element's box, turned with it, in page units.
    private static func outline(_ el: Element) -> Path {
        let c = el.center
        let turn = CGAffineTransform(translationX: c.x, y: c.y)
            .rotated(by: CGFloat(el.rotation * .pi / 180))
            .translatedBy(x: -c.x, y: -c.y)
        return Path(el.frame).applying(turn)
    }

    // MARK: crop

    /// The page as the canvas draws it. In crop mode the photo being cropped
    /// is left out: the crop layer draws it over the dimmed page, whole. So
    /// is a text box being typed in, so its words show once, in the field —
    /// and a shape being typed in is drawn without its words.
    private var shownPage: Page {
        let hidden = [store.cropping?.id, store.editingTextId].compactMap { $0 }
        guard !hidden.isEmpty else { return store.page }
        var page = store.page
        if let id = store.editingTextId, let i = page.elements.firstIndex(where: { $0.id == id && $0.type == .shape }) {
            page.elements[i].text = nil
        }
        page.elements.removeAll { hidden.contains($0.id) && $0.type != .shape }
        return page
    }

    /// Whether a double tap here belongs to the page rather than to the
    /// canvas's zoom: anywhere in crop mode, and on a photo, a text box or an
    /// unlocked shape that takes words — a locked one zooms, as on the
    /// Android twin — or a table's cell, whose words are typed in.
    private func claimsDoubleTap(at point: CGPoint) -> Bool {
        if store.cropping != nil { return true }
        guard let hit = store.page.elements.last(where: { Geometry.hits($0, point: point) }) else { return false }
        return hit.type == .image || hit.type == .text || store.typedIn(hit) != nil
    }

    /// Crop mode over the page: the page dimmed, the whole picture faint
    /// beyond the frame, the frame's part as it will look, and the frame's
    /// brackets. One finger drags the picture or, from a bracket, trims the
    /// frame; two pinch it; a tap anywhere else is Done. Straightening waits
    /// while the picture is being placed, as it does on the Android twin,
    /// and comes back when crop mode ends.
    private func cropLayer(_ photo: Element, _ crop: CropSession) -> some View {
        var level = photo
        level.straighten = nil
        return ZStack {
            Color.black.opacity(0.45)
            cropPicture(photo, crop)
            ElementView(element: level)
                .allowsHitTesting(false)
                .environment(\.onScreen, true)
            cropArt(photo, crop)
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .contentShape(Rectangle())
        .gesture(cropDrag(crop))
        .simultaneousGesture(cropPinchGesture)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Cropping the photo")
        .accessibilityHint("Drag the picture to move it, pinch to zoom it, and pull the frame's corners and edges to trim it")
    }

    /// The whole picture, faint, where it lies behind and beyond the frame.
    private func cropPicture(_ photo: Element, _ crop: CropSession) -> some View {
        let drawn = Crop.drawnPicture(photo, image: crop.imageSize)
        // A trimmed clip shows the frame at its start, as the frame does.
        let src = VideoStore.atRest(photo)
        // On screen: a focus subject still being found shows the circle, and
        // the count read here draws it again once it is.
        let waits = photo.focusBlur?.subject != true
        if !waits { _ = ImageFilterEngine.subjectsFound.version }
        return ZStack {
            if let ui = PhotoLibrary.resolve(src) {
                let shown = ImageFilterEngine.apply(look: photo, to: ui, cacheKey: src ?? "", waits: waits)
                Image(uiImage: shown)
                    .resizable()
                    .frame(width: drawn.width, height: drawn.height)
                    .position(x: drawn.midX, y: drawn.midY)
            }
        }
        .frame(width: photo.w, height: photo.h)
        .opacity(0.43 * photo.opacity)
        .scaleEffect(x: photo.flipH ? -1 : 1, y: photo.flipV ? -1 : 1)
        .rotationEffect(.degrees(photo.rotation))
        .position(x: photo.x + photo.w / 2, y: photo.y + photo.h / 2)
        .allowsHitTesting(false)
    }

    /// The picture's outline, the frame, the thirds while a finger works it,
    /// and a bracket at every corner and edge — the one being pulled in the
    /// accent colour. All turned with the photo.
    private func cropArt(_ photo: Element, _ crop: CropSession) -> some View {
        let seen = Crop.picture(photo, image: crop.imageSize)
        let held = gesture.crop?.handle
        let working = gesture.crop?.isWorking ?? false
        let hairline = 1 * iz
        let bracketLength = 18 * iz
        return Canvas { context, _ in
            context.translateBy(x: photo.x + photo.w / 2, y: photo.y + photo.h / 2)
            context.rotate(by: .degrees(photo.rotation))
            context.translateBy(x: -photo.w / 2, y: -photo.h / 2)
            let frame = CGRect(x: 0, y: 0, width: photo.w, height: photo.h)
            context.stroke(Path(seen), with: .color(.white.opacity(0.6)), lineWidth: hairline)
            context.stroke(Path(frame), with: .color(.white), lineWidth: hairline * 1.5)
            if working {
                context.stroke(Self.thirds(in: frame), with: .color(.white.opacity(0.5)), lineWidth: hairline)
            }
            for handle in Handle.allCases where !photo.holdsPlace {
                context.stroke(Self.bracket(handle, in: frame, length: bracketLength),
                               with: .color(handle == held ? Theme.accent : .white),
                               style: StrokeStyle(lineWidth: hairline * 3, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
    }

    /// Two lines across and two down, a third of the way in from each side.
    private static func thirds(in frame: CGRect) -> Path {
        var path = Path()
        for i in 1...2 {
            let x = frame.minX + frame.width * Double(i) / 3
            let y = frame.minY + frame.height * Double(i) / 3
            path.move(to: CGPoint(x: x, y: frame.minY))
            path.addLine(to: CGPoint(x: x, y: frame.maxY))
            path.move(to: CGPoint(x: frame.minX, y: y))
            path.addLine(to: CGPoint(x: frame.maxX, y: y))
        }
        return path
    }

    /// An L at a corner, a short bar at the middle of an edge.
    private static func bracket(_ handle: Handle, in frame: CGRect, length: Double) -> Path {
        let u = handle.unit
        let p = CGPoint(x: frame.minX + frame.width * u.x, y: frame.minY + frame.height * u.y)
        let l = min(length, frame.width / 3, frame.height / 3)
        var path = Path()
        if handle.isCorner {
            let sx: Double = u.x == 0 ? 1 : -1
            let sy: Double = u.y == 0 ? 1 : -1
            path.move(to: CGPoint(x: p.x + sx * l, y: p.y))
            path.addLine(to: p)
            path.addLine(to: CGPoint(x: p.x, y: p.y + sy * l))
        } else if u.x == 0.5 {
            path.move(to: CGPoint(x: p.x - l * 0.7, y: p.y))
            path.addLine(to: CGPoint(x: p.x + l * 0.7, y: p.y))
        } else {
            path.move(to: CGPoint(x: p.x, y: p.y - l * 0.7))
            path.addLine(to: CGPoint(x: p.x, y: p.y + l * 0.7))
        }
        return path
    }

    /// What a finger landing at `point` works: the nearest bracket within
    /// reach, else the picture — anywhere on it, the part beyond the frame
    /// included, since that is the part you can see you want to bring in —
    /// else nothing of the photo's.
    private func cropTouch(at point: CGPoint, photo: Element, crop: CropSession) -> CropTouch {
        // A photo locked in position has no brackets: its frame stays put.
        var best = photo.holdsPlace ? 0 : Touch.pageUnits(22, zoom: store.zoom)
        var grabbed: Handle?
        for handle in Handle.allCases {
            let at = Geometry.handlePoint(photo, handle)
            let d = Double(hypot(at.x - point.x, at.y - point.y))
            if d < best {
                best = d
                grabbed = handle
            }
        }
        if let handle = grabbed {
            let at = Geometry.handlePoint(photo, handle)
            return .frame(handle, start: photo, grab: CGPoint(x: at.x - point.x, y: at.y - point.y))
        }
        let local = Crop.toFrame(photo, point)
        let frame = CGRect(x: 0, y: 0, width: photo.w, height: photo.h)
        if frame.contains(local) || Crop.picture(photo, image: crop.imageSize).contains(local) {
            return .picture(last: point)
        }
        return .outside
    }

    private func cropDrag(_ crop: CropSession) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
            .onChanged { value in
                guard let photo = store.cropElement else { return }
                if gesture.crop == nil {
                    gesture.crop = cropTouch(at: value.startLocation, photo: photo, crop: crop)
                }
                switch gesture.crop {
                case .some(.picture(let last)):
                    store.moveCropPicture(by: CGPoint(x: value.location.x - last.x, y: value.location.y - last.y))
                    gesture.crop = .picture(last: value.location)
                case .some(.frame(let handle, let start, let grab)):
                    let to = CGPoint(x: value.location.x + grab.x, y: value.location.y + grab.y)
                    let smallest = max(Crop.minFrame, Touch.pageUnits(24, zoom: store.zoom))
                    store.trimCrop(from: start, handle: handle, to: to, minSize: smallest)
                default:
                    break
                }
            }
            .onEnded { value in
                let touch = gesture.crop
                gesture.crop = nil
                store.badge = nil
                let travel = hypot(value.translation.width, value.translation.height) * store.zoom
                guard travel < Touch.dragSlop else { return }
                if case .some(.outside) = touch {
                    // A tap beside the photo is Done, as in every photo
                    // editor — and a tap on something else selects it in the
                    // same touch.
                    store.finishCrop()
                    let hit = store.page.elements.last { Geometry.hits($0, point: value.location) }
                    store.select(hit?.id)
                } else if let last = lastCropTap, Date().timeIntervalSince(last) < 0.3 {
                    lastCropTap = nil
                    store.finishCrop()
                } else {
                    lastCropTap = Date()
                }
            }
    }

    /// Two fingers in crop mode work the picture, not the canvas: spreading
    /// them zooms it about where they landed.
    private var cropPinchGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .onChanged { value in
                let factor = Double(value.magnification) / max(gesture.cropPinch, 0.0001)
                gesture.cropPinch = Double(value.magnification)
                store.zoomCropPicture(by: factor, around: value.startLocation)
            }
            .onEnded { _ in
                gesture.cropPinch = 1
                store.badge = nil
            }
    }

    // MARK: eraser

    /// Painting the region to remove: the strokes so far in translucent red,
    /// the current one live, all in page units for the store to map.
    private var eraserLayer: some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            ForEach(Array(store.eraserStrokes.enumerated()), id: \.offset) { _, stroke in
                Path(Freehand.cgPath(stroke))
                    .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: store.eraserWidth, lineCap: .round, lineJoin: .round))
            }
            if !strokePoints.isEmpty {
                Path(Freehand.cgPath(strokePoints))
                    .stroke(Color.red.opacity(0.45), style: StrokeStyle(lineWidth: store.eraserWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
                .onChanged { value in
                    if strokePoints.isEmpty || strokeStart != value.startLocation {
                        strokeStart = value.startLocation
                        strokePoints = [value.startLocation]
                    }
                    strokePoints.append(value.location)
                }
                .onEnded { _ in
                    store.eraserStrokes.append(Freehand.thinned(strokePoints))
                    strokePoints = []
                    strokeStart = nil
                }
        )
        .accessibilityLabel("Eraser")
        .accessibilityHint("Drag over what should go, then tap Erase")
        // A stroke a two-finger pan cut short never ended; putting the
        // eraser away takes its stub with it.
        .onDisappear { strokePoints = []; strokeStart = nil }
    }

    // MARK: drawing

    /// Above everything while the pen is on, so a stroke never selects or
    /// moves what it crosses. The live line is the same smoothed curve the
    /// finished element will hold.
    private func drawingLayer(_ tool: Freehand.Tool) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if !strokePoints.isEmpty {
                livePen(tool)
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
                .onChanged { value in
                    if strokePoints.isEmpty || strokeStart != value.startLocation {
                        strokeStart = value.startLocation
                        strokePoints = [value.startLocation]
                    }
                    strokePoints.append(value.location)
                }
                .onEnded { _ in
                    store.finishStroke(strokePoints)
                    strokePoints = []
                    strokeStart = nil
                }
        )
        .accessibilityLabel("Drawing surface")
        .accessibilityHint("Drag to draw a stroke")
        // A stroke a two-finger pan cut short never ended; putting the pen
        // away takes its stub with it.
        .onDisappear { strokePoints = []; strokeStart = nil }
    }

    /// The stroke under the finger, as the finished one will be drawn: a
    /// highlighter see-through and multiplying, a glow with its halo — or,
    /// for the eraser, a soft grey trail as wide as it reaches.
    @ViewBuilder
    private func livePen(_ tool: Freehand.Tool) -> some View {
        if tool.pen == .eraser {
            Path { p in p.addLines(strokePoints) }
                .stroke(Color.gray.opacity(0.3),
                        style: StrokeStyle(lineWidth: Freehand.eraserRadius(tool) * 2, lineCap: .round, lineJoin: .round))
        } else {
            let glow: Shadow? = tool.pen == .glow ? Freehand.glow(of: tool) : nil
            let halo: Color = glow.map { Color(hex: $0.color).opacity($0.opacity) } ?? .clear
            // The full blur, as ElementView casts the finished stroke's
            // shadow: at half of it the halo doubled the moment the finger
            // lifted. (Half is the SVG's sigma, not a SwiftUI radius.)
            let spread: Double = glow.map { $0.blur } ?? 0
            Path(Freehand.cgPath(strokePoints))
                .stroke(Color(hex: Freehand.drawnColor(tool)),
                        style: StrokeStyle(lineWidth: Freehand.drawnWidth(tool), lineCap: .round, lineJoin: .round))
                .blendMode(tool.pen == .highlighter ? .multiply : .normal)
                .shadow(color: halo, radius: spread)
        }
    }

    /// What a blank page said before this was: nothing. A white square and a
    /// round button in the corner, with no indication that the button is where
    /// everything comes from.
    ///
    /// Drawn here rather than in PageRenderView on purpose — PageRenderView is
    /// what thumbnails and exports render, and a hint that shipped inside an
    /// exported PNG would be worse than no hint at all.
    private var emptyPageHint: some View {
        VStack(spacing: 10 * iz) {
            Image(systemName: "plus.circle")
                .font(.system(size: 34 * iz, weight: .light))
            Text("Tap + to add text, photos,\nshapes and QR codes")
                .font(.system(size: 15 * iz, weight: .medium))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.onPage)
        .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
        .allowsHitTesting(false)
        .transition(.opacity)
    }

    // MARK: marquee

    /// Hold still on the empty page, then drag: the rubber band, as on the
    /// Android twin (CanvasGestures). The hold is felt as it takes, with
    /// the Android twin's tick.
    private var marqueeGesture: some Gesture {
        LongPressGesture(minimumDuration: CanvasGestures.holdSeconds)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("page")))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                if !gesture.banding {
                    gesture.banding = true
                    commitTextEditIfAny()
                    store.canvasTouchActive = true
                    store.buzz(.tick)
                }
                guard let drag else { return }
                let band = CGRect(
                    x: min(drag.startLocation.x, drag.location.x),
                    y: min(drag.startLocation.y, drag.location.y),
                    width: abs(drag.location.x - drag.startLocation.x),
                    height: abs(drag.location.y - drag.startLocation.y))
                gesture.marquee = band
                // Live: the selection follows the band as it grows, so you
                // see what you are about to get before you let go. A band
                // with no size yet leaves the selection be.
                if band.width > 0 || band.height > 0 { store.select(within: band) }
            }
            .onEnded { _ in
                gesture.marquee = nil
                gesture.banding = false
                store.canvasTouchActive = false
            }
    }

    /// Whether one finger dragged from `point` on the page moves the view:
    /// only where there is nothing to work — no element (at its touch
    /// target's size), no handle of the selection, no guide — and never
    /// while the pen, the eraser or crop mode has the page's touches.
    private func pansFromPage(at point: CGPoint) -> Bool {
        guard store.drawing == nil, store.erasing == nil, store.cropping == nil else { return false }
        let guideReach = Touch.pageUnits(12, zoom: store.zoom)
        let onGuide = store.design.guides.contains { guide in
            abs(Double(guide.vertical ? point.x : point.y) - guide.position) <= guideReach
        }
        return CanvasGestures.pansFromPage(onElement: holdsWorkedPage(at: point) || onGuide, held: 0)
    }

    /// Whether `point` on the page being worked is on something of it to
    /// work: an element shown, at its touch target's size, or within reach
    /// of a handle of the selection — the rest of the page round the
    /// selection still pans. Scrolling through pages, these keep their
    /// touches where they hang off the page, too (ZoomableCanvas.holdsPage).
    private func holdsWorkedPage(at point: CGPoint) -> Bool {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        // Only what is shown has a hit area: a hidden layer is empty page.
        let onElement = store.page.elements.contains { el in
            !el.isHidden && Geometry.hits(Self.reach(el, target), point: point)
        }
        return onElement || SelectionOverlay.handlesTake(point, store: store)
    }

    /// `el` grown about its centre to at least `target` across and down —
    /// its touch target, as its hit area is drawn.
    private static func reach(_ el: Element, _ target: Double) -> Element {
        var grown = el
        let grow = max(0, target - el.w) / 2, rise = max(0, target - el.h) / 2
        grown.x -= grow; grown.w += grow * 2
        grown.y -= rise; grown.h += rise * 2
        return grown
    }

    private func marqueeView(_ band: CGRect) -> some View {
        Rectangle()
            .fill(Theme.accent.opacity(0.10))
            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1 * iz))
            .frame(width: max(band.width, 1), height: max(band.height, 1))
            .position(x: band.midX, y: band.midY)
            .allowsHitTesting(false)
    }

    /// The snapping grid, as hairlines over the page. Drawn here and not in
    /// PageRenderView, so it is never in an export or a thumbnail. Too dense
    /// to see at this zoom, every second or fourth line is drawn.
    private var gridOverlay: some View {
        let spacing = Geometry.drawnGridSpacing(store.snapping.grid, scale: Double(store.zoom), minGap: 6)
        let w = store.pageWidth, h = store.pageHeight
        return Canvas { context, _ in
            var path = Path()
            for x in Geometry.gridLines(across: w, spacing: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: h))
            }
            for y in Geometry.gridLines(across: h, spacing: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: w, y: y))
            }
            context.stroke(path, with: .color(Theme.accent.opacity(0.18)), lineWidth: 1 * iz)
        }
        .frame(width: w, height: h)
        .allowsHitTesting(false)
    }

    /// A guide: a thin line across the page that can be dragged into place,
    /// and pressed and held for Position… and Remove. Its touch target is
    /// wide though the line is not. With the rulers on, one dragged back
    /// onto its ruler goes, in the same step as the drag.
    private func guideLine(_ guide: Guide) -> some View {
        let w = store.pageWidth, h = store.pageHeight
        return Rectangle()
            .fill(Theme.guide.opacity(0.9))
            .frame(width: guide.vertical ? 1.5 * iz : w, height: guide.vertical ? h : 1.5 * iz)
            .contentShape(Rectangle().inset(by: -8 * iz))
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .named("page"))
                    .onChanged { value in
                        store.moveGuideTransient(guide.id, to: guide.vertical ? value.location.x : value.location.y)
                    }
                    .onEnded { value in
                        if rulers && overRuler(value.location, vertical: guide.vertical) {
                            store.removeGuide(guide.id)
                        } else {
                            store.commit()
                        }
                    }
            )
            .onLongPressGesture(minimumDuration: 0.5) { guideMenu = guide }
            .position(x: guide.vertical ? guide.position : w / 2, y: guide.vertical ? h / 2 : guide.position)
            .accessibilityLabel(guideTitle(guide))
            .accessibilityHint("Drag to move, press and hold to place or remove; or use the actions to move, place or remove it")
            .accessibilityActions { guideActions(guide) }
    }

    /// Whether `point` on the page is on screen over the ruler a guide
    /// across it — `vertical` or not — came from.
    private func overRuler(_ point: CGPoint, vertical: Bool) -> Bool {
        let view = store.viewport
        return vertical
            ? Guides.onRuler(Double(point.x), viewportStart: Double(view.minX), zoom: store.zoom)
            : Guides.onRuler(Double(point.y), viewportStart: Double(view.minY), zoom: store.zoom)
    }

    /// A guide moved a step or taken away without a drag, for VoiceOver and
    /// Switch Control — the Android twin's guide actions. Each is one step.
    @ViewBuilder
    private func guideActions(_ guide: Guide) -> some View {
        let step = CanvasAccessibility.nudge(for: store.design)
        Button(guide.vertical ? "Move left" : "Move up") { nudgeGuide(guide, by: -step) }
        Button(guide.vertical ? "Move right" : "Move down") { nudgeGuide(guide, by: step) }
        Button("Position…") { askPosition(guide) }
        Button("Remove guide") { store.removeGuide(guide.id) }
    }

    /// "Vertical guide at 540".
    private func guideTitle(_ guide: Guide) -> String {
        let at = Guides.halfPixel(guide.position)
        let number = at == at.rounded() ? String(Int(at)) : String(at)
        return guide.vertical ? "Vertical guide at \(number)" : "Horizontal guide at \(number)"
    }

    /// Position…: the guide's place typed in, starting from where it is.
    private func askPosition(_ guide: Guide) {
        let at = guide.position
        guidePositionText = at == at.rounded() ? String(Int(at)) : String(at)
        positioningGuide = guide
    }

    private func nudgeGuide(_ guide: Guide, by step: Double) {
        store.moveGuideTransient(guide.id, to: guide.position + step)
        store.commit()
    }

    /// The safe area as a dashed inset. Like the grid, never exported.
    /// Check accessibility's "Show reading order": each element shown on
    /// the page numbered in the order VoiceOver reads it, at its top left.
    /// Never in an export, and nothing to touch.
    private var readingOrderOverlay: some View {
        let shown = store.page.elements.filter { !$0.isHidden }
        let order = CanvasAccessibility.readingOrder(shown, pageHeight: store.pageHeight)
        let boxes = Dictionary(shown.map { ($0.id, Geometry.aabb($0)) }, uniquingKeysWith: { first, _ in first })
        return ZStack {
            ForEach(order.indices, id: \.self) { n in
                if let box = boxes[order[n]] {
                    Text("\(n + 1)")
                        .font(.system(size: 13, weight: .bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .frame(minWidth: 22, minHeight: 22)
                        .background(Theme.accent, in: Capsule())
                        .scaleEffect(iz)
                        .position(x: box.minX, y: box.minY)
                }
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The letters of the match Find and replace is showing, marked over
    /// its box and turning with it — or the whole box, where its words are
    /// drawn round a curve, along a path or the like.
    private func findMark(_ el: Element, _ match: DesignStore.TextMatch) -> some View {
        let rects = FindReplace.letterRects(of: match.plain, in: el)
        let marks = rects.isEmpty ? [CGRect(x: 0, y: 0, width: el.w, height: el.h)] : rects
        return ZStack(alignment: .topLeading) {
            ForEach(marks.indices, id: \.self) { i in
                Rectangle()
                    .fill(Theme.accent.opacity(0.3))
                    .frame(width: marks[i].width, height: marks[i].height)
                    .offset(x: marks[i].minX, y: marks[i].minY)
            }
        }
        .frame(width: el.w, height: el.h, alignment: .topLeading)
        .rotationEffect(.degrees(el.rotation))
        .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var marginOverlay: some View {
        let m = store.snapping.marginInset(for: store.pageSize)
        return Rectangle()
            .strokeBorder(Theme.guide.opacity(0.55),
                          style: StrokeStyle(lineWidth: 1 * iz, dash: [6 * iz, 4 * iz]))
            .frame(width: max(store.pageWidth - 2 * m, 1), height: max(store.pageHeight - 2 * m, 1))
            .position(x: store.pageWidth / 2, y: store.pageHeight / 2)
            .allowsHitTesting(false)
    }

    private func elementHitArea(_ el: Element) -> some View {
        Rectangle()
            .fill(Color.clear)
            .contentShape(Rectangle())
            .frame(width: max(el.w, Touch.pageUnits(Touch.minTarget, zoom: store.zoom)),
                   height: max(el.h, Touch.pageUnits(Touch.minTarget, zoom: store.zoom)))
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
            .onTapGesture(count: 2) {
                // Selecting several, taps are each their own, never a pair:
                // two quick ones put the element in and take it out again,
                // as on the Android twin, rather than typing or cropping.
                if store.selectingMultiple {
                    store.tapInSelectMultiple(el.id)
                    store.tapInSelectMultiple(el.id)
                    return
                }
                // A shape double-tapped is typed in, as a text box is; a
                // table cell's rectangle, its words.
                if let target = store.typedIn(el) {
                    startTextEdit(target)
                } else if el.type == .image {
                    // A photo double-tapped opens crop, where the picture is
                    // worked directly — or says why it cannot.
                    commitTextEditIfAny()
                    store.startCrop(el.id)
                }
            }
            .onTapGesture {
                commitTextEditIfAny()
                // Select multiple: each tap puts the element's group in or
                // takes it out.
                if store.selectingMultiple {
                    store.tapInSelectMultiple(el.id)
                    return
                }
                // A second tap on a member of the selected group takes just
                // that member; otherwise the tap takes the element's group.
                if !store.selectMember(el.id) { store.select(el.id) }
            }
            .onLongPressGesture(minimumDuration: CanvasGestures.holdSeconds) {
                store.select(el.id, additive: true)
                store.buzz(.tick)
            }
            .gesture(moveGesture(el))
            .accessibilityElement()
            .accessibilityLabel(CanvasAccessibility.label(for: el))
            .accessibilityValue(CanvasAccessibility.value(for: el, design: store.design))
            .accessibilityAddTraits(store.selection.contains(el.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(el.type == .text ? "Double tap to select; double tap and hold to edit"
                               : el.type == .image ? "Double tap to select; Crop is in the actions" : "Double tap to select")
            .accessibilityActions { accessibilityActions(for: el) }
    }

    /// The edits that otherwise need a drag, as VoiceOver actions. Each acts
    /// on this element alone, selecting it first, and is one undo step.
    @ViewBuilder
    private func accessibilityActions(for el: Element) -> some View {
        let step = CanvasAccessibility.nudge(for: store.design)
        // The long press's own job: a selection built one element at a time,
        // to group, align or tidy. Offered on locked things too.
        Button(store.selection.contains(el.id) ? "Remove from selection" : "Add to selection") {
            store.select(el.id, additive: true)
        }
        // A position lock keeps it where it is, as a whole lock does, but
        // it can still be copied.
        if !el.holdsPlace {
            Button("Move left") { nudge(el, dx: -step, dy: 0) }
            Button("Move right") { nudge(el, dx: step, dy: 0) }
            Button("Move up") { nudge(el, dx: 0, dy: -step) }
            Button("Move down") { nudge(el, dx: 0, dy: step) }
        }
        if !el.locked {
            Button("Duplicate") { store.select(el.id); store.duplicateSelected() }
        }
        // A position lock asks first (DesignStore.askingDelete).
        if !el.locked {
            Button("Delete") { store.select(el.id); store.deleteSelected() }
        }
        Button("Bring forward") { store.select(el.id); store.reorderSelected(.forward) }
        Button("Send backward") { store.select(el.id); store.reorderSelected(.backward) }
        if let target = store.typedIn(el) {
            Button("Edit text") { startTextEdit(target) }
        }
        if el.type == .image && !el.locked {
            Button("Crop") { store.startCrop(el.id) }
        }
    }

    private func nudge(_ el: Element, dx: Double, dy: Double) {
        store.select(el.id)
        store.nudgeSelected(dx: dx, dy: dy)
    }

    // MARK: move

    private func moveGesture(_ el: Element) -> some Gesture {
        // A real screen-point threshold. The gesture reads the "page" space,
        // so this has to be divided by zoom to mean 10 points on glass. The
        // old form capped the result at 6 page units to stay under an ancestor
        // pan gesture that the scroll view has since replaced — and the cap
        // inverted the intent: at the fit zoom every design opens at (~0.3),
        // it made the threshold ~2 points, so a tap moved the element and
        // pushed an undo step.
        DragGesture(minimumDistance: Touch.pageUnits(Touch.dragSlop, zoom: store.zoom),
                    coordinateSpace: .named("page"))
            .onChanged { value in moveChanged(el, from: value.startLocation, to: value.location) }
            .onEnded { value in moveEnded(from: value.startLocation, to: value.location) }
    }

    /// A move of `el`, and the rest of the selection with it, the finger
    /// gone from `start` to `location` in page units — by its own drag, or
    /// by a drag from another page of the column that made this page the
    /// one worked (otherPageDrag).
    private func moveChanged(_ el: Element, from start: CGPoint, to location: CGPoint) {
        guard !el.holdsPlace, store.editingTextId != el.id else { return }
        if !gesture.dragActive {
            gesture.dragActive = true
            store.canvasTouchActive = true
            // Selected before the step opens: selecting ends any typing
            // as its own step, which must not swallow this move's.
            // Select multiple adds it, and the whole selection moves.
            if !store.selection.contains(el.id) {
                if store.selectingMultiple { store.tapInSelectMultiple(el.id) } else { store.select(el.id) }
            }
            store.beginGesture()
            gesture.dragOriginals = Dictionary(
                uniqueKeysWithValues: store.selectedElements
                    .filter { !$0.holdsPlace }
                    .map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
            let lines = Geometry.taggedSnapLines(design: store.design, page: store.page,
                                                 excluding: Set(gesture.dragOriginals.keys),
                                                 settings: store.snapping)
            gesture.snapTagsX = lines.x
            gesture.snapTagsY = lines.y
            gesture.snapX = lines.x.map(\.position)
            gesture.snapY = lines.y.map(\.position)
            gesture.dragUnion = Geometry.union(
                store.selectedElements.filter { !$0.holdsPlace }.map(Geometry.aabb))
            gesture.siblingBoxes = store.page.elements
                .filter { gesture.dragOriginals[$0.id] == nil && !$0.isHidden }
                .map(Geometry.aabb)
            // One photo on its own may be going into a frame.
            if gesture.dragOriginals.count == 1, let id = gesture.dragOriginals.keys.first,
               let photo = store.element(id), PhotoFrames.canDrop(photo) {
                gesture.framePhoto = id
            }
        }
        var dx = location.x - start.x
        var dy = location.y - start.y
        var gapX: Double?
        var gapY: Double?

        // Snap the union of moved boxes against page + siblings.
        // Translating the grab-time union is exact, not an
        // approximation: rotation happens about each element's own
        // centre, which moves with it, so translating an element
        // translates its bounding box, and the union of translated
        // boxes is the translated union.
        if !gesture.dragUnion.isEmpty {
            let moved = gesture.dragUnion.offsetBy(dx: dx, dy: dy)
            let snap = Geometry.snap(box: moved,
                                     xLines: gesture.snapX, yLines: gesture.snapY,
                                     threshold: 6 / store.zoom)
            dx += snap.dx
            dy += snap.dy
            store.guideX = snap.guideX
            store.guideY = snap.guideY
            let sourceX = Geometry.snapSource(at: snap.guideX, in: gesture.snapTagsX)
            let sourceY = Geometry.snapSource(at: snap.guideY, in: gesture.snapTagsY)
            if store.guideXSource != sourceX { store.guideXSource = sourceX }
            if store.guideYSource != sourceY { store.guideYSource = sourceY }
            // Equal spacing: between two neighbours, land at the
            // same distance from each and say what that distance is —
            // on an axis no line is holding (a grid line gives way),
            // so the two never pull the box between them.
            if store.snapping.toElements {
                let even = Geometry.equalGap(moving: gesture.dragUnion.offsetBy(dx: dx, dy: dy),
                                             siblings: gesture.siblingBoxes, threshold: 6 / store.zoom)
                gapX = (snap.guideX == nil || sourceX == .grid) ? even.gapX : nil
                gapY = (snap.guideY == nil || sourceY == .grid) ? even.gapY : nil
                if gapX != nil { dx += even.dx }
                if gapY != nil { dy += even.dy }
            }
            let spaced = gapX != nil || gapY != nil
            if store.spacingSnapped != spaced { store.spacingSnapped = spaced }
        }

        // Where it is going, for the page edges it crosses, and — once
        // the finger has really travelled — where it came from.
        if !gesture.dragUnion.isEmpty {
            gesture.movedBox = gesture.dragUnion.offsetBy(dx: dx, dy: dy)
        }
        // The frame under the finger, lit up: let go there, the photo
        // goes into it.
        if let photo = gesture.framePhoto {
            let over = store.frameDropTarget(at: location, dragging: photo)
            if gesture.frameTarget != over { gesture.frameTarget = over }
        }
        // Over another page in the column, that page lit up: let go
        // there, it goes to that page.
        if columnOn {
            let over = dropPage(at: location)
            if gesture.dropPage != over { gesture.dropPage = over }
        }
        let travel = hypot(location.x - start.x, location.y - start.y) * store.zoom
        if travel >= 14 && !gesture.ghost { gesture.ghost = true }
        for i in store.design.pages[store.pageIndex].elements.indices {
            let id = store.design.pages[store.pageIndex].elements[i].id
            if let origin = gesture.dragOriginals[id] {
                store.design.pages[store.pageIndex].elements[i].x = origin.x + dx
                store.design.pages[store.pageIndex].elements[i].y = origin.y + dy
            }
        }
        // Where the moving box is, each axis a guide holds marked,
        // and any gap made equal — as the Android twin reads it.
        if let moved = gesture.movedBox {
            store.setBadge(Readouts.move(x: moved.minX, y: moved.minY,
                                         heldX: store.guideX != nil, heldY: store.guideY != nil,
                                         gapX: gapX, gapY: gapY))
        }
    }

    /// The move let go with the finger at `location`, having started at
    /// `start`, in page units.
    private func moveEnded(from start: CGPoint, to location: CGPoint) {
        // Crossing the threshold and landing back where you started is
        // a tap that wandered, not an edit: it must not enter history,
        // or undo fills up with steps that changed nothing.
        let moved = hypot(location.x - start.x, location.y - start.y) * store.zoom
        if gesture.dragActive && moved >= Touch.tapSlop {
            // Let go over a frame, the photo goes into it — the move
            // and the drop one step; over another page in the column,
            // it goes there, one step too; anywhere else it is a move.
            if !dropIntoFrame(at: location) && !dropOntoPage(at: location) { store.commit() }
        } else {
            store.endGesture()
        }
        clearTransient()
    }

    /// The photo being moved goes into the frame under `point`, if there is
    /// one; see DesignStore.dropIntoFrame. True when it did.
    private func dropIntoFrame(at point: CGPoint) -> Bool {
        guard let photo = gesture.framePhoto, let home = gesture.dragOriginals[photo],
              let frame = store.frameDropTarget(at: point, dragging: photo) else { return false }
        return store.dropIntoFrame(photo, onto: frame, home: home)
    }

    /// Let go over another page in the column, what moves goes there,
    /// under the finger as it was held (PageColumn.landing) — the move and
    /// the change of page one step (DesignStore.moveSelectedToPage). True
    /// when it did.
    private func dropOntoPage(at point: CGPoint) -> Bool {
        guard let target = dropPage(at: point), let from = columnSlot else { return false }
        let slots = columnSlots
        // The selection's own box, as the store puts it at the drop.
        let ids = PageMove.moving(store.page.elements, selection: store.selection)
        let moving = store.page.elements.filter { ids.contains($0.id) }
        guard !moving.isEmpty else { return false }
        let chosen = moving.filter { store.selection.contains($0.id) }
        let box = Geometry.union((chosen.isEmpty ? moving : chosen).map(Geometry.aabb))
        pageFromColumn = target
        let at = PageColumn.landing(box, finger: from.toColumn(point), from: from, to: slots[target])
        guard store.moveSelectedToPage(target, at: at) else {
            pageFromColumn = nil
            return false
        }
        return true
    }

    /// The page in the column under `point` on the page being worked, when
    /// it is another one.
    private func dropPage(at point: CGPoint) -> Int? {
        guard let slot = columnSlot else { return nil }
        let index = PageColumn.pageAt(slot.toColumn(point), in: columnSlots)
        return index == store.pageIndex ? nil : index
    }

    // MARK: resize / rotate (called from the overlay)

    private func handleDrag(_ handle: Handle, _ location: CGPoint) {
        if store.selection.count > 1 {
            groupHandleDrag(handle, location)
            return
        }
        guard let selected = store.singleSelection, !selected.holdsPlace else { return }
        if gesture.resizeOriginal?.id != selected.id || !gesture.dragActive {
            store.beginGesture()
            gesture.resizeOriginal = selected
            gesture.dragActive = true
            store.canvasTouchActive = true
            gesture.resizeImage = selected.type == .image && !handle.isCorner
                ? PhotoLibrary.resolve(selected.src)?.size : nil
            // The lines a move snaps to, read once: nothing else moves while
            // the handle is held.
            let lines = Geometry.taggedSnapLines(design: store.design, page: store.page,
                                                 excluding: [selected.id], settings: store.snapping)
            gesture.snapTagsX = lines.x
            gesture.snapTagsY = lines.y
            gesture.snapX = lines.x.map(\.position)
            gesture.snapY = lines.y.map(\.position)
        }
        guard let original = gesture.resizeOriginal else { return }
        if trimPhoto(original, handle: handle, to: location) { return }
        let proportional = original.type != .line && handle.isCorner
        let minSize = original.type == .text ? 12.0 : 8.0
        let next = snapped(Geometry.resize(original, handle: handle, to: location,
                                           proportional: proportional, minSize: minSize),
                           original: original, handle: handle, proportional: proportional, minSize: minSize)
        store.updateSelectedTransient { el in
            el.x = next.minX
            el.w = next.width
            switch el.type {
            case .text:
                el.y = next.minY
                if handle.isCorner {
                    // The type scales with the box, and its tracking with it,
                    // so a spaced-out headline keeps its proportions.
                    let scale = next.width / original.w
                    el.fontSize = max(6, (original.fontSize ?? 42) * scale)
                    el.letterSpacing = original.letterSpacing.map { $0 * scale }
                    el.h = next.height
                } else if el.fitText == true || el.vAlign != nil {
                    // The box is the design here; the type follows it.
                    el.h = next.height
                } else {
                    el.h = FontLibrary.layoutHeight(for: el)
                }
            case .line:
                el.y = next.minY + (next.height - original.h) / 2
                el.h = original.h
            default:
                el.y = next.minY
                el.h = next.height
            }
        }
        if let el = store.singleSelection {
            // Scaling type is changing its size, and that is the number worth
            // reading; everything else is the box.
            store.badge = el.type == .text && handle.isCorner
                ? Readouts.typeSize(FontLibrary.effectiveFontSize(for: el))
                : "\(Int(el.w)) × \(Int(el.h))"
        }
    }

    /// A photo's side trims its frame across a picture that stays where it
    /// is on the page, as crop mode's brackets do and as on the Android twin
    /// — rather than squashing the picture into the new shape. Not for a
    /// photo shown whole or straightened, or one whose picture cannot be
    /// read: those stretch as before. True when it trimmed.
    private func trimPhoto(_ original: Element, handle: Handle, to location: CGPoint) -> Bool {
        guard original.type == .image, !handle.isCorner, original.cropFit != true,
              (original.straighten ?? 0) == 0, let image = gesture.resizeImage,
              image.width > 0, image.height > 0 else { return false }
        var trimmed = Crop.trimmed(original, image: image, handle: handle, to: location, minSize: 8)
        // The side snaps as any side does: the finger is taken on by the
        // snap's correction and the frame trimmed again, so the picture still
        // stays put. Held short of the line by the picture's own edge, it is
        // not on the line, and no guide says it is.
        let target = snapped(trimmed.frame, original: original, handle: handle, proportional: false, minSize: 8)
        if target != trimmed.frame {
            // How far the snap moves the handle, on the page, so a photo
            // turned a quarter is taken on along the way it now faces.
            var aimed = trimmed
            aimed.x = target.minX
            aimed.y = target.minY
            aimed.w = target.width
            aimed.h = target.height
            let to = Geometry.handlePoint(aimed, handle), from = Geometry.handlePoint(trimmed, handle)
            trimmed = Crop.trimmed(original, image: image, handle: handle,
                                   to: CGPoint(x: location.x + to.x - from.x, y: location.y + to.y - from.y), minSize: 8)
            if !Self.same(trimmed.frame, target) { showGuides(Geometry.ResizeSnap(box: target)) }
        }
        store.updateSelectedTransient { el in
            if el.id == trimmed.id { el = trimmed }
        }
        store.badge = "\(Int(trimmed.w)) × \(Int(trimmed.h))"
        return true
    }

    /// A resized box with its moving edges snapped to the lines a move snaps
    /// to (Geometry.snapResize), at a move's reach, and the guides shown as a
    /// move shows them. An element turned a quarter, a half or three
    /// quarters snaps the edges the turn has put square to the page, as on
    /// the Android twin; one turned off the square is left as it is: its
    /// edges do not run along the lines.
    private func snapped(_ box: CGRect, original: Element, handle: Handle,
                         proportional: Bool, minSize: Double) -> CGRect {
        let snap = Geometry.snapTurnedResize(box, rotation: original.rotation, handle: handle,
                                             xLines: gesture.snapX, yLines: gesture.snapY,
                                             threshold: 6 / store.zoom, proportional: proportional,
                                             minSize: minSize) ?? Geometry.ResizeSnap(box: box)
        showGuides(snap)
        return snap.box
    }

    /// The snap guides a resize is holding, each named for what it lines up
    /// with, as a move's are.
    private func showGuides(_ snap: Geometry.ResizeSnap) {
        store.guideX = snap.guideX
        store.guideY = snap.guideY
        let sourceX = Geometry.snapSource(at: snap.guideX, in: gesture.snapTagsX)
        let sourceY = Geometry.snapSource(at: snap.guideY, in: gesture.snapTagsY)
        if store.guideXSource != sourceX { store.guideXSource = sourceX }
        if store.guideYSource != sourceY { store.guideYSource = sourceY }
    }

    /// Two boxes the same to within half a page unit.
    private static func same(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) < 0.5 && abs(a.minY - b.minY) < 0.5
            && abs(a.maxX - b.maxX) < 0.5 && abs(a.maxY - b.maxY) < 0.5
    }

    /// Resize a multi-selection from a corner of its box: the box resizes
    /// exactly as a single element would, and every member is scaled to
    /// follow it.
    private func groupHandleDrag(_ handle: Handle, _ location: CGPoint) {
        if gesture.groupOriginals.isEmpty || !gesture.dragActive {
            let members = store.selectedElements.filter { !$0.holdsPlace }
            guard !members.isEmpty else { return }
            store.beginGesture()
            gesture.dragActive = true
            store.canvasTouchActive = true
            gesture.groupOriginals = members
            gesture.groupBox = Geometry.union(members.map(Geometry.aabb))
        }
        // The floor is on the long side only: a row of lines is as short as
        // a line, and 8 on that side kept it from ever shrinking (and made a
        // thinner one jump up on the first move). Each member keeps its own
        // minimum as it scales.
        let long = max(gesture.groupBox.width, gesture.groupBox.height)
        let short = min(gesture.groupBox.width, gesture.groupBox.height)
        let floor = long > 0 && short > 0 ? 8 * short / long : 8
        let box = Geometry.resize(Geometry.boxElement(gesture.groupBox), handle: handle,
                                  to: location, proportional: true, minSize: floor)
        store.replaceTransient(Geometry.scale(gesture.groupOriginals, from: gesture.groupBox, to: box))
        store.badge = "\(Int(box.width)) × \(Int(box.height))"
    }

    private func groupRotateDrag(_ location: CGPoint) {
        if gesture.groupOriginals.isEmpty || !gesture.dragActive {
            let members = store.selectedElements.filter { !$0.holdsPlace }
            guard !members.isEmpty else { return }
            store.beginGesture()
            gesture.dragActive = true
            store.canvasTouchActive = true
            gesture.groupOriginals = members
            gesture.groupBox = Geometry.union(members.map(Geometry.aabb))
            gesture.rotateCenter = CGPoint(x: gesture.groupBox.midX, y: gesture.groupBox.midY)
            gesture.rotateOffset = Geometry.angle(from: gesture.rotateCenter!, to: location)
        }
        guard let center = gesture.rotateCenter else { return }
        var delta = Geometry.angle(from: center, to: location) - gesture.rotateOffset
        delta = (delta.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let free = delta
        delta = Geometry.snapAngle(delta, step: 45, threshold: 4)
        store.rotationSnapped = delta != free
        store.replaceTransient(Geometry.rotate(gesture.groupOriginals, around: center,
                                               by: (delta * 10).rounded() / 10))
        store.setBadge(Readouts.angle(delta, snapped: delta != free))
    }

    private func rotateDrag(_ location: CGPoint) {
        if store.selection.count > 1 {
            groupRotateDrag(location)
            return
        }
        guard let selected = store.singleSelection, !selected.holdsPlace else { return }
        if gesture.rotateCenter == nil || !gesture.dragActive {
            store.beginGesture()
            gesture.dragActive = true
            store.canvasTouchActive = true
            gesture.rotateCenter = selected.center
            gesture.rotateOffset = Geometry.angle(from: selected.center, to: location) - selected.rotation
        }
        guard let center = gesture.rotateCenter else { return }
        var angle = Geometry.angle(from: center, to: location) - gesture.rotateOffset
        angle = (angle.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        let raw = angle
        angle = Geometry.snapAngle(angle, step: 45, threshold: 4)
        store.rotationSnapped = angle != raw
        store.updateSelectedTransient { $0.rotation = (angle * 10).rounded() / 10 }
        // The digits turn guide-coloured while the angle is held on a snap.
        store.setBadge(Readouts.angle(angle, snapped: store.rotationSnapped))
    }

    private func clearTransient() {
        gesture = GestureState()
        store.guideX = nil
        store.guideY = nil
        store.guideXSource = nil
        store.guideYSource = nil
        store.badge = nil
        store.badgeRuns = nil
        store.rotationSnapped = false
        store.spacingSnapped = false
        store.canvasTouchActive = false
    }

    // MARK: inline text editing

    private func startTextEdit(_ el: Element) {
        store.startTyping(el.id)
    }

    func commitTextEditIfAny() {
        store.endTextEdit()
    }

    /// Typing in place: a field set exactly as the words are drawn — the
    /// drawn size, tracking, line pitch, underline and alignment — over the
    /// box, which the page leaves out meanwhile so the words show once. The
    /// words sit top, middle or bottom as the box places them.
    private func inlineTextEditor(_ el: Element) -> some View {
        let sits: Alignment = el.vAlign == "middle" ? .center : el.vAlign == "bottom" ? .bottom : .top
        let id = el.id
        return InlineTextField(element: el,
                               onChange: { typeInline(id, $0) },
                               onDone: { commitTextEditIfAny() },
                               onToggle: { store.toggleText($0) },
                               onStyled: { store.styleWhileTyping($0) },
                               onWordColour: { store.chooseWordColour(id, range: $0) },
                               onWordScale: { store.scaleWords(id, range: $0, by: $1) },
                               onWordFont: { store.chooseWordFont(id, range: $0) },
                               onWordLink: { store.chooseWordLink(id, range: $0) })
            .frame(width: el.w)
            .frame(width: el.w, height: el.h, alignment: sits)
            // The whole box is the field's: the field is only as tall as its
            // words, and a tap above or below words set in the middle or at
            // the foot fell through to the box and ended the typing. Behind
            // the field, so the field's own taps still place the caret.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture {})
            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1 * iz).allowsHitTesting(false))
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
    }

    /// Typing in a shape: the same field, as wide as the shape's text-safe
    /// box and set in it top, middle or bottom, over the shape — which the
    /// page draws meanwhile without its words. It turns with the shape, and
    /// sits in the box the shape's flip puts it in, the right way round.
    private func shapeTextEditor(_ el: Element) -> some View {
        let words = ShapeText.textElement(for: el)
        let box = ShapeText.shownBox(for: el)
        let sits: Alignment = words.vAlign == "top" ? .top : words.vAlign == "bottom" ? .bottom : .center
        let id = el.id
        return InlineTextField(element: words,
                               onChange: { typeInline(id, $0) },
                               onDone: { commitTextEditIfAny() },
                               onToggle: { store.toggleText($0) },
                               onStyled: { store.styleWhileTyping($0) },
                               wordStyles: false)
            .frame(width: box.width)
            .frame(width: box.width, height: box.height, alignment: sits)
            .overlay(Rectangle().stroke(Theme.accent, lineWidth: 1 * iz).allowsHitTesting(false))
            .position(x: box.midX, y: box.midY)
            .frame(width: el.w, height: el.h)
            // The whole shape is the field's, as a text box is: a tap on it
            // outside the words keeps the typing going.
            .background(Color.clear.contentShape(Rectangle()).onTapGesture {})
            .rotationEffect(.degrees(el.rotation))
            .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
    }

    private func typeInline(_ id: String, _ words: String) {
        store.typeWords(words, into: id)
    }

    // MARK: scroll through pages

    /// Whether the canvas is the column of every page.
    private var columnOn: Bool { pageScroll && canvasWidth > 0 }

    /// Every page's place in the column, while it is one; none otherwise.
    private var columnSlots: [PageColumn.Slot] {
        guard columnOn else { return [] }
        return PageColumn.pageOrigins(store.design.pages.map { store.design.size(for: $0) },
                                      gap: PageColumn.room, gutter: PageColumn.gutter, viewportWidth: canvasWidth)
    }

    /// The page being worked's place in the column.
    private var columnSlot: PageColumn.Slot? {
        let slots = columnSlots
        return slots.indices.contains(store.pageIndex) ? slots[store.pageIndex] : nil
    }

    private var columnSize: CGSize {
        CGSize(width: canvasWidth, height: PageColumn.columnHeight(columnSlots, gap: PageColumn.room))
    }

    /// The page being worked in the column, for the scroll view — with the
    /// widest page's scale, whose zoom range the column's is.
    private func canvasColumn(_ slot: PageColumn.Slot) -> CanvasColumn {
        CanvasColumn(page: slot.rect, scale: slot.scale, widest: columnSlots.map(\.scale).min() ?? slot.scale)
    }

    /// One point on screen, in column units.
    private var columnPoint: Double { (columnSlot?.scale ?? 1) * iz }

    /// Crop, typing, the pen, the eraser or a preview playing holds the
    /// view to the page being worked: scrolling does not change it, and the
    /// headers only say which page is which.
    private var pagePinned: Bool {
        store.cropping != nil || store.editingTextId != nil || store.drawing != nil
            || store.erasing != nil || store.previewTime != nil
    }

    // MARK: the view

    /// The scroll view's zoom of the column, as the store's zoom of the page
    /// — what the handles, the zoom pill and every reach on the page read.
    private func columnZoom(_ scale: Double) -> Binding<Double> {
        Binding(get: { store.zoom / scale }, set: { store.zoom = $0 * scale })
    }

    /// The column fitted to another width, or about another widest page:
    /// the page's zoom follows the column's scale.
    private func rescaleZoom(from old: Double?, to new: Double?) {
        guard let old, let new, old > 0 else { return }
        store.zoom = store.zoom / old * new
    }

    /// A change of view asked of the page, asked of the column: a zoom of
    /// the page is the column's at its scale, a box on the page is where
    /// it lies in the column.
    private func canvasRequest(in slot: PageColumn.Slot?) -> CanvasRequest? {
        guard let slot, let request = store.canvasRequest else { return store.canvasRequest }
        switch request.kind {
        case .fit:
            return request
        case .zoom(let zoom):
            return CanvasRequest(kind: .zoom(zoom / slot.scale), serial: request.serial)
        case .reveal(let box, let covered, let typing):
            return CanvasRequest(kind: .reveal(slot.columnBox(box), covered: covered, typing: typing),
                                 serial: request.serial)
        case .page:
            return request
        }
    }

    /// The part of the canvas on screen, as the page being worked reads it,
    /// and in the column the pages near enough to draw live.
    private func viewportChanged(_ visible: CGRect, fit: Double) {
        var shown = visible
        var fitting = fit
        if let slot = columnSlot {
            seen.visible = visible
            seen.fit = fit
            let across = Double(visible.minX)...Double(max(visible.maxX, visible.minX))
            if seen.across != across { seen.across = across }
            shown = slot.pageBox(visible)
            fitting = fit * slot.scale
            let live = Set(PageColumn.livePages(columnSlots, visible: visible))
            if livePages != live { livePages = live }
        }
        // Only real changes: every write redraws whatever reads it.
        if store.viewport != shown { store.viewport = shown }
        if store.fitZoom != fitting { store.fitZoom = fitting }
    }

    /// The page worked changed, or moved in the column, under a view
    /// standing still — settled on, tapped on, picked elsewhere: what it
    /// reads of the view said again in its own units, for the selection's
    /// bubble, Bring it back and the zoom pill.
    private func republishViewport() {
        guard columnSlot != nil, seen.fit > 0 else { return }
        viewportChanged(seen.visible, fit: seen.fit)
    }

    /// Only a view a finger moved settles on a page: one moved to bring a
    /// page or a box into sight — which may leave another page across the
    /// middle — never starts moving, and leaves the page as it is.
    private func motionChanged(_ moving: Bool) {
        if store.canvasMoving != moving { store.canvasMoving = moving }
        if moving {
            seen.moved = true
        } else if seen.moved {
            seen.moved = false
            settle()
        }
    }

    /// The view come to rest in the column: the page covering its middle
    /// becomes the one worked, and the top bar's "Page n of m" says so.
    /// While crop, typing, the pen, the eraser or a preview has its page,
    /// the page stays, and the view is brought back to it.
    private func settle() {
        let slots = columnSlots
        guard !slots.isEmpty else { return }
        let index = PageColumn.currentPage(seen.visible, in: slots)
        guard index != store.pageIndex else { return }
        if pagePinned {
            revealPage()
        } else {
            pageFromColumn = index
            store.setPage(index)
        }
    }

    /// A page made current from elsewhere — the pages bar, Undo, a page
    /// added — is brought to where Fit puts it (PageColumn.fitTop), as on
    /// the Android twin, unless it is already the page across the middle of
    /// the view; one the column made current is in view.
    private func followPage(_ index: Int) {
        let fromColumn = pageFromColumn == index
        pageFromColumn = nil
        guard columnOn, !fromColumn else { return }
        let slots = columnSlots
        if seen.fit > 0, slots.indices.contains(index), PageColumn.currentPage(seen.visible, in: slots) == index {
            return
        }
        store.requestCanvas(.page)
    }

    /// The page being worked, its header too, brought into sight.
    private func revealPage() {
        guard let slot = columnSlot else { return }
        let shown = slot.rect.union(PageColumn.headerRect(slot, unit: columnPoint))
        store.requestCanvas(.reveal(slot.pageBox(shown)))
    }

    // MARK: touches

    /// A tap off the page being worked: on another page in the column, that
    /// page becomes the one worked and what was tapped on it is selected;
    /// anywhere else the selection goes — Select multiple keeps what it has
    /// built.
    private func backgroundTap(at point: CGPoint) {
        // What of the page worked hangs off it there is that page's, not
        // the column's (ZoomableCanvas.holdsPage).
        if let slot = columnSlot, holdsWorkedPage(at: slot.toPage(point)) { return }
        commitTextEditIfAny()
        let slots = columnSlots
        if let index = PageColumn.pageAt(point, in: slots), index != store.pageIndex, !pagePinned {
            let hit = otherPageElement(index, at: slots[index].toPage(point))
            pageFromColumn = index
            store.setPage(index)
            if let hit { store.select(hit.id) }
            return
        }
        if !store.selectingMultiple { store.select(nil) }
    }

    /// The page other than the one worked that `point` in the column is on,
    /// and the thing shown topmost there under it — none while something
    /// holds the view to its page.
    private func otherPageHit(at point: CGPoint) -> (page: Int, element: Element)? {
        let slots = columnSlots
        guard !pagePinned, let index = PageColumn.pageAt(point, in: slots), index != store.pageIndex else { return nil }
        guard let hit = otherPageElement(index, at: slots[index].toPage(point)) else { return nil }
        return (index, hit)
    }

    /// The topmost thing shown on page `index` of the column under `at`, in
    /// that page's units — each at least its touch target's size on screen,
    /// as on the page worked (elementHitArea) and on the Android twin.
    private func otherPageElement(_ index: Int, at: CGPoint) -> Element? {
        let slots = columnSlots
        guard store.design.pages.indices.contains(index), slots.indices.contains(index) else { return nil }
        // The page worked's zoom, in this page's units.
        let zoom = store.zoom / (columnSlot?.scale ?? 1) * slots[index].scale
        let target = Touch.pageUnits(Touch.minTarget, zoom: zoom)
        return store.design.pages[index].elements.last { el in
            !el.isHidden && Geometry.hits(Self.reach(el, target), point: at)
        }
    }

    /// A double tap on another page (ZoomableCanvas.onOtherPageDoubleTap):
    /// on a photo or words, that page becomes the one worked and the photo
    /// opens crop, or the words their typing — as the Android twin's first
    /// tap makes the page current and its second works what it landed on.
    /// What it takes is what a double tap on the page worked claims
    /// (claimsDoubleTap): a locked shape, or a cell whose words are locked,
    /// zooms. Anywhere else it is not taken, and the canvas zooms — where
    /// the page worked hangs over it, too, as its tap does (backgroundTap).
    private func otherPageDoubleTap(at point: CGPoint) -> Bool {
        if let slot = columnSlot, holdsWorkedPage(at: slot.toPage(point)) { return false }
        guard let found = otherPageHit(at: point) else { return false }
        let hit = found.element
        let typed = store.typedIn(hit, among: store.design.pages[found.page].elements)
        guard hit.type == .image || hit.type == .text || typed != nil else { return false }
        commitTextEditIfAny()
        pageFromColumn = found.page
        store.setPage(found.page)
        store.select(hit.id)
        // A table cell's words are found on the page now worked.
        if let target = store.typedIn(hit) {
            startTextEdit(target)
        } else if hit.type == .image {
            store.startCrop(hit.id)
        }
        return true
    }

    /// One finger dragged from something on another page (ZoomableCanvas's
    /// movesOtherPage), `start` and `now` in column units: that page becomes
    /// the one worked, where it is, and the thing moves as a drag on the
    /// page worked moves it — let go over yet another page, it goes there.
    private func otherPageDrag(_ phase: CanvasDrag, from start: CGPoint, to now: CGPoint) {
        if phase == .began {
            guard let found = otherPageHit(at: start) else { return }
            commitTextEditIfAny()
            pageFromColumn = found.page
            store.setPage(found.page)
            gesture.columnDrag = found.element.id
        }
        guard let id = gesture.columnDrag, let slot = columnSlot else { return }
        let from = slot.toPage(start), to = slot.toPage(now)
        if phase == .ended {
            moveEnded(from: from, to: to)
        } else if let el = store.element(id) {
            moveChanged(el, from: from, to: to)
        }
    }

    /// The headers and "+ Add page" keep their own touches — unless the
    /// page is held, when the headers only say which page is which.
    private func isColumnControl(_ point: CGPoint) -> Bool {
        let slots = columnSlots
        guard !slots.isEmpty, !pagePinned else { return false }
        let unit = columnPoint
        if PageColumn.addPageRect(slots, unit: unit)?.contains(point) == true { return true }
        return slots.contains { PageColumn.headerRect($0, unit: unit).contains(point) }
    }

    /// Delete from a header: asked first when the page has something on it,
    /// as in the pages bar.
    private func askDeletePage() {
        if store.page.elements.isEmpty {
            store.deletePage()
        } else {
            confirmingPageDelete = true
        }
    }

    // MARK: drawing the column

    /// Every page down the column, each under its header, with "+ Add page"
    /// after the last. Only the page being worked takes touches and shows
    /// the selection, guides, grid and margins; the others are drawn live
    /// near the view and as a thumbnail further off. It is drawn last, so a
    /// thing dragged off it stays over the page it is dragged across.
    private func columnContent(_ worked: PageColumn.Slot) -> some View {
        let slots = columnSlots
        return ZStack(alignment: .topLeading) {
            ForEach(slots.indices, id: \.self) { i in
                if i != store.pageIndex { otherPage(i, slot: slots[i]) }
                pageHeader(i, slot: slots[i])
            }
            if !pagePinned, let add = PageColumn.addPageRect(slots, unit: columnPoint) {
                onScreenSize(AddPageRow(store: store), in: add, height: PageColumn.addPageHeight)
            }
            if let drop = gesture.dropPage, slots.indices.contains(drop) {
                dropOutline(slots[drop])
            }
            workedPage(worked)
        }
        .frame(width: canvasWidth, height: PageColumn.columnHeight(slots, gap: PageColumn.room),
               alignment: .topLeading)
    }

    /// `content` laid out at its size on screen, `height` points tall, and
    /// scaled into `rect` of the column — the same size however far the
    /// column is zoomed — cut across to the part of the column on screen.
    private func onScreenSize(_ content: some View, in rect: CGRect, height: Double) -> some View {
        ColumnRow(seen: seen, rect: rect, height: height, unit: columnPoint, content: content)
    }

    /// The page being worked: the canvas's own page, in its page units,
    /// scaled into its place in the column.
    private func workedPage(_ slot: PageColumn.Slot) -> some View {
        pageContent
            .coordinateSpace(name: "page")
            .frame(width: store.pageWidth, height: store.pageHeight)
            .scaleEffect(slot.scale, anchor: .topLeading)
            .frame(width: slot.rect.width, height: slot.rect.height, alignment: .topLeading)
            .offset(x: slot.origin.x, y: slot.origin.y)
    }

    /// Another page: live near the view, a thumbnail further off, with
    /// nothing on it to touch — a tap there is the canvas's (backgroundTap).
    private func otherPage(_ index: Int, slot: PageColumn.Slot) -> some View {
        let page = store.design.pages[index]
        let r = slot.rect
        let point = columnPoint
        return Group {
            if livePages.contains(index) {
                PageRenderView(design: store.design, page: page)
                    // Its bleed too, and its trim dashed, as round the page
                    // being worked — only that page names it.
                    .background {
                        if bleed > 0 { BleedBand(design: store.design, page: page, bleed: bleed, unit: point / slot.scale) }
                    }
                    .overlay {
                        if bleed > 0 { TrimLine(size: store.design.size(for: page), unit: point / slot.scale) }
                    }
                    .environment(\.onScreen, true)
                    .scaleEffect(slot.scale, anchor: .topLeading)
                    .frame(width: r.width, height: r.height, alignment: .topLeading)
            } else {
                PageThumbnail(design: store.design, page: page)
                    .frame(width: r.width, height: r.height)
            }
        }
        .background(Rectangle().fill(Color.white).shadow(color: .black.opacity(0.16), radius: 12 * point, y: 3 * point))
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * point))
        .allowsHitTesting(false)
        .offset(x: r.minX, y: r.minY)
    }

    private func pageHeader(_ index: Int, slot: PageColumn.Slot) -> some View {
        let row = PageHeaderRow(store: store, index: index, pinned: pagePinned,
                                onDelete: { askDeletePage() },
                                onNotes: { editingPageNotes = true })
        return onScreenSize(row, in: PageColumn.headerRect(slot, unit: columnPoint), height: PageColumn.header)
    }

    /// The page a move would go to if let go now.
    private func dropOutline(_ slot: PageColumn.Slot) -> some View {
        let r = slot.rect
        return Rectangle()
            .stroke(Theme.accent, lineWidth: 3 * columnPoint)
            .frame(width: r.width, height: r.height)
            .offset(x: r.minX, y: r.minY)
            .allowsHitTesting(false)
    }
}

/// A header row or "+ Add page" in the column: laid out at its size on
/// screen, `height` points tall, scaled into `rect` of the column, and cut
/// across to the part of the column on screen (PageColumn.trimmed) — so,
/// zoomed in, its buttons stay in reach rather than a page's width away. A
/// view of its own, so only it redraws as the view pans across.
private struct ColumnRow<Content: View>: View {
    let seen: CanvasView.ColumnSeen
    let rect: CGRect
    let height: Double
    /// Column units to a point on screen.
    let unit: Double
    let content: Content

    var body: some View {
        if let r = PageColumn.trimmed(rect, to: seen.across, least: unit) {
            content
                .frame(width: r.width / unit, height: height)
                .scaleEffect(unit, anchor: .topLeading)
                .frame(width: r.width, height: r.height, alignment: .topLeading)
                .offset(x: r.minX, y: r.minY)
        }
    }
}
