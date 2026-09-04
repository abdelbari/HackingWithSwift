// Edit the brand kit.

import SwiftUI

struct BrandKitSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var kit = BrandKit.load()
    @State private var newColor = Color.blue

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
                                .accessibilityLabel("Brand colour \(hex)")
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
                    let candidates = store.design.pages.flatMap { $0.elements }
                        .filter { $0.type == .image }.compactMap(\.src)
                    if candidates.isEmpty && kit.logos.isEmpty {
                        Text("Add a picture to the design, then mark it here as a logo.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(Set(kit.logos + candidates)).sorted(), id: \.self) { src in
                        HStack {
                            if let ui = PhotoLibrary.resolve(src) {
                                Image(uiImage: PhotoLibrary.preview(ui, key: src))
                                    .resizable().aspectRatio(contentMode: .fit).frame(width: 44, height: 44)
                            }
                            Toggle("Logo", isOn: Binding(
                                get: { kit.logos.contains(src) },
                                set: { on in
                                    if on { if !kit.logos.contains(src) { kit.logos.append(src) } }
                                    else { kit.logos.removeAll { $0 == src } }
                                }))
                        }
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
                    Button("Done") { kit.save(); dismiss() }
                }
            }
        }
        .presentationDetents([.large])
    }
}
