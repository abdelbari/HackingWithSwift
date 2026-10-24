// The crop bars' frame shapes, a photo's and a graphic's alike: Free, the
// picture's own, the orientation chip, the shared ratios (CropAspect) and
// Custom…, which asks for a width and a height. The chip the frame has is
// lit, named the way round the frame has it, and the orientation chip shows
// a portrait or landscape frame as the frame is, turning the lit ratio the
// other way round; it waits on Free, Original and 1:1.

import SwiftUI

struct CropRatioChips: View {
    /// The chip the frame has (CropAspect.matched).
    var match: CropAspect.Match
    /// Whether the frame is taller than it is wide.
    var portrait: Bool
    /// A chip chosen: its ratio, the way round it shows.
    var onAspect: (CropAspect, Bool) -> Void
    /// The orientation chip.
    var onTurn: () -> Void
    /// Custom…'s ratio, width over height.
    var onCustom: (Double) -> Void

    @State private var asking = false
    @State private var typedW = ""
    @State private var typedH = ""

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.free)
                chip(.original)
                turnChip
                ForEach(CropAspect.allCases.filter { $0.sides != nil }, id: \.self) { aspect in
                    chip(aspect)
                }
                customChip
            }
        }
        .alert("Custom ratio", isPresented: $asking) {
            TextField("Width", text: $typedW).keyboardType(.numberPad)
            TextField("Height", text: $typedH).keyboardType(.numberPad)
            Button("Apply") { applyCustom() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Whole numbers from 1 to \(CropAspect.customMost).")
        }
    }

    private func chip(_ aspect: CropAspect) -> some View {
        let lit = aspect == match.aspect
        let turned = lit && match.turned
        return Button(aspect.name(turned: turned)) { onAspect(aspect, turned) }
            .buttonStyle(.bordered)
            .tint(lit ? Theme.accent : .secondary)
            .controlSize(.small)
            .accessibilityAddTraits(lit ? .isSelected : [])
    }

    /// Portrait or landscape, as the frame is: the lit ratio turned.
    private var turnChip: some View {
        Button(action: onTurn) {
            Image(systemName: portrait ? "rectangle.portrait" : "rectangle")
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.small)
        .disabled(!match.aspect.turns)
        .accessibilityLabel("Orientation")
        .accessibilityValue(portrait ? tr("Portrait") : tr("Landscape"))
        .accessibilityHint("Turns the ratio the other way round")
    }

    private var customChip: some View {
        Button("Custom…") {
            typedW = ""
            typedH = ""
            asking = true
        }
        .buttonStyle(.bordered)
        .tint(.secondary)
        .controlSize(.small)
    }

    /// The typed ratio applied, when both are whole numbers from 1 to 100.
    private func applyCustom() {
        guard let ratio = CropAspect.customRatio(typedW, typedH) else { return }
        onCustom(ratio)
    }
}
