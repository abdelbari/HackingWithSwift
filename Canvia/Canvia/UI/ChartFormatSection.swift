// Edit chart's Format section, the Android twin's ChartFormatRows: a value's
// prefix and suffix, its decimals and compact numbers, for any kind that
// writes values; the axes' titles for a kind with axes; a donut's or ring's
// hole; the bars' gap and rounded ends; a line's weight and points; a
// pictogram's icon; how a part-to-whole kind's values read, while they are
// shown, and where the legend sits, while there is one. Each is kept in the chart's spec (only its format
// fields are read from `format`), so Update makes the chart again with it as
// one undo step.

import SwiftUI

struct ChartFormatSection: View {
    let kind: DataGraphics.ChartKind
    /// Whether the chart writes its values, and has a legend: the Labels
    /// and the Legend position are offered only then.
    let values: Bool
    let legend: Bool
    @Binding var format: ChartSpec

    /// The icons a pictogram offers, those the library has.
    private static let icons = [
        "person", "star", "favorite", "home", "directions_car", "local_cafe", "shopping_cart",
        "attach_money", "pets", "water_drop", "bolt", "school", "sports_soccer", "flight", "check_circle",
    ]

    var body: some View {
        if !kind.isProgress { numbers }
        if kind.hasAxisTitles { titles }
        if kind.hasHole || kind.hasBars || kind.hasLine { shapes }
        if kind == .pictogram { iconPicker }
        if (values && kind.isPartToWhole) || (legend && kind.hasLegend) { labelsAndLegend }
    }

    /// Value, % or both on a part-to-whole kind's values; the legend along
    /// the bottom, the top or down the right.
    private var labelsAndLegend: some View {
        Section {
            if values && kind.isPartToWhole {
                Picker("Labels", selection: labelAs) {
                    Text("Value").tag("value")
                    Text(verbatim: "%").tag("percent")
                    Text("Both").tag("both")
                }
                .pickerStyle(.segmented)
            }
            if legend && kind.hasLegend {
                Picker("Legend position", selection: legendAt) {
                    Text("Bottom").tag("bottom")
                    Text("Top").tag("top")
                    Text("Right").tag("right")
                }
            }
        }
    }

    /// The labels as they read; the kind's own (DataGraphics.labelAs) is
    /// kept as nil, so only a choice that differs is written.
    private var labelAs: Binding<String> {
        Binding(get: { DataGraphics.labelAs(withKind(format)) },
                set: { picked in
                    var bare = withKind(format)
                    bare.labelAs = nil
                    format.labelAs = picked == DataGraphics.labelAs(bare) ? nil : picked
                })
    }

    /// The legend's place; bottom, the default, kept as nil.
    private var legendAt: Binding<String> {
        Binding(get: { format.legendAt ?? "bottom" },
                set: { format.legendAt = DataGraphics.keptLegendAt($0) })
    }

    /// `spec` as the kind picked draws it, which `format` may not be yet.
    private func withKind(_ spec: ChartSpec) -> ChartSpec {
        var out = spec
        out.kind = kind.rawValue
        return out
    }

    /// The value's prefix, suffix, decimals and compact form.
    private var numbers: some View {
        Section("Format") {
            HStack(spacing: 12) {
                affixField(tr("Prefix"), text: $format.prefix)
                affixField(tr("Suffix"), text: $format.suffix)
            }
            Stepper(value: decimals, in: -1...3) {
                LabeledContent("Decimals", value: format.decimals.map(String.init) ?? tr("Auto"))
            }
            Toggle("Compact numbers", isOn: $format.compact)
        }
    }

    /// Decimals, -1 standing for Auto.
    private var decimals: Binding<Int> {
        Binding(get: { format.decimals ?? -1 }, set: { format.decimals = $0 < 0 ? nil : min($0, 3) })
    }

    private var titles: some View {
        Section("Axis titles") {
            TextField("X axis", text: text($format.xTitle))
            TextField("Y axis", text: text($format.yTitle))
        }
    }

    @ViewBuilder
    private var shapes: some View {
        Section {
            if kind.hasHole { holeSlider }
            if kind.hasBars {
                percentSlider(tr("Bar gap"), value: Binding(get: { format.gap ?? DataGraphics.defaultGap },
                                                             set: { format.gap = $0 }),
                              range: 0...DataGraphics.maxGap)
                Toggle("Rounded bars", isOn: $format.roundBars)
            }
            if kind.hasLine {
                Stepper(value: lineWidth, in: 0...DataGraphics.maxLineWidth, step: 1) {
                    LabeledContent("Line weight", value: format.lineWidth.map { "\(Int($0.rounded()))" } ?? tr("Auto"))
                }
                if kind != .radar { Toggle("Points", isOn: $format.points) }
            }
        }
    }

    private var holeSlider: some View {
        let own = kind == .donut ? DataGraphics.donutHole : DataGraphics.ringHole
        return percentSlider(tr("Hole"), value: Binding(get: { format.hole ?? own }, set: { format.hole = $0 }),
                             range: DataGraphics.minHole...DataGraphics.maxHole)
    }

    /// The line's weight, 0 standing for Auto.
    private var lineWidth: Binding<Double> {
        Binding(get: { format.lineWidth ?? 0 },
                set: { format.lineWidth = $0 < DataGraphics.minLineWidth ? nil : min($0, DataGraphics.maxLineWidth) })
    }

    private var iconPicker: some View {
        Section("Icon") {
            Picker("Icon", selection: Binding(get: { format.icon ?? DataGraphics.defaultIcon },
                                              set: { format.icon = $0 == DataGraphics.defaultIcon ? nil : $0 })) {
                ForEach(Self.icons.compactMap { IconLibrary.icon($0) }) { icon in
                    Text(icon.name).tag(icon.id)
                }
            }
        }
    }

    /// A share from `range`, in whole percent.
    private func percentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        let readout = "\(Int((value.wrappedValue * 100).rounded()))%"
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text(readout).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .accessibilityHidden(true)
            Slider(value: Binding(get: { value.wrappedValue * 100 }, set: { value.wrappedValue = $0.rounded() / 100 }),
                   in: range.lowerBound * 100...range.upperBound * 100)
                .accessibilityLabel(title)
                .accessibilityValue(readout)
        }
    }

    /// A prefix or suffix, kept to 4 characters.
    private func affixField(_ title: String, text: Binding<String?>) -> some View {
        let held = Binding<String>(get: { text.wrappedValue ?? "" },
                                   set: { text.wrappedValue = ChartSpec.affix($0) })
        return VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextField(title, text: held)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(title)
        }
    }

    /// An optional title as a field's text, blank for none.
    private func text(_ value: Binding<String?>) -> Binding<String> {
        Binding(get: { value.wrappedValue ?? "" }, set: { value.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
