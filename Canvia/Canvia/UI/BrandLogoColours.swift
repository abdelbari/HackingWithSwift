// The colours a logo suggests in the brand kit (PhotoPalette.logo): offered
// as chips once a logo is added, or from a logo's menu, 'Colours from this
// logo'. Each chip tapped goes into the palette chosen; 'Add as a palette'
// makes them a palette of their own, "<logo name> colours", whose source is
// the logo (BrandKit.addLogoPalette). The Android twin's LogoColourChips.

import SwiftUI

/// What a logo offers: the logo, its name as its file came in (nil for
/// none), and up to six colours.
struct LogoColours: Equatable {
    var src: String
    var name: String?
    var colors: [String]

    /// `src`'s colours, read from its pixels, and its name from the
    /// uploads, its extension dropped. The reading — the uploads list, the
    /// full-size decode, the 128-pixel redraw and the extraction — is done
    /// off the main actor, so the brand kit does not stall on a large logo,
    /// as on the Android twin. A library picture is drawn by the app, here,
    /// as DesignExporter draws one.
    @MainActor
    static func of(_ src: String) async -> LogoColours {
        let id = src.hasPrefix("media:") ? String(src.dropFirst("media:".count)) : src
        let drawn = src.hasPrefix("asset:") ? PhotoLibrary.resolve(src) : nil
        let read = await Task.detached(priority: .userInitiated) { () -> (name: String?, colors: [String]) in
            let file = Uploads.all().first { $0.id == id }?.fileName
            let name = file.map { ($0 as NSString).deletingPathExtension }.flatMap { $0.isEmpty ? nil : $0 }
            let colors = (drawn ?? PhotoLibrary.resolve(src)).map(PhotoPalette.logo(from:)) ?? []
            return (name, colors)
        }.value
        return LogoColours(src: src, name: read.name, colors: read.colors)
    }
}

/// The offer as a section of the brand kit's form: the chips, which palette
/// they go into, 'Add as a palette' and Done.
struct LogoColoursSection: View {
    let offer: LogoColours
    let kit: BrandKit
    /// A colour put into the palette at an index.
    let add: (String, Int) -> Void
    let addPalette: () -> Void
    let done: () -> Void
    @State private var target = 0

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 10)]

    /// The kit's palettes, or the one a first colour starts.
    private var palettes: [BrandPalette] {
        kit.palettes.isEmpty ? [BrandPalette(name: BrandKit.firstPaletteName, colors: [])] : kit.palettes
    }

    private var into: Int { min(max(target, 0), palettes.count - 1) }

    var body: some View {
        Section {
            if offer.colors.isEmpty {
                Text("No colours to take from this logo.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(offer.colors, id: \.self) { hex in chip(hex) }
                }
            }
            paletteMenu
            if !offer.colors.isEmpty {
                Button("Add as a palette", action: addPalette)
            }
            Button("Done", action: done)
        } header: {
            Text("Colours from this logo")
        }
    }

    /// Which palette a chip tapped goes into: the first to start.
    private var paletteMenu: some View {
        Menu {
            ForEach(palettes.indices, id: \.self) { index in
                Button {
                    target = index
                } label: {
                    if index == into { Label(palettes[index].name, systemImage: "checkmark") } else { Text(palettes[index].name) }
                }
            }
        } label: {
            Text("Add to \(palettes[into].name)")
        }
    }

    /// A colour, ticked once it is in the palette chosen.
    private func chip(_ hex: String) -> some View {
        let palette = palettes[into]
        let added = palette.colors.contains { $0.caseInsensitiveCompare(hex) == .orderedSame }
        let spoken = kit.spokenColour(hex)
        return Button { add(hex, into) } label: {
            Circle()
                .fill(Color(hex: hex))
                .overlay(Circle().stroke(added ? Color.accentColor : Theme.hairline, lineWidth: added ? 3 : 1))
                .overlay {
                    if added {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color(hex: DataGraphics.ink(for: Page(background: .color(hex)))))
                    }
                }
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.borderless)
        .disabled(added)
        .accessibilityLabel(added ? tr("%@, in %@", spoken, palette.name) : spoken)
        .accessibilityHint(tr("Add to %@", palette.name))
    }
}
