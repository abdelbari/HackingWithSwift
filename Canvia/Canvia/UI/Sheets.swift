// Editor sheets: colors, background, fonts, effects, spacing, filters,
// crop, position, layers, resize.

import SwiftUI
import UIKit

private let sheetDetents: Set<PresentationDetent> = [.medium, .large]

// MARK: - color picker

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

                    let docColors = ColorTools.documentColors(store.design)
                    if !docColors.isEmpty {
                        section("Document colors", colors: docColors)
                    }
                    section("Default colors", colors: ContentLibrary.defaultSwatches)

                    if allowGradients, let onPickGradient {
                        Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(ContentLibrary.gradients) { preset in
                                Button {
                                    onPickGradient(preset.paint)
                                    dismiss()
                                } label: {
                                    RoundedRectangle(cornerRadius: 9)
                                        .fill(gradientFill(preset))
                                        .frame(height: 40)
                                }
                            }
                        }
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
        // Continuous picking runs through transient updates; record the whole
        // session as one undo step however the sheet closes.
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
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
                        onPick(hex)
                        dismiss()
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

// MARK: - background

struct BackgroundSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    private let photoColumns = [GridItem(.adaptive(minimum: 90), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Solid colors").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ContentLibrary.defaultSwatches, id: \.self) { hex in
                            Button {
                                store.applyToPage { $0.background = .color(hex) }
                            } label: {
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(Color(hex: hex))
                                    .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.black.opacity(0.12)))
                                    .frame(height: 40)
                            }
                        }
                    }

                    Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(ContentLibrary.gradients) { preset in
                            Button {
                                store.applyToPage { $0.background = .gradient(preset.paint) }
                            } label: {
                                let pts = preset.paint.unitPoints
                                RoundedRectangle(cornerRadius: 9)
                                    .fill(LinearGradient(
                                        stops: preset.stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
                                        startPoint: pts.start, endPoint: pts.end))
                                    .frame(height: 40)
                            }
                        }
                    }

                    Text("Photos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: photoColumns, spacing: 10) {
                        ForEach(PhotoLibrary.photos) { photo in
                            Button {
                                store.applyToPage { $0.background = .image("asset:\(photo.id)") }
                            } label: {
                                photoThumb(photo.id)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Background")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
    }
}

func photoThumb(_ id: String) -> some View {
    Group {
        if let ui = PhotoLibrary.image(id: id) {
            Image(uiImage: ui)
                .resizable()
                .aspectRatio(4 / 3, contentMode: .fill)
        } else {
            Color(.systemGray5)
        }
    }
    .frame(height: 68)
    .clipShape(RoundedRectangle(cornerRadius: 9))
}

// MARK: - fonts

struct FontSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(FontLibrary.stacks) { stack in
                    Button {
                        store.updateSelected { $0.fontFamily = stack.key }
                        dismiss()
                    } label: {
                        HStack {
                            Text(stack.name)
                                .font(FontLibrary.font(family: stack.key, size: 20, weight: 500, italic: false))
                            Spacer()
                            if store.singleSelection?.fontFamily == stack.key {
                                Image(systemName: "checkmark").foregroundStyle(Color(hex: "#8b3dff"))
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .navigationTitle("Fonts")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents(sheetDetents)
    }
}

// MARK: - text effects

struct EffectsSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 76), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TextEffect.allCases) { effect in
                        let active = TextEffect.from(store.singleSelection?.effect) == effect
                        Button {
                            store.updateSelected { $0.effect = TextEffectSpec(type: effect.rawValue) }
                        } label: {
                            VStack(spacing: 6) {
                                effectPreview(effect)
                                    .frame(width: 64, height: 44)
                                Text(effect.displayName).font(.system(size: 11))
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color(.systemGray6))
                                .overlay(RoundedRectangle(cornerRadius: 10)
                                    .stroke(active ? Color(hex: "#8b3dff") : .clear, lineWidth: 2)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Text effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func effectPreview(_ effect: TextEffect) -> some View {
        var el = Element.text("Ag", fontSize: 30, w: 64)
        el.color = "#6d28d9"
        el.align = "center"
        el.effect = TextEffectSpec(type: effect.rawValue)
        el.h = 44
        return TextElementView(element: el)
    }
}

// MARK: - spacing

struct SpacingSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let el = store.singleSelection {
                    Section("Line height") {
                        Slider(value: transientBinding(el.lineHeight ?? 1.25) { v, e in e.lineHeight = v },
                               in: 0.8...2.4, step: 0.05)
                    }
                    Section("Letter spacing") {
                        Slider(value: transientBinding(el.letterSpacing ?? 0) { v, e in e.letterSpacing = v },
                               in: -2...20, step: 0.5)
                    }
                }
            }
            .navigationTitle("Spacing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.commit(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    private func transientBinding(_ value: Double,
                                  _ set: @escaping (Double, inout Element) -> Void) -> Binding<Double> {
        Binding(
            get: { value },
            set: { v in
                store.updateSelectedTransient { el in
                    set(v, &el)
                    if el.type == .text { el.h = FontLibrary.measuredHeight(for: el) }
                }
            })
    }
}

// MARK: - image filters

struct FiltersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(ImageFilterPreset.allCases) { preset in
                        let active = ImageFilterPreset.from(store.singleSelection?.filter) == preset
                        Button {
                            store.updateSelected { $0.filter = preset.rawValue }
                        } label: {
                            VStack(spacing: 6) {
                                filterPreview(preset)
                                Text(preset.displayName).font(.system(size: 11))
                            }
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 10)
                                .stroke(active ? Color(hex: "#8b3dff") : .clear, lineWidth: 2))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func filterPreview(_ preset: ImageFilterPreset) -> some View {
        Group {
            if let src = store.singleSelection?.src,
               let full = PhotoLibrary.resolve(src) {
                // Filter a small copy: ten full-size variants of a 1200x900
                // artwork would be ~43 MB for a row of 76pt thumbnails.
                let base = PhotoLibrary.preview(full, key: src)
                Image(uiImage: ImageFilterEngine.apply(preset, to: base, cacheKey: src + "|preview"))
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Color(.systemGray5)
            }
        }
        .frame(width: 76, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - crop

struct CropSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if let el = store.singleSelection {
                    Section("Zoom") {
                        Slider(value: cropBinding(el.cropScale ?? 1) { v, e in e.cropScale = v },
                               in: 1...3)
                    }
                    Section("Horizontal focus") {
                        Slider(value: cropBinding(el.cropX ?? 0.5) { v, e in e.cropX = v }, in: 0...1)
                    }
                    Section("Vertical focus") {
                        Slider(value: cropBinding(el.cropY ?? 0.5) { v, e in e.cropY = v }, in: 0...1)
                    }
                    Button("Reset crop") {
                        store.updateSelected { $0.cropScale = 1; $0.cropX = 0.5; $0.cropY = 0.5 }
                    }
                }
            }
            .navigationTitle("Crop & focus")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { store.commit(); dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .onDisappear {
            if store.hasPendingChanges { store.commit() }
        }
    }

    private func cropBinding(_ value: Double,
                             _ set: @escaping (Double, inout Element) -> Void) -> Binding<Double> {
        Binding(get: { value }, set: { v in store.updateSelectedTransient { set(v, &$0) } })
    }
}

// MARK: - position / arrange

struct PositionSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Layer order") {
                    HStack {
                        orderButton("To front", "square.3.layers.3d.top.filled") { store.reorderSelected(.front) }
                        orderButton("Forward", "square.2.layers.3d.top.filled") { store.reorderSelected(.forward) }
                        orderButton("Backward", "square.2.layers.3d.bottom.filled") { store.reorderSelected(.backward) }
                        orderButton("To back", "square.3.layers.3d.bottom.filled") { store.reorderSelected(.back) }
                    }
                }
                Section(store.selection.count > 1 ? "Align selection" : "Align to page") {
                    HStack {
                        orderButton("Left", "align.horizontal.left") { store.alignSelected(.left) }
                        orderButton("Center", "align.horizontal.center") { store.alignSelected(.centerX) }
                        orderButton("Right", "align.horizontal.right") { store.alignSelected(.right) }
                    }
                    HStack {
                        orderButton("Top", "align.vertical.top") { store.alignSelected(.top) }
                        orderButton("Middle", "align.vertical.center") { store.alignSelected(.centerY) }
                        orderButton("Bottom", "align.vertical.bottom") { store.alignSelected(.bottom) }
                    }
                }
                if store.selection.count >= 3 {
                    Section("Distribute evenly") {
                        HStack {
                            orderButton("Horizontally", "arrow.left.and.right") {
                                store.distributeSelected(.horizontal)
                            }
                            orderButton("Vertically", "arrow.up.and.down") {
                                store.distributeSelected(.vertical)
                            }
                        }
                        // Distribute skips locked elements, so gate on the
                        // unlocked count — disabled rather than hidden, so the
                        // control doesn't appear and vanish with lock state.
                        .disabled(!store.canDistribute)
                    }
                }
                Section("Flip") {
                    HStack {
                        orderButton("Horizontal", "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                            store.flipSelected(horizontal: true)
                        }
                        orderButton("Vertical", "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                            store.flipSelected(horizontal: false)
                        }
                    }
                }
                if let el = store.singleSelection {
                    Section("Exact") {
                        numberRow("X", value: el.x) { v in store.updateSelected { $0.x = v } }
                        numberRow("Y", value: el.y) { v in store.updateSelected { $0.y = v } }
                        numberRow("Width", value: el.w) { v in store.updateSelected { $0.w = max(8, v) } }
                        if el.type != .text {
                            numberRow("Height", value: el.h) { v in store.updateSelected { $0.h = max(8, v) } }
                        }
                        numberRow("Rotation", value: el.rotation) { v in store.updateSelected { $0.rotation = v } }
                    }
                }
            }
            .navigationTitle("Position")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
    }

    private func orderButton(_ label: String, _ system: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                Text(label).font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderless)
    }

    private func numberRow(_ label: String, value: Double, commit: @escaping (Double) -> Void) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField(label, value: Binding(get: { value }, set: { commit($0) }), format: .number.precision(.fractionLength(0...1)))
                .keyboardType(.numbersAndPunctuation)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
        }
    }
}

