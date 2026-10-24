// The typing bar's highlighter: a marker colour behind the words chosen, as
// Canva marks a phrase in a heading. None takes the marker away; then the
// brand's colours, the recent colours and five marker presets
// (Spans.highlightPresets), the same on the Android twin. Each pick is one
// step (DesignStore.highlightWords).

import SwiftUI

struct HighlightSheet: View {
    @Bindable var store: DesignStore
    /// For words other than the box typed in — a Doc block's: the marker
    /// they share, and what a pick does. Nil for the store's own.
    var marked: (highlight: String?, shared: Bool)?
    var onPick: ((String?) -> Void)?
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if !marker.shared {
                        Text("Mixed").font(.subheadline).foregroundStyle(.secondary)
                    }
                    noneButton
                    section(tr("Markers"), colors: Spans.highlightPresets)
                    let brand = BrandKit.load().palettes.flatMap(\.colors)
                    if !brand.isEmpty { section(tr("Brand colours"), colors: brand) }
                    let recents = RecentColors.all
                    if !recents.isEmpty { section(tr("Recent"), colors: recents) }
                }
                .padding()
            }
            .navigationTitle("Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents(sheetDetents)
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }

    /// The marker the words share, and whether they share one.
    private var marker: (highlight: String?, shared: Bool) {
        marked ?? store.wordHighlight
    }

    /// A marker picked, or None.
    private func pick(_ hex: String?) {
        if let onPick { onPick(hex) } else { store.highlightWords(hex) }
    }

    /// The marker the words share now, for the ring.
    private var current: String? {
        marker.shared ? marker.highlight : nil
    }

    private var noneButton: some View {
        let chosen = marker.shared && marker.highlight == nil
        return Button {
            pick(nil)
        } label: {
            Label("None", systemImage: chosen ? "checkmark.circle.fill" : "circle.slash")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.accentSubtle))
        }
    }

    private func section(_ title: String, colors: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(Array(colors.enumerated()), id: \.offset) { _, hex in swatch(hex) }
            }
        }
    }

    private func swatch(_ hex: String) -> some View {
        let chosen = current?.lowercased() == hex.lowercased()
        return Button {
            pick(hex)
            RecentColors.record(hex)
        } label: {
            Circle()
                .fill(Color(hex: hex))
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(Theme.hairline))
                .overlay { if chosen { Circle().stroke(Theme.accent, lineWidth: 3).padding(-4) } }
        }
        .accessibilityLabel(ElementNames.spokenColour(hex))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}
