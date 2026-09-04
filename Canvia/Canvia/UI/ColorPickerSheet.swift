// Choosing a colour.
//
// Everything a colour decision needs in one place: the system picker, the
// colours this person used recently, the colours already in the document,
// companions derived from whatever is chosen, and the default swatches.
//
// It stays open while you compare. Comparing three colours used to mean three
// open/scroll/tap/dismiss cycles; Done is right there in the toolbar when the
// choice is made.

import SwiftUI
import UIKit

struct ColorPickerSheet: View {
    @Bindable var store: DesignStore
    var title: String
    var current: String?
    var allowGradients = false
    var onPick: (String) -> Void
    var onPickGradient: ((Paint) -> Void)?
    /// Continuous variant for the system ColorPicker, which updates its
    /// binding on every drag tick; falls back to onPick when absent.
    var onPickTransient: ((String) -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var custom = Color.white
    /// Read once when the sheet opens: the picture does not change while it
    /// is up, and the body runs on every tick of the colour wheel.
    @State private var photoColors: [String] = []

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ColorPicker("Custom color", selection: $custom, supportsOpacity: false)
                        .onChange(of: custom) {
                            let hex = UIColor(custom).hexString
                            if let onPickTransient { onPickTransient(hex) } else { onPick(hex) }
                        }
                        // Recorded when the picker closes, not on every drag
                        // tick: a slow sweep through the colour wheel would
                        // otherwise fill the recents with eighteen shades of
                        // the same green.
                        .onDisappear { RecentColors.record(UIColor(custom).hexString) }

                    // Recents first: the colour you used thirty seconds ago is
                    // the one you are most likely to want again, and it was
                    // previously three taps away in the system picker.
                    let recents = RecentColors.all
                    if !recents.isEmpty {
                        section("Recent", colors: recents)
                    }

                    let docColors = ColorTools.documentColors(store.design)
                    if !docColors.isEmpty {
                        section("Document colors", colors: docColors)
                    }

                    // The photo's own colours, when there is a photo: the
                    // selected picture, or the page's background picture. A
                    // caption over a photo in a colour from the photo is the
                    // whole trick of making the two look like one design.
                    if !photoColors.isEmpty {
                        section("From the photo", colors: photoColors)
                    }

                    harmonySection

                    section("Default colors", colors: ContentLibrary.defaultSwatches)

                    if allowGradients, let onPickGradient {
                        Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ContentLibrary.gradients) { preset in
                                Button {
                                    onPickGradient(preset.paint)
                                } label: {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(gradientFill(preset))
                                        .frame(height: 40)
                                }
                            }
                        }
                    }

                    if allowGradients, let onPickGradient {
                        patternsSection(onPickGradient)
                        photoFillSection(onPickGradient)
                    }

                    ForEach(ContentLibrary.palettes) { palette in
                        section(palette.name, colors: palette.colors)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .onAppear { photoColors = photoPalette }
        // Continuous picking runs through transient updates; record the whole
        // session as one undo step however the sheet closes.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    /// Companions for whatever is currently chosen. Picking a second colour
    /// that goes with the first is the hardest part of making something look
    /// designed, and it is the part arithmetic can actually do.
    @ViewBuilder
    private var harmonySection: some View {
        let seed = current ?? UIColor(custom).hexString
        Text("Goes with \(seed)")
            .font(.footnote.weight(.bold))
            .foregroundStyle(.secondary)
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ColorHarmony.allCases) { kind in
                HStack(spacing: 8) {
                    Text(kind.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 92, alignment: .leading)
                    ForEach(Array(ColorTheory.harmony(kind, from: seed).enumerated()), id: \.offset) { _, hex in
                        Button { choose(hex) } label: {
                            RoundedRectangle(cornerRadius: 7)
                                .fill(Color(hex: hex))
                                .frame(height: 30)
                                .overlay(RoundedRectangle(cornerRadius: 7)
                                    .stroke(Theme.hairline, lineWidth: 1))
                        }
                        .accessibilityLabel("\(kind.displayName) \(hex)")
                    }
                }
            }
        }
    }

    /// Six patterns in the current colour over white. Tap one to fill with
    /// it; the colour swatches above keep working on it afterwards, since a
    /// pattern's foreground is the paint's colour.
    private func patternsSection(_ pick: @escaping (Paint) -> Void) -> some View {
        let ink = current ?? UIColor(custom).hexString
        return VStack(alignment: .leading, spacing: 8) {
            Text("Patterns").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Patterns.names, id: \.self) { name in
                    let paint = Paint.pattern(name, color: ink, secondary: "#ffffff", scale: 12)
                    Button { pick(paint) } label: {
                        PatternFill(paint: paint)
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
                    }
                    .accessibilityLabel("\(Patterns.displayName(name)) pattern")
                }
            }
        }
    }

    /// The library's photos, and any the document already uses, as fills.
    private func photoFillSection(_ pick: @escaping (Paint) -> Void) -> some View {
        var sources = PhotoLibrary.photos.prefix(8).map { "asset:\($0.id)" }
        for page in store.design.pages {
            for el in page.elements where el.type == .image {
                if let src = el.src, !sources.contains(src) { sources.append(src) }
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            Text("Photo fill").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sources, id: \.self) { src in
                    Button { pick(.image(src)) } label: {
                        Group {
                            if let ui = PhotoLibrary.resolve(src) {
                                Image(uiImage: PhotoLibrary.preview(ui, key: src))
                                    .resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Color(.systemGray5)
                            }
                        }
                        .frame(height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .accessibilityLabel("Fill with photo")
                }
            }
        }
    }

    private var photoPalette: [String] {
        let src: String?
        if let el = store.singleSelection, el.type == .image {
            src = el.src
        } else if case .image(let background) = store.page.background {
            src = background
        } else {
            return []
        }
        guard let src, let image = PhotoLibrary.resolve(src) else { return [] }
        return PhotoPalette.extract(from: image)
    }

    /// One place every swatch tap goes through, so nothing can pick a colour
    /// without it landing in the recents.
    private func choose(_ hex: String) {
        RecentColors.record(hex)
        onPick(hex)
    }

    private func gradientFill(_ preset: GradientPreset) -> LinearGradient {
        let pts = preset.paint.unitPoints
        return LinearGradient(
            stops: preset.stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
            startPoint: pts.start, endPoint: pts.end)
    }

    private func section(_ title: String, colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(colors, id: \.self) { hex in
                    Button {
                        // Stay open. Comparing three colours used to mean
                        // three open/scroll/tap/dismiss cycles; Done is right
                        // there in the toolbar when the choice is made.
                        choose(hex)
                    } label: {
                        RoundedRectangle(cornerRadius: 9)
                            .fill(Color(hex: hex))
                            .overlay(RoundedRectangle(cornerRadius: 9)
                                .stroke(Color.black.opacity(0.12)))
                            .frame(height: 40)
                            .overlay {
                                if current?.lowercased() == hex.lowercased() {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.bold)
                                        .foregroundStyle(UIColor(hex: hex).isLight ? .black : .white)
                                }
                            }
                    }
                }
            }
        }
    }
}
