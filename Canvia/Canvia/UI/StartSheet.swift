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
    @Environment(\.dismiss) private var dismiss
    @State private var presetId: String?
    @State private var category: String?

    init(initialPresetId: String?, onCreate: @escaping (Design) -> Void, onCustomSize: @escaping () -> Void) {
        self.initialPresetId = initialPresetId
        self.onCreate = onCreate
        self.onCustomSize = onCustomSize
        _presetId = State(initialValue: initialPresetId)
    }

    private var preset: SizePreset? {
        guard let presetId else { return nil }
        return SizePreset.all.first { $0.id == presetId }
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
                Text("\(Int(preset.w)) × \(Int(preset.h)) px")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var sizePicker: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 12)], alignment: .leading, spacing: 16) {
            ForEach(SizePreset.all) { preset in
                SizeTile(preset: preset) { presetId = preset.id }
            }
            CustomSizeTile(action: onCustomSize)
        }
        .padding(20)
    }
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
                        TemplateThumb(template: preview).opacity(0.4)
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

/// The blank start first, then every template at exactly this size.
private struct StartGrid: View {
    let preset: SizePreset
    @Binding var category: String?
    var onCreate: (Design) -> Void

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
                    onCreate(Design(title: preset.name, width: preset.w, height: preset.h))
                }
                ForEach(shown) { template in
                    StartTemplateCard(template: template) { onCreate(template.instantiate()) }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 24)
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

/// A page at whatever size is needed: each side says its range under it
/// and says so again when it is out of it, four ratio shortcuts, and the
/// last few sizes made. Nothing is clamped behind anyone's back — Create
/// waits until both sides are in range.
struct CustomSizeSheet: View {
    var onCreate: (Design) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var width = "1080"
    @State private var height = "1080"
    /// Read once as the sheet opens.
    @State private var recent = CustomSizes.recent()

    var body: some View {
        let w = CustomSizes.side(width)
        let h = CustomSizes.side(height)
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        sideField("Width", text: $width, valid: w != nil)
                        sideField("Height", text: $height, valid: h != nil)
                    }
                    HStack(spacing: 8) {
                        ForEach(CustomSizes.ratios.indices, id: \.self) { i in
                            let item = CustomSizes.ratios[i]
                            chip(item.label) {
                                height = CustomSizes.height(forWidth: width, ratio: item.ratio)
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
                                    width = String(size.width)
                                    height = String(size.height)
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
                        onCreate(Design(title: CustomSizes.title(width: w, height: h), width: w, height: h))
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
                    .keyboardType(.numberPad)
                    .accessibilityHint(valid ? CustomSizes.rangeText : CustomSizes.outOfRangeText)
                Text("px").foregroundStyle(.secondary)
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
        // Digits only, five at most, however they arrive — typed or pasted.
        .onChange(of: text.wrappedValue) { _, typed in
            let clean = CustomSizes.digits(typed)
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
