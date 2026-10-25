// The editor opening a design where it was left, and keeping the place as
// it goes (LastPlace, DesignStore.rememberPlace): the page and the zoom
// brought back as it appears, and kept as a page is left, as the app goes
// into the background and as the editor closes. Deep links, pinned
// shortcuts and quick actions open through the same editor, so they come
// back to the same place.

import SwiftUI

struct KeepsPlace: ViewModifier {
    let store: DesignStore
    /// The place as the editor opened, before any page left rewrites it.
    @Binding var leftOff: LastPlace.Place?
    @State private var opened = false
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { firstAppear() }
            .onChange(of: store.pageIndex) { _, _ in store.rememberPlace() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { store.rememberPlace() }
            }
            .onDisappear { store.rememberPlace() }
    }

    /// Once, as the editor opens: the place it was left at kept for
    /// Present from where I left off, then the design opened there.
    private func firstAppear() {
        guard !opened else { return }
        opened = true
        leftOff = LastPlace.place(for: store.design.id)
        resume()
    }

    /// The page made current at once; a zoom other than fit asked of the
    /// canvas once it has laid out and fitted the page, as it does first.
    private func resume() {
        guard let zoom = store.resumePlace()?.zoom else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { store.requestCanvas(.zoom(zoom)) }
    }
}

/// A Doc's place: how far down its blocks the view was, brought back as it
/// opens by scrolling to the block that far down, and kept as the app goes
/// into the background and as the Doc closes.
struct KeepsDocPlace: ViewModifier {
    let store: DesignStore
    let blockIds: [String]
    @Binding var top: String?
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .onAppear { resume() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .background { remember() }
            }
            .onDisappear { remember() }
    }

    private func resume() {
        guard let scroll = store.resumePlace()?.scroll, !blockIds.isEmpty else { return }
        let index = min(Int((scroll * Double(blockIds.count)).rounded(.down)), blockIds.count - 1)
        top = blockIds[max(index, 0)]
    }

    private func remember() {
        let index = top.flatMap { blockIds.firstIndex(of: $0) } ?? 0
        store.rememberDocPlace(scroll: blockIds.isEmpty ? 0 : Double(index) / Double(blockIds.count))
    }
}
