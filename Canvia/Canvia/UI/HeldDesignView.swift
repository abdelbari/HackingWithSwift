// A design in one window, as DesignWindows rules: edited there when that
// window holds it; otherwise shown read-only, as the Android twin's
// HeldDesignView shows it.

import SwiftUI

/// A window's hold on a design, let go when the view keeping it goes for
/// good — not while a full-screen cover is over it (Present, a scan), as
/// the Android twin's DisposableEffect lets go only as its editor leaves.
private final class WindowHold {
    var held: (id: String, window: DesignWindows.Window)?

    deinit {
        if let held { DesignWindows.shared.close(held.id, in: held.window) }
    }
}

/// The editor `editor` makes for design `designId` when `window` holds it,
/// else the design read-only (HeldDesignView); let go as it closes.
struct WindowedDesign<Editor: View>: View {
    let designId: String
    let window: DesignWindows.Window
    let onClose: () -> Void
    @ViewBuilder let editor: () -> Editor
    @State private var editable: Bool?
    @State private var hold = WindowHold()

    var body: some View {
        // One container, so its appearing and going are the design's alone,
        // not each of the views it switches between.
        ZStack {
            if editable == true {
                editor()
            } else if editable == false {
                HeldDesignView(designId: designId, onClose: onClose)
            }
        }
        .onAppear {
            // Decided once, and held until this view goes for good, so a
            // full-screen cover over the editor keeps it this window's.
            guard editable == nil else { return }
            let mine = DesignWindows.shared.open(designId, in: window)
            if mine { hold.held = (designId, window) }
            editable = mine
        }
    }
}

/// A design another window is editing, shown here read-only: "Open in
/// another window" over its pages, each drawn as its thumbnail is, and a
/// way back. Nothing here writes to it.
struct HeldDesignView: View {
    let designId: String
    let onClose: () -> Void
    @State private var design: Design?

    var body: some View {
        VStack(spacing: 0) {
            header
            Text("Open in another window")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.accentColor.opacity(0.15))
            if let design {
                pages(design)
            } else {
                Spacer()
            }
        }
        .onAppear { design = DesignLibrary.load(id: designId) }
    }

    private var header: some View {
        HStack {
            Button(action: onClose) {
                Image(systemName: "xmark").frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("Close"))
            Text(design?.title ?? "")
                .font(.headline)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer()
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 56)
    }

    private func pages(_ design: Design) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(Array(design.pages.enumerated()), id: \.element.id) { index, page in
                    pagePicture(design, page: page)
                        .accessibilityElement()
                        .accessibilityLabel(tr("Page %d of %d", index + 1, design.pages.count))
                        .accessibilityAddTraits(.isImage)
                }
            }
            .padding(16)
        }
        // Left to right in every language, as the canvas is.
        .designDirection()
    }

    private func pagePicture(_ design: Design, page: Page) -> some View {
        let size = design.size(for: page)
        let ratio = min(max(size.width / max(size.height, 1), 0.2), 5)
        return PageThumbnail(design: design, page: page, pixelWidth: 600)
            .aspectRatio(ratio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .border(Color.secondary.opacity(0.3))
    }
}