// MARK: - layers

struct LayersSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Top-most first; List reordering maps back to array indices.
                ForEach(Array(store.page.elements.reversed())) { el in
                    HStack(spacing: 12) {
                        layerThumb(el)
                        Text(layerName(el)).lineLimit(1)
                        Spacer()
                        if el.locked { Image(systemName: "lock.fill").foregroundStyle(.secondary) }
                        if store.selection.contains(el.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color(hex: "#8b3dff"))
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.select(el.id) }
                }
                .onMove { source, destination in
                    let count = store.page.elements.count
                    var reversed = Array(store.page.elements.reversed())
                    reversed.move(fromOffsets: source, toOffset: destination)
                    store.applyToPage { $0.elements = reversed.reversed() }
                    _ = count
                }
                .onDelete { offsets in
                    let reversed = Array(store.page.elements.reversed())
                    let removable = Set(offsets.map { reversed[$0] }
                        .filter { !$0.locked }
                        .map(\.id))
                    guard !removable.isEmpty else { return }
                    store.applyToPage { page in
                        page.elements.removeAll { removable.contains($0.id) }
                    }
                    store.selection.subtract(removable)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
    }

    private func layerName(_ el: Element) -> String {
        switch el.type {
        case .text: return String((el.text ?? "Text").split(separator: "\n").first ?? "Text")
        case .shape: return ContentLibrary.shape(el.shapeId).name
        case .image: return "Image"
        case .sticker: return "Sticker \(el.glyph ?? "")"
        case .line: return "Line"
        }
    }

    @ViewBuilder
    private func layerThumb(_ el: Element) -> some View {
        switch el.type {
        case .shape:
            LibraryShape(definition: ContentLibrary.shape(el.shapeId), cornerRadius: 0)
                .fill(Color(hex: el.fill?.primaryColor ?? "#888888"))
                .frame(width: 28, height: 28)
        case .image:
            if let ui = PhotoLibrary.resolve(el.src) {
                Image(uiImage: ui).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 28, height: 28).clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                Image(systemName: "photo").frame(width: 28, height: 28)
            }
        case .sticker:
            Text(el.glyph ?? "⭐").font(.system(size: 20)).frame(width: 28, height: 28)
        case .text:
            Text("T").font(.system(size: 18, weight: .bold))
                .foregroundStyle(Color(hex: el.color ?? "#333333"))
                .frame(width: 28, height: 28)
        case .line:
            Rectangle().fill(Color(hex: el.color ?? "#333333"))
                .frame(width: 24, height: 3).frame(width: 28, height: 28)
        }
    }
}

// MARK: - resize design

struct ResizeSheet: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss
    @State private var customW = ""
    @State private var customH = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Presets") {
                    ForEach(SizePreset.all) { preset in
                        Button {
                            store.resizeDesign(width: preset.w, height: preset.h)
                            dismiss()
                        } label: {
                            HStack {
                                Label(preset.name, systemImage: preset.icon)
                                Spacer()
                                Text("\(Int(preset.w)) × \(Int(preset.h))")
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
                Section("Custom") {
                    HStack {
                        TextField("Width", text: $customW).keyboardType(.numberPad)
                        Text("×")
                        TextField("Height", text: $customH).keyboardType(.numberPad)
                        Button("Apply") {
                            let w = min(4000, max(40, Double(customW) ?? store.design.width))
                            let h = min(4000, max(40, Double(customH) ?? store.design.height))
                            store.resizeDesign(width: w, height: h)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }
            .navigationTitle("Resize design")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                customW = String(Int(store.design.width))
                customH = String(Int(store.design.height))
            }
        }
        .presentationDetents(sheetDetents)
    }
}
