// Check accessibility: every finding of one pass, page by page — "5 things
// on 3 pages" — each with Show, which goes to the element, and its fix:
// Fix colour, Add alt text (with Suggest from the on-device classifier, and
// "Use: …" for what the app already knows of the picture),
// Mark decorative, Make it 12, Fix heading level, Make it a heading, Add
// captions — which opens the clip's or the voice-over's captions over the
// editor (DesignStore.captionsAsked). Clips filmed without sound are not
// asked about, once their files are read.
// Contrast is a section of its own, with Fix all contrast as one undo
// step, as Check contrast had it. Show reading
// order numbers the page's elements on the canvas in VoiceOver's order.
// The Android twin's AccessibilitySheet.

import SwiftUI

struct AccessibilitySheet: View {
    @Bindable var store: DesignStore
    /// The pages it looks at, by index — the pages an export makes, when
    /// the Export sheet opens it; nil for every page.
    var pages: Set<Int>? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var findings: [AccessibilityAudit.Finding] = []
    /// The finding whose alt text is being written, kept while the alert
    /// comes and goes.
    @State private var describing: AccessibilityAudit.Finding?
    @State private var askingAlt = false
    @State private var altDraft = ""
    /// The clips whose files have no sound of their own, read off the main
    /// thread as the sheet opens; until they are, every clip is taken to
    /// have some.
    @State private var silentClips: Set<String> = []
    /// What the app already knows of each picture missing a description,
    /// by element id (AltText.suggest), read off the main thread: its row's
    /// "Use: …".
    @State private var suggestions: [String: String] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Show reading order", isOn: $store.showsReadingOrder)
                } footer: {
                    Text("Numbers each element on the page in the order VoiceOver reads it: rows top to bottom, left to right.")
                }
                viewAsSection
                if findings.isEmpty {
                    Section {
                        Label("Nothing to fix. Text reads clearly, pictures are described, nothing is too small or flashes.",
                              systemImage: "checkmark.seal")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    let contrast = findings.filter { $0.kind == .contrast }
                    if !contrast.isEmpty { contrastSection(contrast) }
                    let others = findings.filter { $0.kind != .contrast }
                    ForEach(AccessibilityAudit.byPage(others)) { group in
                        Section(pageTitle(group.pageIndex, count: group.findings.count)) {
                            ForEach(group.findings) { row($0) }
                        }
                    }
                }
            }
            .navigationTitle(AccessibilityAudit.summary(findings))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .alert("Describe this picture", isPresented: $askingAlt) {
                TextField("What it shows", text: $altDraft)
                Button("Suggest") {
                    // Vision's classifier, and where it is unsure what the
                    // app already knows (read off the main thread as the
                    // sheet opened, loadSuggestions).
                    if let f = describing, let el = element(f),
                       let draft = PhotoLibrary.resolve(el.src).flatMap({ AltText.describe($0) })
                        ?? suggestions[el.id] {
                        altDraft = draft
                    }
                    // The alert closes on any button; open it again, with
                    // the draft in the field, as the toolbar's Alt text does.
                    askingAlt = true
                }
                Button("Save") { saveAlt() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Read by VoiceOver and written into SVG exports. Suggest asks the on-device classifier for a first draft.")
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear { refresh() }
        .task {
            silentClips = await Self.silentClips(in: store.design)
            refresh()
        }
        .task(id: altTextMissing) { await loadSuggestions() }
        // Edits made under the sheet — an undo, a colour changed by hand —
        // are checked again.
        .onChange(of: store.design) { _, _ in refresh() }
        .onDisappear {
            store.showsReadingOrder = false
            store.viewAs = .typical
        }
        .onChange(of: store.viewAs) { _, kind in
            AccessibilityNotification.Announcement(ColourVision.announcement(kind)).post()
        }
    }

    /// "View as": the canvas as each colour vision deficiency sees it,
    /// while the sheet is open.
    private var viewAsSection: some View {
        Section {
            Picker("View as", selection: $store.viewAs) {
                ForEach(ColourVision.Sight.allCases) { kind in
                    Text(kind.label).tag(kind)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("View as")
        }
    }

    private func refresh() {
        let all = AccessibilityAudit.findings(store.design, silentClips: silentClips)
        findings = pages.map { AccessibilityAudit.onPages(all, $0) } ?? all
    }

    /// "Page 2 · 3 things".
    private func pageTitle(_ index: Int, count: Int) -> String {
        tr("Page %d · %@", index + 1, trn("%d thing|%d things", count))
    }

    private func contrastSection(_ list: [AccessibilityAudit.Finding]) -> some View {
        Section {
            ForEach(list) { row($0) }
            if list.count > 1 {
                Button("Fix all contrast") { fixAllContrast(list) }
                    .fontWeight(.semibold)
            }
        } header: {
            Text(trn("Contrast · %d hard-to-read text|Contrast · %d hard-to-read texts", list.count))
        } footer: {
            Text("Text against what is behind it, to WCAG AA: 4.5:1, or 3:1 for large text.")
        }
    }

    private func row(_ f: AccessibilityAudit.Finding) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: symbol(f.kind))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name(of: f))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(f.kind == .contrast ? tr("%@ · page %d", f.message, f.pageIndex + 1) : f.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Button("Show") { store.reveal(elementId: f.elementId, onPage: f.pageIndex) }
                    .buttonStyle(.bordered)
                if let fix = f.fix {
                    Button(tr(fix.rawValue)) { apply(fix, f) }
                        .buttonStyle(.borderedProminent)
                }
                if f.kind == .altText {
                    Button("Mark decorative") { markDecorative(f) }
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
            // What the app already knows of it; written only when tapped.
            if f.fix == .addAltText, let id = f.elementId, let suggestion = suggestions[id] {
                Button(tr("Use: %@", suggestion)) { useSuggestion(suggestion, f) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
    }

    private func symbol(_ kind: AccessibilityAudit.Kind) -> String {
        switch kind {
        case .contrast: return "circle.lefthalf.striped.horizontal"
        case .altText: return "text.below.photo"
        case .smallText: return "textformat.size.smaller"
        case .flashing: return "bolt.horizontal"
        case .linkText: return "link"
        case .chartColours: return "chart.pie"
        case .readingOrder: return "list.number"
        case .headings: return "textformat.size"
        case .colourVision: return "eye"
        case .captions: return "captions.bubble"
        case .missingLetters: return "character.textbox"
        case .safeZone: return "rectangle.inset.filled"
        }
    }

    /// The element as Layers names it, or the page.
    private func name(of f: AccessibilityAudit.Finding) -> String {
        guard let el = element(f) else { return tr("Page %d", f.pageIndex + 1) }
        return ElementNames.name(of: el)
    }

    /// The finding's element, looked up on its own page.
    private func element(_ f: AccessibilityAudit.Finding) -> Element? {
        let pages = store.design.pages
        guard pages.indices.contains(f.pageIndex), let id = f.elementId else { return nil }
        return pages[f.pageIndex].elements.first { $0.id == id }
    }

    private func apply(_ fix: AccessibilityAudit.Fix, _ f: AccessibilityAudit.Finding) {
        switch fix {
        case .addAltText:
            altDraft = element(f)?.altText ?? ""
            describing = f
            askingAlt = true
        case .addCaptions:
            // On its page, the clip selected; the editor opens its captions.
            store.reveal(elementId: f.elementId, onPage: f.pageIndex)
            store.captionsAsked = f.source
        case .fixColour, .makeIt12, .fixHeadingLevel, .makeHeading, .moveInside:
            let next = AccessibilityAudit.fixed(store.design, f)
            guard next != store.design else { return }
            store.apply { $0 = next }
            refresh()
        }
    }

    /// The clips of `design` whose files are on this phone and have no sound
    /// of their own — which Check accessibility does not ask captions for.
    /// A clip not here is taken to have sound, as on the Android twin.
    static func silentClips(in design: Design) async -> Set<String> {
        var silent: Set<String> = []
        for id in DesignPackage.videoIDs(in: design) where VideoStore.url(for: id) != nil {
            if await VideoStore.soundLength(of: id) == nil { silent.insert(id) }
        }
        return silent
    }

    /// Every contrast finding fixed, as one step.
    private func fixAllContrast(_ list: [AccessibilityAudit.Finding]) {
        let next = AccessibilityAudit.fixedAllContrast(store.design, list)
        guard next != store.design else { return }
        store.apply { $0 = next }
        refresh()
    }

    private func markDecorative(_ f: AccessibilityAudit.Finding) {
        guard let id = f.elementId else { return }
        let next = AccessibilityAudit.markedDecorative(store.design, pageIndex: f.pageIndex, elementId: id)
        store.apply { $0 = next }
        refresh()
    }

    /// The elements whose row offers Add alt text, which the suggestions
    /// are read for again as they change.
    private var altTextMissing: [String] {
        findings.filter { $0.fix == .addAltText }.compactMap(\.elementId)
    }

    /// Each such element's suggestion: what the phone knows of it besides
    /// the design (AltText.hints) read off the main thread, the libraries
    /// looked up on it.
    private func loadSuggestions() async {
        let elements = findings.filter { $0.fix == .addAltText }.compactMap { element($0) }
        let hints = await Task.detached(priority: .utility) { () -> [String: AltText.Hints] in
            var out: [String: AltText.Hints] = [:]
            for el in elements { out[el.id] = AltText.hints(for: el) }
            return out
        }.value
        var made: [String: String] = [:]
        for el in elements { made[el.id] = AltText.suggest(el, hints: hints[el.id] ?? AltText.Hints()) }
        suggestions = made
    }

    /// "Use: …": `text` as the finding's element's description, kept with
    /// its picture's src (altTextSource) so a Replace takes it away, as one
    /// step. Not on a locked page.
    private func useSuggestion(_ text: String, _ f: AccessibilityAudit.Finding) {
        guard let id = f.elementId, !store.refusesLockedPage(at: f.pageIndex) else { return }
        store.apply { design in
            if design.pages.indices.contains(f.pageIndex),
               let i = design.pages[f.pageIndex].elements.firstIndex(where: { $0.id == id }) {
                design.pages[f.pageIndex].elements[i].altText = text
                design.pages[f.pageIndex].elements[i].altTextSource = design.pages[f.pageIndex].elements[i].src
            }
        }
        refresh()
    }

    private func saveAlt() {
        guard let f = describing, let id = f.elementId else { return }
        let text = altDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.apply { design in
            if design.pages.indices.contains(f.pageIndex),
               let i = design.pages[f.pageIndex].elements.firstIndex(where: { $0.id == id }) {
                design.pages[f.pageIndex].elements[i].altText = text
                design.pages[f.pageIndex].elements[i].altTextSource = nil
            }
        }
        refresh()
    }
}
