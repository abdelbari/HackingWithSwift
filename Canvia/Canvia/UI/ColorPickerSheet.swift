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
    /// A line over the choices saying what they will colour, when that is
    /// not the whole of what is selected — the words chosen in a text box.
    var note: String? = nil
    var allowGradients = false
    /// Patterns and photo fills, which only a shape draws.
    var allowPatterns = false
    /// The fill there now, when it is a gradient, a pattern or a photo, so
    /// its tile is ringed and tapping it again records nothing.
    var currentPaint: Paint?
    var onPick: (String) -> Void
    var onPickGradient: ((Paint) -> Void)?
    /// Continuous variant for the system ColorPicker, which updates its
    /// binding on every drag tick; falls back to onPick when absent.
    var onPickTransient: ((String) -> Void)?
    /// Offer the selection's own colours as swatches, when it has two or
    /// more, each changed on its own (see ColourSwap).
    var swapsColours = false
    @Environment(\.dismiss) private var dismiss
    /// The selection's colour being changed, as it is now; nil changes the
    /// whole selection as before.
    @State private var swapTarget: String?
    /// That colour as it was when the open step began, which every tick of
    /// the wheel swaps from.
    @State private var swapFrom: String?
    /// That colour as it was when its swatch was tapped: what Change all
    /// looks for across the design.
    @State private var swapOrigin: String?
    /// Change all, offered for ten seconds after a swap.
    @State private var changeAll: ChangeAllOffer?
    @State private var custom = Color.white
    /// Read once when the sheet opens: the picture does not change while it
    /// is up, and the body runs on every tick of the colour wheel.
    @State private var photoColors: [String] = []
    @State private var eyedropping = false
    @State private var gradientKind = "linear"

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Group {
                        if let note {
                            Text(note)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        swapRow
                        ColorPicker("A colour of your own", selection: $custom, supportsOpacity: false)
                            .onChange(of: custom) { pickLive(UIColor(custom).hexString) }
                            // Recorded when the picker closes, not on every drag
                            // tick: a slow sweep through the colour wheel would
                            // otherwise fill the recents with eighteen shades of
                            // the same green.
                            .onDisappear { RecentColors.record(UIColor(custom).hexString) }
                    }

                    // Recents first: the colour you used thirty seconds ago is
                    // the one you are most likely to want again, and it was
                    // previously three taps away in the system picker.
                    Group {
                        Button {
                            eyedropping = true
                        } label: {
                            Label("Pick from the page", systemImage: "eyedropper")
                                .frame(maxWidth: .infinity)
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
                        }
                        .sheet(isPresented: $eyedropping) {
                            EyedropperSheet(design: store.design, page: store.page) { hex in choose(hex) }
                        }

                        // The active brand kit's palettes, each by name.
                        let kit = BrandKit.load()
                        ForEach(Array(kit.palettes.enumerated()), id: \.offset) { _, palette in
                            if !palette.colors.isEmpty {
                                section(kit.title(of: palette), colors: palette.colors)
                            }
                        }
                    }

                    let recents = RecentColors.all
                    if !recents.isEmpty {
                        section(tr("Recent"), colors: recents)
                    }

                    let docColors = ColorTools.documentColors(store.design)
                    if !docColors.isEmpty {
                        section(tr("In this design"), colors: docColors)
                    }

                    // The colours of the photos on the page — every one, the
                    // background too, whatever is selected. A caption over a
                    // photo in a colour from the photo is the whole trick of
                    // making the two look like one design.
                    Group {
                        if !photoColors.isEmpty {
                            section(tr("From the photos"), colors: photoColors)
                        }

                        // The palette that best covers what is on the page
                        // already, as the Android twin suggests it — a second
                        // colour that belongs is the hard part.
                        if let suggested = ColorTools.suggestedPalette(for: store.page) {
                            section(tr("Goes with these · %@", suggested.name), colors: suggested.colors)
                        }
                    }

                    harmonySection

                    section(tr("Default colours"), colors: ContentLibrary.defaultSwatches)

                    if allowGradients, swapTarget == nil, let onPickGradient {
                        Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        Picker("Gradient shape", selection: $gradientKind) {
                            Text("Linear").tag("linear")
                            Text("Radial").tag("radial")
                            Text("Angular").tag("angular")
                        }
                        .pickerStyle(.segmented)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ContentLibrary.gradients) { preset in
                                gradientTile(preset, pick: onPickGradient)
                            }
                        }
                    }

                    if allowGradients, allowPatterns, swapTarget == nil, let onPickGradient {
                        patternsSection(onPickGradient)
                        photoFillSection(onPickGradient)
                    }

                    // By position: the library repeats a few palette ids, and
                    // ForEach needs each row to be told apart.
                    ForEach(Array(ContentLibrary.palettes.enumerated()), id: \.offset) { _, palette in
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
        .onAppear {
            if currentPaint?.kind == "gradient" { gradientKind = GradientPreset.kind(of: currentPaint) }
        }
        // Read again when the page's photos change; the pictures load here
        // and their colours are read off the main thread.
        .task(id: PhotoPalette.sources(on: store.page)) {
            let pictures = Array(PhotoPalette.sources(on: store.page).lazy
                .compactMap { PhotoLibrary.resolve($0) }.prefix(4))
            let colours = await Task.detached(priority: .userInitiated) {
                PhotoPalette.fromPhotos(pictures)
            }.value
            photoColors = colours
        }
        // Continuous picking runs through transient updates; record the whole
        // session as one undo step however the sheet closes.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
        // Change all goes after ten seconds, counted again from each swap.
        .task(id: changeAll) {
            guard changeAll != nil else { return }
            try? await Task.sleep(for: .seconds(ChangeAllOffer.seconds))
            if !Task.isCancelled { changeAll = nil }
        }
    }

    /// The colour the swatches ring: the one being changed, else the one
    /// there now.
    private var shownCurrent: String? { swapTarget ?? current }

    /// The selection's colours, one swatch each, when it has two or more:
    /// tapping one makes it the colour every pick below changes, and
    /// tapping it again goes back to colouring the whole selection. After
    /// a swap, Change all offers the same swap everywhere else in the
    /// design.
    @ViewBuilder
    private var swapRow: some View {
        let colours = swapsColours
            ? ColourSwap.colours(store.selectedElements.filter(ColourSwap.takesSwap)) : []
        if colours.count >= 2 || (swapsColours && swapTarget != nil) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Colours in selection").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(colours, id: \.self) { hex in swapSwatch(hex) }
                    }
                    .padding(4)
                }
                if let offer = changeAll {
                    Button {
                        store.swapColourEverywhere(from: offer.from, to: offer.to)
                        swapFrom = swapTarget
                        changeAll = nil
                    } label: {
                        Label("Change all (\(offer.count))", systemImage: "paintbrush")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Theme.accentSubtle))
                    }
                    .transition(.opacity)
                }
            }
        }
    }

    private func swapSwatch(_ hex: String) -> some View {
        let chosen = swapTarget == hex
        return Button {
            // A step left open by the wheel is kept before the target moves,
            // so the next swap starts from the colours as they now are.
            if store.hasPendingChanges { store.commit() }
            swapTarget = chosen ? nil : hex
            swapFrom = swapTarget
            swapOrigin = swapTarget
            changeAll = nil
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.hairline))
                .overlay { if chosen { Circle().stroke(Theme.accent, lineWidth: 3).padding(-4) } }
        }
        // Named in words, as every swatch is.
        .accessibilityLabel(ElementNames.spokenColour(hex))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A colour from the wheel, live: the target's swap while one is
    /// chosen, else the sheet's own transient pick.
    private func pickLive(_ hex: String) {
        if swapTarget != nil, let from = swapFrom {
            store.swapSelectionColourTransient(from: from, to: hex)
            swapTarget = Self.swatchKey(hex)
            offerChangeAll(to: hex)
        } else if let onPickTransient {
            onPickTransient(hex)
        } else {
            onPick(hex)
        }
    }

    /// A colour as the selection's swatches name it: lowercase "#rrggbb".
    private static func swatchKey(_ hex: String) -> String {
        ColourSwap.parse(hex)?.rgb ?? hex
    }

    /// Change all for the swap just made, when anything else in the design
    /// still has the colour it was.
    private func offerChangeAll(to hex: String) {
        guard let origin = swapOrigin, origin != hex else { changeAll = nil; return }
        let count = ColourSwap.count(store.design, from: origin)
        changeAll = count > 0 ? ChangeAllOffer(from: origin, to: hex, count: count) : nil
    }

    /// Companions for whatever is currently chosen. Picking a second colour
    /// that goes with the first is the hardest part of making something look
    /// designed, and it is the part arithmetic can actually do.
    @ViewBuilder
    private var harmonySection: some View {
        let seed = shownCurrent ?? UIColor(custom).hexString
        Text("Goes with this colour")
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
                        .accessibilityLabel("\(kind.displayName): \(ElementNames.colourName(hex))")
                    }
                }
            }
        }
    }

    /// Six patterns in the current colour over white. Tap one to fill with
    /// it; the colour swatches above keep working on it afterwards, since a
    /// pattern's foreground is the paint's colour.
    private func patternsSection(_ pick: @escaping (Paint) -> Void) -> some View {
        // With no one current colour — several things selected — the ink is
        // the Android twin's dark one: the untouched wheel's white made six
        // blank tiles and a white-on-white fill.
        let ink = current ?? currentPaint?.color ?? "#1f2430"
        return VStack(alignment: .leading, spacing: 8) {
            Text("Patterns").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Patterns.names, id: \.self) { name in
                    let paint = Paint.pattern(name, color: ink, secondary: "#ffffff", scale: 12)
                    let chosen = FillChoices.isPattern(currentPaint, named: name)
                    Button {
                        guard !chosen else { return }
                        pick(paint)
                        store.buzz(.tick)
                    } label: {
                        PatternFill(paint: paint)
                            .frame(height: 40)
                            .clipShape(RoundedRectangle(cornerRadius: 9))
                            .overlay(chosenRing(chosen))
                    }
                    .accessibilityLabel("\(Patterns.displayName(name)) pattern")
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    /// The library's photos, and any the document already uses, as fills.
    private func photoFillSection(_ pick: @escaping (Paint) -> Void) -> some View {
        let sources = FillChoices.photoFillSources(store.design)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Photo fill").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(sources, id: \.self) { src in
                    let chosen = FillChoices.isPhoto(currentPaint, src: src)
                    Button {
                        guard !chosen else { return }
                        pick(.image(src))
                        store.buzz(.tick)
                    } label: {
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
                        .overlay { if chosen { chosenRing(true) } }
                    }
                    .accessibilityLabel(FillChoices.photoFillLabel(src, sources: sources))
                    .accessibilityAddTraits(chosen ? .isSelected : [])
                }
            }
        }
    }

    /// One place every swatch tap goes through, so nothing can pick a colour
    /// without it landing in the recents.
    private func choose(_ hex: String) {
        RecentColors.record(hex)
        // Felt when it changes something, as on the Android twin.
        if shownCurrent?.lowercased() != hex.lowercased() { store.buzz(.tick) }
        if swapTarget != nil, let from = swapFrom {
            // One colour of the selection, as one step.
            store.swapSelectionColour(from: from, to: hex)
            swapTarget = Self.swatchKey(hex)
            swapFrom = swapTarget
            offerChangeAll(to: hex)
        } else {
            onPick(hex)
        }
    }

    /// One of the gradients, in the shape chosen above: ringed when it is
    /// the fill there now, and then a tap records nothing.
    private func gradientTile(_ preset: GradientPreset, pick: @escaping (Paint) -> Void) -> some View {
        let paint = preset.paint(kind: gradientKind)
        let chosen = FillChoices.isGradient(currentPaint, paint)
        return Button {
            guard !chosen else { return }
            pick(paint)
            store.buzz(.tick)
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(paint.gradientStyle())
                .frame(height: 40)
                .overlay(chosenRing(chosen))
        }
        .accessibilityLabel(tr("%@ %@ gradient", preset.name, Self.gradientKindWord(gradientKind)))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// A gradient's shape — "linear", "radial", "angular" — as its spoken
    /// name says it; the background's gradients say it too.
    static func gradientKindWord(_ kind: String) -> String {
        switch kind {
        case "linear": return tr("linear")
        case "radial": return tr("radial")
        case "angular": return tr("angular")
        default: return kind
        }
    }

    private func chosenRing(_ chosen: Bool) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .stroke(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 3 : 1)
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
                                if shownCurrent?.lowercased() == hex.lowercased() {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.bold)
                                        .foregroundStyle(UIColor(hex: hex).isLight ? .black : .white)
                                        .accessibilityHidden(true)
                                }
                            }
                    }
                    // Named in words, and the chosen one said to be chosen.
                    .accessibilityLabel(ElementNames.spokenColour(hex))
                    .accessibilityAddTraits(shownCurrent?.lowercased() == hex.lowercased() ? .isSelected : [])
                }
            }
        }
    }
}

/// Change all, as offered after a swap: the colour the selection had, the
/// one it has now, and how many other elements still have the first.
struct ChangeAllOffer: Equatable {
    var from: String
    var to: String
    var count: Int

    /// How long the offer stays.
    static let seconds = 10
}
