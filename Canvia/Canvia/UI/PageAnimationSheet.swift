// Page animations: every element on the page arriving, leaving or both, one
// after another in layer order (PageAnimation) — from More, or the hold
// menu's Animate, with nothing selected. A tile picks its kind and plays the
// page to show it; Enter, Exit and Both say when; Remove from page takes it
// off. An element's own animation is kept over the page's. As the Android
// twin's Page animations.

import SwiftUI

struct PageAnimationSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    /// When the elements move: picked before a kind, kept for the next tile.
    @State private var mode = PageAnimation.enter
    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    private var current: PageAnimation? { store.page.pageAnimation }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    modePicker
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(PageAnimation.kinds, id: \.self) { kind in tile(kind) }
                    }
                    if current != nil { removeButton }
                    Text("Each element on the page moves in turn. An element's own animation is kept.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
            .navigationTitle("Page animations")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear { mode = current?.mode ?? PageAnimation.enter }
    }

    /// Enter, Exit or Both; changing it changes the page's animation when it
    /// has one.
    private var modePicker: some View {
        Picker("When", selection: Binding(get: { mode }, set: { pick($0) })) {
            ForEach(PageAnimation.modes, id: \.self) { Text(PageAnimation.modeName($0)).tag($0) }
        }
        .pickerStyle(.segmented)
    }

    private func tile(_ kind: String) -> some View {
        let chosen = current?.kind == kind
        return Button {
            play(PageAnimation(kind: kind, mode: mode))
        } label: {
            VStack(spacing: 6) {
                Image(systemName: Self.symbol(kind))
                    .font(.title2)
                    .frame(height: 30)
                Text(PageAnimation.name(kind))
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 76)
            .background(RoundedRectangle(cornerRadius: 12).fill(chosen ? Theme.accentSubtle : Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(chosen ? Theme.accent : Theme.hairline,
                                                                lineWidth: chosen ? 2 : 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var removeButton: some View {
        Button(role: .destructive) {
            store.stopPreview()
            store.setPageAnimation(nil)
        } label: {
            Label("Remove from page", systemImage: "xmark.circle")
                .frame(maxWidth: .infinity)
                .padding(10)
        }
    }

    /// A mode picked: kept for the next tile, and given to the page's
    /// animation when it has one.
    private func pick(_ next: String) {
        mode = next
        guard var animation = current, animation.mode != next else { return }
        animation.mode = next
        play(animation)
    }

    /// `animation` given to the page, as one step, and the page played to
    /// show it — from where its exits begin, for one that only leaves.
    private func play(_ animation: PageAnimation) {
        store.setPageAnimation(animation)
        guard store.page.pageAnimation == animation else { return }
        store.playPreview(from: animation.enters ? 0 : store.exitPreviewStart)
    }

    /// Each kind's tile picture.
    static func symbol(_ kind: String) -> String {
        switch kind {
        case "rise": return "arrow.up.square"
        case "fade": return "circle.lefthalf.filled"
        case "pan": return "arrow.left.square"
        case "breathe": return "lungs"
        case "tumble": return "arrow.counterclockwise.square"
        case "stomp": return "arrow.down.to.line"
        default: return "sparkles"
        }
    }
}
