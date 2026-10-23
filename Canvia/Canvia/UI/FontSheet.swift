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
//
// When the texts selected have letters past Latin's — Cyrillic, Greek,
// Vietnamese — a "Fonts for these letters" chip, on to begin with, lists
// only the fonts that have them all (FontLibrary.covers); any font that
// lacks some is marked, its letters to be drawn in a stand-in. A font In
// this design can be replaced everywhere it is used (FontSwap), and after
// a font is chosen for texts whose old font is used elsewhere too, Change
// all offers the same swap everywhere, for ten seconds, as the colour
// sheet does. Add a font… takes several files at once, a family's .zip
// or a collection among them, and says in one line what came of them.

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
    /// What adding the files last picked came to, in one line, and each
    /// file left out with why.
    @State private var problem: String?
    @State private var skippedFiles: [String] = []
    /// Only the fonts that have every letter of the texts selected, while
    /// they have letters past Latin's.
    @State private var lettersOnly = true
    /// The font In this design being replaced everywhere.
    @State private var replacing: Replacing?
    /// Change all, offered for ten seconds after a font is chosen.
    @State private var changeAll: ChangeAllOffer?

    private struct Replacing: Identifiable {
        var id: String
    }

    /// What Add a font… lets through: every font type the system knows,
    /// and a WOFF by its two MIME types and its extension — the Android
    /// twin's FONT_TYPES — which is unpacked as it is added (CustomFonts).
    static let fontTypes: [UTType] = [UTType.font, UTType.zip]
        + ["font/woff", "application/font-woff", "font/woff2", "font/collection"].compactMap { UTType(mimeType: $0) }
        + ["woff", "woff2", "ttc", "otc"].compactMap { UTType(filenameExtension: $0) }

    /// A face chosen for something else: the sheet's title, the face it has
    /// now (nil for none) and what to do with the one picked.
    struct Choice {
        var title: String
        var current: String?
        var onPick: (String?) -> Void
        /// Whether None is offered first.
        var none = true
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
        NavigationStack {
            fontList
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
        .fileImporter(isPresented: $addingFont, allowedContentTypes: Self.fontTypes,
                      allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result, !urls.isEmpty else { return }
            add(urls)
        }
        .sheet(item: $replacing) { target in replaceSheet(target.id) }
        // Change all goes after ten seconds, counted again from each pick.
        .task(id: changeAll) {
            guard changeAll != nil else { return }
            try? await Task.sleep(for: .seconds(ChangeAllOffer.seconds))
            if !Task.isCancelled { changeAll = nil }
        }
        .onAppear {
            own = FontStore.installed()
            recent = RecentFonts.all()
            kit = BrandKit.load()
        }
    }

    /// The sections: the note, the weights, the categories and the fonts.
    private var fontList: some View {
        let browsing = FontChoices.isBrowsing(query: query, category: category)
        let letters = self.letters
        return List {
            if words {
                Section {
                    Text(DesignStore.wordFontNote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            changeAllRow
            if choice == nil && !words {
                weightRow
            }
            if words {
                wordsFaceRows
            }
            Section { categoryChips }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            lettersChip(letters)
            if browsing {
                browsingSections(letters)
            } else {
                foundSection(letters)
            }
        }
    }

    /// Browsing: None for a face of something else, the brand kit's fonts,
    /// Recently used, Popular, In this design, Your fonts and every font.
    @ViewBuilder
    private func browsingSections(_ letters: String) -> some View {
        if choice?.none == true {
            Section { row(nil) }
        }
        ForEach(FontChoices.browsing(kit: kit, recent: recent, design: store.design)) { section in
            let keys = covering(section.keys, letters)
            if !keys.isEmpty {
                Section(section.title) {
                    ForEach(keys, id: \.self) { browsingRow($0, inDesign: section.title == FontChoices.inDesignTitle) }
                }
            }
        }
        yourFonts(letters)
        Section(FontChoices.allTitle) {
            ForEach(covering(FontLibrary.all.map(\.id), letters), id: \.self) { row($0) }
        }
    }

    /// What a search or a category finds, or the tags to try.
    private func foundSection(_ letters: String) -> some View {
        let found = covering(FontChoices.found(query: query, category: category, own: own), letters)
        return Section {
            if found.isEmpty {
                Text(FontChoices.noneFound(query))
                    .foregroundStyle(.secondary)
                tagChips
            } else {
                ForEach(found, id: \.self) { row($0) }
            }
        }
    }

    /// The letters the fonts are chosen for: the words of the texts
    /// selected, as they read — none when choosing a face for something
    /// else.
    private var letters: String {
        guard choice == nil else { return "" }
        return store.textsRead.map { RichText.strip($0.text ?? "") }.joined(separator: "\n")
    }

    /// `keys` less the fonts missing some of `letters`, while the chip asks
    /// for only those that have them all.
    private func covering(_ keys: [String], _ letters: String) -> [String] {
        guard lettersOnly, FontLibrary.needsMoreThanLatin(letters) else { return keys }
        return keys.filter { FontLibrary.covers($0, letters) }
    }

    /// "Fonts for these letters": while the texts selected have letters
    /// past Latin's, on to begin with, listing only the fonts with them all.
    @ViewBuilder
    private func lettersChip(_ letters: String) -> some View {
        if FontLibrary.needsMoreThanLatin(letters) {
            Section {
                Button { lettersOnly.toggle() } label: {
                    Label("Fonts for these letters", systemImage: lettersOnly ? "checkmark" : "character")
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(lettersOnly ? Theme.accent : Theme.card, in: Capsule())
                        .foregroundStyle(lettersOnly ? Color.white : Theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(lettersOnly ? .isSelected : [])
            }
            .listRowBackground(Color.clear)
        }
    }

    /// A font In this design has Replace everywhere… beside it, when the
    /// sheet chooses for the texts selected.
    @ViewBuilder
    private func browsingRow(_ key: String, inDesign: Bool) -> some View {
        if inDesign && choice == nil && !words {
            HStack {
                row(key)
                Menu {
                    Button { replacing = Replacing(id: key) } label: {
                        Label("Replace everywhere…", systemImage: "arrow.triangle.2.circlepath")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("More")
            }
            .buttonStyle(.borderless)
        } else {
            row(key)
        }
    }

    /// The picker in replace mode: the font chosen takes `from`'s place
    /// everywhere it is used, as one step.
    private func replaceSheet(_ from: String) -> some View {
        let name = FontStore.displayName(from, in: store.design)
        let pick: (String?) -> Void = { to in
            if let to { store.replaceFontEverywhere(from: from, to: to) }
        }
        return FontSheet(store: store, choice: Choice(title: tr("Replace %@ with", name), current: from,
                                                      onPick: pick, none: false))
    }

    /// Change all, while it is offered: the font just chosen everywhere
    /// the old one is used.
    @ViewBuilder
    private var changeAllRow: some View {
        if let offer = changeAll {
            Section {
                Button {
                    store.replaceFontEverywhere(from: offer.from, to: offer.to)
                    changeAll = nil
                } label: {
                    Label("Change all (\(offer.count))", systemImage: "textformat")
                }
            }
        }
    }

    /// "Try: elegant, retro, handwritten, rounded": the tags offered when a
    /// search finds nothing, each in the app's language, a tap filling the
    /// search with it, as on the Android twin.
    private var tagChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Text(FontChoices.tryTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                ForEach(FontLibrary.suggestedTags, id: \.self) { tag in
                    Button { query = FontLibrary.tagName(tag) } label: {
                        Text(FontLibrary.tagName(tag))
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Theme.card, in: Capsule())
                            .foregroundStyle(Theme.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
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
        let font = store.wordFace
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
    /// what came of the files last added, each left out said with why.
    private func yourFonts(_ letters: String) -> some View {
        let keys = Set(covering(CustomFonts.families(own).map(\.key), letters))
        return Section(FontChoices.yoursTitle) {
            ForEach(CustomFonts.families(own).filter { keys.contains($0.key) }) { family in
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
                    .foregroundStyle(skippedFiles.isEmpty ? Color.secondary : Color.red)
            }
            ForEach(skippedFiles, id: \.self) { line in
                Text(line)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        // A font missing some of the letters of the texts selected.
        let short = key.map { !FontLibrary.covers($0, letters) } ?? false
        let said: String = key == nil ? tr("No font")
            : missing ? tr("%@ font, missing", name) : tr("%@ font", name)
        let counted = count.map { "\(said), \($0)" } ?? said
        let spoken = short ? counted + ", " + Self.standInNote : counted
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
                if short {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityHidden(true)
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

    /// What a font that lacks some of the letters is said to do.
    static let standInNote = tr("Some letters will use a stand-in font")

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
        let old = chosen
        store.updateSelected { el in
            guard ShapeText.carriesWords(el) else { return }
            el.setFontFamily(key)
            ShapeText.fitWords(&el)
        }
        // The old font still used elsewhere: Change all, for a while.
        let left = old.map { $0 == listed(key) ? 0 : FontSwap.count(store.design, family: $0) } ?? 0
        changeAll = left > 0 ? old.map { ChangeAllOffer(from: $0, to: key, count: left) } : nil
    }

    /// The files picked — fonts, a family's .zip, a collection — read and
    /// kept as fonts of your own away from the main thread, each checked,
    /// loaded as a face and stored once however often it is added
    /// (FontStore.addPicked); what came of them said in one line, the files
    /// left out listed with why. One family added is picked.
    private func add(_ urls: [URL]) {
        adding = true
        let store = self.store
        Task { @MainActor in
            let imported = await Task.detached(priority: .userInitiated) { FontStore.addPicked(urls) }.value
            adding = false
            own = FontStore.installed()
            problem = imported.summary
            skippedFiles = imported.skipped
            store.buzz(imported.keys.isEmpty ? .reject : .confirm)
            if imported.families.count == 1, let first = imported.keys.first {
                pick(FontStore.familyKey(first, in: store.design))
            }
        }
    }
}
