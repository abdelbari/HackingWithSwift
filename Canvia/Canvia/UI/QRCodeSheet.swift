// A code's words changed where it sits: the same size, place, turn and
// frame, a new code. The Android twin's "QR code" field in its photo panel.
//
// The code on the page follows the typing, keeping the last one that could
// be made while the field is empty or holds more than a code carries, and
// the whole edit is one Undo however much was typed.

import SwiftUI

struct QRCodeSheet: View {
    let store: DesignStore
    let id: String
    @State private var draft: String
    @Environment(\.dismiss) private var dismiss

    init(store: DesignStore, id: String, payload: String) {
        self.store = store
        self.id = id
        _draft = State(initialValue: payload)
    }

    var body: some View {
        let problem = CodeGenerator.problem(with: draft)
        NavigationStack {
            Form {
                Section {
                    // One line, unless a payload from elsewhere (a contact
                    // card, say) runs to several — then all of it shows.
                    TextField("Link or text", text: $draft, axis: .vertical)
                        .lineLimit(1...5)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityHint(problem ?? "")
                } header: {
                    Text("QR code")
                } footer: {
                    Text(problem ?? "The code on the page changes as you type.")
                        .foregroundStyle(problem == nil ? Color.secondary : Color(.systemRed))
                }
            }
            .navigationTitle("Edit code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
        .onChange(of: draft) { _, text in
            guard CodeGenerator.problem(with: text) == nil else { return }
            let source = CodeGenerator.source(for: text)
            guard store.element(id)?.src != source else { return }
            store.updateSelectedTransient { el in
                if el.id == id { el.src = source }
            }
        }
        // However it closes, the typing is one step.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }
}
