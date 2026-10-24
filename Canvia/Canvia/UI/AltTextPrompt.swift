// Settings ▸ Accessibility's Ask for alt text: what a photo, graphic or
// chart just added shows, asked straight away (DesignStore.altTextPrompt) —
// Save keeps it as the element's alt text, as one step; Skip asks nothing
// more of it. The Android twin's AltTextPrompt.

import SwiftUI

struct AltTextPrompt: ViewModifier {
    @Bindable var store: DesignStore
    @State private var draft = ""

    func body(content: Content) -> some View {
        content
            .alert("Alt text", isPresented: Binding(get: { store.altTextPrompt != nil },
                                                    set: { if !$0 { store.answerAltTextPrompt("") } })) {
                TextField("What it shows", text: $draft)
                Button("Save") { answer(draft) }
                Button("Skip", role: .cancel) { answer("") }
            }
    }

    private func answer(_ text: String) {
        store.answerAltTextPrompt(text)
        draft = ""
    }
}
