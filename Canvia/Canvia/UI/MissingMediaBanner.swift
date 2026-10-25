// The editor's one line when a design opens with files missing
// (MissingMedia): "3 items are missing from this design", with Show — which
// selects the first, then steps through them — and Dismiss, which puts it
// away until the design changes (meta.json's "missingNoteDismissed", as the
// export sheet's accessibility row is put away). Under the top bar, where
// tips go, never over the page.

import SwiftUI

struct MissingMediaBanner: View {
    @Bindable var store: DesignStore
    /// What is gone, read as the design opens and again as it changes.
    @State private var items: [MissingMedia.Absent] = []
    @State private var dismissed: Int64?
    /// Which item Show is on; nil before Show.
    @State private var showing: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// The design's revision: when it last changed.
    private var revision: Int64 { Int64(store.design.updatedAt.rounded()) }

    /// What Show steps through: those on a page.
    private var onPages: [MissingMedia.Absent] { items.filter { $0.pageIndex >= 0 } }

    var body: some View {
        // A stack that is there even when empty, so its task runs.
        VStack(spacing: 0) {
            if !items.isEmpty && dismissed != revision { banner }
        }
        .task(id: revision) { await read() }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(MissingMedia.banner(items.count))
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if !onPages.isEmpty { stepper }
            Button("Dismiss") { dismiss() }
                .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.orange.opacity(0.14))
        .overlay(alignment: .bottom) { Divider() }
        .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
    }

    /// Show, then the one shown of how many, with the way back and on.
    @ViewBuilder
    private var stepper: some View {
        if let at = showing {
            Button { step(-1) } label: { Image(systemName: "chevron.backward") }
                .disabled(at == 0)
                .accessibilityLabel("Previous")
            Text(tr("%d of %d", at + 1, onPages.count))
                .font(.footnote.monospacedDigit())
            Button { step(1) } label: { Image(systemName: "chevron.forward") }
                .disabled(at >= onPages.count - 1)
                .accessibilityLabel("Next")
        } else {
            Button("Show") { go(to: 0) }
                .font(.footnote.weight(.semibold))
        }
    }

    private func step(_ delta: Int) {
        go(to: (showing ?? 0) + delta)
    }

    /// Item `index` selected on its page — a background by its page alone.
    private func go(to index: Int) {
        let list = onPages
        guard list.indices.contains(index) else { return }
        showing = index
        let item = list[index]
        store.reveal(elementId: item.kind == .background ? nil : item.elementId, onPage: item.pageIndex)
    }

    private func dismiss() {
        let rev = revision
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { dismissed = rev }
        DesignLibrary.dismissMissingNote(store.design.id, revision: rev)
    }

    /// What is gone, looked for off the main thread, and whether the line
    /// was put away at this revision.
    @MainActor
    private func read() async {
        let design = store.design
        dismissed = DesignLibrary.versionMeta(for: design.id).missingNoteDismissed
        let found = await Task.detached(priority: .utility) { MissingMedia.onThisPhone(design) }.value
        if found.count != items.count { showing = nil }
        items = found
    }
}
