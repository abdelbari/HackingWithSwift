// A brand role's More: the rest of its type beyond the face — a colour (the
// kit's own colours first, kept as references so they follow the palette,
// then a few plain ones), letter and line spacing, capitals and italic —
// as the Android twin's brand kit editor lists them. Each change is kept as
// it is made, as every brand kit change is.

import SwiftUI

struct BrandRoleMore: View {
    @Binding var face: BrandFont
    var palettes: [BrandPalette]

    /// Plain colours after the kit's own.
    private static let plain = ["#000000", "#ffffff", "#1f2430", "#6b7280"]

    var body: some View {
        DisclosureGroup("More") {
            colourRow
            spacingRow
            lineRow
            Toggle(isOn: Binding(get: { face.uppercase == true }, set: { face.uppercase = $0 })) {
                Label("Aa uppercase", systemImage: "textformat")
            }
            Toggle("Italic", isOn: Binding(get: { face.italic == true }, set: { face.italic = $0 }))
        }
    }

    /// None, then every colour of every palette as a reference, then plain.
    private var colourRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { face.color = nil } label: {
                    Image(systemName: face.color == nil ? "checkmark.circle.fill" : "circle.slash")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("None")
                ForEach(references, id: \.self) { ref in swatch(ref) }
                ForEach(Self.plain, id: \.self) { hex in swatch(hex) }
            }
            .padding(4)
        }
    }

    /// "palette:<p>:<c>" for each of the kit's colours, palette by palette.
    private var references: [String] {
        palettes.enumerated().flatMap { p, palette in
            palette.colors.indices.map { "\(BrandFont.paletteRef)\(p):\($0)" }
        }
    }

    private func swatch(_ value: String) -> some View {
        let hex = BrandFont.resolved(value, palettes: palettes) ?? "#000000"
        let chosen = face.color == value
        return Button { face.color = value } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Theme.hairline))
                .overlay { if chosen { Circle().stroke(Theme.accent, lineWidth: 3).padding(-4) } }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(ElementNames.spokenColour(hex))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// Letter spacing on a page 1080 wide, -10 to 40.
    private var spacingRow: some View {
        let value = face.letterSpacing ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Letter spacing")
                Spacer()
                Text(verbatim: "\(Int(value.rounded()))").monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: Binding(get: { value }, set: { face.letterSpacing = $0 == 0 ? nil : $0.rounded() }),
                   in: -10...40)
                .accessibilityLabel("Letter spacing")
        }
    }

    /// Line spacing, 0.8 to 2.5 times the size.
    private var lineRow: some View {
        let value = face.lineHeight ?? 1.25
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Line spacing")
                Spacer()
                Text(verbatim: String(format: "%.2f", value)).monospacedDigit()
            }
            .font(.subheadline)
            Slider(value: Binding(get: { value }, set: { face.lineHeight = ($0 * 100).rounded() / 100 }),
                   in: 0.8...2.5)
                .accessibilityLabel("Line spacing")
        }
    }
}
