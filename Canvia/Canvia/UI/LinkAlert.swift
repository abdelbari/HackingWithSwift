// The link prompt, one for an element — the Link button on its bar — and for
// words chosen while typing — the typing bar's Link: a web address, an email
// or a phone number typed as people type them and read as the Android twin
// reads them (see Links), Save off while what is typed reads as none, and
// Remove when there is a link to take off.

import SwiftUI

extension View {
    /// Asks for a link while `isPresented`, starting from `draft`; `onSave`
    /// gets the link to set, or nil to take it off.
    func linkAlert(isPresented: Binding<Bool>, draft: Binding<String>, linked: Bool,
                   onSave: @escaping (String?) -> Void) -> some View {
        modifier(LinkAlert(isPresented: isPresented, draft: draft, linked: linked, onSave: onSave))
    }
}

struct LinkAlert: ViewModifier {
    @Binding var isPresented: Bool
    @Binding var draft: String
    var linked: Bool
    var onSave: (String?) -> Void

    func body(content: Content) -> some View {
        content.alert(linked ? "Edit link" : "Link", isPresented: $isPresented) {
            TextField("canvia.app", text: $draft)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            // Save is off while what is typed reads as no link, as the
            // Android twin's Done is, and the message below says why: an
            // alert cannot ask again from its own button, so the typing was
            // being dropped without a word.
            Button("Save") { save() }
                .disabled(Self.unreadable(draft))
            if linked {
                Button("Remove", role: .destructive) { onSave(nil) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(Self.unreadable(draft)
                 ? "That doesn't read as a link. Try a web address like canvia.app, an email address or a phone number."
                 : "A web address, email or phone number. Clickable in a PDF, and opened by a tap in Present.")
        }
    }

    /// Whether something is typed that does not read as a link. Nothing at
    /// all is fine: saving it takes the link off.
    static func unreadable(_ draft: String) -> Bool {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !typed.isEmpty && Links.normalized(typed) == nil
    }

    /// What was typed as a link, or none when nothing was. Save is off for
    /// anything else, so there is nothing else to handle.
    private func save() {
        let typed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            onSave(nil)
        } else if let url = Links.normalized(typed) {
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
            .linkAlert(isPresented: $asking, draft: $draft, linked: linked) { url in
                if let target { store.linkWords(url, in: target) }
            }
    }

    private var linked: Bool {
        target.flatMap { store.sharedLink(of: $0) } != nil
    }
}
