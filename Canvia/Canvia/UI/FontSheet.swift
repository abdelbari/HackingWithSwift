// The font picker: a search by name (case and accents aside), the category
// chips, and each font a row drawn in its own face, the one in use ticked.
// Browsing, the brand kit's fonts come first, then Recently used on this
// phone (as the sheet opened), the fonts In this design, Your fonts — a
// family a row, with how many weights it has — with "Add a font…", and
// then every font (see FontChoices). A tap sets every
// unlocked text selected, as one Undo, and the sheet stays up to try
// another; for the brand kit it chooses a face, None first, and closes.
// Opened from the typing bar's Aa it sets the words chosen instead, under a
// note that says so, as the colour sheet does for their colour; the box's
// own face gives them back to it — and then the Weight row and an Italic
// toggle set those words alone, each reading Mixed where they differ
// (DesignStore.weightWords, italicWords). The Android twin's FontSheet, in
// the same words. Choosing for the texts selected, the Weight row comes
// first: Light to Black, the weights their fonts have, each named in the
// face at that weight, as the Android twin's Text panel has it under Font.

import SwiftUI
import UniformTypeIdentifiers

struct FontSheet: View {
    @Bindable var store: DesignStore
    /// Set when the sheet chooses for something other than the texts
    /// selected — the brand kit's faces.
    var choice: Choice? = nil
    /// Set when the sheet chooses for the words chosen while typing
    /// (DesignStore.wordFontTarget).
    var words = false
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category = FontLibrary.allCategories
    @State private var own: [Uploads.FontEntry] = []
    @State private var recent: [String] = []
    @State private var kit = BrandKit()
    @State private var addingFont = false
    @State private var adding = false
    /// Why the font last picked could not be added, in the picker's words.
    @State private var problem: String?

    /// A face chosen for something else: the sheet's title, the face it has
    /// now (nil for none) and what to do with the one picked.
    struct Choice {
        var title: String
        var current: String?
        var onPick: (String?) -> Void
    }

    /// The font in use: the one every text selected shares — an old name
    /// counting as the family it means, and none ticked when they differ —
    /// or the face being chosen.
    private var chosen: String? {
        if let choice { return choice.current.map { listed($0) } }
        if words { return store.wordFont.map { listed($0) } }
        return store.sharedText { listed($0.fontFamily) }
    }

    /// A stored key as the picker lists it: the family it means, a font of
    /// your own as its family's Regular face.
    private func listed(_ key: String?) -> String {
        FontStore.familyKey(FontLibrary.resolve(key), in: store.design)
    }

