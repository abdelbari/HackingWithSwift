// Edit the brand kit.

import SwiftUI

struct BrandKitSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var kit = BrandKit.load()
    @State private var newColor = Color.blue
    /// The logos there when the sheet opened, listed even once switched off.
    @State private var openedWithLogos = BrandKit.load().logos
    /// The face being chosen in the font picker.
    @State private var choosingFace: Face?

    /// The kit's two faces.
    private enum Face: String, Identifiable {
        case heading = "Heading face"
        case body = "Body face"

        var id: String { rawValue }
    }

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(kit.colors, id: \.self) { hex in
                            RoundedRectangle(cornerRadius: 9)
                                .fill(Color(hex: hex))
                                .frame(height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Theme.hairline))
                                .contextMenu {
                                    Button("Remove", role: .destructive) { kit.colors.removeAll { $0 == hex } }
                                }
                                .accessibilityLabel("\(ElementNames.spokenColour(hex)), brand colour")
                                .accessibilityAction(named: "Remove") { kit.colors.removeAll { $0 == hex } }
                        }
                    }
                    ColorPicker("Add a colour", selection: $newColor, supportsOpacity: false)
                    Button("Add") { kit.addColor(UIColor(newColor).hexString) }
                    if !ColorTools.documentColors(store.design).isEmpty {
                        Button("Add this design's colours") {
                            for hex in ColorTools.documentColors(store.design, limit: 6).reversed() { kit.addColor(hex) }
                        }
                    }
                } header: {
                    Text("Colours")
                } footer: {
                    Text("Offered first in every colour picker. Press and hold a swatch to remove it.")
                }

                Section("Type") {
                    faceRow(.heading, kit.headingFamily, weight: kit.headingWeight)
                    faceRow(.body, kit.bodyFamily, weight: kit.bodyWeight)
                }

                Section {
                    let candidates = BrandKit.logoCandidates(openedWith: openedWithLogos, current: kit.logos,
                                                             design: store.design)
                    if candidates.isEmpty {
                        Text("Add a picture to the design, then mark it here as a logo.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(candidates.enumerated()), id: \.element) { index, src in
                        logoRow(src, index: index, count: candidates.count)
                    }
                } header: {
                    Text("Logos")
                } footer: {
                    Text("Logos appear in the Photos tab of Add, in every design.")
                }
            }
            .navigationTitle("Brand kit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        // The font picker, None first, every font and your own, as for a
        // text — as the Android twin chooses a brand face.
        .sheet(item: $choosingFace) { face in
            FontSheet(store: store, choice: FontSheet.Choice(
                title: face.rawValue,
                current: face == .heading ? kit.headingFamily : kit.bodyFamily,
                onPick: { key in
                    if face == .heading { kit.headingFamily = key } else { kit.bodyFamily = key }
                }))
        }
        // Every change kept as it is made, as on the Android twin, so the
        // sheet can be swiped away as well as closed with Done.
        .onChange(of: kit) { _, changed in changed.save() }
    }

    /// A face of the kit, its name drawn in itself at the kit's weight for
    /// it, or None; a tap opens the font picker. One of your own not on
    /// this phone says so.
    private func faceRow(_ face: Face, _ family: String?, weight: Int) -> some View {
        let name = family.map { FontStore.displayName($0, in: store.design) } ?? "None"
        let missing = family.flatMap { FontStore.missingNote($0, in: store.design) }
        return Button { choosingFace = face } label: {
            HStack {
                Text(face.rawValue).foregroundStyle(.primary)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(name)
                        .font(family.map { FontLibrary.font(family: $0, size: 17, weight: weight, italic: false) } ?? .body)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let missing {
                        Text(missing).font(.caption).foregroundStyle(.red)
                    }
                }
            }
        }
        .accessibilityLabel(face.rawValue)
        .accessibilityValue(missing ?? name)
    }

    /// One switch per picture, told apart by its place in the list — the
    /// picture is all that differs, and VoiceOver cannot see it.
    private func logoRow(_ src: String, index: Int, count: Int) -> some View {
        HStack {
            if let ui = PhotoLibrary.resolve(src) {
                Image(uiImage: PhotoLibrary.preview(ui, key: src))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
            Toggle("Picture \(index + 1)", isOn: Binding(
                get: { kit.logos.contains(src) },
                set: { on in
                    if on { if !kit.logos.contains(src) { kit.logos.append(src) } }
                    else { kit.logos.removeAll { $0 == src } }
                }))
            .accessibilityLabel("Picture \(index + 1) of \(count), a brand logo")
        }
    }
}
