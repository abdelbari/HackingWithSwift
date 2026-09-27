// Edit the brand kit.

import SwiftUI

struct BrandKitSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var kit = BrandKit.load()
    @State private var newColor = Color.blue
    /// The logos there when the sheet opened, listed even once switched off.
    @State private var openedWithLogos = BrandKit.load().logos

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
                    Picker("Heading face", selection: Binding(
                        get: { kit.headingFamily ?? "" }, set: { kit.headingFamily = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag("")
                        ForEach(FontLibrary.stacks) { Text($0.name).tag($0.key) }
                    }
                    Picker("Body face", selection: Binding(
                        get: { kit.bodyFamily ?? "" }, set: { kit.bodyFamily = $0.isEmpty ? nil : $0 })) {
                        Text("None").tag("")
                        ForEach(FontLibrary.stacks) { Text($0.name).tag($0.key) }
                    }
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
        // Every change kept as it is made, as on the Android twin, so the
        // sheet can be swiped away as well as closed with Done.
        .onChange(of: kit) { _, changed in changed.save() }
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
