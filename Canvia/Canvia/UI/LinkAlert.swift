// The link prompt, one for an element — the Link button on its bar — and for
// words chosen while typing — the typing bar's Link: a web address, an email
// or a phone number typed as people type them and read as the Android twin
// reads them (see Links), Save off while what is typed reads as none, and
// Remove when there is a link to take off. Below, "Pages in this design":
// each page, its thumbnail and its name, a tap linking to it — by the page's
// own id, so moving pages keeps the link on its page. A link to a page since
// deleted says "Page removed".

import SwiftUI

extension View {
    /// Asks for a link while `isPresented`, starting from `draft`; `onSave`
    /// gets the link to set, or nil to take it off. With `design`, its
    /// pages are offered too.
    func linkAlert(isPresented: Binding<Bool>, draft: Binding<String>, linked: Bool, design: Design? = nil,
                   onSave: @escaping (String?) -> Void) -> some View {
        modifier(LinkAlert(isPresented: isPresented, draft: draft, linked: linked, design: design, onSave: onSave))
    }
}

struct LinkAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var draft: String
    var linked: Bool
    var design: Design?
    var onSave: (String?) -> Void

    func body(content: Content) -> some View {
        content.sheet(isPresented: $isPresented) {
            LinkSheet(draft: draft, linked: linked, design: design) { url in
                isPresented = false
                onSave(url)
            } onCancel: {
                isPresented = false
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// Whether something is typed that does not read as a link. Nothing at
    /// all is fine: saving it takes the link off.
    static func unreadable(_ draft: String, in design: Design? = nil) -> Bool {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && Links.normalized(typed, in: design) == nil
    }
}

/// The sheet itself: the address field, and the design's pages to link to.
struct LinkSheet: View {
    /// The link as stored when the sheet opened.
    let draft: String
    var linked: Bool
    var design: Design?
    var onSave: (String?) -> Void
    var onCancel: () -> Void
    /// What is typed: the stored address, or nothing for a page link, which
    /// the pages below show.
    @State private var typed: String

    init(draft: String, linked: Bool, design: Design?, onSave: @escaping (String?) -> Void,
         onCancel: @escaping () -> Void) {
        self.draft = draft
        self.linked = linked
        self.design = design
        self.onSave = onSave
        self.onCancel = onCancel
        _typed = State(initialValue: Links.pageId(draft) == nil ? draft : "")
    }

    var body: some View {
        NavigationStack {
            Form {
                addressSection
                if let design, !design.pages.isEmpty { pagesSection(design) }
            }
            .navigationTitle(linked ? tr("Edit link") : tr("Link"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: onCancel)
        }
        ToolbarItem(placement: .confirmationAction) {
            // Save is off while what is typed reads as no link, as the
            // Android twin's Done is, and the words below say why.
            Button("Save") { save() }
                .disabled(LinkAlert.unreadable(typed, in: design))
        }
    }

    private var addressSection: some View {
        Section {
            TextField("canvia.app", text: $typed)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if let design, Links.isDangling(draft, in: design) {
                Label("Page removed", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            if linked {
                Button("Remove", role: .destructive) { onSave(nil) }
            }
        } footer: {
            Text(LinkAlert.unreadable(typed, in: design)
                 ? tr("That doesn't read as a link. Try a web address like canvia.app, an email address or a phone number.")
                 : tr("A web address, email or phone number. Clickable in a PDF, and opened by a tap in Present."))
        }
    }

    private func pagesSection(_ design: Design) -> some View {
        Section("Pages in this design") {
            ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, page in
                pageRow(design, index: index, page: page)
            }
        }
    }

    /// A page to link to: its thumbnail, from the thumbnail cache, and its
    /// name — "Page 3 · Pricing" — ticked when it is the link now.
    private func pageRow(_ design: Design, index: Int, page: Page) -> some View {
        let link = Links.pageLink(page.id)
        let size = design.size(for: page)
        let aspect = size.height > 0 ? min(max(size.width / size.height, 0.5), 2) : 1
        let chosen = Links.pageId(draft) == page.id && typed.isEmpty
        return Button {
            onSave(link)
        } label: {
            HStack(spacing: 12) {
                PageThumbnail(design: design, page: page, pixelWidth: 96)
                    .frame(width: 40 * aspect, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                Text(PageTitles.named(index + 1, title: page.title))
                    .foregroundStyle(Color.primary)
                Spacer()
                if chosen { Image(systemName: "checkmark").foregroundStyle(Theme.accent) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Links.spoken(link, in: design) ?? PageTitles.named(index + 1, title: page.title))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }

    /// What was typed as a link; with nothing typed, a page link kept as it
    /// was, or none.
    private func save() {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            onSave(Links.pageId(draft) == nil ? nil : draft)
        } else if let url = Links.normalized(text, in: design) {
            onSave(url)
        }
    }
}

/// The typing bar's Link: the prompt, asked for the words the store was
/// asked to link (DesignStore.chooseWordLink), and its answer put on them as
/// one step. The words are held here as the prompt opens, so however the
/// alert orders its button's action and its closing, the answer lands.
struct WordLinkPrompt: ViewModifier {
    @Bindable var store: DesignStore
    @State private var target: WordRange?
    @State private var draft = ""
    @State private var asking = false

    func body(content: Content) -> some View {
        content
            .onChange(of: store.wordLinkTarget) { _, request in
                guard let request else { return }
                store.wordLinkTarget = nil
                target = request
                draft = store.sharedLink(of: request) ?? ""
                asking = true
            }
            .linkAlert(isPresented: $asking, draft: $draft, linked: linked, design: store.design) { url in
                if let target { store.linkWords(url, in: target) }
            }
    }

    private var linked: Bool {
        target.flatMap { store.sharedLink(of: $0) } != nil
    }
}
