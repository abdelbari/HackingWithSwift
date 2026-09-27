// Export sheet: the chooser. PNG / JPEG at 1-3x and multi-page PDF, all
// rendered from the same PageRenderView the canvas uses and handed to the
// system share sheet. The rendering and encoding themselves live in
// DesignExporter.

import SwiftUI
import UIKit

struct ExportSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 2.0
    @State private var longEdgeText = ""
    @State private var selectionOnly = false
    @State private var copied = false
    @State private var paper = PrintLayout.Options()
    @State private var pickingAudio = false
    @State private var audioRefused = false
    @State private var audioSeconds: Double?
    @State private var jpegQuality = 0.92
    @State private var transparent = false
    @State private var pageRange = RangeChoice.current
    @State private var sharedURLs: [URL] = []
    /// What the last save to Photos came to, and whether anything went in.
    @State private var photosNote: PhotosNote?
    @State private var photosFormat = DesignExporter.RasterFormat.png
    /// Said under Motion when a video's music could not be put in.
    @State private var musicNote: String?
    /// The volume while its slider is dragged; written to the design once,
    /// when the drag ends, so a drag is one Undo.
    @State private var dragVolume: Double?
    /// What the progress card says is happening.
    @State private var workingLabel = "Rendering"

    private struct PhotosNote: Equatable {
        var text: String
        var ok: Bool
    }

    private enum RangeChoice: String, CaseIterable, Identifiable {
        case current, all
        var id: String { rawValue }
        var label: String { self == .current ? "This page" : "All pages" }
        var exportRange: DesignExporter.PageRange { self == .current ? .current : .all }
    }
    /// Fraction done while an export runs; nil when idle. Rasters report a
    /// page at a time, the movie a frame at a time.
    @State private var progress: Double?
    @State private var exportTask: Task<Void, Never>?
    private var exporting: Bool { progress != nil }
    @State private var exportedURL: URL?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            // One computed property per section. As a single expression the
            // form was past what the type checker will resolve "in reasonable
            // time" — every string interpolation, ternary and `if` adds a
            // branch, and eight sections of them is too many.
            Form {
                qualitySection
                jpegSection
                if store.design.pages.count > 1 && !selectionOnly { pagesSection }
                transparencySection
                formatSection
                clipboardSection
                photosSection
                if UIPrintInteractionController.isPrintingAvailable { printSection }
                motionSection
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .navigationTitle("Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Closing stops an export under way: finished after the sheet
                // had gone, it would pop a share sheet or the print dialog
                // from nowhere, as on the Android twin.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { exportTask?.cancel(); dismiss() }
                }
            }
            .sheet(item: Binding(
                get: { exportedURL.map(ShareURL.init) },
                set: { if $0 == nil { exportedURL = nil; sharedURLs = [] } })) { item in
                // Every file at once when a range produced several: handing
                // them over one sheet at a time would mean nine dismissals for
                // a nine-page deck.
                ShareSheet(urls: sharedURLs.isEmpty ? [item.url] : sharedURLs)
            }
            .overlay {
                if let progress { progressCard(progress) }
            }
        }
        // While the progress card is up, Cancel or Close is the way out, not
        // a swipe; and however the sheet goes, the export goes with it.
        .interactiveDismissDisabled(exporting)
        .onDisappear { exportTask?.cancel() }
        .presentationDetents([.medium])
    }

    /// Determinate, with a way out. A spinner with no number is fine for a
    /// PNG; a nine-page 4K video takes long enough that not knowing whether
    /// it is a tenth done or nine tenths, and having no button to press, is
    /// the difference between waiting and force-quitting.
    private func progressCard(_ fraction: Double) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: fraction) {
                Text("\(workingLabel)… \(Int((fraction * 100).rounded()))%")
                    .font(.subheadline.weight(.semibold))
            }
            .progressViewStyle(.linear)
            Button("Cancel", role: .cancel) { exportTask?.cancel() }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
    }

    /// Progress from the movie writer's queue, delivered to the sheet's
    /// state on the main actor.
    private func report(_ fraction: Double) {
        Task { @MainActor in progress = min(1, max(0, fraction)) }
    }

    // MARK: sections

    private var qualitySection: some View {
        Section {
            Picker("Scale", selection: $scale) {
                Text("1×").tag(1.0)
                Text("2×").tag(2.0)
                Text("3×").tag(3.0)
            }
            .pickerStyle(.segmented)
            // A multiplier chosen is what applies; a long edge typed, while
            // it is there, wins.
            .onChange(of: scale) { longEdgeText = "" }
            // The size people are actually told to produce. Typing 1080 puts
            // every exported page's long side there, each at its own size.
            HStack {
                Text("Long edge")
                Spacer()
                TextField(longEdgePlaceholder, text: $longEdgeText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                    .onChange(of: longEdgeText) {
                        // Digits only, five at most, as the Android twin takes them.
                        let digits = String(longEdgeText.filter(\.isNumber).prefix(5))
                        if digits != longEdgeText { longEdgeText = digits }
                    }
                Text("px").foregroundStyle(.secondary)
                Menu {
                    ForEach(DesignExporter.sizePresets) { preset in
                        Button(preset.name) { longEdgeText = String(Int(preset.longEdge)) }
                    }
                } label: {
                    Image(systemName: "list.bullet").accessibilityLabel("Size presets")
                }
            }
            if !store.selection.isEmpty {
                Toggle("Selection only, cropped to its bounds", isOn: $selectionOnly)
            }
        } header: {
            Text("Size")
        } footer: {
            // "2×" means nothing on its own; the pixel count is the thing
            // people actually need to match a platform's requirements. It also
            // gives the size cap somewhere honest to appear rather than
            // silently under-delivering.
            VStack(alignment: .leading, spacing: 4) {
                Text(sizeNote)
                if let warning = resolutionWarning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// The long edge typed, when it is one: a number of at least 16 pixels.
    private var typedLongEdge: Double? {
        guard let px = Double(longEdgeText), px >= 16 else { return nil }
        return px
    }

    /// The scale page `index` of `design` is exported at: from the long edge
    /// typed, at that page's own size, or else the multiplier.
    private func pageScale(_ index: Int, in design: Design) -> Double {
        guard let px = typedLongEdge else { return scale }
        return DesignExporter.scale(forLongEdge: px, size: design.size(at: index))
    }

    /// The pages an export will write, of the design it renders.
    private var exportedIndices: [Int] {
        exportedRange.indices(in: exportedDesign, current: exportedPageIndex)
    }

    /// The page the size readout and warnings speak for: the one exported,
    /// or the first of several.
    private var shownIndex: Int { exportedIndices.first ?? 0 }

    private var longEdgePlaceholder: String {
        let design = exportedDesign
        let edge = DesignExporter.longEdge(size: design.size(at: shownIndex), requested: scale)
        return "\(Int(edge))"
    }

    /// A selection export is a one-page design, so it is always "this page"
    /// of that design.
    private var exportedRange: DesignExporter.PageRange {
        selectionOnly ? .current : pageRange.exportRange
    }

    private var exportedPageIndex: Int { selectionOnly ? 0 : store.pageIndex }

    /// The design that is actually rendered: the whole page, or the selection
    /// as a page of its own.
    private var exportedDesign: Design {
        if selectionOnly,
           let cropped = DesignExporter.selectionDesign(design: store.design, page: store.page,
                                                        ids: store.selection) {
            return cropped
        }
        return store.design
    }

    /// Soft output, said before the export rather than discovered in the
    /// post: a long edge too short for a phone screen, or a photo that will
    /// be stretched past the pixels it has.
    private var resolutionWarning: String? {
        let design = exportedDesign
        let shown = shownIndex
        let edge = DesignExporter.longEdge(size: design.size(at: shown), requested: pageScale(shown, in: design))
        if edge < DesignExporter.softBelowLongEdge {
            return "Only \(Int(edge)) px on the long side — will look soft on most screens."
        }
        // Every page that goes out, each at the scale it will render at —
        // not only the first page, which may not even be among them.
        var blurry = 0
        for index in exportedIndices {
            let effective = DesignExporter.effectiveScale(size: design.size(at: index),
                                                          requested: pageScale(index, in: design))
            blurry += DesignExporter.upscaledImages(page: design.pages[index], scale: effective,
                                                    pixelSize: { src in
                PhotoLibrary.resolve(src).map { CGSize(width: $0.size.width * $0.scale,
                                                        height: $0.size.height * $0.scale) }
            }).count
        }
        guard blurry > 0 else { return nil }
        return blurry == 1
            ? "One photo has fewer pixels than this size needs and will look blurry."
            : "\(blurry) photos have fewer pixels than this size needs and will look blurry."
    }

    private var jpegSection: some View {
        let percent = Int((jpegQuality * 100).rounded())
        return Section {
            Slider(value: $jpegQuality, in: 0.3...1)
        } header: {
            Text("JPEG quality")
        } footer: {
            let each = exportedIndices.count > 1 ? " a page" : ""
            Text("\(percent)% — about \(estimatedSize)\(each). PNG and PDF are lossless and ignore this.")
        }
    }

    private var pagesSection: some View {
        let note = pageRange == .all
            ? "One file per page, numbered — so each can be posted on its own."
            : "Page \(store.pageIndex + 1) only."
        return Section {
            Picker("Pages", selection: $pageRange) {
                ForEach(RangeChoice.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Pages")
        } footer: {
            Text(note)
        }
    }

    private var transparencySection: some View {
        Section {
            Toggle("Transparent background", isOn: $transparent)
        } footer: {
            Text("PNG only. Drops the page's own background rather than "
                 + "flattening it, so the export really has nothing behind it.")
        }
    }

    private var formatSection: some View {
        // Said from the page choice above, which the PDF follows.
        let pages = store.design.pages.count
        let pdfSubtitle = pages == 1
            ? "Print-ready document, vector"
            : (pageRange == .all ? "All \(pages) pages, vector" : "Page \(store.pageIndex + 1) only, vector")
        // PNG and JPEG write a file a page, so they follow it too.
        let count = exportedIndices.count
        let what = count > 1 ? "\(count) pages, one file each" : "Current page"
        let jpegSubtitle = "\(what), about \(estimatedSize)\(count > 1 ? " a page" : "")"
        return Section("Format") {
            exportButton("PNG", subtitle: "\(what), best for sharing", icon: "photo") {
                try await export(.png)
            }
            exportButton("JPEG", subtitle: jpegSubtitle, icon: "photo.fill") {
                try await export(.jpeg)
            }
            exportButton("PDF", subtitle: pdfSubtitle, icon: "doc.richtext", working: "Making the PDF") {
                try await exportPDF()
            }
            exportButton("SVG", subtitle: "Current page, editable vectors",
                         icon: "scribble.variable") {
                try exportSVG()
            }
        }
    }

    private var photosSection: some View {
        let kind = photosFormat == .png ? "PNG" : "JPEG"
        return Section {
            // The same two picture formats the share rows make: a JPEG for
            // a photo-heavy post, a PNG for flat colour or a clear
            // background. The quality above applies to the JPEG.
            Picker("Picture format", selection: $photosFormat) {
                Text("PNG").tag(DesignExporter.RasterFormat.png)
                Text("JPEG").tag(DesignExporter.RasterFormat.jpeg)
            }
            .pickerStyle(.segmented)
            exportButton("\(kind) to Photos", subtitle: photosSubtitle, icon: "photo.badge.plus",
                         working: "Saving to your photos") {
                try await saveToPhotos(photosFormat)
            }
            exportButton("Video to Photos", subtitle: movieSubtitle, icon: "film.stack",
                         working: "Rendering the video") {
                try await saveToPhotos(nil)
            }
        } header: {
            Text("Photos")
        } footer: {
            if let photosNote {
                Label(photosNote.text, systemImage: photosNote.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(photosNote.ok ? Color.green : Color.red)
            }
        }
    }

    private var photosSubtitle: String {
        let count = exportedIndices.count
        let each = count > 1 ? "\(count) pages, one photo each" : "Current page, straight into your library"
        return photosFormat == .jpeg ? "\(each), about \(estimatedSize)\(count > 1 ? " a page" : "")" : each
    }

    /// Render, then hand the files to Photos rather than the share sheet.
    /// `nil` means the movie. Each picture is counted as it goes in, and
    /// what went in is said even after a Cancel.
    @MainActor
    private func saveToPhotos(_ format: DesignExporter.RasterFormat?) async throws {
        photosNote = nil
        guard let format else {
            try await saveMovieToPhotos()
            return
        }
        let urls = try await DesignExporter.exportPages(
            design: exportedDesign, range: exportedRange, current: exportedPageIndex,
            format: format, scale: scale, longEdge: typedLongEdge ?? 0, quality: jpegQuality,
            // JPEG has no alpha channel to be transparent in.
            transparent: transparent && format == .png,
            progress: { progress = $0 })
        let outcome = try await PhotoSaver.save(urls)
        if let message = outcome.message {
            photosNote = PhotosNote(text: message, ok: outcome.anySaved)
            announce(message)
        }
    }

    /// The video into Photos. Music that would not go in leaves a silent
    /// video, and says so.
    @MainActor
    private func saveMovieToPhotos() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
        let movie = try await MovieExporter.exportMP4(design: store.design,
                                                      settings: MovieExporter.Settings(store.design.motion),
                                                      to: url, progress: report)
        let outcome = try await PhotoSaver.save([url])
        if outcome.cancelled && !outcome.anySaved { return }
        var text = outcome.anySaved ? "Saved the video to your photos." : "Couldn't save to your photos."
        if movie.musicLost { text += " " + Self.musicLostNote }
        photosNote = PhotosNote(text: text, ok: outcome.anySaved)
        announce(text)
    }

    /// Said when a video's music could not be mixed in, as the Android twin
    /// says it.
    static let musicLostNote = "Couldn't add the music, so it has none."

    /// VoiceOver hears the outcome of a save; the footer it lands in is
    /// easily missed from the button that was pressed.
    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    private var clipboardSection: some View {
        Section {
            exportButton("Canvia design file", subtitle: "The design and its photos, to send or back up",
                         icon: "shippingbox") {
                let url = DesignExporter.fileURL(for: store.design, ext: DesignPackage.ext)
                // Gathered here, where library photos are drawn; written out
                // away from the main actor, since turning every photo and
                // clip into base64 takes long enough, on a design with clips,
                // to freeze the sheet.
                let contents = DesignPackage.contents(of: store.design)
                try await Task.detached(priority: .userInitiated) {
                    try DesignPackage.encode(contents).write(to: url)
                }.value
                sharedURLs = [url]
                exportedURL = url
            }
            exportButton(copied ? "Copied" : "Copy as image",
                         subtitle: "PNG on the clipboard, for Messages, Mail or Notes",
                         icon: copied ? "checkmark.circle" : "doc.on.clipboard") {
                try copyToClipboard()
            }
        }
    }

    /// The page on screen — or the selection, cut to its bounds — as one
    /// image on the clipboard. It copied the first page whichever was open.
    @MainActor
    private func copyToClipboard() throws {
        let design = exportedDesign
        let index = min(max(exportedPageIndex, 0), design.pages.count - 1)
        guard let cg = DesignExporter.render(design: design, page: design.pages[index],
                                             scale: pageScale(index, in: design), transparent: transparent)
        else { throw DesignExporter.ExportError.renderFailed }
        UIPasteboard.general.image = UIImage(cgImage: cg)
        copied = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            copied = false
        }
    }

    private var printSection: some View {
        Section {
            exportButton("Send to a printer", subtitle: "AirPrint, on the paper layout below", icon: "printer",
                         working: "Preparing to print") {
                try await printDesign()
            }
            exportButton("Print-ready PDF", subtitle: "Paper, bleed and crop marks as set", icon: "doc.badge.gearshape",
                         working: "Making the print PDF") {
                let url = DesignExporter.fileURL(for: store.design, ext: "pdf", suffix: "-print")
                // The design the other formats render, so "Selection only"
                // prints the selection rather than page 1 of the whole thing.
                try await DesignExporter.exportPrintPDF(design: exportedDesign, range: exportedRange,
                                                        current: exportedPageIndex, options: paper, to: url,
                                                        progress: { progress = $0 })
                sharedURLs = [url]
                exportedURL = url
            }
            DisclosureGroup("Paper layout") { paperSettings }
        } header: {
            Text("Print")
        } footer: {
            Text(paperNote)
        }
    }

    private var paperNote: String {
        let pts = PrintLayout.pagePoints(design: exportedDesign, bleed: paper.bleed)
        switch paper.fit {
        case .fit: return "Fitted to \(paper.paper.name)\(paper.landscape ? " landscape" : "")."
        case .actual:
            let fits = pts.width <= paper.printable.width && pts.height <= paper.printable.height
            return fits ? "Prints at actual size, \(String(format: "%.0f × %.0f mm", pts.width / 2.835, pts.height / 2.835))."
                        : "Larger than the sheet at actual size — it will be clipped. Tile it instead."
        case .tile:
            let n = PrintLayout.tiles(page: pts, printable: paper.printable.size, overlap: paper.overlap).count
            return "\(n) sheets of \(paper.paper.name), overlapping by \(Int(paper.overlap)) pt to trim and join."
        }
    }

    private var paperSettings: some View {
        Group {
            Picker("Paper", selection: $paper.paper) {
                ForEach(PrintLayout.papers) { Text($0.name).tag($0) }
            }
            Toggle("Landscape", isOn: $paper.landscape)
            Picker("Placement", selection: $paper.fit) {
                ForEach(PrintLayout.Fit.allCases) { Text($0.name).tag($0) }
            }
            Stepper(value: $paper.bleed, in: 0...36, step: 3) { Text("Bleed \(String(format: "%.0f", paper.bleed / 2.835)) mm") }
            Toggle("Crop marks", isOn: $paper.cropMarks)
        }
    }

    private var motionSection: some View {
        Section {
            exportButton("MP4 video", subtitle: movieSubtitle, icon: "film", working: "Rendering the video") {
                try await exportMovie()
            }
            exportButton("Animated GIF", subtitle: movieSubtitle, icon: "square.stack.3d.down.right",
                         working: "Rendering the GIF") {
                try await exportGIF()
            }
            DisclosureGroup("Motion settings") { motionSettings }
        } header: {
            Text("Motion")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if let musicNote {
                    Label(musicNote, systemImage: "speaker.slash.fill")
                        .foregroundStyle(.orange)
                }
                Text(motionNote)
            }
        }
    }

    /// How it moves, as the Android twin says it: each page's hold (a page
    /// with a time of its own keeps it), the push in, the fade or cut, and
    /// whether the music under it is on this phone.
    private var motionNote: String {
        let m = store.design.motion ?? MotionSettings()
        let settings = MovieExporter.Settings(store.design.motion)
        var note = "Each page holds \(String(format: "%.1f", settings.secondsPerPage))s unless it has its own time"
        if m.movement { note += ", with a slow push in" }
        note += m.crossfade ? ", and fades into the next." : ", and cuts to the next."
        if m.soundtrack != nil {
            note += AudioStore.url(for: m.soundtrack) != nil
                ? " The video has music under it."
                : " The music was chosen on another phone and isn't on this one."
        }
        return note
    }

    /// Timing, frame rate and the two moves, saved with the design.
    private var motionSettings: some View {
        let binding = Binding<MotionSettings>(
            get: { store.design.motion ?? MotionSettings() },
            set: { next in
                store.apply { $0.motion = next == MotionSettings() ? nil : next }
            })
        return Group {
            Stepper(value: binding.secondsPerPage, in: MotionSettings.secondsRange, step: 0.5) {
                Text("Hold each page \(String(format: "%.1f", binding.wrappedValue.secondsPerPage))s")
            }
            Picker("Frame rate", selection: binding.fps) {
                ForEach(MotionSettings.fpsChoices, id: \.self) { Text("\($0) fps").tag($0) }
            }
            Toggle("Slow push in", isOn: binding.movement)
            Toggle("Cross-fade between pages", isOn: binding.crossfade)
            soundtrackRows(binding)
        }
    }

    /// A music file under the video: picked from Files, looped or trimmed
    /// to the video's length, faded out over the last second.
    @ViewBuilder
    private func soundtrackRows(_ binding: Binding<MotionSettings>) -> some View {
        let current = binding.wrappedValue.soundtrack
        // A design from the Android twin, or one sent over from another
        // phone, brings the soundtrack's id but not the file, and the video
        // is made without it. Shown as it is rather than as if it would play.
        let here: Bool = AudioStore.url(for: current) != nil
        HStack {
            Label(soundtrackLabel(current, here: here), systemImage: "music.note")
                .lineLimit(1)
            Spacer()
            if let audioSeconds, here {
                Text(String(format: "%.0fs", audioSeconds)).font(.caption).foregroundStyle(.secondary)
            }
            Button(here ? "Change…" : "Choose…") { pickingAudio = true }
                .font(.callout)
            if current != nil {
                // Only the design lets go of it. The file stays, because a
                // duplicate, a saved version or the undo step can still point
                // at it; the sweep at launch removes it once nothing does.
                Button(role: .destructive) {
                    binding.wrappedValue.soundtrack = nil
                    audioSeconds = nil
                } label: { Image(systemName: "xmark.circle") }
                .accessibilityLabel("Remove soundtrack")
            }
        }
        .fileImporter(isPresented: $pickingAudio, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // The one it replaces is left where it is, for the same reason
            // as a removal: something else may still play it.
            guard let id = AudioStore.store(url) else {
                audioRefused = true
                return
            }
            // Only music that plays becomes the soundtrack: a file with no
            // sound in it would make a silent video without a word. Music
            // that plays is kept among your uploads, to choose again.
            Task {
                guard let seconds = await AudioStore.duration(of: id), seconds > 0 else {
                    AudioStore.delete(id)
                    audioRefused = true
                    return
                }
                Uploads.record(id, kind: .audio)
                binding.wrappedValue.soundtrack = id
                audioSeconds = seconds
            }
        }
        .task(id: current) {
            if let id = current { audioSeconds = await AudioStore.duration(of: id) }
        }
        .alert("That file isn't music this phone can play", isPresented: $audioRefused) {
            Button("OK", role: .cancel) {}
        }
        if current != nil && !here {
            Text("This music was chosen on another phone. Choose it again here to hear it in the video.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        if here {
            volumeRow(binding)
        }
    }

    /// The soundtrack's volume. Held here while dragged and written once
    /// on release, so a drag is one Undo, not dozens; VoiceOver's swipes
    /// write a tenth at a time.
    private func volumeRow(_ binding: Binding<MotionSettings>) -> some View {
        let stored = binding.wrappedValue.soundVolume ?? 1
        let shown = dragVolume ?? stored
        let percent = "\(Int((shown * 100).rounded()))%"
        func write(_ v: Double) { binding.wrappedValue.soundVolume = v == 1 ? nil : v }
        return HStack {
            Text("Volume")
                .accessibilityHidden(true)
            Slider(value: Binding(get: { dragVolume ?? stored }, set: { dragVolume = $0 }),
                   in: 0...1,
                   onEditingChanged: { editing in
                       guard !editing, let v = dragVolume else { return }
                       dragVolume = nil
                       if v != stored { write(v) }
                   })
            .accessibilityLabel("Soundtrack volume")
            .accessibilityValue(percent)
            .accessibilityAdjustableAction { direction in
                let step = direction == .increment ? 0.1 : -0.1
                write(min(1, max(0, ((stored + step) * 10).rounded() / 10)))
            }
            Text(percent)
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    /// What the soundtrack row says: nothing chosen, the music's own name
    /// (or its kind), or that it was chosen on another phone and is not on
    /// this one.
    private func soundtrackLabel(_ id: String?, here: Bool) -> String {
        guard let id else { return "No soundtrack" }
        return here ? AudioStore.label(for: id) : "Music from another phone"
    }

    private func exportButton(_ title: String, subtitle: String, icon: String, working: String = "Rendering",
                              action: @escaping @MainActor () async throws -> Void) -> some View {
        Button {
            progress = 0
            workingLabel = working
            errorMessage = nil
            musicNote = nil
            // Render on the main actor after the progress card appears. Every
            // long path steps aside between pages or frames, so the bar moves
            // and Cancel can be tapped while it works.
            exportTask = Task { @MainActor in
                defer { progress = nil; exportTask = nil }
                do { try await action() }
                catch is CancellationError { /* asked for; nothing to report */ }
                catch { errorMessage = "Export failed: \(error.localizedDescription)" }
            }
        } label: {
            HStack {
                Image(systemName: icon).frame(width: 30)
                VStack(alignment: .leading) {
                    Text(title).fontWeight(.semibold)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .foregroundStyle(.primary)
        .disabled(exporting)
    }

    /// The pixel size of the page shown — each page is sized on its own, so
    /// a deck of mixed sizes says so.
    private var sizeNote: String {
        let design = exportedDesign
        let pageSize = design.size(at: shownIndex)
        let requested = pageScale(shownIndex, in: design)
        let size = DesignExporter.outputSize(size: pageSize, requested: requested)
        var note = "\(Int(size.width)) × \(Int(size.height)) px"
        if DesignExporter.isClamped(size: pageSize, requested: requested) {
            note += " — reduced from \(String(format: "%.1f", requested))× so the render fits in memory"
        }
        if exportedIndices.count > 1 && design.hasMixedPageSizes {
            note += " for this page; each page at its own size"
        }
        return note + "."
    }

    private var estimatedSize: String {
        let design = exportedDesign
        let bytes = DesignExporter.estimatedJPEGBytes(size: design.size(at: shownIndex),
                                                      requested: pageScale(shownIndex, in: design),
                                                      quality: jpegQuality)
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    @MainActor
    private func export(_ format: DesignExporter.RasterFormat) async throws {
        let urls = try await DesignExporter.exportPages(
            design: exportedDesign, range: exportedRange, current: exportedPageIndex,
            format: format, scale: scale, longEdge: typedLongEdge ?? 0, quality: jpegQuality,
            // JPEG has no alpha channel to be transparent in.
            transparent: transparent && format == .png,
            progress: { progress = $0 })
        sharedURLs = urls
        exportedURL = urls.first
    }

    /// The film's length from its timeline, so a page with a hold of its
    /// own counts at that hold.
    private var movieSubtitle: String {
        let pages = store.design.pages.count
        let settings = MovieExporter.Settings(store.design.motion)
        let seconds = MovieExporter.seconds(design: store.design, settings: settings)
        let length = String(format: "%.0f", max(1, seconds))
        return pages > 1 ? "All \(pages) pages, \(length)s" : "One page, \(length)s"
    }

    /// Printing goes through the same vector PDF the export does, so what
    /// comes out of the printer is the document rather than a picture of it —
    /// text stays text at the printer's own resolution.
    @MainActor
    private func printDesign() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "pdf")
        // What the other formats render: the selection as a page of its own
        // when "Selection only" is on. The range and index are that design's
        // — with the whole design they pointed at page 1, not the selection.
        let design = exportedDesign
        try await DesignExporter.exportPrintPDF(design: design, range: exportedRange, current: exportedPageIndex,
                                                options: paper, to: url, progress: { progress = $0 })

        let info = UIPrintInfo.printInfo()
        info.outputType = .general
        info.jobName = store.design.title.isEmpty ? "Canvia design" : store.design.title
        let size = design.size(at: exportedPageIndex)
        info.orientation = size.width > size.height ? .landscape : .portrait
        // Cancelled while the last sheet was drawn: no dialog from nowhere.
        try Task.checkCancellation()

        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = url
        // iPad refuses the sheet-less presentation and raises rather than
        // failing quietly, so it gets an anchor rect.
        if let anchor = Self.keyWindow, UIDevice.current.userInterfaceIdiom == .pad {
            controller.present(from: CGRect(x: anchor.bounds.midX, y: anchor.bounds.midY,
                                            width: 1, height: 1),
                               in: anchor, animated: true, completionHandler: nil)
        } else {
            controller.present(animated: true, completionHandler: nil)
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    @MainActor
    private func exportMovie() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "mp4")
        let movie = try await MovieExporter.exportMP4(design: store.design,
                                                      settings: MovieExporter.Settings(store.design.motion),
                                                      to: url, progress: report)
        // The picture is kept when the music will not go under it; the
        // sheet says so beside the share, as the Android twin toasts it.
        if movie.musicLost {
            musicNote = Self.musicLostNote
            announce(Self.musicLostNote)
        }
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportGIF() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "gif")
        try await MovieExporter.exportGIF(design: store.design, settings: MovieExporter.Settings(store.design.motion),
                                    to: url, progress: { progress = $0 })
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportSVG() throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "svg")
        try DesignExporter.exportSVG(design: exportedDesign,
                                     page: exportedDesign.pages[exportedPageIndex], to: url)
        sharedURLs = [url]
        exportedURL = url
    }

    @MainActor
    private func exportPDF() async throws {
        let url = DesignExporter.fileURL(for: store.design, ext: "pdf")
        try await DesignExporter.exportPDF(design: store.design, range: pageRange.exportRange,
                                           current: store.pageIndex, to: url, progress: { progress = $0 })
        sharedURLs = [url]
        exportedURL = url
    }
}

private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
