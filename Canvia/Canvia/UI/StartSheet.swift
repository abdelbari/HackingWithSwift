// Choosing a size and choosing something to start from, as one gesture.
//
// The size just named is the filter: an Instagram post opens on a blank
// Instagram post and every template made at exactly that size, never the
// whole library. The blank start is the first cell and never scrolls away;
// topic is a chip row inside the size, and only when the size has enough to
// need one. Two depths — pick a size, then pick a start — swapped in place,
// so there is never a sheet over a sheet. The Android twin's StartSheet.

import SwiftUI

struct StartSheet: View {
    /// The size the sheet opened on; nil when it opened on the sizes.
    let initialPresetId: String?
    var onCreate: (Design) -> Void
    var onCustomSize: () -> Void
    /// Open a PowerPoint…, above the sizes; nil offers none.
    var onPowerPoint: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var presetId: String?
    @State private var category: String?

    init(initialPresetId: String?, onCreate: @escaping (Design) -> Void, onCustomSize: @escaping () -> Void,
         onPowerPoint: (() -> Void)? = nil) {
        self.initialPresetId = initialPresetId
        self.onCreate = onCreate
        self.onCustomSize = onCustomSize
        self.onPowerPoint = onPowerPoint
        _presetId = State(initialValue: initialPresetId)
    }

    private var preset: SizePreset? {
        guard let presetId else { return nil }
        return SizePreset.byId(presetId)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let preset {
                    StartGrid(preset: preset, category: $category, onCreate: onCreate)
                } else {
                    sizePicker
                }
            }
            .background(Theme.workspace)
            .navigationTitle(preset?.name ?? "What are you making?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) { header }
                ToolbarItem(placement: .topBarLeading) {
                    // Only when the sizes were where this began: a way back
                    // to them rather than closing and starting again.
                    if preset != nil && initialPresetId == nil {
                        Button {
                            presetId = nil
                            category = nil
                        } label: {
                            Image(systemName: "chevron.backward")
                        }
                        .accessibilityLabel("Back to sizes")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(spacing: 1) {
            Text(preset?.name ?? "What are you making?")
                .font(.headline)
                .lineLimit(1)
            if let preset {
                // In its own unit: "210 × 297 mm".
                Text(preset.unit == nil ? "\(preset.dimensions) px" : preset.dimensions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// Open a PowerPoint…, first, then the sizes, Custom size last.
    private var sizePicker: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let onPowerPoint { powerPointButton(onPowerPoint) }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], alignment: .leading, spacing: 16) {
                ForEach(SizePreset.hero) { preset in
                    SizeTile(preset: preset) { presetId = preset.id }
                }
                CustomSizeTile(action: onCustomSize)
            }
        }
        .padding(20)
    }

    /// A deck as a design at its own size.
    private func powerPointButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(Self.openPowerPoint, systemImage: "rectangle.on.rectangle")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
    }

    /// Home ▸ New design's way to bring in a deck.
    static let openPowerPoint = "Open a PowerPoint…"
}

/// A size, drawn at the shape it makes with a real design at that size
/// faded behind it, and how many ready-made starts it has.
struct SizeTile: View {
    let preset: SizePreset
    var action: () -> Void

    var body: some View {
        let count = ContentLibrary.templateCounts[preset.id] ?? 0
        // The output's own shape, 104 tall, within reason either way.
        let ratio = min(max(preset.w / preset.h, 64.0 / 104), 184.0 / 104)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(Theme.card)
                    if let preview = ContentLibrary.sizedTemplates(for: preset).first {
                        TemplateThumb(template: preview, badge: false).opacity(0.4)
                    }
                }
                .aspectRatio(ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.hairline))
                // One height for every tile, so the names below line up
                // across a row whatever shape each size is.
                .frame(maxWidth: .infinity, minHeight: 104, maxHeight: 104, alignment: .leading)
                Text(preset.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text("\(count) ready-made")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preset.name), \(count) ready-made designs")
    }
}

