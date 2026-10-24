// Export sheet: the chooser. A Share row of one-tap buttons — share now,
// save to Photos, copy as image, print — over a File type picker that opens
// on the type suggested from the design (ExportSuggestion), with only that
// type's options under it: PNG / JPEG at 1-3x, multi-page PDF, print-ready
// PDF, SVG, a PowerPoint deck, video and GIF, all rendered from the same
// views the canvas uses and handed to the system share sheet. The rendering
// and encoding themselves live in DesignExporter and PptxExporter; each
// button hands the app's ExportQueue a job made from a snapshot of the
// design (ExportJobs), so an export carries on once the sheet is closed.

import SwiftUI
import UIKit

struct ExportSheet: View {
    @Bindable var store: DesignStore
    /// Opened from Home, on the design as saved: nothing here changes it,
    /// so its motion settings and music are shown but not offered.
    var readOnly = false
    /// A Doc, whose pages `store` holds laid out (DocPages): its Word
    /// document is made from its blocks. Nil for every other design.
    var doc: Design? = nil
    /// The Doc's own store, opened in its editor: where Plan a post keeps
    /// the post, which `store`'s laid-out pages would not.
    var docStore: DesignStore? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var scale = 2.0
    @State private var longEdgeText = ""
    @State private var selectionOnly = false
    @State private var copied = false
    @State private var paper = PrintLayout.Options()
    @State private var pickingAudio = false
    @State private var audioRefused = false
    @State private var jpegQuality = 0.92
    @State private var transparent = false
    /// All pages to start with, the first of the row as in Canva: the
    /// video and GIF follow the choice now, and play the whole design
    /// unless asked otherwise.
    @State private var pageRange = RangeChoice.all
    /// The pages ticked in Choose…, by id — this design's, for the session.
    @State private var chosenIds: [String] = []
    @State private var choosingPages = false
    /// The video's size: 720p, 1080p or, where the encoder takes it, 4K.
    @State private var resolution = MovieExporter.Resolution.standard
    /// The captions as an .srt beside a shared video, for players that
    /// show their own; they are drawn into the video regardless.
    @State private var captionsSrt = false
    /// PDFs drawn as one 300-dpi picture a page.
    @State private var flatten = false
    /// The PDF's notes pages, and its photos at 150 dpi.
    @State private var pdfNotes = false
    /// The PowerPoint's "Styled text": editable, or the exact look.
    @State private var pptxStyledText = ExportLast.styledEditable
    @State private var pdfCompress = false
    /// "Remember these settings": the last export, as JSON; empty is off.
    @AppStorage(ExportLast.key) private var exportLast = ""
    /// Settings' default export format: the plain picture suggested.
    @AppStorage(AppDefaults.exportFormatKey) private var defaultFormat = "png"
    @State private var remember = false
    /// The file type the Share row makes, and the one read from the design
    /// (ExportSuggestion) that the picker badges Suggested.
    @State private var fileType = "png"
    @State private var suggested = "png"
    /// The PDF's outline: a bookmark for each page, by its title.
    @State private var pdfBookmarks = true
    /// A tagged PDF for screen readers: on unless a remembered export said
    /// otherwise, and never for a flattened one.
    @State private var pdfTagged = true
    /// The web page's menu, narrow-screen wrapping and clips
    /// (HTMLExporter.Settings).
    @State private var htmlNav = true
    @State private var htmlStack = true
    @State private var htmlMedia = true
    /// The web page as Preview shows it, and as Save to Files moves it.
    @State private var previewURL: URL?
    @State private var movingURL: URL?
    /// While Preview or Save to device makes the page.
    @State private var makingHTML = false
    @State private var sharedURLs: [URL] = []
    /// What the last save to Photos came to, and whether anything went in.
    @State private var photosNote: PhotosNote?
    /// Said under Motion when a video's music could not be put in.
    @State private var musicNote: String?
    /// Each track's music's length in seconds, by AudioStore id, read as
    /// Motion's track rows show.
    @State private var trackLengths: [String: Double] = [:]
    /// Each photo the PDF holds, its pixels by source, read from the file
    /// headers off the main thread for the PDF's size note.
    @State private var pdfPixelSizes: [String: CGSize] = [:]
    /// Close asked with an export running: keep it going, or stop it.
    @State private var askingKeep = false
    /// Save as one ZIP, and the PNG's Compress file (ExportPlan).
    @State private var zip = false
    @State private var pngCompress = false
    /// Said beside the share: a PNG that went out uncompressed.
    @State private var exportNote: String?
    /// What Check accessibility finds in the design as it stands, read off
    /// the main thread as the sheet opens; nil until it is.
    @State private var a11yFindings: [AccessibilityAudit.Finding]?
    /// The revision the accessibility row was put away at, from the
    /// design's meta.json.
    @State private var a11yDismissed: Int64?
    @State private var reviewingA11y = false
    @State private var a11yAnnounced = false
    /// Settings' "Remind me to check accessibility".
    @AppStorage(ExportPlan.a11yNudgeKey) private var remindA11y = true
    /// The last audit, by design and revision, so opening the sheet again
    /// on an unchanged design reads nothing again.
    @MainActor private static var a11yKept: (id: String, revision: Int64, findings: [AccessibilityAudit.Finding])?

    private struct PhotosNote: Equatable {
        var text: String
        var ok: Bool
    }

    /// "All pages (N)" | "Current page" | "Choose…"; the raw values are
    /// what "Remember these settings" writes.
    private enum RangeChoice: String, CaseIterable, Identifiable {
        case all, current, chosen
        var id: String { rawValue }
    }

    private func label(_ choice: RangeChoice) -> String {
        switch choice {
        case .all: return tr("All pages (%d)", store.design.pages.count)
        case .current: return tr("Current page")
        case .chosen: return tr("Choose…")
        }
    }

    /// The page choice as the exporter takes it. A one-page design has no
    /// choice to show, and is that page, as before.
    private var pageExportRange: DesignExporter.PageRange {
        let picked: DesignExporter.PageRange
        switch pageRange {
        case .all: picked = .all
        case .current: picked = .current
        case .chosen: picked = .chosen(chosenIds)
        }
        return ExportChoices.exportRange(picked, in: store.design)
    }

    /// Choosing "Choose…" opens the pages to tick; set from a remembered
    /// setting it does not.
    private var rangeBinding: Binding<RangeChoice> {
        Binding(get: { pageRange }, set: { next in
            pageRange = next
            if next == .chosen { choosingPages = true }
        })
    }
    /// The app's exports: the one running, those waiting, and what is done.
    private var queue: ExportQueue { ExportQueue.shared }
    @State private var exportedURL: URL?
    @State private var errorMessage: String?
    /// Mockups, over the sheet.
    @State private var showingMockups = false
    /// Plan a post…, over the sheet.
    @State private var planningPost = false

