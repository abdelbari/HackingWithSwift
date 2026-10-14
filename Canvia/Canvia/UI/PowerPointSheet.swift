// After a PowerPoint is opened as a design: its name, what came in and what
// could not ("Imported 12 slides. 3 items couldn't be brought in (2 charts,
// 1 SmartArt)."), and Open design. The design is on the shelf already, so
// closing the sheet keeps it. The Android twin's PowerPointSheet.

import SwiftUI

struct PowerPointSheet: View {
    let opened: PowerPoints.Opened
    var onOpen: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(opened.design.title)
                .font(.title2.weight(.bold))
                .lineLimit(2)
                .accessibilityAddTraits(.isHeader)
            Text(opened.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            buttons
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium])
    }

    private var buttons: some View {
        HStack(spacing: 8) {
            Spacer()
            Button("Close") { dismiss() }
                .frame(minHeight: 44)
            Button("Open design", action: onOpen)
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
        }
        .padding(.top, 8)
    }
}

extension View {
    /// The PowerPoint put in `deck` read in as a new design under an
    /// "Opening the PowerPoint…" card, then the sheet that says what came
    /// in, whose Open design hands the design to `onOpen` once the sheet has
    /// gone.
    func powerPointImport(_ deck: Binding<URL?>, onOpen: @escaping (Design) -> Void) -> some View {
        modifier(PowerPointHost(deck: deck, onOpen: onOpen))
    }
}

private struct PowerPointHost: ViewModifier {
    @Binding var deck: URL?
    var onOpen: (Design) -> Void
    @State private var working = false
    @State private var opened: PowerPoints.Opened?
    /// Open design was tapped: opened once the sheet has gone.
    @State private var opening: Design?
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .overlay { if working { OpeningDesignCard(label: "Opening the PowerPoint…") } }
            .onChange(of: deck) { _, url in
                if let url { start(url) }
            }
            .sheet(item: $opened, onDismiss: afterSheet) { shown in
                PowerPointSheet(opened: shown) {
                    opening = shown.design
                    opened = nil
                }
            }
            .alert("Couldn't open that file", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            } message: {
                Text(failure ?? "")
            }
    }

    private func start(_ url: URL) {
        if deck != nil { deck = nil }
        guard !working else { return }
        working = true
        let taken = DesignLibrary.recents().map(\.title)
        Task { @MainActor in
            defer {
                working = false
                DesignPackage.discardInboxCopy(url)
            }
            do {
                opened = try await PowerPoints.importFile(at: url, taken: taken)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private func afterSheet() {
        guard let design = opening else { return }
        opening = nil
        onOpen(design)
    }
}