/// Any size at all, at the end of the sizes.
struct CustomSizeTile: View {
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Theme.card)
                    .overlay(Image(systemName: "slider.horizontal.3").font(.title2).foregroundStyle(.secondary))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.inkSecondary.opacity(0.5)))
                    .frame(height: 104)
                Text("Custom size")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.top, 4)
                Text("Any dimensions")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Custom size")
    }
}

/// The blank start first, then your own templates at exactly this size,
/// then every template of the library's at it.
private struct StartGrid: View {
    let preset: SizePreset
    @Binding var category: String?
    var onCreate: (Design) -> Void
    @State private var mine: [UserTemplate] = []
    /// A template of several pages, while its strip asks which.
    @State private var templateSet: Template?

    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        let bucket = ContentLibrary.sizedTemplates(for: preset)
        let shown = category.map { c in bucket.filter { $0.category == c } } ?? bucket
        VStack(alignment: .leading, spacing: 16) {
            // A chip row only earns its space when the size has enough that
            // narrowing it helps.
            if ContentLibrary.showsTopics(bucket) {
                topicChips(bucket)
            }
            LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                BlankCard(preset: preset) {
                    // Named for what it is, as the Android twin names it;
                    // Home makes the name one the shelf does not have yet.
                    onCreate(preset.makeDesign())
                }
                if category == nil {
                    ForEach(mine) { entry in
                        StartUserTemplateCard(entry: entry) { use(entry) }
                    }
                }
                ForEach(shown) { template in
                    StartTemplateCard(template: template) { start(from: template) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .onAppear { mine = UserTemplates.sized(UserTemplates.all(), width: preset.w, height: preset.h) }
        .sheet(item: $templateSet) { template in
            TemplateSetSheet(template: template, note: TemplateSetSheet.startNote,
                             applyAll: { onCreate(template.instantiate(for: preset)) },
                             usePage: { onCreate(template.instantiate(for: preset, onlyPage: $0)) })
        }
    }

    /// A new design from a template: a template of several pages shows its
    /// strip first — all of them, or the page picked alone — as the Android
    /// twin's Start sheet asks.
    private func start(from template: Template) {
        if template.pageCount > 1 {
            templateSet = template
        } else {
            onCreate(template.instantiate(for: preset))
        }
    }

    /// A new design from a fresh copy of the template, every page, in the
    /// size's unit.
    private func use(_ entry: UserTemplate) {
        guard let template = UserTemplates.load(id: entry.id) else { return }
        var design = UserTemplates.newDesign(from: template)
        design.unit = preset.unit
        design.dpi = preset.dpi
        onCreate(design)
    }

    private func topicChips(_ bucket: [Template]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All \(bucket.count)", selected: category == nil) { category = nil }
                ForEach(ContentLibrary.topics(in: bucket), id: \.self) { name in
                    chip(name, selected: category == name) {
                        category = category == name ? nil : name
                    }
                }
            }
        }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(selected ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// "Start with nothing", the same shape as every template beside it, and
/// the one thing on the sheet in the accent colour.
private struct BlankCard: View {
    let preset: SizePreset
    var action: () -> Void

    var body: some View {
        let ratio = min(max(preset.w / preset.h, 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Theme.accentSubtle)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 2))
                    .overlay(Image(systemName: "plus").font(.title2.weight(.semibold)).foregroundStyle(Theme.accent))
                    .aspectRatio(ratio, contentMode: .fit)
                Text("Blank \(preset.name.lowercased())")
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Blank \(preset.name)")
    }
}

private struct StartTemplateCard: View {
    let template: Template
    var action: () -> Void

    var body: some View {
        let ratio = min(max(template.width / template.height, 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                TemplateThumb(template: template)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                Text(template.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(template.name), \(template.category) template")
    }
}

/// One of your own templates among a size's starts.
private struct StartUserTemplateCard: View {
    let entry: UserTemplate
    var action: () -> Void

    var body: some View {
        let ratio = min(max(entry.width / max(entry.height, 1), 0.45), 2.2)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                UserTemplateThumb(entry: entry)
                    .aspectRatio(ratio, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.hairline))
                Text(entry.name)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(entry.name), your template")
    }
}

/// A page at whatever size is needed: each side says its range under it
/// and says so again when it is out of it, four ratio shortcuts, and the
/// last few sizes made. Nothing is clamped behind anyone's back — Create
/// waits until both sides are in range.
struct CustomSizeSheet: View {
    var onCreate: (Design) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var width: String
    @State private var height: String
    /// What the sides are typed in: px, in, mm or cm — at first, Settings'
    /// custom size unit.
    @State private var unit: String
    /// Read once as the sheet opens.
    @State private var recent = CustomSizes.recent()

    /// 1080 × 1080 pixels to start, written in Settings' unit, as the
    /// Android twin starts its sides.
    init(onCreate: @escaping (Design) -> Void) {
        self.onCreate = onCreate
        let unit = AppDefaults.unit()
        let side = CustomSizes.convert("1080", from: "px", to: unit)
        _width = State(initialValue: side)
        _height = State(initialValue: side)
        _unit = State(initialValue: unit)
    }

    var body: some View {
        let w = CustomSizes.side(width, unit: unit)
        let h = CustomSizes.side(height, unit: unit)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    UnitPicker(unit: $unit)
                        // The size stays the size: what is typed is
                        // rewritten in the new unit.
                        .onChange(of: unit) { old, new in
                            width = CustomSizes.convert(width, from: old, to: new)
                            height = CustomSizes.convert(height, from: old, to: new)
                        }
                    HStack(alignment: .top, spacing: 12) {
                        sideField("Width", text: $width, valid: w != nil)
                        sideField("Height", text: $height, valid: h != nil)
                    }
                    HStack(spacing: 8) {
                        ForEach(CustomSizes.ratios.indices, id: \.self) { i in
                            let item = CustomSizes.ratios[i]
                            chip(item.label) {
                                height = CustomSizes.height(forWidth: width, ratio: item.ratio, unit: unit)
                            }
                            .accessibilityLabel("Ratio \(item.label)")
                        }
                    }
                    if !recent.isEmpty {
                        Text("Recently used")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            ForEach(recent, id: \.self) { size in
                                chip(size.label) {
                                    // Kept in pixels, written in the unit
                                    // the sides are typed in.
                                    width = CustomSizes.convert(String(size.width), from: "px", to: unit)
                                    height = CustomSizes.convert(String(size.height), from: "px", to: unit)
                                }
                                .accessibilityLabel("\(size.width) by \(size.height)")
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Theme.workspace)
            .navigationTitle("Custom size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        guard let w, let h else { return }
                        CustomSizes.remember(width: w, height: h)
                        onCreate(CustomSizes.design(width: w, height: h, unit: unit))
                    }
                    .fontWeight(.semibold)
                    .disabled(w == nil || h == nil)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func sideField(_ label: String, text: Binding<String>, valid: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                TextField(label, text: text)
                    .keyboardType(unit == "px" ? .numberPad : .decimalPad)
                    .accessibilityHint(valid ? CustomSizes.rangeText : CustomSizes.outOfRangeText)
                Text(unit).foregroundStyle(.secondary)
            }
            .padding(10)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(valid ? Theme.hairline : Color(.systemRed), lineWidth: valid ? 1 : 1.5))
            Text(valid ? CustomSizes.rangeText : CustomSizes.outOfRangeText)
                .font(.caption)
                .foregroundStyle(valid ? Color.secondary : Color(.systemRed))
        }
        .frame(maxWidth: .infinity)
        // Digits only, five at most, however they arrive — typed or pasted;
        // and one decimal point in a physical unit.
        .onChange(of: text.wrappedValue) { _, typed in
            let clean = CustomSizes.field(typed, unit: unit)
            if clean != typed { text.wrappedValue = clean }
        }
    }

    private func chip(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Theme.card, in: Capsule())
                .overlay(Capsule().stroke(Theme.hairline))
                .foregroundStyle(Theme.ink)
        }
        .buttonStyle(.plain)
    }
}

/// px | in | mm | cm, for a size typed in Custom size and Resize. A size in
/// a physical unit is made at 300 dpi.
struct UnitPicker: View {
    @Binding var unit: String

    var body: some View {
        Picker("Unit", selection: $unit) {
            ForEach(Units.all, id: \.self) { Text($0).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}