    var body: some View {
        NavigationStack {
            form
                .confirmationDialog(ExportChoices.keepQuestion, isPresented: $askingKeep, titleVisibility: .visible) {
                    Button(ExportChoices.keep) { keepGoing() }
                        .keyboardShortcut(.defaultAction)
                    Button(ExportChoices.stop, role: .destructive) {
                        queue.cancelAll()
                        dismiss()
                    }
                }
                .sheet(item: Binding(
                    get: { exportedURL.map(ShareURL.init) },
                    set: { if $0 == nil { exportedURL = nil; sharedURLs = [] } }),
                       onDismiss: { takeFinished() }) { item in
                    // Every file at once when a range produced several: handing
                    // them over one sheet at a time would mean nine dismissals for
                    // a nine-page deck.
                    ShareSheet(urls: sharedURLs.isEmpty ? [item.url] : sharedURLs)
                }
                .overlay {
                    if let job = queue.current { progressCard(job) }
                }
                .sheet(isPresented: $showingMockups) {
                    // The design as saved has no editor to add a picture to.
                    MockupSheet(design: store.design, store: readOnly ? nil : store, startPage: store.pageIndex)
                }
                .sheet(isPresented: $planningPost) { PlanPostSheet(store: docStore ?? store) }
                .sheet(isPresented: $choosingPages, onDismiss: {
                    ExportChoices.remember(chosenIds, for: store.design)
                }) {
                    PagePickerSheet(design: store.design, chosen: $chosenIds)
                }
        }
        .onAppear {
            restoreSettings()
            queue.sheetOpen = true
            takeFinished()
        }
        // Gone, the queue delivers what finishes from here on.
        .onDisappear { queue.sheetOpen = false }
        .onChange(of: queue.finished.count) { takeFinished() }
        .onChange(of: queue.delivering) { takeFinished() }
        .presentationDetents([.medium])
    }

