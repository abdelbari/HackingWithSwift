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
    /// Opens the page background panel: the hold menu's Background, from
    /// VoiceOver's actions on the page.
    var onBackground: () -> Void = {}
    @State private var gesture = GestureState()
    /// The edge scroll for drags on the canvas (ZoomableCanvas).
    @State private var edges = EdgeScroller()
    /// Where the last finger landed on the page, for a hold, which says
    /// nothing of where it is: the menu a still hold on the empty page
    /// brings up, a hold on the selection's body (ZoomableCanvas.onPress).
    @State private var pagePress: CGPoint?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.displayScale) private var displayScale
    /// The empty page's hint grows with Larger Text, by this much: words
    /// about the canvas, not on it.
    @ScaledMetric(relativeTo: .subheadline) private var hintScale: Double = 1
    /// The stroke being drawn, in page units, while the pen is on.
    @State private var strokePoints: [CGPoint] = []
    /// Where the stroke under way began. A drag the canvas's two-finger pan
    /// cancels never ends, so a new touch — a new start — begins a stroke
    /// afresh rather than joining the one cut short with a straight jump.
    @State private var strokeStart: CGPoint?
    /// Shape assist: the shape the stroke under way snapped to as the
    /// finger rested at its end, where the finger came to rest, and the
    /// wait for it to rest long enough.
    @State private var snapped: ShapeAssist.Snap?
    @State private var restAt: CGPoint?
    @State private var restWait: Task<Void, Never>?
    /// Shape assist, from the Draw bar: on unless turned off.
    @AppStorage(ShapeAssist.key) private var shapeAssist = true
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
    /// Those of them drawn as a picture all the same: small on screen, or
    /// among many in view (PageColumn.drawMode).
    @State private var picturePages: Set<Int> = []
    /// The pages near enough for a thumbnail (PageColumn.thumbnailPages),
    /// and those of them in view, whose thumbnails are made first.
    @State private var thumbPages: Set<Int> = []
    @State private var pagesInView: Set<Int> = []
    /// The part of the column on screen, kept without redrawing the canvas
    /// on every frame of a scroll.
    @State private var seen = ColumnSeen()
    /// How long the finger was last down on an element, for telling a quick
    /// tap that types from one on its way to a hold.
    @State private var press = PressClock()
    /// A page header's Delete asking first, and its Notes.
    @State private var confirmingPageDelete = false
    @State private var editingPageNotes = false
    /// The bleed band's "Bleed" label, shown for its first few seconds.
    @State private var bleedLabel = false
    /// Rulers, from the More menu: off unless turned on (RulersView).
    @AppStorage(Guides.rulersKey) private var rulers = false
    /// Settings ▸ Editing's "Zoom in to type small text": on unless turned
    /// off (Viewport.typingZoom).
    @AppStorage(Viewport.typingZoomKey) private var typingZoomOn = true
    /// The view zoomed in on the words being typed, in page units, while it
    /// is; and the box last weighed for it, so it is weighed once a box.
    @State private var typingFocus: TypingFocus?
    @State private var typingWeighed: String?

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

    /// When the finger last landed on an element, and how long it stayed
    /// down once lifted: written and read by the gestures alone, so nothing
    /// is watched and nothing redraws as it changes.
    final class PressClock {
        var began: Date?
        /// Seconds from landing to lifting, once lifted.
        var held: Double?
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
        /// Their neighbours in rows and columns, worked out once: the
        /// siblings do not move while the drag lasts (Geometry.neighbours).
        var siblingRows: Geometry.Neighbours?
        var siblingColumns: Geometry.Neighbours?
        /// What a resize may match the size of, taken as the handle is
        /// grabbed: the other shown elements, while snapping to elements is
        /// on (Geometry.matchingSize).
        var sizeSiblings: [Element] = []
        /// The photo being moved, when it is one photo or clip that can go
        /// into a frame (PhotoFrames.canDrop).
        var framePhoto: String?
        /// The frame under the finger it would go into, lit up while it is.
        var frameTarget: String?
        var resizeOriginal: Element?
        /// The element a dragged line end has snapped to: let go there, the
        /// line is tied to it (LineRoutes).
        var endTarget: String?
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
        /// Whether a hold on a locked page has been refused, for the rest
        /// of its drag.
        var lockedHold = false
        /// The backdrop a hold has taken (CanvasGestures.isBackdrop): a drag
        /// from it draws the band rather than moving it.
        var backdropHold: String?
        /// Where a band held out from another page or the workspace began,
        /// in the page's units, and whether it is held to the page — one
        /// from the workspace (CanvasGestures.clampedBand).
        var bandStart: CGPoint?
        var bandClamped = false
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
        .confirmationDialog(guideMenu.map { guideTitle($0) } ?? tr("Guide"),
                            isPresented: Binding(get: { guideMenu != nil }, set: { if !$0 { guideMenu = nil } }),
                            titleVisibility: .visible, presenting: guideMenu) { guide in
            Button("Position…") { askPosition(guide) }
            Button("Remove guide", role: .destructive) { store.removeGuide(guide.id) }
            Button("Cancel", role: .cancel) {}
        }
        // Worded as Android's Position… dialog words it.
        .alert(positioningGuide?.vertical == false ? tr("Horizontal guide") : tr("Vertical guide"),
               isPresented: Binding(get: { positioningGuide != nil },
                                    set: { if !$0 { positioningGuide = nil } }),
               presenting: positioningGuide) { guide in
            // In the design's unit, as Position's numbers are.
            let unit = store.design.physicalUnit ?? "px"
            TextField(guide.vertical ? tr("From the left (%@)", unit) : tr("From the top (%@)", unit), text: $guidePositionText)
                .keyboardType(.decimalPad)
            Button("Move") {
                let limit = guide.vertical ? store.pageWidth : store.pageHeight
                if let position = Guides.typedPosition(guidePositionText, limit: limit,
                                                       unit: store.design.physicalUnit, dpi: store.design.effectiveDPI) {
                    store.setGuidePosition(guide.id, to: position)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { guide in
            Text(tr("From 0 to %@", Units.readout(guide.vertical ? store.pageWidth : store.pageHeight, store.design)
                    + (store.design.physicalUnit == nil ? " px" : Units.suffix(store.design))))
        }
        // Typing in place stays above the keyboard: when it starts, when the
        // keyboard arrives or changes, and as the box grows line by line.
        .onChange(of: typingBox) { _, _ in revealTyping() }
        .onChange(of: store.editingTextId) { _, id in typingChanged(id) }
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
            holdsOtherPage: { point in otherPageEmpty(at: point) },
            onOtherPageHold: { phase, start, now in otherPageHold(phase, from: start, to: now) },
            holdsWorkspace: { point in onWorkspace(point) },
            typingFocus: typingFocus.map { canvasTypingFocus($0, in: slot) },
            onViewport: { visible, fit in viewportChanged(visible, fit: fit) },
            onMotion: { moving in motionChanged(moving) },
            edgeScroller: edges,
            onPress: { point in pagePress = point }
        ) {
            // Left to right in any language (ReadingDirection): the page's
            // coordinates, the gestures' and the handles' never mirror.
            Group {
                if let slot {
                    columnContent(slot)
                } else {
                    pageContent
                        .coordinateSpace(name: "page")
                        .frame(width: store.pageWidth, height: store.pageHeight)
                }
            }
            .designDirection()
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

    /// The box being typed in, as it is now — none while a finger is
    /// working it, its move handle dragged, so the view follows the finger
    /// and the scroll at the screen's edge (edgeTrack) rather than pulling
    /// the box back over the keyboard; it is kept above the keyboard again
    /// as the finger lifts.
    private var typingBox: CGRect? {
        guard !store.canvasTouchActive else { return nil }
        return store.editingTextId.flatMap { store.element($0) }.map(Geometry.aabb)
    }

    private func revealTyping() {
        guard let box = typingBox else { return }
        // Small words zoom up to be read as typing opens in them; the
        // keyboard's reveal keeps them above it once it comes.
        if let focus = typingZoom(box) {
            typingFocus = focus
            return
        }
        store.requestCanvas(.reveal(box, typing: true))
    }

    /// The zoom typing in the box `box` asks for, weighed once as typing
    /// opens in it (Viewport.typingZoom): its words brought up to a size
    /// that reads, centred on the line the typing opened on — or none, when
    /// they read as they are, the setting is off, or crop, the pen or a
    /// preview has the page; typing never zooms out.
    private func typingZoom(_ box: CGRect) -> TypingFocus? {
        guard let id = store.editingTextId, typingWeighed != id else { return nil }
        typingWeighed = id
        guard typingZoomOn, store.cropping == nil, store.drawing == nil, store.erasing == nil,
              store.previewTime == nil, let el = store.element(id) else { return nil }
        let words = el.type == .shape ? ShapeText.textElement(for: el) : el
        let size = FontLibrary.effectiveFontSize(for: words)
        let screen = CGRect(x: 0, y: 0, width: store.viewport.width * store.zoom, height: store.viewport.height * store.zoom)
        let most = Geometry.zoomRange(fit: store.fitZoom).upperBound
        guard let zoom = Viewport.typingZoom(fontSize: size, box: box, viewport: screen, zoom: store.zoom,
                                             maxZoom: most) else { return nil }
        // The line the tap landed on, held within the box, else the last
        // line, where the caret opens (Viewport.typingLine).
        let y = Viewport.typingLine(box: box, fontSize: size, tapY: store.typingPoint.map { Double($0.y) })
        return TypingFocus(id: id, zoom: zoom, around: CGPoint(x: box.midX, y: y))
    }

    /// Typing opened in another box, or ended: ended, the view goes back
    /// to where it was before it zoomed in (ZoomableCanvas.returnFromTyping).
    private func typingChanged(_ id: String?) {
        guard id == nil else { return }
        typingWeighed = nil
        if typingFocus != nil { typingFocus = nil }
    }

    /// The typing zoom asked of the page, asked of the column: the column's
    /// zoom at the page's scale, its point where it lies in the column.
    private func canvasTypingFocus(_ focus: TypingFocus, in slot: PageColumn.Slot?) -> TypingFocus {
        guard let slot else { return focus }
        return TypingFocus(id: focus.id, zoom: focus.zoom / slot.scale, around: slot.toColumn(focus.around))
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
                // The hold menu's items, for VoiceOver, on the page itself.
                .accessibilityElement()
                .accessibilityLabel("Page")
                .accessibilityActions { pageActions }

            // Deselect (and commit any inline text edit) on the page surface
            // itself: the workspace-background tap can't fire here because
            // the opaque page sits above it in the ZStack.
            PageRenderView(design: store.design, page: shownPage)
                .environment(\.animationTime, store.previewTime.map { ($0, store.pageHold) })
                // A clip plays on in a player only while the clock runs,
                // never for a scrub.
                .environment(\.clipsPlay, store.previewRuns)
                // While Play runs, or a trim handle is dragged, a clip shows
                // the frames decoded so far rather than holding up the
                // canvas for each one.
                .environment(\.liveVideo, store.previewTime != nil || store.clipScrub != nil)
                // A photo's subject is found for focus off the main thread.
                .environment(\.onScreen, true)
                .environment(\.playsPictures, playAnimated)
                // A caption box at rest shows the cue at the playhead.
                .environment(\.captionTime, store.playheadInPage)
                // Carries the document edge in dark mode, where a shadow on a
                // dark workspace is invisible.
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * iz))
                .contentShape(Rectangle())
                .onTapGesture { emptyPageTap() }
                // Held still on the empty page, a drag draws a rubber band;
                // a drag from there straight away moves the view instead
                // (see pansFromPage and ZoomableCanvas). Let go without a
                // drag, the hold brings up the menu at the finger.
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
                // Its badges grow with Larger Text, as far as accessibility2.
                selectionOverlay.chromeTypeSize()
                endTargetOutline
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
                if let brush = store.brushing, let photo = store.brushElement { brushLayer(brush, photo) }
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

    /// The handles, the move handle and the selection's body, each drag
    /// carried on at the screen's edge (edgeTrack).
    private var selectionOverlay: SelectionOverlay {
        SelectionOverlay(store: store,
                         onHandleDrag: { handle, at in
                             handleDrag(handle, at)
                             edgeTrack(at) { handleDrag(handle, $0) }
                         },
                         onHandleEnd: { edges.stop(); store.commit(); clearTransient() },
                         onRotateDrag: { at in
                             rotateDrag(at)
                             edgeTrack(at) { rotateDrag($0) }
                         },
                         onRotateEnd: { edges.stop(); store.commit(); clearTransient(); store.tipEvent = .rotated },
                         onMoveDrag: { start, at in
                             selectionMoved(from: start, to: at)
                             edgeTrack(at) { selectionMoved(from: start, to: $0) }
                         },
                         onMoveEnd: { start, at in
                             edges.stop()
                             moveEnded(from: start, to: at)
                         },
                         onBodyTap: { at, count in bodyTap(at: at, count: count) },
                         onBodyHold: { if let at = pagePress { bodyHold(at: at) } },
                         onBodyPressing: pressed,
                         onEndDrag: { atStart, at in
                             endDrag(atStart, at)
                             edgeTrack(at) { endDrag(atStart, $0) }
                         },
                         onEndDragEnd: { atStart in endDragEnded(atStart) })
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
        // A clip's trim handle dragged shows its frame there; Hold to
        // compare shows the selected photo without its looks. Neither is
        // written.
        var page = Trimming.scrubbed(store.page, store.clipScrub)
        if store.comparing, let id = store.singleSelection?.id { page = PhotoEdits.comparing(page, id) }
        // Show original, held in a brush: the photo as it was before it.
        if let brush = store.brushing, brush.comparing,
           let i = page.elements.firstIndex(where: { $0.id == brush.id }) {
            page.elements[i] = ImageMasking.original(page.elements[i], retouching: brush.retouching)
        }
        let hidden = [store.cropping?.id, store.editingTextId].compactMap { $0 }
        guard !hidden.isEmpty else { return page }
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
    /// while a finger places the picture or pulls a bracket, as it does on
    /// the Android twin, and shows the rest of the time — as the bar's dial
    /// turns it, and as crop mode ends.
    private func cropLayer(_ photo: Element, _ crop: CropSession) -> some View {
        var level = photo
        if gesture.crop?.isWorking == true { level.straighten = nil }
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
        // The thirds under a finger, and while the bar's straighten dial is
        // held.
        let working = (gesture.crop?.isWorking ?? false) || store.cropDialHeld
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

    // MARK: brushes

    /// Painting a photo with a brush: the stroke under the finger, as wide
    /// as it paints, in red to erase, green to restore, and blue for a blur
    /// or pixelate (grey to take it off); each stroke lands on the photo as
    /// the finger lifts. Over the whole page, so a stroke never selects or
    /// moves what it crosses.
    private func brushLayer(_ brush: BrushSession, _ photo: Element) -> some View {
        let width = ObjectEraser.pageWidth(share: brush.size, element: photo, imageSize: brush.imageSize)
        return ZStack {
            Color.clear.contentShape(Rectangle())
            if !strokePoints.isEmpty {
                Path(Freehand.cgPath(strokePoints))
                    .stroke(Self.brushInk(brush).opacity(0.45),
                            style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
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
                    store.brushStroke(Freehand.thinned(strokePoints))
                    strokePoints = []
                    strokeStart = nil
                }
        )
        .accessibilityLabel("Brush")
        .accessibilityHint("Drag over the photo to paint, then tap Done")
        .onDisappear { strokePoints = []; strokeStart = nil }
    }

    /// The colour a brush's stroke shows in under the finger.
    private static func brushInk(_ brush: BrushSession) -> Color {
        switch (brush.retouching, brush.reverse) {
        case (false, false): return .red
        case (false, true): return .green
        case (true, false): return .blue
        case (true, true): return .gray
        }
    }

    // MARK: drawing

    /// Above everything while the pen is on, so a stroke never selects or
    /// moves what it crosses. The live line is the same smoothed curve the
    /// finished element will hold.
    private func drawingLayer(_ tool: Freehand.Tool) -> some View {
        ZStack {
            Color.clear.contentShape(Rectangle())
            if let snap = snapped, let shape = ShapeAssist.element(snap, tool: tool) {
                // The shape the stroke will become, as it will be drawn.
                ElementView(element: shape).allowsHitTesting(false)
            } else if !strokePoints.isEmpty {
                livePen(tool)
            }
        }
        .frame(width: store.pageWidth, height: store.pageHeight)
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .named("page"))
                .onChanged { value in drawn(to: value, tool: tool) }
                .onEnded { _ in
                    restWait?.cancel()
                    if let snap = snapped {
                        store.finishSnappedStroke(snap)
                    } else {
                        store.finishStroke(strokePoints)
                    }
                    endStroke()
                }
        )
        .accessibilityLabel("Drawing surface")
        .accessibilityHint("Drag to draw a stroke")
        // A stroke a two-finger pan cut short never ended; putting the pen
        // away takes its stub with it.
        .onDisappear { endStroke() }
    }

    /// The pen moved on to `value`'s point. A stroke snapped by shape
    /// assist stays snapped while the finger rests, and is a stroke again
    /// once it moves on; a pen with ink waits, each time the finger comes to
    /// rest, for it to rest long enough (awaitRest).
    private func drawn(to value: DragGesture.Value, tool: Freehand.Tool) {
        if strokePoints.isEmpty || strokeStart != value.startLocation {
            endStroke()
            strokeStart = value.startLocation
            strokePoints = [value.startLocation]
        }
        if snapped != nil {
            guard let rest = restAt, ShapeAssist.movedOn(from: rest, to: value.location, zoom: store.zoom) else { return }
            snapped = nil
        }
        strokePoints.append(value.location)
        if shapeAssist && tool.pen.hasInk { awaitRest(at: value.location) }
    }

    /// Shape assist: the finger come to rest at `point` — or still resting,
    /// within ShapeAssist.holdSlop of where it did — and, once it has rested
    /// for ShapeAssist.holdSeconds, the stroke read as a shape: shown as it
    /// will be drawn, with a tick.
    private func awaitRest(at point: CGPoint) {
        if let rest = restAt, !ShapeAssist.movedOn(from: rest, to: point, zoom: store.zoom) { return }
        restAt = point
        restWait?.cancel()
        restWait = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(ShapeAssist.holdSeconds * 1_000_000_000))
            guard !Task.isCancelled, snapped == nil, let snap = ShapeAssist.classify(strokePoints) else { return }
            snapped = snap
            store.buzz(.tick)
        }
    }

    /// The stroke under way let go of, snapped or not.
    private func endStroke() {
        restWait?.cancel()
        restWait = nil
        restAt = nil
        snapped = nil
        strokePoints = []
        strokeStart = nil
    }

    /// The stroke under the finger, as the finished one will be drawn: a
    /// highlighter see-through and multiplying, a glow with its halo, at
    /// the pen's transparency — or,
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
                .opacity(Freehand.strokeOpacity(tool))
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
                .font(.system(size: 34 * iz * hintScale, weight: .light))
            Text("Tap + to add text, photos,\nshapes and QR codes")
                .font(.system(size: 15 * iz * hintScale, weight: .medium))
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
                // No band, and no menu, on a locked page: the hold is said
                // once, with Unlock, as a tap there is.
                if gesture.lockedHold { return }
                if !gesture.banding && store.isPageLocked {
                    gesture.lockedHold = true
                    dismissHoldMenu()
                    store.refusesLockedPage()
                    return
                }
                if !gesture.banding {
                    gesture.banding = true
                    commitTextEditIfAny()
                    dismissHoldMenu()
                    store.canvasTouchActive = true
                    store.buzz(.tick)
                }
                guard let drag else { return }
                let start = drag.startLocation
                drawBand(from: start, to: drag.location, startedOn: nil)
                edgeTrack(drag.location) { drawBand(from: start, to: $0, startedOn: nil) }
            }
            .onEnded { _ in
                edges.stop()
                gesture.lockedHold = false
                // Let go without having drawn a band, the hold was a still
                // one: the menu at the finger (CanvasGestures).
                var drawn = 0.0
                if let band = gesture.marquee { drawn = Double(max(band.width, band.height)) * store.zoom }
                let held = gesture.banding
                gesture.marquee = nil
                gesture.banding = false
                store.canvasTouchActive = false
                if held, drawn < Touch.dragSlop, let at = pagePress,
                   CanvasGestures.action(.hold, on: .emptyPage) == .menu {
                    store.holdMenuAt = at
                }
            }
    }

    /// The rubber band from `start` to `location`, in page units. Live: the
    /// selection follows the band as it grows, so you see what you are
    /// about to get before you let go. A band smaller than a drag on screen
    /// leaves the selection be — it may yet be a still hold.
    /// One drawn from a backdrop leaves it out unless it catches nothing
    /// else (`startedOn`); one from the workspace is held to the page
    /// (`clamped`).
    private func drawBand(from start: CGPoint, to location: CGPoint, startedOn: String?, clamped: Bool = false) {
        let band = clamped ? CanvasGestures.clampedBand(from: start, to: location, page: store.pageSize)
            : CGRect(x: min(start.x, location.x), y: min(start.y, location.y),
                     width: abs(location.x - start.x), height: abs(location.y - start.y))
        gesture.marquee = band
        if max(band.width, band.height) * store.zoom >= Touch.dragSlop { store.select(within: band, startedOn: startedOn) }
    }

    /// A drag from the backdrop `id` a hold has taken: the band, from
    /// where the finger landed (CanvasGestures: a backdrop).
    private func backdropBand(_ id: String, from start: CGPoint, to location: CGPoint) {
        if !gesture.banding {
            gesture.banding = true
            dismissHoldMenu()
            store.canvasTouchActive = true
        }
        drawBand(from: start, to: location, startedOn: id)
        edgeTrack(location) { drawBand(from: start, to: $0, startedOn: id) }
    }

    /// The band from a backdrop let go.
    private func backdropBandEnded() {
        edges.stop()
        gesture.marquee = nil
        gesture.banding = false
        gesture.backdropHold = nil
        store.canvasTouchActive = false
    }

    /// Whether a hold at `point` in the content, off every page, may draw
    /// a band from the workspace: while nothing holds the view to its page.
    private func onWorkspace(_ point: CGPoint) -> Bool {
        guard !pagePinned else { return false }
        let slots = columnSlots
        return slots.isEmpty || PageColumn.pageAt(point, in: slots) == nil
    }

    /// While a finger drags something at `location` on the page, the view
    /// scrolls at the screen's edge (Viewport.edgeScroll) and `carry` is
    /// called with the point on the page then under the finger.
    private func edgeTrack(_ location: CGPoint, carry: @escaping (CGPoint) -> Void) {
        edges.covered = store.panelOpen ? 0.5 : 0
        let slot = columnSlot
        edges.track(slot?.toColumn(location) ?? location) { content in
            carry(slot?.toPage(content) ?? content)
        }
    }

    /// Whether one finger dragged from `point` on the page moves the view:
    /// only where there is nothing to work — no element (at its touch
    /// target's size), no handle of the selection, no guide — and never
    /// while the pen, the eraser or crop mode has the page's touches.
    private func pansFromPage(at point: CGPoint) -> Bool {
        guard store.drawing == nil, store.erasing == nil, store.cropping == nil, store.brushing == nil else { return false }
        let guideReach = Touch.pageUnits(12, zoom: store.zoom)
        let onGuide = store.design.guides.contains { guide in
            abs(Double(guide.vertical ? point.x : point.y) - guide.position) <= guideReach
        }
        return CanvasGestures.pansFromPage(onElement: holdsWorkedPage(at: point) || onGuide, held: 0)
    }

    /// The hold menu's items as VoiceOver's actions on the page, at the
    /// middle of the page.
    @ViewBuilder
    private var pageActions: some View {
        let centre = CGPoint(x: store.pageWidth / 2, y: store.pageHeight / 2)
        if voiceOver && store.canPasteAtFinger {
            Button(HoldMenu.HoldItem.paste.title) { chooseFromHoldMenu(.paste, at: centre) }
        }
        if voiceOver && store.hasPageOnClipboard {
            Button(HoldMenu.HoldItem.pastePage.title) { chooseFromHoldMenu(.pastePage, at: centre) }
        }
        Button(HoldMenu.HoldItem.selectAll.title) { chooseFromHoldMenu(.selectAll, at: centre) }
        Button(HoldMenu.HoldItem.addText.title) { chooseFromHoldMenu(.addText, at: centre) }
        Button(HoldMenu.HoldItem.background.title) { chooseFromHoldMenu(.background, at: centre) }
    }

    private func chooseFromHoldMenu(_ item: HoldMenu.HoldItem, at point: CGPoint) {
        HoldMenuPill.choose(item, at: point, store: store, openBackground: onBackground)
    }

    /// The hold menu put away: a tap anywhere else on the canvas, a drag,
    /// the view moving.
    private func dismissHoldMenu() {
        if store.holdMenuAt != nil { store.holdMenuAt = nil }
    }

    /// Whether `point` on the page being worked is on something of it to
    /// work: an element shown, at its touch target's size, or within reach
    /// of a handle of the selection, its move handle among them — the rest
    /// of the page round the selection still pans. Scrolling through pages,
    /// these keep their touches where they hang off the page, too
    /// (ZoomableCanvas.holdsPage).
    private func holdsWorkedPage(at point: CGPoint) -> Bool {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        // Only what is shown has a hit area: a hidden layer is empty page.
        let onElement = store.page.elements.contains { el in
            !el.isHidden && Self.touches(el, point, target)
        }
        return onElement || SelectionOverlay.handlesTake(point, store: store)
            || SelectionOverlay.lineEndsTake(point, store: store)
            || SelectionOverlay.moveHandleTakes(point, store: store)
            || SelectionOverlay.bodyTakes(point, store: store)
    }

    /// Whether a finger at `point` takes `el`, its touch target `target`
    /// across: an elbowed or curved line within half that of its route,
    /// anything else in its box grown to the target (reach) — as the
    /// Android twin's elementAt.
    private static func touches(_ el: Element, _ point: CGPoint, _ target: Double) -> Bool {
        if LineRoutes.keepsLevel(el) { return !el.isHidden && LineRoutes.near(el, point, reach: target / 2) }
        return Geometry.hits(reach(el, target), point: point)
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
                        let move: (CGPoint) -> Void = { at in
                            store.moveGuideTransient(guide.id, to: guide.vertical ? at.x : at.y)
                        }
                        move(value.location)
                        edgeTrack(value.location, carry: move)
                    }
                    .onEnded { value in
                        edges.stop()
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
        Button(guide.vertical ? tr("Move left") : tr("Move up")) { nudgeGuide(guide, by: -step) }
        Button(guide.vertical ? tr("Move right") : tr("Move down")) { nudgeGuide(guide, by: step) }
        Button("Position…") { askPosition(guide) }
        Button("Remove guide") { store.removeGuide(guide.id) }
    }

    /// "Vertical guide at 540".
    private func guideTitle(_ guide: Guide) -> String {
        let at = Guides.halfPixel(guide.position)
        let number = at == at.rounded() ? String(Int(at)) : String(at)
        return guide.vertical ? tr("Vertical guide at %@", number) : tr("Horizontal guide at %@", number)
    }

    /// Position…: the guide's place typed in, starting from where it is.
    private func askPosition(_ guide: Guide) {
        let at = guide.position
        // In the design's unit when it has a physical one.
        guidePositionText = store.design.physicalUnit != nil ? Units.readout(at, store.design)
            : at == at.rounded() ? String(Int(at)) : String(at)
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
                        .font(.footnote.weight(.bold).monospacedDigit())
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
        let zone = HitZone(el, target: Touch.pageUnits(Touch.minTarget, zoom: store.zoom))
        return Rectangle()
            .fill(Color.clear)
            .contentShape(zone.shape)
            .frame(width: zone.size.width, height: zone.size.height)
            .rotationEffect(.degrees(zone.rotation))
            .position(zone.center)
            .onTapGesture(count: 2, coordinateSpace: .named("page")) { elementDoubleTap(el, at: $0) }
            .onTapGesture(count: 1, coordinateSpace: .named("page")) { elementTap(el, at: $0) }
            .onLongPressGesture(minimumDuration: CanvasGestures.holdSeconds,
                                perform: { elementHold(el) }, onPressingChanged: pressed)
            .gesture(moveGesture(el))
            .accessibilityElement()
            .accessibilityLabel(CanvasAccessibility.label(for: el))
            .accessibilityValue(CanvasAccessibility.value(for: el, design: store.design))
            .accessibilityAddTraits(store.selection.contains(el.id) ? [.isButton, .isSelected] : .isButton)
            .accessibilityHint(el.type == .text ? tr("Double tap to select; double tap and hold to edit")
                               : el.type == .image ? tr("Double tap to select; Crop is in the actions")
                               : tr("Double tap to select"))
            .accessibilityActions { accessibilityActions(for: el) }
    }

    /// A tap on `el` at page point `point` — on its own hit area, or passed
    /// on from the selection's body over it. In paint mode it takes the
    /// copied style. On what is already the one thing selected it types in
    /// it, the caret where the finger was, as in Canva.
    private func elementTap(_ el: Element, at point: CGPoint) {
        dismissHoldMenu()
        if store.stylePainting {
            store.paintStyle(onto: el.id)
            return
        }
        if startsTyping(el), let target = store.typedIn(el) {
            startTextEdit(target, at: point)
            return
        }
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

    private func elementDoubleTap(_ el: Element, at point: CGPoint) {
        dismissHoldMenu()
        if store.stylePainting {
            store.paintStyle(onto: el.id)
            return
        }
        // Selecting several, taps are each their own, never a pair:
        // two quick ones put the element in and take it out again,
        // as on the Android twin, rather than typing or cropping.
        if store.selectingMultiple {
            store.tapInSelectMultiple(el.id)
            store.tapInSelectMultiple(el.id)
            return
        }
        // Letters full of a photo offer Adjust photo first, with Edit
        // text beside it (PhotoInLettersPrompts).
        if el.type == .text, el.textFill?.isPhoto == true, !el.locked {
            commitTextEditIfAny()
            store.select(el.id)
            store.photoAdjustOffer = el.id
            return
        }
        // A shape double-tapped is typed in, as a text box is; a
        // table cell's rectangle, its words — the word under the
        // finger chosen, as in Canva.
        if let target = store.typedIn(el) {
            startTextEdit(target, at: point, word: true)
        } else if el.type == .image {
            // A photo double-tapped opens crop, where the picture is
            // worked directly — or says why it cannot.
            commitTextEditIfAny()
            store.startCrop(el.id)
        }
    }

    private func elementHold(_ el: Element) {
        dismissHoldMenu()
        // A backdrop — locked, or covering the page — held is the empty
        // page's: the menu at the finger, and a drag on from there draws the
        // band (CanvasGestures). A locked page says so instead.
        if CanvasGestures.isBackdrop(el, page: store.pageSize, selection: store.selection) {
            guard !store.refusesLockedPage() else { return }
            commitTextEditIfAny()
            gesture.backdropHold = el.id
            store.buzz(.tick)
            if let at = pagePress, CanvasGestures.action(.hold, on: .backdrop) == .menu { store.holdMenuAt = at }
            return
        }
        store.select(el.id, additive: true)
        store.buzz(.tick)
    }

    /// A tap on the empty page: the selection goes — Select multiple keeps
    /// what it has built — and paint mode and the hold menu with it.
    private func emptyPageTap() {
        commitTextEditIfAny()
        dismissHoldMenu()
        if store.stylePainting { store.stylePainting = false }
        // A locked page's own tap says so, with Unlock.
        if store.refusesLockedPage() { return }
        if !store.selectingMultiple { store.select(nil) }
    }

    /// A tap or a double tap on the selection's body: what it would do on
    /// the topmost thing shown there, as though the selection were not over
    /// it — the thing on top is tapped as before — or, where there is
    /// nothing, on the empty page.
    private func bodyTap(at point: CGPoint, count: Int) {
        guard let hit = topmost(at: point) else {
            if count == 1 { emptyPageTap() }
            return
        }
        if count == 2 { elementDoubleTap(hit, at: point) } else { elementTap(hit, at: point) }
    }

    /// A hold on the selection's body: the selected thing under the finger
    /// — the uppermost of them, in its turned frame — goes out of the
    /// selection, with its group, as a hold on it does where it is on top;
    /// in the gap between several, nothing. As on the Android twin
    /// (Gestures: a hold on the body is TOGGLE). Taps still go to the
    /// topmost thing (bodyTap).
    private func bodyHold(at point: CGPoint) {
        let under = store.page.elements.last { store.selection.contains($0.id) && Geometry.hits($0, point: point) }
        if let under { elementHold(under) }
    }

    /// The topmost thing shown at `point`, at its touch target's size, as
    /// its hit area takes touches.
    private func topmost(at point: CGPoint) -> Element? {
        let target = Touch.pageUnits(Touch.minTarget, zoom: store.zoom)
        return store.page.elements.last { !$0.isHidden && Self.touches($0, point, target) }
    }

    /// A finger landing on an element or lifting from it: how long it was
    /// down, kept for the tap that may follow.
    private func pressed(_ pressing: Bool) {
        if pressing {
            press.began = Date()
            press.held = nil
            if gesture.backdropHold != nil { gesture.backdropHold = nil }
        } else {
            press.held = press.began.map { Date().timeIntervalSince($0) }
        }
    }

    /// Whether a tap on `el` types in it rather than selecting it
    /// (CanvasGestures.tapTypes): how long the finger was down is read once.
    private func startsTyping(_ el: Element) -> Bool {
        let held = press.held ?? 0
        press.held = nil
        guard store.editingTextId == nil else { return false }
        return CanvasGestures.tapTypes(onlySelected: store.selection == [el.id], typable: store.typedIn(el) != nil,
                                       selectingMultiple: store.selectingMultiple, held: held)
    }

    /// The edits that otherwise need a drag, as VoiceOver actions — moving,
    /// resizing and turning among them. Each acts on this element alone,
    /// selecting it first, and is one undo step.
    @ViewBuilder
    private func accessibilityActions(for el: Element) -> some View {
        let step = CanvasAccessibility.nudge(for: store.design)
        // The long press's own job: a selection built one element at a time,
        // to group, align or tidy. Offered on locked things too.
        Button(store.selection.contains(el.id) ? tr("Remove from selection") : tr("Add to selection")) {
            store.select(el.id, additive: true)
        }
        // A position lock keeps it where it is, as a whole lock does, but
        // it can still be copied.
        if !el.holdsPlace {
            Button("Move left") { nudge(el, dx: -step, dy: 0) }
            Button("Move right") { nudge(el, dx: step, dy: 0) }
            Button("Move up") { nudge(el, dx: 0, dy: -step) }
            Button("Move down") { nudge(el, dx: 0, dy: step) }
            // Each said after, where it is and how big, as its value is.
            Button("Make larger") { if store.resizeForScreenReader(el.id, larger: true) { sayPlacement(el.id) } }
            Button("Make smaller") { if store.resizeForScreenReader(el.id, larger: false) { sayPlacement(el.id) } }
            // An elbowed or curved line stays level.
            if !LineRoutes.keepsLevel(el) {
                Button("Turn clockwise") { if store.turnForScreenReader(el.id, clockwise: true) { sayPlacement(el.id) } }
                Button("Turn anticlockwise") { if store.turnForScreenReader(el.id, clockwise: false) { sayPlacement(el.id) } }
            }
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
            Button("Edit text") { startTextEdit(target, at: nil) }
        }
        if el.type == .image && !el.locked {
            Button("Crop") { store.startCrop(el.id) }
        }
        // A table's cell moves its row or column, as the Table panel's
        // arrows do — the cell alone selected first, not its whole table.
        if el.table != nil && !el.locked {
            Button("Move row up") { inCell(el) { store.moveTableRow(by: -1) } }
            Button("Move row down") { inCell(el) { store.moveTableRow(by: 1) } }
            Button("Move column left") { inCell(el) { store.moveTableColumn(by: -1) } }
            Button("Move column right") { inCell(el) { store.moveTableColumn(by: 1) } }
        }
    }

    /// `action` done with table cell `el` alone selected.
    private func inCell(_ el: Element, _ action: () -> Void) {
        store.endTextEdit()
        store.selection = [el.id]
        action()
    }

    /// Where `id` is and how big, said: its VoiceOver value, as a resize or
    /// a turn from the actions leaves it.
    private func sayPlacement(_ id: String) {
        guard let now = store.element(id) else { return }
        AccessibilityNotification.Announcement(CanvasAccessibility.value(for: now, design: store.design)).post()
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
            .onChanged { value in
                let start = value.startLocation
                // Held first on a backdrop, the drag draws the band.
                if gesture.backdropHold == el.id {
                    backdropBand(el.id, from: start, to: value.location)
                    return
                }
                moveChanged(el, from: start, to: value.location)
                edgeTrack(value.location) { moveChanged(el, from: start, to: $0) }
            }
            .onEnded { value in
                edges.stop()
                if gesture.backdropHold == el.id {
                    backdropBandEnded()
                    return
                }
                moveEnded(from: value.startLocation, to: value.location)
            }
    }

    /// The selection moved by a drag on its body or its move handle, as a
    /// drag on one of its elements moves it. A box being typed into moves
    /// too, by its move handle: the words so far are kept as their own step
    /// first, so the move is one Undo of its own.
    private func selectionMoved(from start: CGPoint, to location: CGPoint) {
        guard let el = store.selectedElements.first(where: { !$0.holdsPlace }) else { return }
        let typing = store.editingTextId == el.id
        if typing && !gesture.dragActive { store.commit() }
        moveChanged(el, from: start, to: location, typing: typing)
    }

    /// A move of `el`, and the rest of the selection with it, the finger
    /// gone from `start` to `location` in page units — by its own drag, or
    /// by a drag from another page of the column that made this page the
    /// one worked (otherPageDrag).
    private func moveChanged(_ el: Element, from start: CGPoint, to location: CGPoint, typing: Bool = false) {
        guard !el.holdsPlace, typing || store.editingTextId != el.id else { return }
        if !gesture.dragActive {
            gesture.dragActive = true
            store.canvasTouchActive = true
            dismissHoldMenu()
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
            gesture.siblingRows = Geometry.neighbours(gesture.siblingBoxes, alongX: true)
            gesture.siblingColumns = Geometry.neighbours(gesture.siblingBoxes, alongX: false)
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
                let spacing = evenSpacing(gesture.dragUnion.offsetBy(dx: dx, dy: dy),
                                          freeX: snap.guideX == nil || sourceX == .grid,
                                          freeY: snap.guideY == nil || sourceY == .grid)
                gapX = spacing.gapX
                gapY = spacing.gapY
                dx += spacing.dx
                dy += spacing.dy
            }
            let spaced = gapX != nil || gapY != nil
            if store.spacingSnapped != spaced { store.spacingSnapped = spaced }
            // Every gap now equal, bracketed with its width.
            var marks: [Geometry.GapPair] = []
            if gapX != nil || gapY != nil {
                let landed = gesture.dragUnion.offsetBy(dx: dx, dy: dy)
                if gapX != nil {
                    marks += Geometry.equalGapPairs(landed, siblings: gesture.siblingBoxes, alongX: true,
                                                    near: gesture.siblingRows)
                }
                if gapY != nil {
                    marks += Geometry.equalGapPairs(landed, siblings: gesture.siblingBoxes, alongX: false,
                                                    near: gesture.siblingColumns)
                }
            }
            if store.gapMarks != marks { store.gapMarks = marks }
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
                                         gapX: gapX, gapY: gapY, in: store.design))
        }
    }

    /// Equal spacing for the moving box `moved`, on an axis no line is
    /// holding (`freeX`, `freeY`; a grid line gives way): between two
    /// neighbours, the same distance from each (Geometry.equalGap) — else a
    /// gap to a neighbour matching one already there, a third card added to
    /// a row at the gap the first two have (Geometry.matchingGap). The shift
    /// and the gap made equal on each axis.
    private func evenSpacing(_ moved: CGRect, freeX: Bool, freeY: Bool) -> Geometry.EqualGap {
        let reach = 6 / store.zoom
        let even = Geometry.equalGap(moving: moved, siblings: gesture.siblingBoxes, threshold: reach)
        let match = Geometry.matchingGap(moving: moved, siblings: gesture.siblingBoxes, threshold: reach,
                                         nearX: gesture.siblingRows, nearY: gesture.siblingColumns)
        var out = Geometry.EqualGap()
        if freeX, let gap = even.gapX {
            out.gapX = gap
            out.dx = even.dx
        } else if freeX, let gap = match.gapX {
            out.gapX = gap
            out.dx = match.dx
        }
        if freeY, let gap = even.gapY {
            out.gapY = gap
            out.dy = even.dy
        } else if freeY, let gap = match.gapY {
            out.gapY = gap
            out.dy = match.dy
        }
        return out
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
    /// it is another one — and not locked, which nothing goes onto.
    private func dropPage(at point: CGPoint) -> Int? {
        guard let slot = columnSlot,
              let index = PageColumn.pageAt(slot.toColumn(point), in: columnSlots),
              index != store.pageIndex, store.design.pages.indices.contains(index),
              !PageLocks.isLocked(store.design.pages[index]) else { return nil }
        return index
    }

    // MARK: a line's ends (called from the overlay)

    /// A selected line's start (or, not `atStart`, its end) dragged to
    /// `location`, the other end holding still: snapped to another
    /// element's edge midpoints and centre, else its angle to 15 degrees
    /// (LineRoutes.endDragged), with its length and angle read out. The
    /// whole drag is one step.
    private func endDrag(_ atStart: Bool, _ location: CGPoint) {
        guard let selected = store.singleSelection, selected.type == .line, !selected.holdsPlace else { return }
        if gesture.resizeOriginal?.id != selected.id || !gesture.dragActive {
            store.beginGesture()
            gesture.resizeOriginal = selected
            gesture.dragActive = true
            store.canvasTouchActive = true
        }
        guard let original = gesture.resizeOriginal else { return }
        let others = store.page.elements.filter { !$0.isHidden }
        let drag = LineRoutes.endDragged(original, atStart: atStart, pointer: location, others: others,
                                         reach: Touch.pageUnits(Touch.handleReach, zoom: store.zoom))
        if drag.target != nil && drag.target != gesture.endTarget { store.buzz(.tick) }
        gesture.endTarget = drag.target
        store.updateSelectedTransient { el in
            if el.id == drag.line.id { el = drag.line }
        }
        store.badge = LineRoutes.readout(drag, design: store.design)
    }

    /// The end let go: on an element's edge or centre it is tied to that
    /// element, in the same step as the drag; elsewhere it is free.
    private func endDragEnded(_ atStart: Bool) {
        if gesture.resizeOriginal != nil {
            let target = gesture.endTarget
            store.updateSelectedTransient { el in
                if el.type == .line { el = LineRoutes.tied(el, atStart: atStart, to: target) }
            }
            if target != nil { store.buzz(.confirm) }
        }
        edges.stop()
        store.commit()
        clearTransient()
    }

    /// What a dragged line end would be tied to, let go: outlined as a
    /// photo's frame is when a photo would go into it.
    @ViewBuilder
    private var endTargetOutline: some View {
        if let id = gesture.endTarget, let target = store.element(id) {
            Self.outline(target)
                .stroke(Theme.accent, lineWidth: 3 * iz)
                .frame(width: store.pageWidth, height: store.pageHeight)
                .allowsHitTesting(false)
        }
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
            gesture.sizeSiblings = store.snapping.toElements
                ? store.page.elements.filter { $0.id != selected.id && !$0.isHidden } : []
        }
        guard let original = gesture.resizeOriginal else { return }
        if trimPhoto(original, handle: handle, to: location) { return }
        let proportional = original.type != .line && handle.isCorner
        let minSize = original.type == .text ? 12.0 : 8.0
        let lined = snapped(Geometry.resize(original, handle: handle, to: location,
                                            proportional: proportional, minSize: minSize),
                            original: original, handle: handle, proportional: proportional, minSize: minSize)
        let next = matchedSize(lined, original: original, handle: handle, proportional: proportional, minSize: minSize)
        store.updateSelectedTransient { el in
            el.x = next.minX
            el.w = next.width
            switch el.type {
            case .text:
                el.y = next.minY
                if handle.isCorner {
                    // The type scales with the box, and its tracking with it,
                    // so a spaced-out headline keeps its proportions — the
                    // size to one decimal place, as it is typed, but free
                    // to pass 800 as the box does.
                    let scale = next.width / original.w
                    el.fontSize = max(6, TypeReadouts.tenth((original.fontSize ?? 42) * scale))
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
                : Units.readout(width: el.w, height: el.h, store.design)
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
        var at = location
        var trimmed = Crop.trimmed(original, image: image, handle: handle, to: at, minSize: 8)
        // The side snaps as any side does: the finger is taken on by the
        // snap's correction and the frame trimmed again, so the picture still
        // stays put. Held short of the line by the picture's own edge, it is
        // not on the line, and no guide says it is.
        let target = snapped(trimmed.frame, original: original, handle: handle, proportional: false, minSize: 8)
        if target != trimmed.frame {
            at = aimed(at, from: trimmed, to: target, handle: handle)
            trimmed = Crop.trimmed(original, image: image, handle: handle, to: at, minSize: 8)
            if !Self.same(trimmed.frame, target) { showGuides(Geometry.ResizeSnap(box: target)) }
        }
        // Then a side no line holds matched to another element's size, as
        // any side is (matchedSize), and trimmed to it the same way. Held
        // short of it by the picture's own edge, it is not matched, and no
        // "=" says it is.
        let sized = matchedSize(trimmed.frame, original: original, handle: handle, proportional: false, minSize: 8)
        if sized != trimmed.frame {
            let retrimmed = Crop.trimmed(original, image: image, handle: handle,
                                         to: aimed(at, from: trimmed, to: sized, handle: handle), minSize: 8)
            if Self.same(retrimmed.frame, sized) {
                trimmed = retrimmed
            } else {
                if !store.sizeMarks.isEmpty { store.sizeMarks = [] }
                if store.spacingSnapped { store.spacingSnapped = false }
            }
        }
        store.updateSelectedTransient { el in
            if el.id == trimmed.id { el = trimmed }
        }
        store.badge = Units.readout(width: trimmed.w, height: trimmed.h, store.design)
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

    /// A resized box `box` with the sides `handle` moves that no snap line
    /// holds matched to another element's width or height within a move's
    /// reach (Geometry.matchingSize) — the edges across from them staying
    /// put, a corner keeping its proportions matching one side — and every
    /// box of that size marked "=" (store.sizeMarks), felt as a snap is.
    /// Only on an element square to the page, as the snap lines are, and
    /// not a line (Geometry.matchesSizes); the box as it was when nothing
    /// came within reach.
    private func matchedSize(_ box: CGRect, original: Element, handle: Handle,
                             proportional: Bool, minSize: Double) -> CGRect {
        var marks: [Geometry.SizeMark] = []
        defer {
            if store.sizeMarks != marks { store.sizeMarks = marks }
            let spaced = !marks.isEmpty
            if store.spacingSnapped != spaced { store.spacingSnapped = spaced }
        }
        guard !gesture.sizeSiblings.isEmpty, Geometry.matchesSizes(original),
              !(proportional && (store.guideX != nil || store.guideY != nil)) else { return box }
        // A side a line holds stays on it.
        let sideX = store.guideX == nil ? handle.unit.x : 0.5
        let sideY = store.guideY == nil ? handle.unit.y : 0.5
        guard let side = Handle.allCases.first(where: { $0.unit == CGPoint(x: sideX, y: sideY) }) else { return box }
        let m = Geometry.matchingSize(box, handle: side, siblings: gesture.sizeSiblings,
                                      threshold: 6 / store.zoom, proportional: proportional)
        guard !m.widthOf.isEmpty || !m.heightOf.isEmpty, m.w >= minSize, m.h >= minSize else { return box }
        // The edges across from the handle stay put.
        let u = handle.unit, w = CGFloat(m.w), h = CGFloat(m.h)
        let x: CGFloat = u.x == 0 ? box.maxX - w : (u.x == 1 ? box.minX : box.midX - w / 2)
        let y: CGFloat = u.y == 0 ? box.maxY - h : (u.y == 1 ? box.minY : box.midY - h / 2)
        let out = CGRect(x: x, y: y, width: w, height: h)
        let boxes = Dictionary(gesture.sizeSiblings.map { ($0.id, Geometry.aabb($0)) }, uniquingKeysWith: { first, _ in first })
        if !m.widthOf.isEmpty { marks.append(Geometry.SizeMark(box: out, width: true)) }
        if !m.heightOf.isEmpty { marks.append(Geometry.SizeMark(box: out, width: false)) }
        marks += m.widthOf.compactMap { boxes[$0].map { Geometry.SizeMark(box: $0, width: true) } }
        marks += m.heightOf.compactMap { boxes[$0].map { Geometry.SizeMark(box: $0, width: false) } }
        return out
    }

    /// The finger's point `location` taken on as far as `el`'s `handle` must
    /// move for its box to be `target`, on the page, so a photo turned a
    /// quarter is taken on along the way it now faces.
    private func aimed(_ location: CGPoint, from el: Element, to target: CGRect, handle: Handle) -> CGPoint {
        var moved = el
        moved.x = target.minX
        moved.y = target.minY
        moved.w = target.width
        moved.h = target.height
        let to = Geometry.handlePoint(moved, handle), from = Geometry.handlePoint(el, handle)
        return CGPoint(x: location.x + to.x - from.x, y: location.y + to.y - from.y)
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
        store.badge = Units.readout(width: box.width, height: box.height, store.design)
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
        edges.stop()
        gesture = GestureState()
        store.guideX = nil
        store.guideY = nil
        store.guideXSource = nil
        store.guideYSource = nil
        store.badge = nil
        store.badgeRuns = nil
        store.rotationSnapped = false
        store.spacingSnapped = false
        if !store.gapMarks.isEmpty { store.gapMarks = [] }
        if !store.sizeMarks.isEmpty { store.sizeMarks = [] }
        store.canvasTouchActive = false
    }

    // MARK: inline text editing

    /// Typing in `el`, the caret where a tap at page point `point` puts
    /// it — the word there chosen with `word` — or at the end.
    private func startTextEdit(_ el: Element, at point: CGPoint?, word: Bool = false) {
        store.startTyping(el.id, at: point, word: word)
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
                               onStyled: { store.styleWhileTyping($0) },
                               onWordColour: { store.chooseWordColour(id, range: $0) },
                               onWordScale: { store.scaleWords(id, range: $0, by: $1) },
                               onWordFont: { store.chooseWordFont(id, range: $0) },
                               onWordLink: { store.chooseWordLink(id, range: $0) },
                               onToggle: { toggle in store.styleWhileTyping { store.toggleText(toggle) } },
                               onAlign: { align in store.styleWhileTyping { alignTyped(align) } },
                               onLines: { store.changeLines(id, covering: $0, $1) },
                               onNextCell: nextCell(el),
                               typing: typingHooks)
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
                               onStyled: { store.styleWhileTyping($0) },
                               onToggle: { toggle in store.styleWhileTyping { store.toggleText(toggle) } },
                               onAlign: { align in store.styleWhileTyping { alignTyped(align) } },
                               wordStyles: false,
                               typing: typingHooks)
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

    /// Tab, and the typing bar's arrow, in a table's cell: typing goes on in
    /// the next cell (DesignStore.typeInNextCell) — once the key or the tap
    /// is done with, as this field goes and the next cell's opens. Nil for
    /// words that are no cell's.
    private func nextCell(_ el: Element) -> ((Bool) -> Void)? {
        guard el.table != nil else { return nil }
        return { back in
            DispatchQueue.main.async { _ = store.typeInNextCell(back: back) }
        }
    }

    private func typeInline(_ id: String, _ words: String) {
        store.typeWords(words, into: id)
    }

    /// ⇧⌘L, C, R or J while typing: the box typed in aligned, as the Align
    /// button aligns it.
    private func alignTyped(_ align: String) {
        store.updateSelected { e in
            guard ShapeText.carriesWords(e) else { return }
            e.align = align
        }
    }

    /// The typing field's caret, its bursts and their Undo, kept by the
    /// store: Undo while typing takes back a burst and the typing stays open.
    private var typingHooks: InlineTextField.Typing {
        var hooks = InlineTextField.Typing()
        hooks.selection = { store.typingSelection = $0 }
        hooks.step = { store.closeTypingStep() }
        hooks.undo = { store.undo() }
        hooks.redo = { store.redo() }
        hooks.canUndo = { store.canUndo }
        hooks.canRedo = { store.canRedo }
        hooks.asked = store.typingSelectionAsked
        return hooks
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
            || store.erasing != nil || store.brushing != nil || store.previewTime != nil
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
            let slots = columnSlots
            let live = Set(PageColumn.livePages(slots, visible: visible))
            if livePages != live { livePages = live }
            let thumbs = Set(PageColumn.thumbnailPages(slots, visible: visible))
            if thumbPages != thumbs { thumbPages = thumbs }
            let inView = Set(PageColumn.pages(slots, within: 0, of: visible))
            if pagesInView != inView { pagesInView = inView }
            let pictures = picturedPages(live, slots: slots, visible: visible, inView: inView.count)
            if picturePages != pictures { picturePages = pictures }
        }
        // Only real changes: every write redraws whatever reads it.
        if store.viewport != shown { store.viewport = shown }
        if store.fitZoom != fitting { store.fitZoom = fitting }
    }

    /// Which of the `live` pages are drawn as pictures all the same. A page
    /// and the view are both measured in column units, whose share of each
    /// other is the same as on screen.
    private func picturedPages(_ live: Set<Int>, slots: [PageColumn.Slot], visible: CGRect, inView: Int) -> Set<Int> {
        live.filter { i in
            slots.indices.contains(i)
                && PageColumn.drawMode(pageIndex: i, workedIndex: store.pageIndex,
                                       pageScreenWidth: Double(slots[i].rect.width),
                                       viewportWidth: Double(visible.width), inViewCount: inView) == .picture
        }
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
            dismissHoldMenu()
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
        dismissHoldMenu()
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
    /// built. Painting a style, what was tapped on the other page takes it,
    /// and a tap on nothing there or on the workspace puts the roller down,
    /// as on the Android twin, where the page under the finger is the one
    /// worked as it lands.
    private func backgroundTap(at point: CGPoint) {
        // What of the page worked hangs off it there is that page's, not
        // the column's (ZoomableCanvas.holdsPage).
        if let slot = columnSlot, holdsWorkedPage(at: slot.toPage(point)) { return }
        commitTextEditIfAny()
        dismissHoldMenu()
        let slots = columnSlots
        if let index = PageColumn.pageAt(point, in: slots), index != store.pageIndex, !pagePinned {
            let hit = otherPageElement(index, at: slots[index].toPage(point))
            pageFromColumn = index
            // The page first: the style is pasted onto the page worked.
            store.setPage(index)
            if store.stylePainting {
                if let hit { store.paintStyle(onto: hit.id) } else { store.stylePainting = false }
            } else if let hit {
                store.select(hit.id)
            }
            return
        }
        if store.stylePainting { store.stylePainting = false }
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
            !el.isHidden && Self.touches(el, at, target)
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
        // Painting a style, a double tap pastes it, as two taps would,
        // rather than typing or cropping.
        if store.stylePainting {
            pageFromColumn = found.page
            store.setPage(found.page)
            store.paintStyle(onto: hit.id)
            return true
        }
        let typed = store.typedIn(hit, among: store.design.pages[found.page].elements)
        guard hit.type == .image || hit.type == .text || typed != nil else { return false }
        commitTextEditIfAny()
        pageFromColumn = found.page
        store.setPage(found.page)
        store.select(hit.id)
        // A table cell's words are found on the page now worked.
        if let target = store.typedIn(hit) {
            startTextEdit(target, at: nil)
        } else if hit.type == .image {
            store.startCrop(hit.id)
        }
        return true
    }

    /// Whether `point` in the column is on the empty part of a page other
    /// than the one worked — nothing shown there — while the view is free
    /// to change page.
    private func otherPageEmpty(at point: CGPoint) -> Bool {
        let slots = columnSlots
        guard !pagePinned, let index = PageColumn.pageAt(point, in: slots), index != store.pageIndex else { return false }
        return otherPageElement(index, at: slots[index].toPage(point)) == nil
    }

    /// A hold on the empty part of another page (ZoomableCanvas's
    /// onOtherPageHold), `start` and `now` in column units: as it is felt,
    /// that page becomes the one worked, with the hold's tick, as the
    /// Android twin's page under the finger is; dragged on, it draws the
    /// band there, and let go without one, the menu at the finger comes up,
    /// as a hold on the page worked does (marqueeGesture). `now` is nil when
    /// the hold was taken away — a second finger — which opens no menu. A
    /// hold on the workspace comes here too, on a page alone as in the
    /// column: its band is held to the page nearest (workspaceHoldBegan).
    private func otherPageHold(_ phase: CanvasDrag, from start: CGPoint, to now: CGPoint?) {
        switch phase {
        case .began:
            otherPageHoldBegan(at: start)
        case .moved:
            guard gesture.banding, let from = gesture.bandStart, let now else { return }
            let clamped = gesture.bandClamped
            let to = columnSlot?.toPage(now) ?? now
            drawBand(from: from, to: to, startedOn: nil, clamped: clamped)
            edgeTrack(to) { drawBand(from: from, to: $0, startedOn: nil, clamped: clamped) }
        case .ended:
            guard gesture.banding, let at = gesture.bandStart else { return }
            edges.stop()
            var drawn = 0.0
            if let band = gesture.marquee { drawn = Double(max(band.width, band.height)) * store.zoom }
            let target: CanvasGestures.Target = gesture.bandClamped ? .workspace : .emptyPage
            gesture.marquee = nil
            gesture.banding = false
            gesture.bandStart = nil
            gesture.bandClamped = false
            store.canvasTouchActive = false
            guard now != nil, drawn < Touch.dragSlop else { return }
            guard !holdsWorkedPage(at: at), CanvasGestures.action(.hold, on: target) == .menu else { return }
            store.holdMenuAt = at
        }
    }

    /// The hold on another page taking, `point` in column units: that page
    /// is made the one worked and the band is held out from there. Off
    /// every page, it is the workspace's.
    private func otherPageHoldBegan(at point: CGPoint) {
        let slots = columnSlots
        guard !pagePinned, let index = PageColumn.pageAt(point, in: slots), index != store.pageIndex else {
            workspaceHoldBegan(at: point)
            return
        }
        commitTextEditIfAny()
        dismissHoldMenu()
        pageFromColumn = index
        store.setPage(index)
        holdBand(from: columnSlot?.toPage(point) ?? point, clamped: false)
    }

    /// A hold on the workspace taking, `point` in the content's units: the
    /// band is drawn on the page it is over — in the column, the page under
    /// where it began, else the nearest (PageColumn.currentPage), made the
    /// one worked — held to that page, from the point on it nearest the
    /// finger (CanvasGestures.clampedBand). A locked page says so instead.
    private func workspaceHoldBegan(at point: CGPoint) {
        guard onWorkspace(point) else { return }
        let slots = columnSlots
        if !slots.isEmpty {
            let index = PageColumn.pageAt(point, in: slots) ?? PageColumn.currentPage(CGRect(origin: point, size: .zero), in: slots)
            if index != store.pageIndex {
                pageFromColumn = index
                store.setPage(index)
            }
        }
        commitTextEditIfAny()
        dismissHoldMenu()
        guard !store.refusesLockedPage() else { return }
        let onPage = CanvasGestures.onPage(columnSlot?.toPage(point) ?? point, page: store.pageSize)
        holdBand(from: onPage, clamped: true)
    }

    /// The band held out from `start` on the page worked, as a hold there
    /// is felt.
    private func holdBand(from start: CGPoint, clamped: Bool) {
        gesture.bandStart = start
        gesture.bandClamped = clamped
        gesture.banding = true
        store.canvasTouchActive = true
        store.buzz(.tick)
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
            edges.stop()
            moveEnded(from: from, to: to)
        } else if let el = store.element(id) {
            moveChanged(el, from: from, to: to)
            // Carried on at the screen's edge, in the column's units.
            edges.covered = store.panelOpen ? 0.5 : 0
            edges.track(now) { otherPageDrag(.moved, from: start, to: $0) }
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
        if store.page.elements.isEmpty && !store.isPageLocked {
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

    /// Another page: live near the view, a thumbnail further off, a white
    /// page further still, with nothing on it to touch — a tap there is the canvas's (backgroundTap).
    /// Near the view but small on screen, or among many in view, it is a
    /// picture too (PageColumn.drawMode), until a tap makes it the page
    /// worked — drawn live until there is a picture of it, as the Android
    /// twin draws it meanwhile, never white for a frame.
    private func otherPage(_ index: Int, slot: PageColumn.Slot) -> some View {
        let page = store.design.pages[index]
        let r = slot.rect
        let point = columnPoint
        // A picture as wide as its bucket of the page's width on screen.
        let pixels = PageColumn.pictureWidth(screenPixels: Double(r.width) / point * Double(displayScale))
        return Group {
            if livePages.contains(index) && !picturePages.contains(index) {
                livePage(page, slot: slot)
            } else if thumbPages.contains(index) {
                // Those in view are drawn first (ThumbnailCache), each made
                // again in its turn there when its page changes, the last
                // one shown meanwhile.
                PageThumbnail(design: store.design, page: page, pixelWidth: pixels,
                              priority: pagesInView.contains(index) ? 0 : 1,
                              fallback: livePages.contains(index) ? AnyView(livePage(page, slot: slot)) : nil)
                    .frame(width: r.width, height: r.height)
            } else {
                Color.white
                    .frame(width: r.width, height: r.height)
            }
        }
        .background(Rectangle().fill(Color.white).shadow(color: .black.opacity(0.16), radius: 12 * point, y: 3 * point))
        .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * point))
        .allowsHitTesting(false)
        .offset(x: r.minX, y: r.minY)
    }

    /// Another page drawn live, scaled into its place in the column.
    private func livePage(_ page: Page, slot: PageColumn.Slot) -> some View {
        let r = slot.rect
        let point = columnPoint
        return PageRenderView(design: store.design, page: page)
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

/// Where a finger takes an element on the canvas: its box grown about its
/// centre to the touch target, or, for an elbowed or curved line, a band a
/// target wide along its route, so a curve is taken where it bows and an
/// elbow leaves what is in its box to be touched — as touches (above) and
/// the Android twin's elementAt find them.
private struct HitZone {
    var size: CGSize
    var center: CGPoint
    var rotation: Double
    var shape: AnyShape

    init(_ el: Element, target: Double) {
        guard LineRoutes.keepsLevel(el) else {
            size = CGSize(width: max(el.w, target), height: max(el.h, target))
            center = CGPoint(x: el.x + el.w / 2, y: el.y + el.h / 2)
            rotation = el.rotation
            shape = AnyShape(Rectangle())
            return
        }
        let box = LineRoutes.outlineOf(el)
        let originX = box.x - target / 2, originY = box.y - target / 2
        let points = LineRoutes.polyline(el).map { local -> CGPoint in
            let page = LineRoutes.toPage(el, local)
            return CGPoint(x: Double(page.x) - originX, y: Double(page.y) - originY)
        }
        size = CGSize(width: box.w + target, height: box.h + target)
        center = CGPoint(x: box.x + box.w / 2, y: box.y + box.h / 2)
        rotation = 0
        shape = AnyShape(RouteBand(points: points, width: target))
    }
}

/// A line's route, `points` in the zone's own frame, stroked `width` wide.
private struct RouteBand: Shape {
    var points: [CGPoint]
    var width: Double

    func path(in rect: CGRect) -> Path {
        var route = Path()
        route.addLines(points)
        return route.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
    }
}