    var body: some View {
        let browsing = FontChoices.isBrowsing(query: query, category: category)
        NavigationStack {
            List {
                if words {
                    Section {
                        Text(DesignStore.wordFontNote)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                if choice == nil && !words {
                    weightRow
                }
                if words {
                    wordsFaceRows
                }
                Section { categoryChips }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                if browsing {
                    if choice != nil {
                        Section { row(nil) }
                    }
                    ForEach(FontChoices.browsing(kit: kit, recent: recent, design: store.design)) { section in
                        Section(section.title) {
                            ForEach(section.keys, id: \.self) { row($0) }
                        }
                    }
                    yourFonts
                    Section(FontChoices.allTitle) {
                        ForEach(FontLibrary.all) { row($0.id) }
                    }
                } else {
                    let found = FontChoices.found(query: query, category: category, own: own)
                    Section {
                        if found.isEmpty {
                            Text(FontChoices.noneFound(query))
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(found, id: \.self) { row($0) }
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search fonts")
            .navigationTitle(choice?.title ?? tr("Fonts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .fileImporter(isPresented: $addingFont, allowedContentTypes: [.font]) { result in
            guard case .success(let url) = result else { return }
            add(url)
        }
        .onAppear {
            own = FontStore.installed()
            recent = RecentFonts.all()
            kit = BrandKit.load()
        }
    }

    /// "All" and the six categories, in the catalogue's order.
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach([FontLibrary.allCategories] + FontLibrary.categories, id: \.self) { name in
                    let selected = category == name
                    Button { category = name } label: {
                        // The catalogue's category, said in the app's words.
                        Text(tr(name))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selected ? Theme.accent : Theme.card, in: Capsule())
                            .foregroundStyle(selected ? Color.white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// The weights the texts selected can take (TypeReadouts.weights), each
    /// named in the first one's font at that weight, the one they are drawn
    /// at chosen — its name in the title, or Mixed. A tap sets every
    /// unlocked text selected to it, as one Undo, each measured again; the
    /// sheet stays up. No row for texts only in fonts of your own, each one
    /// face, drawn at its own weight.
    @ViewBuilder
    private var weightRow: some View {
        let texts = store.textsRead
        let weights = TypeReadouts.weights(texts)
        if !weights.isEmpty {
            let font = texts.first(where: TypeReadouts.isWeighable)?.fontFamily ?? "sans"
            let drawn = TypeReadouts.drawnWeight(texts)
            Section("Weight: \(TypeReadouts.weightReadout(texts))") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(weights, id: \.self) { weight in
                            weightChip(weight, font: font, chosen: weight == drawn)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
    }

    /// The selected words' Weight row — the cuts their font has, each named
    /// in that font at that weight, the one they share chosen, "Weight:
    /// Mixed" where they differ — and the Italic toggle, on when every word
    /// is slanted, Mixed when some are, as the Android twin's WordsFaceRows.
    @ViewBuilder
    private var wordsFaceRows: some View {
        let font = store.wordFont ?? "sans"
        let weights = FontLibrary.weights(font)
        let weight = store.wordWeight
        let italic = store.wordItalic
        let readout = weight.map(FontLibrary.weightName) ?? TypeReadouts.mixed
        Section(tr("Weight: %@", readout)) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(weights, id: \.self) { cut in
                        weightChip(cut, font: font, chosen: cut == weight, pick: { store.weightWords(cut) })
                    }
                    italicChip(italic)
                }
                .padding(.vertical, 4)
            }
        }
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets())
    }

    /// The Italic toggle for the selected words: on, off, or Mixed.
    private func italicChip(_ italic: Bool?) -> some View {
        let on = italic == true
        let label = italic == nil ? tr("Italic: %@", TypeReadouts.mixed) : tr("Italic")
        let state = italic.map { $0 ? tr("On") : tr("Off") } ?? TypeReadouts.mixed
        return Button { store.italicWords(!on) } label: {
            Text(label)
                .font(.subheadline.weight(.medium).italic())
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityValue(state)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// One weight, its name drawn at it in `font`; a tap sets every
    /// unlocked text selected to it, or does `pick`.
    private func weightChip(_ weight: Int, font: String, chosen: Bool, pick: (() -> Void)? = nil) -> some View {
        Button { if let pick { pick() } else { store.setFontWeight(weight) } } label: {
            Text(FontLibrary.weightName(weight))
                .font(FontLibrary.font(family: font, size: 15, weight: weight, italic: false))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(chosen ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(chosen ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The fonts of your own on this phone, a family a row with how many
    /// weights it has, newest first, and the row that adds another — with
    /// what was wrong with the last one, if anything.
    private var yourFonts: some View {
        Section(FontChoices.yoursTitle) {
            ForEach(CustomFonts.families(own)) { family in
                row(family.key, weights: family.weights.count)
            }
            Button { addingFont = true } label: {
                HStack {
                    Label(CustomFonts.addTitle, systemImage: "plus")
                    if adding {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(adding)
            if let problem {
                Text(problem)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    /// One font, its name in its own face — None for nil — ticked when it is
    /// the one in use; one of your own not on this phone says Missing, and
    /// a family of yours how many weights it has.
    private func row(_ key: String?, weights: Int? = nil) -> some View {
        let name = key.map { FontStore.displayName($0, in: store.design) } ?? tr("None")
        let missing = key.flatMap { FontStore.missingNote($0, in: store.design) } != nil
        let ticked = key == chosen
        let count = weights.map(CustomFonts.weightCount)
        let said: String = key == nil ? tr("No font")
            : missing ? tr("%@ font, missing", name) : tr("%@ font", name)
        let spoken = count.map { "\(said), \($0)" } ?? said
        return Button { pick(key) } label: {
            HStack {
                Text(name)
                    .font(key.map { FontLibrary.font(family: $0, size: 20, weight: 400, italic: false) } ?? .body)
                    .lineLimit(1)
                Spacer()
                if let count {
                    Text(count)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if missing {
                    Text("Missing")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.red)
                }
                if ticked {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(spoken)
        .accessibilityAddTraits(ticked ? .isSelected : [])
    }

    /// The face picked: the brand kit's, which closes the sheet, the words
    /// chosen while typing, or every unlocked text selected and a shape's
    /// words, as one Undo. Either way
    /// it heads this phone's Recently used. Each box is measured again even
    /// when its face is unchanged, so a font of your own just added snaps
    /// its words out of Modern Sans's height.
    private func pick(_ key: String?) {
        if let key { RecentFonts.record(key) }
        if let choice {
            choice.onPick(key)
            dismiss()
            return
        }
        guard let key else { return }
        if words {
            store.fontWords(key)
            return
        }
        // A face for the whole box takes the faces chosen for its words away.
        store.updateSelected { el in
            guard ShapeText.carriesWords(el) else { return }
            el.setFontFamily(key)
            el.h = ShapeText.heightForWords(el)
        }
    }

    /// The .ttf or .otf picked, read and kept as a font of your own away
    /// from the main thread — checked, loaded as a face, stored once however
    /// often it is added — and then picked; or what was wrong with it, said.
    private func add(_ url: URL) {
        adding = true
        let store = self.store
        Task { @MainActor in
            let outcome = await Task.detached(priority: .userInitiated) { () -> Result<String, CustomFonts.Problem> in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                // Too big is known from the size, before a byte is read.
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size <= CustomFonts.maxBytes else { return .failure(.tooBig) }
                guard let data = try? Data(contentsOf: url) else { return .failure(.notAFont) }
                return FontStore.add(data)
            }.value
            adding = false
            own = FontStore.installed()
            switch outcome {
            case .success(let key):
                problem = nil
                store.buzz(.confirm)
                pick(key)
            case .failure(let refusal):
                problem = refusal.message
                store.buzz(.reject)
            }
        }
    }
}
