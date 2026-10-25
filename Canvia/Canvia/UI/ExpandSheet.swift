// Expand, from crop mode: the photo grown to a new shape — the page's, 1:1,
// 4:5, 9:16 or 16:9 — round the picture it has, the new border filled by
// Blur, Mirror, Stretch or Fill (PhotoExpand), off the main thread with a
// ring while it is made, as one step (PhotoExpanding.swift). A photo
// expanded already offers Undo expand, and Change fill makes it again from
// its original in the fill chosen; once grown to the page's shape, Set as
// background. The Android twin's ExpandSheet; chips as crop mode's.

import SwiftUI

struct ExpandSheet: View {
    @Bindable var store: DesignStore
    let id: String
    @Environment(\.dismiss) private var dismiss
    @State private var ratio = PhotoExpand.page
    @State private var mode: String?

    private var photo: Element? { store.element(id) }
    private var origin: PhotoExpand.Origin? { photo?.expandedFrom }
    private var chosenMode: String { mode ?? origin?.mode ?? PhotoExpand.blur }
    private var usable: Bool { DesignStore.isStillPhoto(photo) && !store.expandBusy }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Grows the photo to a new shape and fills the new edges from the picture.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    ratioRow
                    modeRow
                    actions
                    if store.expandedToPage == id {
                        Button("Set as background") {
                            store.expandedAsBackground(id)
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding()
            }
            .navigationTitle("Expand")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    private var ratioRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Shape").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PhotoExpand.ratios, id: \.key) { choice in
                        chip(choice.key == PhotoExpand.page ? tr("Page") : choice.key, lit: ratio == choice.key) {
                            ratio = choice.key
                        }
                    }
                }
            }
        }
    }

    private var modeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Fill").font(.subheadline.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(PhotoExpand.modes, id: \.key) { choice in
                        chip(PhotoExpand.name(choice.key), lit: chosenMode == choice.key) { mode = choice.key }
                    }
                }
            }
        }
    }

    /// Undo expand and Change fill for a photo expanded already; the ring
    /// while a picture is made; and Expand.
    private var actions: some View {
        HStack(spacing: 12) {
            if origin != nil {
                Button("Undo expand") { store.undoExpand(id) }
                    .disabled(store.expandBusy)
                Button("Change fill") { store.changeExpandFill(id, mode: chosenMode) }
                    .disabled(!usable)
            }
            Spacer(minLength: 0)
            if store.expandBusy {
                ProgressView()
                    .accessibilityLabel("Expanding the photo")
            }
            Button("Expand") { store.expandPhoto(id, ratio: ratio, mode: chosenMode) }
                .fontWeight(.semibold)
                .buttonStyle(.borderedProminent)
                .disabled(!usable)
        }
    }

    private func chip(_ name: String, lit: Bool, _ pick: @escaping () -> Void) -> some View {
        Button(name, action: pick)
            .buttonStyle(.bordered)
            .tint(lit ? Theme.accent : .secondary)
            .controlSize(.small)
            .disabled(store.expandBusy)
            .accessibilityAddTraits(lit ? .isSelected : [])
    }
}
