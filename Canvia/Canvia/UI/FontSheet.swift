// The font picker: a search by name (case and accents aside), the category
// chips, and each font a row drawn in its own face, the one in use ticked.
// Browsing, the brand kit's fonts come first, then Recently used on this
// phone (as the sheet opened), the fonts In this design, Your fonts with
// "Add a font…", and then every font (see FontChoices). A tap sets every
// unlocked text selected, as one Undo, and the sheet stays up to try
// another; for the brand kit it chooses a face, None first, and closes.
// Opened from the typing bar's Aa it sets the words chosen instead, under a
// note that says so, as the colour sheet does for their colour; the box's
// own face gives them back to it. The Android twin's FontSheet, in the same
// words.

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
        if let choice { return choice.current.map { FontLibrary.resolve($0) } }
        if words { return store.wordFont.map { FontLibrary.resolve($0) } }
        return store.sharedText { FontLibrary.resolve($0.fontFamily) }
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
            .navigationTitle(choice?.title ?? "Fonts")
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
                        Text(name)
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

    /// The fonts of your own on this phone, newest first, and the row that
    /// adds another — with what was wrong with the last one, if anything.
    private var yourFonts: some View {
        Section(FontChoices.yoursTitle) {
            ForEach(own, id: \.id) { row($0.key) }
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
    /// the one in use; one of your own not on this phone says Missing.
    private func row(_ key: String?) -> some View {
        let name = key.map { FontStore.displayName($0, in: store.design) } ?? "None"
        let missing = key.flatMap { FontStore.missingNote($0, in: store.design) } != nil
        let ticked = key == chosen
        let spoken: String = key == nil ? "No font" : missing ? "\(name) font, missing" : "\(name) font"
        return Button { pick(key) } label: {
            HStack {
                Text(name)
                    .font(key.map { FontLibrary.font(family: $0, size: 20, weight: 400, italic: false) } ?? .body)
                    .lineLimit(1)
                Spacer()
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
