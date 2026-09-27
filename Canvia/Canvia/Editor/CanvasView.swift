// Interactive canvas: the page rendered in page-pixel coordinates, inside a
// scroll view that owns zoom and pan (see ZoomableCanvas), with a gesture
// layer for select/move and a selection overlay for handles. All gesture math
// runs in the "page" coordinate space so zoom never affects it.

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

    /// Inverse zoom: ornaments are drawn in page units but should
    /// stay a constant size on screen.
    private var iz: Double { 1 / max(store.zoom, 0.01) }

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
        /// What a finger in crop mode is working, from when it lands.
        var crop: CropTouch?
        /// A crop-mode pinch's magnification when last applied.
        var cropPinch = 1.0
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
        // Zoom and pan live in a UIScrollView rather than in SwiftUI gestures.
        // See ZoomableCanvas for why: a MagnifyGesture on this stack can never
        // outrank the per-element DragGestures inside it, which is what made
        // pinching impossible once elements covered the page.
        ZoomableCanvas(
            contentSize: CGSize(width: store.pageWidth, height: store.pageHeight),
            zoom: $store.zoom,
            fitToken: "\(store.design.id)-\(store.pageWidth)x\(store.pageHeight)",
            onBackgroundTap: {
                commitTextEditIfAny()
                store.select(nil)
            },
            onPencilTap: { store.toggleDrawing() },
            pinchZooms: store.cropping == nil,
            claimsDoubleTap: { point in claimsDoubleTap(at: point) },
            request: store.canvasRequest,
            onViewport: { visible, fit in
                // Only real changes: every write redraws whatever reads it.
                if store.viewport != visible { store.viewport = visible }
                if store.fitZoom != fit { store.fitZoom = fit }
            }
        ) {
            pageContent
                .coordinateSpace(name: "page")
                .frame(width: store.pageWidth, height: store.pageHeight)
        }
        .ignoresSafeArea(.keyboard)
        // Typing in place stays above the keyboard: when it starts, when the
        // keyboard arrives or changes, and as the box grows line by line.
        .onChange(of: typingBox) { _, _ in revealTyping() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { _ in
            revealTyping()
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
                // workspace — and a 42pt black halo at 3x.
                .shadow(color: .black.opacity(0.16), radius: 12 * iz, y: 3 * iz)

            // Deselect (and commit any inline text edit) on the page surface
            // itself: the workspace-background tap can't fire here because
            // the opaque page sits above it in the ZStack.
            PageRenderView(design: store.design, page: shownPage)
                .environment(\.animationTime, store.previewTime.map { ($0, store.pageHold) })
                // While Play runs, a clip shows the frames decoded so far
                // rather than holding up the canvas for each one.
                .environment(\.liveVideo, store.previewTime != nil)
                // Carries the document edge in dark mode, where a shadow on a
                // dark workspace is invisible.
                .overlay(Rectangle().stroke(Theme.hairline, lineWidth: 1 * iz))
                .contentShape(Rectangle())
                .onTapGesture {
                    commitTextEditIfAny()
                    store.select(nil)
                }
                // A one-finger drag from empty page draws a rubber band.
                // It starts on the page, so the workspace pan (which refuses
                // touches on the page) never competes with it.
                .gesture(marqueeGesture)

            Group {
                if store.snapping.showGrid { gridOverlay }
                if store.snapping.marginEnabled && store.snapping.showMargins { marginOverlay }
                ForEach(store.design.guides) { guide in guideLine(guide) }
            }

            if store.page.elements.isEmpty {
                emptyPageHint
            }

            // Hit layer: one transparent overlay per element for taps/drags,
            // announced in reading order rather than stacking order.
            let order = CanvasAccessibility.readingOrder(store.page.elements, pageHeight: store.pageHeight)
            ForEach(store.page.elements) { el in
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

            if let band = gesture.marquee { marqueeView(band) }

            if let id = store.editingTextId, let el = store.element(id) {
                inlineTextEditor(el)
            }

            // The modes that take the whole page's touches, over everything.
            Group {
                if let tool = store.drawing { drawingLayer(tool) }
                if store.erasing != nil { eraserLayer }
                if let crop = store.cropping, let photo = store.cropElement { cropLayer(photo, crop) }
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
    /// unnoticed. Neither is ever part of the design.
    private func moveFurniture(_ moved: CGRect) -> some View {
        let start = gesture.dragUnion
        let w = store.pageWidth, h = store.pageHeight
        let showGhost = gesture.ghost
        let edgeWidth = 2 * iz
        let dash: [CGFloat] = [6 * iz, 6 * iz]
        let ghostWidth = 1.4 * iz
        return Canvas { context, _ in
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

    // MARK: crop

    /// The page as the canvas draws it. In crop mode the photo being cropped
    /// is left out: the crop layer draws it over the dimmed page, whole. So
    /// is a text box being typed in, so its words show once, in the field.
    private var shownPage: Page {
        let hidden = [store.cropping?.id, store.editingTextId].compactMap { $0 }
        guard !hidden.isEmpty else { return store.page }
        var page = store.page
        page.elements.removeAll { hidden.contains($0.id) }
        return page
    }

    /// Whether a double tap here belongs to the page rather than to the
    /// canvas's zoom: anywhere in crop mode, and on a photo or a text box.
    private func claimsDoubleTap(at point: CGPoint) -> Bool {
        if store.cropping != nil { return true }
        guard let hit = store.page.elements.last(where: { Geometry.hits($0, point: point) }) else { return false }
        return hit.type == .image || hit.type == .text
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
        return ZStack {
            if let ui = PhotoLibrary.resolve(photo.src) {
                let shown = ImageFilterEngine.apply(ImageFilterPreset.from(photo.filter),
                                                    adjustments: photo.adjustments ?? .neutral,
                                                    duotone: photo.duotone, to: ui, cacheKey: photo.src ?? "")
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
            for handle in Handle.allCases {
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
        var best = Touch.pageUnits(22, zoom: store.zoom)
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

    private var marqueeGesture: some Gesture {
        DragGesture(minimumDistance: Touch.pageUnits(Touch.dragSlop, zoom: store.zoom),
                    coordinateSpace: .named("page"))
            .onChanged { value in
                if gesture.marquee == nil {
                    commitTextEditIfAny()
                    store.canvasTouchActive = true
                }
                let band = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y))
                gesture.marquee = band
                // Live: the selection follows the band as it grows, so you
                // see what you are about to get before you let go.
                store.select(within: band)
            }
            .onEnded { _ in
                gesture.marquee = nil
                store.canvasTouchActive = false
            }
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
    /// PageRenderView, so it is never in an export or a thumbnail.
    private var gridOverlay: some View {
        let spacing = store.snapping.grid
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

    /// A guide: a thin line across the page that can be dragged into place
    /// and removed with a long press. Its touch target is wide though the
    /// line is not.
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
                    .onEnded { _ in store.commit() }
            )
            .onLongPressGesture(minimumDuration: 0.5) { store.removeGuide(guide.id) }
            .position(x: guide.vertical ? guide.position : w / 2, y: guide.vertical ? h / 2 : guide.position)
            .accessibilityLabel(guide.vertical ? "Vertical guide at \(Int(guide.position))" : "Horizontal guide at \(Int(guide.position))")
            .accessibilityHint("Drag to move, press and hold to remove; or use the actions to move or remove it")
            .accessibilityActions { guideActions(guide) }
    }

    /// A guide moved a step or taken away without a drag, for VoiceOver and
    /// Switch Control — the Android twin's guide actions. Each is one step.
    @ViewBuilder
    private func guideActions(_ guide: Guide) -> some View {
        let step = CanvasAccessibility.nudge(for: store.design)
        Button(guide.vertical ? "Move left" : "Move up") { nudgeGuide(guide, by: -step) }
        Button(guide.vertical ? "Move right" : "Move down") { nudgeGuide(guide, by: step) }
        Button("Remove guide") { store.removeGuide(guide.id) }
    }

    private func nudgeGuide(_ guide: Guide, by step: Double) {
        store.moveGuideTransient(guide.id, to: guide.position + step)
        store.commit()
    }

    /// The safe area as a dashed inset. Like the grid, never exported.
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
                if el.type == .text && !el.locked {
                    startTextEdit(el)
                } else if el.type == .image {
                    // A photo double-tapped opens crop, where the picture is
                    // worked directly — or says why it cannot.
                    commitTextEditIfAny()
                    store.startCrop(el.id)
                }
            }
            .onTapGesture {
                commitTextEditIfAny()
                // A second tap on a member of the selected group takes just
                // that member; otherwise the tap takes the element's group.
                if !store.selectMember(el.id) { store.select(el.id) }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                store.select(el.id, additive: true)
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
        if !el.locked {
            Button("Move left") { nudge(el, dx: -step, dy: 0) }
            Button("Move right") { nudge(el, dx: step, dy: 0) }
            Button("Move up") { nudge(el, dx: 0, dy: -step) }
            Button("Move down") { nudge(el, dx: 0, dy: step) }
            Button("Duplicate") { store.select(el.id); store.duplicateSelected() }
            Button("Delete") { store.select(el.id); store.deleteSelected() }
        }
        Button("Bring forward") { store.select(el.id); store.reorderSelected(.forward) }
        Button("Send backward") { store.select(el.id); store.reorderSelected(.backward) }
        if el.type == .text && !el.locked {
            Button("Edit text") { startTextEdit(el) }
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
            .onChanged { value in
                guard !el.locked, store.editingTextId != el.id else { return }
                if !gesture.dragActive {
                    gesture.dragActive = true
                    store.canvasTouchActive = true
                    // Selected before the step opens: selecting ends any typing
                    // as its own step, which must not swallow this move's.
                    if !store.selection.contains(el.id) { store.select(el.id) }
                    store.beginGesture()
                    gesture.dragOriginals = Dictionary(
                        uniqueKeysWithValues: store.selectedElements
                            .filter { !$0.locked }
                            .map { ($0.id, CGPoint(x: $0.x, y: $0.y)) })
                    let lines = Geometry.taggedSnapLines(design: store.design, page: store.page,
                                                         excluding: Set(gesture.dragOriginals.keys),
                                                         settings: store.snapping)
                    gesture.snapTagsX = lines.x
                    gesture.snapTagsY = lines.y
                    gesture.snapX = lines.x.map(\.position)
                    gesture.snapY = lines.y.map(\.position)
                    gesture.dragUnion = Geometry.union(
                        store.selectedElements.filter { !$0.locked }.map(Geometry.aabb))
                    gesture.siblingBoxes = store.page.elements
                        .filter { gesture.dragOriginals[$0.id] == nil }
                        .map(Geometry.aabb)
                }
                var dx = value.location.x - value.startLocation.x
                var dy = value.location.y - value.startLocation.y
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
                let travel = hypot(value.translation.width, value.translation.height) * store.zoom
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
            .onEnded { value in
                // Crossing the threshold and landing back where you started is
                // a tap that wandered, not an edit: it must not enter history,
                // or undo fills up with steps that changed nothing.
                let moved = hypot(value.translation.width, value.translation.height) * store.zoom
                if gesture.dragActive && moved >= Touch.tapSlop {
                    store.commit()
                } else {
                    store.endGesture()
                }
                clearTransient()
            }
    }

    // MARK: resize / rotate (called from the overlay)

    private func handleDrag(_ handle: Handle, _ location: CGPoint) {
        if store.selection.count > 1 {
            groupHandleDrag(handle, location)
            return
        }
        guard let selected = store.singleSelection, !selected.locked else { return }
        if gesture.resizeOriginal?.id != selected.id || !gesture.dragActive {
            store.beginGesture()
            gesture.resizeOriginal = selected
            gesture.dragActive = true
            store.canvasTouchActive = true
            gesture.resizeImage = selected.type == .image && !handle.isCorner
                ? PhotoLibrary.resolve(selected.src)?.size : nil
        }
        guard let original = gesture.resizeOriginal else { return }
        if trimPhoto(original, handle: handle, to: location) { return }
        let proportional = original.type != .line && handle.isCorner
        let minSize = original.type == .text ? 12.0 : 8.0
        let next = Geometry.resize(original, handle: handle, to: location,
                                   proportional: proportional, minSize: minSize)
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
        let trimmed = Crop.trimmed(original, image: image, handle: handle, to: location, minSize: 8)
        store.updateSelectedTransient { el in
            if el.id == trimmed.id { el = trimmed }
        }
        store.badge = "\(Int(trimmed.w)) × \(Int(trimmed.h))"
        return true
    }

    /// Resize a multi-selection from a corner of its box: the box resizes
    /// exactly as a single element would, and every member is scaled to
    /// follow it.
    private func groupHandleDrag(_ handle: Handle, _ location: CGPoint) {
        if gesture.groupOriginals.isEmpty || !gesture.dragActive {
            let members = store.selectedElements.filter { !$0.locked }
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
            let members = store.selectedElements.filter { !$0.locked }
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
        guard let selected = store.singleSelection, !selected.locked else { return }
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
        // Any typing before is ended as its own step, and the step for this
        // typing opens after it. Only this box is selected, even inside a
        // group, as on the Android twin: its text controls show while it is
        // typed, and a group corner or Delete never works the whole group.
        store.endTextEdit()
        store.selection = [el.id]
        store.beginGesture()
        store.editingTextId = el.id
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
                               onToggle: { store.toggleText($0) })
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

    private func typeInline(_ id: String, _ words: String) {
        store.beginGesture()
        guard let i = store.design.pages[store.pageIndex].elements.firstIndex(where: { $0.id == id }),
              store.design.pages[store.pageIndex].elements[i].text != words else { return }
        store.design.pages[store.pageIndex].elements[i].text = words
        let h = FontLibrary.layoutHeight(for: store.design.pages[store.pageIndex].elements[i])
        store.design.pages[store.pageIndex].elements[i].h = h
    }
}