    /// The rows, their title and Close — kept apart from the sheets and
    /// dialogs `body` hangs on them, so each chain type-checks in good time.
    private var form: some View {
        // One computed property per section. As a single expression the
        // form was past what the type checker will resolve "in reasonable
        // time" — every string interpolation, ternary and `if` adds a
        // branch, and eight sections of them is too many.
        //
        // The Share row first, as Canva's sheet opens: one tap makes the
        // file type below with the settings as they stand. Then the type,
        // Suggested badged on the one read from the design, and only that
        // type's options.
        Form {
            shareSection
            fileTypeSection
            if store.design.pages.count > 1 && !selectionOnly { pagesSection }
            a11ySection
            if offersSelection { selectionSection }
            typeOptions
            designFileSection
            rememberSection
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
        }
        // The selection on its own is a picture's, an SVG's or a print's.
        .onChange(of: fileType) { if !offersSelection { selectionOnly = false } }
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Closing with an export running asks whether to keep it
            // going; swiping the sheet away keeps it, the default.
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { if queue.isBusy { askingKeep = true } else { dismiss() } }
            }
        }
    }

    /// Keep: the export goes on without the sheet, and notifications are
    /// asked for the first time one does, to say when it is done.
    private func keepGoing() {
        ExportNotifications.askPermission()
        dismiss()
    }

    /// An export done while the sheet is up, delivered as it always was:
    /// shared, printed, or what Photos took or a failure said. One at a
    /// time, the next once this one's share sheet or print dialog has gone;
    /// a notification's tap is used up here too.
    private func takeFinished() {
        guard exportedURL == nil, !queue.delivering, let done = queue.takeRequested()?.finished else { return }
        let result = done.result
        if let failed = result.failed {
            // Under any said already, so a second does not replace the first.
            let before = errorMessage.map { $0 + "\n" } ?? ""
            errorMessage = before + failed
            return
        }
        if let print = result.print {
            ExportPresenter.print(print)
        } else if !result.urls.isEmpty {
            sharedURLs = result.urls
            exportedURL = result.urls.first
        }
        if let note = result.photosNote {
            photosNote = PhotosNote(text: note, ok: result.photosSaved)
            announce(note)
        }
        if result.musicLost {
            musicNote = Self.musicLostNote
            announce(Self.musicLostNote)
        }
        if let skipped = result.skipped {
            errorMessage = skipped
            announce(skipped)
        }
        if let note = result.note {
            exportNote = note
            announce(note)
        }
    }

    /// Determinate, with a way out. A spinner with no number is fine for a
    /// PNG; a nine-page 4K video takes long enough that not knowing whether
    /// it is a tenth done or nine tenths, and having no button to press, is
    /// the difference between waiting and force-quitting.
    private func progressCard(_ job: ExportQueue.Job) -> some View {
        VStack(spacing: 14) {
            ProgressView(value: queue.progress) {
                Text(ExportChoices.pillText(label: job.label, fraction: queue.progress))
                    .font(.subheadline.weight(.semibold))
            }
            .progressViewStyle(.linear)
            if !queue.waiting.isEmpty {
                Text(ExportChoices.waitingText(queue.waiting.count))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Button("Cancel", role: .cancel) { queue.cancel(job.id) }
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 260)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 16, y: 6)
        .accessibilityElement(children: .combine)
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
        selectionOnly ? .current : pageExportRange
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
        // An expanded whiteboard measured as it exports (Whiteboards).
        return Whiteboards.flattened(store.design)
    }

    /// Soft output, said before the export rather than discovered in the
    /// post: a long edge too short for a phone screen, or a photo that will
    /// be stretched past the pixels it has.
    private var resolutionWarning: String? {
        let design = exportedDesign
        let shown = shownIndex
        let edge = DesignExporter.longEdge(size: design.size(at: shown), requested: pageScale(shown, in: design))
        if edge < DesignExporter.softBelowLongEdge {
            return tr("Only %d px on the long side — will look soft on most screens.", Int(edge))
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
            ? tr("One photo has fewer pixels than this size needs and will look blurry.")
            : trn("%d photo has fewer pixels than this size needs and will look blurry."
                  + "|%d photos have fewer pixels than this size needs and will look blurry.", blurry)
    }

    private var jpegSection: some View {
        let percent = Int((jpegQuality * 100).rounded())
        return Section {
            Slider(value: $jpegQuality, in: 0.3...1)
        } header: {
            Text("JPEG quality")
        } footer: {
            let size = estimatedSize
            Text(exportedIndices.count > 1
                 ? tr("%d%% — about %@ a page. PNG and PDF are lossless and ignore this.", percent, size)
                 : tr("%d%% — about %@. PNG and PDF are lossless and ignore this.", percent, size))
        }
    }

    private var pagesSection: some View {
        var note = tr("Page %d only.", store.pageIndex + 1)
        if pageRange == .all {
            note = tr("One file per page, numbered — so each can be posted on its own.")
            if hiddenPages > 0 { note = allPagesText + ". " + note }
        } else if pageRange == .chosen {
            note = tr("%@. Pictures and SVGs are a file a page; the PDF, video and GIF play them in order.", chosenText)
        }
        return Section {
            Picker("Pages", selection: rangeBinding) {
                ForEach(RangeChoice.allCases) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.segmented)
            if pageRange == .chosen {
                Button("Choose pages… (\(chosenText))") { choosingPages = true }
            }
            if ExportPlan.offersZip(format: fileType, files: exportedIndices.count) {
                Toggle("Save as one ZIP", isOn: $zip)
                Text(tr("%@, with a file for each page inside.", ExportPlan.zipName(store.design.title)))
                    .font(.footnote).foregroundStyle(.secondary)
            }
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
            Text(tr("PNG only. Drops the page's own background rather than "
                    + "flattening it, so the export really has nothing behind it."))
        }
    }

    /// Compress file: the PNG in at most 256 colours, kept only when it
    /// comes out enough smaller (ExportPlan), with the sizes before and
    /// after for the page shown.
    private var compressSection: some View {
        let design = exportedDesign
        let size = DesignExporter.outputSize(size: design.size(at: shownIndex),
                                             requested: pageScale(shownIndex, in: design))
        let w = Int(size.width), h = Int(size.height)
        let before = ExportChoices.sizeText(ExportPlan.estimatedPngBytes(width: w, height: h))
        let after = ExportChoices.sizeText(ExportPlan.estimatedCompressedPngBytes(width: w, height: h))
        return Section {
            Toggle("Compress file", isOn: $pngCompress)
        } footer: {
            Text(tr("About %@, or about %@ compressed (lower quality)", before, after))
        }
    }

    // MARK: accessibility

    /// The design's revision: when it last changed.
    private var revision: Int64 { Int64(store.design.updatedAt.rounded()) }

    /// "3 accessibility suggestions", with Review — Check accessibility on
    /// the pages going out — and a way to put it away until the design
    /// changes; for documents and pictures, while Settings asks for it.
    @ViewBuilder
    private var a11ySection: some View {
        let found = AccessibilityAudit.onPages(a11yFindings ?? [], Set(sharedIndices))
        if ExportPlan.showsA11yNudge(format: fileType, findings: found.count, remind: remindA11y,
                                     revision: revision, dismissed: a11yDismissed) {
            Section {
                HStack(spacing: 12) {
                    Label(AccessibilityAudit.suggestions(found), systemImage: "accessibility")
                    Spacer(minLength: 0)
                    Button("Review") { reviewingA11y = true }
                        .buttonStyle(.borderless)
                    Button { dismissA11y() } label: { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Dismiss")
                }
            }
            .onAppear { announceA11y(found) }
            .sheet(isPresented: $reviewingA11y) {
                AccessibilitySheet(store: store, pages: Set(sharedIndices))
            }
        }
    }

    /// The audit, once per revision of the design, off the main thread.
    @MainActor
    private func readA11y() async {
        let design = store.design
        let id = design.id
        let rev = revision
        a11yDismissed = DesignLibrary.versionMeta(for: id).a11yNudgeDismissed
        if let kept = Self.a11yKept, kept.id == id, kept.revision == rev {
            a11yFindings = kept.findings
            return
        }
        // The drawn pictures are registered here, on the main thread,
        // before the audit reads any.
        _ = PhotoLibrary.photos
        let found = await Task.detached(priority: .utility) { AccessibilityAudit.findings(design) }.value
        Self.a11yKept = (id, rev, found)
        a11yFindings = found
    }

    /// The row said once to VoiceOver, as it first shows.
    private func announceA11y(_ found: [AccessibilityAudit.Finding]) {
        guard !a11yAnnounced else { return }
        a11yAnnounced = true
        announce(AccessibilityAudit.suggestions(found))
    }

    /// The row put away until the design changes, in its meta.json.
    private func dismissA11y() {
        a11yDismissed = revision
        DesignLibrary.dismissA11yNudge(store.design.id, revision: revision)
    }

    // MARK: share

    /// The file types the selection on its own can be made into.
    private static let selectionTypes: Set<String> = ["png", "jpg", "svg", "print"]

    /// Whether "Selection only" is offered: something is selected, and the
    /// file type can be cut to it.
    private var offersSelection: Bool {
        !store.selection.isEmpty && Self.selectionTypes.contains(fileType)
    }

    private var selectionSection: some View {
        Section {
            Toggle("Selection only, cropped to its bounds", isOn: $selectionOnly)
        }
    }

    /// Share: one tap each, in the file type chosen below with the settings
    /// as they stand. Side by side where they fit; one under another at the
    /// largest text sizes, so every button stays whole.
    private var shareSection: some View {
        Section {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { shareButtons }
                VStack(alignment: .leading, spacing: 8) { shareButtons }
            }
        } header: {
            Text("Share")
        } footer: {
            shareFooter
        }
    }

    @ViewBuilder
    private var shareButtons: some View {
        Button(Self.shareLabel(fileType, count: shareCount)) { shareNow() }
            .buttonStyle(.borderedProminent)
            .disabled(!canShare)
        // A ZIP is no picture for Photos.
        if !zipping {
            Button(fileType == "mp4" || fileType == "gif" ? tr("Save the video to photos") : tr("Save to photos")) { saveNow() }
                .buttonStyle(.bordered)
                .disabled(!savesToPhotos || !canShare)
        }
        Button(copied ? tr("Copied") : tr("Copy as image")) { copyNow() }
            .buttonStyle(.bordered)
        if UIPrintInteractionController.isPrintingAvailable {
            Button("Print") { printNow() }
                .buttonStyle(.bordered)
                .disabled(leftOut(exportedIndices) != nil)
        }
        // The page on a phone, a laptop, a print or a shirt.
        Button("Mockups") { showingMockups = true }
            .buttonStyle(.bordered)
        // A reminder with the caption, the file made when it rings; kept
        // with the design, which the sheet from Home does not change.
        if !readOnly || docStore != nil {
            Button("Plan a post…") { planningPost = true }
                .buttonStyle(.bordered)
        }
    }

    /// Why Share cannot now, what Photos took, and a video's lost music.
    @ViewBuilder
    private var shareFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let why = unavailable { Text(why) }
            if let photosNote {
                Label(photosNote.text, systemImage: photosNote.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(photosNote.ok ? Color.green : Color.red)
            }
            if let musicNote {
                Label(musicNote, systemImage: "speaker.slash.fill")
                    .foregroundStyle(.orange)
            }
            if let exportNote { Text(exportNote) }
        }
    }

    /// The pages the chosen type makes: the PDF, PowerPoint, video and GIF
    /// follow the page choice alone; pictures, SVGs and prints the
    /// selection too.
    private var sharedIndices: [Int] {
        switch fileType {
        case "pdf", "pptx", "html": return pdfIndices
        case "mp4", "gif": return moviePages
        default: return exportedIndices
        }
    }

    private var shareCount: Int { sharedIndices.count }

    /// Said in place of making anything: no pages chosen, or every page
    /// hidden.
    private var unavailable: String? { leftOut(sharedIndices) }

    private var canShare: Bool { unavailable == nil }

    /// What goes into Photos for the chosen type: the pictures, or the
    /// film; nothing for a document.
    private var savesToPhotos: Bool { ["png", "jpg", "mp4", "gif"].contains(fileType) }

    /// The chosen type, made and handed to the share sheet.
    @MainActor
    private func shareNow() {
        switch fileType {
        case "pdf":
            run(tr("Making the PDF"), format: "pdf") {
                ExportJobs.pdf(designSnapshot, flatten: flatten, notes: pdfNotes, compress: pdfCompress, bookmarks: pdfBookmarks,
                               tagged: pdfTagged && !flatten)
            }
        case "print":
            // The design the pictures render, so "Selection only" prints
            // the selection rather than page 1 of the whole thing.
            run(tr("Making the print PDF"), format: "print") {
                ExportJobs.printPDF(exportedSnapshot, options: paper, flatten: flatten, printing: false, bookmarks: pdfBookmarks)
            }
        case "svg":
            run(tr("Rendering"), format: "svg") { zipped(ExportJobs.svg(exportedSnapshot)) }
        case "pptx":
            run(tr("Making the PowerPoint"), format: "pptx") {
                ExportJobs.powerPoint(designSnapshot, styled: pptxStyledText != ExportLast.styledPicture)
            }
        case "html":
            run(tr("Making the web page"), format: "html") { ExportJobs.html(designSnapshot, settings: htmlSettings) }
        case "mp4":
            run(tr("Rendering the video"), format: "mp4") {
                ExportJobs.movie(designSnapshot, settings: movieSettings, captions: captionsSrt)
            }
        case "gif":
            run(tr("Rendering the GIF"), format: "gif") { ExportJobs.gif(designSnapshot, settings: movieSettings) }
        case "docx":
            // A Doc as a Word document, from its blocks (DocxWriter).
            guard let doc else { return }
            run(tr("Making the Word document"), format: "docx") { ExportJobs.docx(doc) }
        default:
            let format = fileType
            run(tr("Rendering"), format: format) { zipped(picturesWork(format == "jpg" ? .jpeg : .png)) }
        }
    }

    /// Whether the files go out as one ZIP: asked for, where the type
    /// writes several.
    private var zipping: Bool {
        zip && ExportPlan.offersZip(format: fileType, files: exportedIndices.count)
    }

    /// `work`, its files put in one ZIP when they go out as one.
    private func zipped(_ work: @escaping ExportQueue.Work) -> ExportQueue.Work {
        zipping ? ExportJobs.zipped(work, design: exportedDesign) : work
    }

    /// The chosen type straight into Photos: the pictures, or the film.
    @MainActor
    private func saveNow() {
        photosNote = nil
        switch fileType {
        case "mp4":
            run(tr("Rendering the video"), format: "mp4") { ExportJobs.movieToPhotos(designSnapshot, settings: movieSettings) }
        case "gif":
            run(tr("Rendering the GIF"), format: "gif") { ExportJobs.gifToPhotos(designSnapshot, settings: movieSettings) }
        default:
            let format = fileType == "jpg" ? DesignExporter.RasterFormat.jpeg : .png
            run(tr("Saving to your photos"), format: fileType == "jpg" ? "jpg" : "png") {
                ExportJobs.picturesToPhotos(picturesSnapshot, format: format, scale: scale, longEdge: typedLongEdge ?? 0,
                                            quality: jpegQuality, transparent: transparent)
            }
        }
    }

    /// AirPrint, on the paper layout under Print-ready PDF.
    @MainActor
    private func printNow() {
        run(tr("Preparing to print"), format: "print") {
            ExportJobs.printPDF(exportedSnapshot, options: paper, flatten: flatten, printing: true, bookmarks: pdfBookmarks)
        }
    }

    /// "Share PDF", "Share 3 PNGs", "Share a print-ready PDF": the one-tap
    /// button for file type `type`, `count` pages making `count` files of a
    /// picture or an SVG — as the Android twin labels it.
    static func shareLabel(_ type: String, count: Int) -> String {
        switch type {
        case "pdf": return tr("Share PDF")
        case "print": return tr("Share a print-ready PDF")
        case "svg": return count > 1 ? trn("Share %d SVG|Share %d SVGs", count) : tr("Share SVG")
        case "pptx": return tr("Share PowerPoint")
        case "mp4": return tr("Share MP4")
        case "gif": return tr("Share GIF")
        case "html": return tr("Share web page")
        case "docx": return tr("Share Word document")
        default:
            let kind = type == "jpg" ? "JPG" : "PNG"
            return count > 1 ? trn("Share %d %@|Share %d %@s", count, kind) : tr("Share %@", kind)
        }
    }

    // MARK: file type

    /// Every type the design can be made into, Suggested badged on the one
    /// read from it; what the chosen one is for said under them.
    private var fileTypeSection: some View {
        Section {
            Picker("File type", selection: $fileType) {
                ForEach(offeredTypes, id: \.self) { type in
                    fileTypeRow(type).tag(type)
                }
            }
            .pickerStyle(.navigationLink)
        } footer: {
            Text(Self.typeNote(fileType))
        }
        .task(id: revision) { await readA11y() }
    }

    /// The file types offered: a Word document is a Doc's alone.
    private var offeredTypes: [String] {
        ExportLast.fileTypes.filter { $0 != "docx" || doc != nil }
    }

    private func fileTypeRow(_ type: String) -> some View {
        let name = Self.formatName(type)
        return HStack(spacing: 8) {
            Text(name)
            if type == suggested {
                Text("Suggested")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.15)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(type == suggested ? tr("%@, suggested", name) : name)
    }

    /// A file type's name: "PNG", "Print-ready PDF".
    static func formatName(_ type: String) -> String {
        switch type {
        case "png": return "PNG"
        case "jpg": return "JPG"
        case "pdf": return "PDF"
        case "print": return tr("Print-ready PDF")
        case "svg": return "SVG"
        case "pptx": return tr("PowerPoint")
        case "mp4": return "MP4"
        case "html": return "HTML"
        case "docx": return tr("Word document")
        default: return "GIF"
        }
    }

    /// What a file type is for, under the picker.
    static func typeNote(_ type: String) -> String {
        switch type {
        case "png": return tr("Sharp edges, and can be clear")
        case "jpg": return tr("Smaller, for photos")
        case "pdf": return tr("A document: sharp at any size, on screen or paper.")
        case "print": return tr("For a printer or a print shop, laid out on paper with bleed and crop marks.")
        case "svg": return tr("Editable vectors for another program.")
        case "pptx": return tr("Editable slides.")
        case "mp4": return tr("A video of the pages, with their motion and music.")
        case "html": return tr("A web page: the pages as sections, with a menu, links and video.")
        case "docx": return tr("A Word document: headings, lists, tables and pictures, to edit in Word.")
        default: return tr("A looping animation, without sound.")
        }
    }

    /// The chosen type's options alone.
    @ViewBuilder
    private var typeOptions: some View {
        switch fileType {
        case "png":
            qualitySection
            transparencySection
            compressSection
        case "jpg":
            qualitySection
            jpegSection
        case "pdf":
            pdfSection
        case "print":
            printSection
        case "svg":
            noteSection(svgNote)
        case "pptx":
            pptxSection
        case "html":
            htmlSection
        case "docx":
            EmptyView()
        default:
            motionSection
        }
    }

    /// The PowerPoint's styled-text choice, and the slides it will make.
    private var pptxSection: some View {
        Section {
            styledTextRow
        } footer: {
            Text(leftOut(pdfIndices) ?? pptxSubtitle)
        }
    }

    /// The web page's switches, Preview and Save to Files, and what it
    /// will be made as.
    private var htmlSection: some View {
        Section {
            Toggle("Menu from page titles", isOn: $htmlNav)
            Toggle("Fit the menu to phones", isOn: $htmlStack)
                .disabled(!htmlNav)
            Toggle("Include videos", isOn: $htmlMedia)
            Button("Preview") { previewHTML() }
                .disabled(leftOut(pdfIndices) != nil || makingHTML)
            Button("Save to device") { saveHTML() }
                .disabled(leftOut(pdfIndices) != nil || makingHTML)
            if makingHTML { ProgressView(tr("Making the web page")) }
        } footer: {
            Text(leftOut(pdfIndices) ?? htmlNote)
        }
        .sheet(item: Binding(get: { previewURL.map(ShareURL.init) }, set: { if $0 == nil { previewURL = nil } })) { item in
            WebPreview(url: item.url)
        }
        .fileMover(isPresented: Binding(get: { movingURL != nil }, set: { if !$0 { movingURL = nil } }),
                   file: movingURL) { _ in movingURL = nil }
    }

    private var htmlSettings: HTMLExporter.Settings {
        HTMLExporter.Settings(nav: htmlNav, mobileStack: htmlStack, embedMedia: htmlMedia)
    }

    /// "3 pages as sections of one index.html", or in a .zip with its
    /// clips.
    private var htmlNote: String {
        let pages = pagesWord(pdfIndices.count)
        return HTMLExporter.zipped(store.design, pages: pdfIndices, settings: htmlSettings)
            ? tr("%@ as sections, in a .zip with its videos.", pages)
            : tr("%@ as sections of one index.html.", pages)
    }

    /// The page written to a folder of its own and shown here, in a web
    /// view read from its file. Made while the sheet stays live
    /// (`makingHTML`).
    @MainActor
    private func previewHTML() {
        let snapshot = designSnapshot
        let settings = htmlSettings
        makingHTML = true
        Task { @MainActor in
            defer { makingHTML = false }
            do {
                previewURL = try await HTMLExporter.preview(snapshot.design, pages: snapshot.pages, settings: settings)
            } catch {
                errorMessage = tr("Couldn't make the web page")
            }
        }
    }

    /// The page made, and moved where the person picks in Files.
    @MainActor
    private func saveHTML() {
        let snapshot = designSnapshot
        let settings = htmlSettings
        makingHTML = true
        Task { @MainActor in
            defer { makingHTML = false }
            do {
                movingURL = try await HTMLExporter.export(snapshot.design, pages: snapshot.pages, settings: settings)
                rememberSettings("html")
            } catch {
                errorMessage = tr("Couldn't make the web page")
            }
        }
    }

    private func noteSection(_ text: String) -> some View {
        Section {
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// The SVGs, from the page choice: a file a page.
    private var svgNote: String {
        if let why = leftOut(exportedIndices) { return why }
        let count = exportedIndices.count
        return count > 1 ? tr("%@, one SVG each", pagesWord(count)) : tr("%@, editable vectors", onePageText)
    }

    /// The PDF's switches — flattened, notes pages, compressed, bookmarks —
    /// and the size it will come to.
    private var pdfSection: some View {
        Section {
            Toggle("Flatten PDF", isOn: $flatten)
            pdfOptions
        } header: {
            Text(verbatim: "PDF")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(leftOut(pdfIndices) ?? pdfSubtitle)
                Text("Flatten draws each PDF page as one 300-dpi picture: no editable text and no links, so a print shop gets no font surprises.")
                Text("A bookmark for each page, by its title, so a reader can jump between them.")
                Text("Headings, reading order and alt text a screen reader can follow.")
            }
        }
    }

    /// The PDF's switches, and the size it will come to.
    @ViewBuilder
    private var pdfOptions: some View {
        Toggle("Include notes", isOn: $pdfNotes)
        Toggle("Compress", isOn: $pdfCompress)
        // An outline entry a page, by its title, for a reader's navigation;
        // the file's title and language go in always.
        Toggle("Bookmarks", isOn: $pdfBookmarks)
        // Headings, reading order and alt text for a screen reader — not
        // for a flattened file, which is pictures.
        Toggle("Tagged for screen readers", isOn: Binding(get: { pdfTagged && !flatten }, set: { pdfTagged = $0 }))
            .disabled(flatten)
        Text(pdfSizeNote)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .task(id: pdfPhotoSources) { await readPDFPixelSizes() }
    }

    /// "About 3.2 MB": the PDF's photos as they will be kept, and 30 KB a
    /// sheet (ExportChoices.estimatedPDFBytes), from the pixel sizes read
    /// so far.
    private var pdfSizeNote: String {
        let bytes = ExportChoices.estimatedPDFBytes(design: store.design, indices: pdfIndices, notes: pdfNotes,
                                                    compress: pdfCompress) { pdfPixelSizes[$0] }
        return ExportChoices.sizeText(bytes)
    }

    /// Every photo source the PDF holds, the master's and backgrounds too.
    private var pdfPhotoSources: [String] {
        ExportChoices.pdfPhotos(design: store.design, indices: pdfIndices).map { $0.src }
    }

    /// The pixels of each photo not yet read, from its header, off the main
    /// thread, as the Android twin's sheet reads them on its IO dispatcher.
    private func readPDFPixelSizes() async {
        let wanted = pdfPhotoSources.filter { pdfPixelSizes[$0] == nil }
        guard !wanted.isEmpty else { return }
        let read = await Task.detached(priority: .utility) { () -> [String: CGSize] in
            var sizes: [String: CGSize] = [:]
            for src in wanted { sizes[src] = ExportChoices.photoPixelSize(src) }
            return sizes
        }.value
        pdfPixelSizes.merge(read) { _, new in new }
    }

    /// What the PDF holds, from the page choice.
    private var pdfSubtitle: String {
        let kind = flatten ? tr("flattened at 300 dpi") : tr("vector")
        guard store.design.pages.count > 1 else { return tr("Print-ready document, %@", kind) }
        switch pageRange {
        case .all: return "\(allPagesText), \(kind)"
        case .current: return tr("Page %d only, %@", store.pageIndex + 1, kind)
        case .chosen: return "\(chosenText), \(kind)"
        }
    }

    /// The PowerPoint's styled text: editable as the closest DrawingML
    /// match (shadows, outlines, glows, gradient letters, curves and
    /// columns kept as text), or the exact look as a picture — the
    /// "pptxStyledText" setting both phones keep.
    private var styledTextRow: some View {
        Picker("Styled text:", selection: $pptxStyledText) {
            Text("Editable (closest match)").tag(ExportLast.styledEditable)
            Text("Exact look").tag(ExportLast.styledPicture)
        }
    }

    /// Said from the page choice above, which the PowerPoint follows as the
    /// PDF does: a slide a page, hidden pages left out of All pages.
    private var pptxSubtitle: String {
        let kind = tr("editable slides")
        guard store.design.pages.count > 1 else { return tr("One slide, editable text and shapes") }
        switch pageRange {
        case .all: return "\(allPagesText), \(kind)"
        case .current: return tr("Page %d only, %@", store.pageIndex + 1, kind)
        case .chosen: return "\(chosenText), \(kind)"
        }
    }

    /// "3 pages", or "3 of 8 pages" when they were chosen.
    private func pagesWord(_ count: Int) -> String {
        pageRange == .chosen && !selectionOnly
            ? ExportChoices.countText(count, of: store.design.pages.count)
            : trn("%d page|%d pages", count)
    }

    /// "3 of 8 pages": what Choose… has ticked.
    private var chosenText: String {
        ExportChoices.countText(chosenIds.count, of: store.design.pages.count)
    }

    /// Kept for the next Export, or forgotten, with the switch.
    private var rememberSection: some View {
        Section {
            Toggle("Remember these settings", isOn: $remember)
                .onChange(of: remember) { _, on in
                    if !on {
                        exportLast = ""
                    } else if ExportLast.read(exportLast) == nil {
                        // Switched on here, not restored as the sheet opened.
                        rememberSettings(fileType)
                    }
                }
        } footer: {
            Text("The format, size, quality, background, page choice and PDF options of your last export, ready next time. The pages ticked in Choose… stay with this design until the app closes.")
        }
    }

    /// The settings now, under `format`, when Remember is on — and whether
    /// that was the type suggested, so the next export follows the
    /// suggestion for its own design rather than this one's.
    private func rememberSettings(_ format: String) {
        guard remember else { return }
        exportLast = ExportLast(format: format, scale: scale, longEdge: typedLongEdge.map { Int($0) },
                                jpegQuality: jpegQuality, transparent: transparent,
                                pages: pageRange.rawValue, pdfNotes: pdfNotes, pdfCompress: pdfCompress,
                                pptxStyledText: pptxStyledText, suggested: format == suggested,
                                pdfBookmarks: pdfBookmarks, colourProfile: paper.colourProfile.rawValue,
                                html: htmlSettings, zip: zip, pngCompress: pngCompress, pdfTagged: pdfTagged).json
    }

    /// The pages ticked this session, the design's bleed, and the
    /// remembered settings, as the sheet opens.
    private func restoreSettings() {
        chosenIds = ExportChoices.chosen(for: store.design)
        // The Bleed stepper starts at the design's own bleed, on paper.
        paper.bleed = Bleed.printPoints(store.design)
        // The file type: the last export's when remembered and chosen by
        // hand; else the one suggested from the design (ExportSuggestion),
        // a plain picture in Settings' default format.
        // A Doc's suggestion is its own, not its pages' (a PDF).
        let read = ExportSuggestion.suggest(doc ?? store.design)
        suggested = read != "png" ? read : (defaultFormat == "jpg" ? "jpg" : "png")
        fileType = suggested
        guard let last = ExportLast.read(exportLast) else { return }
        remember = true
        // A Word document is a Doc's alone.
        if !last.suggested && (last.format != "docx" || doc != nil) { fileType = last.format }
        pdfBookmarks = last.pdfBookmarks
        pdfTagged = last.pdfTagged
        scale = [1.0, 2.0, 3.0].contains(last.scale) ? last.scale : 2
        jpegQuality = last.jpegQuality
        transparent = last.transparent
        pdfNotes = last.pdfNotes
        pdfCompress = last.pdfCompress
        pptxStyledText = last.pptxStyledText
        htmlNav = last.html.nav
        htmlStack = last.html.mobileStack
        htmlMedia = last.html.embedMedia
        zip = last.zip
        pngCompress = last.pngCompress
        paper.colourProfile = PrintLayout.ColourProfile.of(last.colourProfile)
        pageRange = RangeChoice(rawValue: last.pages) ?? .all
        // After the scale's own change has cleared the field, which it does
        // once this pass is drawn.
        let edge = last.longEdge.map { String($0) } ?? ""
        DispatchQueue.main.async { longEdgeText = edge }
    }

    /// Said when a video's music could not be mixed in, as the Android twin
    /// says it.
    static let musicLostNote = ExportChoices.musicLost

    /// VoiceOver hears the outcome of a save; the footer it lands in is
    /// easily missed from the button that was pressed.
    private func announce(_ text: String) {
        UIAccessibility.post(notification: .announcement, argument: text)
    }

    /// The design itself, to open in Canvia on another phone.
    private var designFileSection: some View {
        Section {
            exportButton(tr("Canvia design file"), subtitle: tr("The design and its photos, to send or back up"),
                         icon: "shippingbox", working: tr("Packing the design file")) {
                ExportJobs.designFile(store.design)
            }
        }
    }

    /// At once, not queued: a picture of one page on the clipboard.
    @MainActor
    private func copyNow() {
        errorMessage = nil
        do { try copyToClipboard() } catch { errorMessage = ExportChoices.failedText(error.localizedDescription) }
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

    /// The print-ready PDF's options — the Share row's Print and Share
    /// both take them — and its paper.
    private var printSection: some View {
        Section {
            Toggle("Flatten PDF", isOn: $flatten)
            Toggle("Bookmarks", isOn: $pdfBookmarks)
            colourProfileRows
            // Compress is the plain PDF's; a print shop gets every pixel.
            Toggle("Compress", isOn: .constant(false))
                .disabled(true)
            Text(ExportChoices.printKeepsQuality)
                .font(.footnote)
                .foregroundStyle(.secondary)
            DisclosureGroup("Paper layout") { paperSettings }
        } header: {
            Text("Print")
        } footer: {
            Text(paperNote)
        }
    }

    /// The print-ready PDF's colour profile: RGB, or CMYK for a print
    /// shop — flattened, and said how big — with a word when the design has
    /// colours no press reaches (Cmyk.dullerColours).
    @ViewBuilder
    private var colourProfileRows: some View {
        Picker("Colour profile", selection: $paper.colourProfile) {
            ForEach(PrintLayout.ColourProfile.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        if paper.colourProfile == .cmyk {
            Text(cmykNote)
                .font(.footnote)
                .foregroundStyle(.secondary)
            // The warning covers what will print: the selection when Selection only is on.
            if !Cmyk.dullerColours(exportedDesign).isEmpty {
                Label(Cmyk.dullerWarning, systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// "CMYK · flattened · about 24 MB": every sheet at 300 dpi, four
    /// bytes a pixel, packed to about half (CmykPdf.estimatedBytes).
    private var cmykNote: String {
        let sheets = DesignExporter.sheetCount(design: exportedDesign, indices: exportedIndices, options: paper)
        return CmykPdf.note(CmykPdf.estimatedBytes(sheets: sheets, size: paper.sheet))
    }

    private var paperNote: String {
        let pts = PrintLayout.pagePoints(design: exportedDesign, bleed: paper.bleed)
        switch paper.fit {
        case .fit:
            return paper.landscape ? tr("Fitted to %@ landscape.", paper.paper.name) : tr("Fitted to %@.", paper.paper.name)
        case .actual:
            let fits = pts.width <= paper.printable.width && pts.height <= paper.printable.height
            // Whole millimetres, whatever the design is measured in, as
            // Android's PrintLayout.note says it: the size it truly is now
            // that a page prints at its dpi.
            let millimetres = String(format: "%.0f × %.0f mm", pts.width / 2.835, pts.height / 2.835)
            return fits ? tr("Prints at actual size, %@.", millimetres)
                        : tr("Larger than the sheet at actual size — it will be clipped. Tile it instead.")
        case .tile:
            let n = PrintLayout.tiles(page: pts, printable: paper.printable.size, overlap: paper.overlap).count
            return trn("%d sheets of %@, overlapping by %d pt to trim and join."
                       + "|%d sheets of %@, overlapping by %d pt to trim and join.", n, paper.paper.name, Int(paper.overlap))
        case .several:
            // "10 per sheet, 2 sheets", as the Android twin says it.
            let plan = DesignExporter.severalPlan(design: exportedDesign, indices: exportedIndices, options: paper)
            return PrintLayout.severalNote(perSheet: plan.perSheet, sheets: plan.sheets.count)
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
            if paper.fit == .several { severalSettings }
            Stepper(value: $paper.bleed, in: 0...36, step: 3) { Text("Bleed \(Int((paper.bleed / 2.835).rounded())) mm") }
            // A design with no bleed of its own has one made for it.
            if paper.bleed > 0 && !Bleed.shown(exportedDesign) {
                Text(PrintLayout.enlargedNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Toggle("Crop marks", isOn: $paper.cropMarks)
        }
    }

    /// Several to a sheet: one page over and over, or one of each; and, for
    /// a design of two pages with both printed, its back printed on the
    /// other side — the switch there, and said, otherwise, as the Android
    /// twin's is.
    @ViewBuilder
    private var severalSettings: some View {
        Picker("Fill the sheet with", selection: $paper.several) {
            ForEach(PrintLayout.Several.allCases) { Text($0.name).tag($0) }
        }
        let twoSided = exportedDesign.pages.count == 2 && exportedIndices.count == 2
        Toggle("Double-sided", isOn: Binding(get: { paper.duplex && twoSided }, set: { paper.duplex = $0 }))
            .disabled(!twoSided)
        Text(twoSided ? tr("Page 1 on the front, page 2 on the back. Print on both sides, flipping on the long edge.")
                      : tr("Double-sided takes a design of two pages, both printed: a front and a back."))
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    /// The video's or GIF's: the video's size, how it moves, and its
    /// music, set in the editor.
    private var motionSection: some View {
        Section {
            Text(leftOut(moviePages) ?? movieSubtitle)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if fileType == "mp4" {
                Picker("Video size", selection: $resolution) {
                    ForEach(MovieExporter.resolutions(for: store.design)) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                // The .srt goes beside a shared video only.
                if Captions.any(store.design) {
                    Toggle("Also save captions (.srt)", isOn: $captionsSrt)
                }
            }
            if !readOnly { DisclosureGroup("Motion settings") { motionSettings } }
        } header: {
            Text("Motion")
        } footer: {
            Text(motionNote)
        }
    }

    /// How it moves, as the Android twin says it: each page's hold (a page
    /// with a time of its own keeps it), the push in, the fade or cut, and
    /// whether the music under it is on this phone.
    private var motionNote: String {
        let m = store.design.motion ?? MotionSettings()
        let settings = MovieExporter.Settings(store.design.motion)
        let hold = String(format: "%.1f", settings.secondsPerPage)
        let note: String
        if m.movement {
            note = m.crossfade
                ? tr("Each page holds %@s unless it has its own time, with a slow push in, and fades into the next.", hold)
                : tr("Each page holds %@s unless it has its own time, with a slow push in, and cuts to the next.", hold)
        } else {
            note = m.crossfade
                ? tr("Each page holds %@s unless it has its own time, and fades into the next.", hold)
                : tr("Each page holds %@s unless it has its own time, and cuts to the next.", hold)
        }
        return note + Self.musicSentence(store.design.audioTracks)
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
            trackRows
        }
    }

    /// What the motion note says of the music (AudioTracks.musicNote): the
    /// tracks whose music is not on this phone counted.
    static func musicSentence(_ tracks: [AudioTrack]) -> String {
        AudioTracks.musicNote(tracks: tracks.count, away: tracks.filter(AudioTracks.isMissing).count)
    }

    /// The design's audio tracks as the Android twin lists them: each by
    /// its name with where it starts, how long it plays and whether its
    /// music is on this phone, and Remove — trimmed, faded and moved in the
    /// editor's Audio sheet — and music from Files added as another track
    /// from the start.
    @ViewBuilder
    private var trackRows: some View {
        ForEach(store.design.audioTracks) { track in
            trackRow(track)
        }
        Button("Add music…") { pickingAudio = true }
            .fileImporter(isPresented: $pickingAudio, allowedContentTypes: [.audio]) { result in
                addMusic(result)
            }
            .alert("That file isn't music this phone can play", isPresented: $audioRefused) {
                Button("OK", role: .cancel) {}
            }
        Text("Set where each track starts, its trim, volume and fades under More > Audio.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .task(id: store.design.audioTracks.compactMap(\.audioId)) { await readTrackLengths() }
    }

    /// One track: its name and line (AudioTracks.summary), and Remove.
    private func trackRow(_ track: AudioTrack) -> some View {
        let name = AudioTracks.name(of: track)
        let line = AudioTracks.summary(of: track, duration: track.audioId.flatMap { trackLengths[$0] },
                                       missing: AudioTracks.isMissing(track))
        return HStack {
            Image(systemName: "waveform")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).lineLimit(1)
                Text(line).font(.caption).foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            Spacer()
            Button { store.removeAudioTrack(track.id) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove \(name)")
        }
    }

    private func readTrackLengths() async {
        for id in Set(store.design.audioTracks.compactMap(\.audioId)) where trackLengths[id] == nil {
            if let seconds = await AudioStore.duration(of: id) { trackLengths[id] = seconds }
        }
    }

    /// Music picked in Files as another track, one Undo: only music that
    /// plays — a file with no sound in it would make a silent video without
    /// a word — kept among your uploads to choose again.
    private func addMusic(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let id = AudioStore.store(url) else {
            audioRefused = true
            return
        }
        Task {
            guard let seconds = await AudioStore.duration(of: id), seconds > 0 else {
                AudioStore.delete(id)
                audioRefused = true
                return
            }
            Uploads.record(id, kind: .audio)
            store.addAudioTrack(id)
        }
    }

    /// A row that makes something: its job, made as it is tapped from the
    /// design and the settings as they stand, goes to the app's queue —
    /// after any export already running. `unavailable`, when set, is why it
    /// cannot now — every page it would make is hidden — said in place of
    /// its subtitle, with the row disabled.
    private func exportButton(_ title: String, subtitle: String, icon: String, working: String = tr("Rendering"),
                              unavailable: String? = nil, format: String? = nil,
                              job: @escaping @MainActor () -> ExportQueue.Work) -> some View {
        Button {
            run(working, format: format, job: job)
        } label: {
            rowLabel(title, subtitle: unavailable ?? subtitle, icon: icon)
        }
        .foregroundStyle(.primary)
        .disabled(unavailable != nil)
    }

    /// An export asked for: its job, made now from the design and the
    /// settings as they stand, to the app's queue — after any export
    /// already running — and the settings kept under `format`, when asked.
    @MainActor
    private func run(_ working: String, format: String?, job: @MainActor () -> ExportQueue.Work) {
        errorMessage = nil
        musicNote = nil
        exportNote = nil
        queue.enqueue(ExportQueue.Job(label: working, designId: store.design.id, work: job()))
        // Kept for next time, when asked to be.
        if let format { rememberSettings(format) }
    }

    private func rowLabel(_ title: String, subtitle: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon).frame(width: 30)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.semibold)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    /// The page choice as it stands, over the whole design: what the PDF,
    /// PowerPoint, video and GIF write.
    private var designSnapshot: ExportSnapshot {
        ExportSnapshot(store.design, range: pageExportRange, current: store.pageIndex)
    }

    /// The design the pictures, SVGs and print render — the selection as a
    /// page of its own when "Selection only" is on — with its pages.
    private var exportedSnapshot: ExportSnapshot {
        ExportSnapshot(exportedDesign, range: exportedRange, current: exportedPageIndex)
    }

    /// The pictures' snapshot: the page on screen shows its captions at the
    /// timeline's playhead, as the canvas does; a selection on its own page
    /// and every other page their first cue — the Android twin's rule.
    private var picturesSnapshot: ExportSnapshot {
        var snapshot = exportedSnapshot
        if !selectionOnly { snapshot.captionTime = store.playheadInPage }
        return snapshot
    }

    private func picturesWork(_ format: DesignExporter.RasterFormat) -> ExportQueue.Work {
        ExportJobs.pictures(picturesSnapshot, format: format, scale: scale, longEdge: typedLongEdge ?? 0,
                            quality: jpegQuality, transparent: transparent, compress: pngCompress)
    }

    /// How many pages are hidden, and so left out of "All pages" and the
    /// video.
    private var hiddenPages: Int { store.design.pages.count - store.design.visiblePageIndices.count }

    /// "All 5 pages", or "All 5 pages, 2 hidden left out", as the Android
    /// twin says it.
    private var allPagesText: String {
        PageVisibility.allPages(total: store.design.pages.count, hidden: hiddenPages)
    }

    /// What a one-page export is of: the page on screen — or, when the rest
    /// of "All pages" is hidden, the one page left.
    private var onePageText: String {
        if let only = exportedIndices.first, only != exportedPageIndex { return tr("Page %d", only + 1) }
        return tr("Current page")
    }

    /// The pages the PDF row writes, which follow the page choice alone.
    private var pdfIndices: [Int] {
        pageExportRange.indices(in: store.design, current: store.pageIndex)
    }

    /// The pages the video and GIF play: every page shown, the page on
    /// screen, or those chosen.
    private var moviePages: [Int] {
        MovieExporter.playedPages(design: store.design, range: pageExportRange, current: store.pageIndex)
    }

    /// The motion settings with the video size chosen.
    private var movieSettings: MovieExporter.Settings {
        var settings = MovieExporter.Settings(store.design.motion)
        settings.maxEdge = resolution.maxEdge
        return settings
    }

    /// Said on a row with no page to make, in place of what it makes: none
    /// ticked in Choose…, or every page hidden.
    private func leftOut(_ indices: [Int]) -> String? {
        guard indices.isEmpty else { return nil }
        return pageRange == .chosen && !selectionOnly ? tr("No pages chosen") : PageVisibility.everyPageHidden
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
            note = tr("%@ — reduced from %@× so the render fits in memory", note, String(format: "%.1f", requested))
        }
        if exportedIndices.count > 1 && design.hasMixedPageSizes {
            note = tr("%@ for this page; each page at its own size", note)
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

    /// The film's length from its timeline, so a page with a hold of its
    /// own counts at that hold, and a hidden page not at all.
    private var movieSubtitle: String {
        let pages = store.design.pages.count
        let seconds = MovieExporter.seconds(design: store.design, settings: movieSettings,
                                            range: pageExportRange, current: store.pageIndex)
        let length = String(format: "%.0f", max(1, seconds))
        let size = MovieExporter.videoSize(for: store.design, maxEdge: resolution.maxEdge)
        let pixels = "\(Int(size.width)) × \(Int(size.height))"
        guard pages > 1 else { return tr("One page, %@s, %@", length, pixels) }
        switch pageRange {
        case .all: return tr("%@, %@s, %@", allPagesText, length, pixels)
        case .current: return tr("Current page, %@s, %@", length, pixels)
        case .chosen: return tr("%@, %@s, %@", chosenText, length, pixels)
        }
    }
}

struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
