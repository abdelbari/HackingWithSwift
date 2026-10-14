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
    /// The PowerPoints put in `decks` read in as new designs, one at a
    /// time, under an "Opening the PowerPoint…" card, then the sheet that
    /// says what came in, whose Open design hands the design to `onOpen`
    /// once the sheet has gone. The host empties `decks` as it takes them,
    /// so each is served once.
    func powerPointImport(_ decks: Binding<[URL]>, onOpen: @escaping (Design) -> Void) -> some View {
        modifier(PowerPointHost(decks: decks, onOpen: onOpen))
    }
}

private struct PowerPointHost: ViewModifier {
    @Binding var decks: [URL]
    var onOpen: (Design) -> Void
    @State private var working = false
    @State private var opened: PowerPoints.Opened?
    /// Open design was tapped: opened once the sheet has gone.
    @State private var opening: Design?
    @State private var failure: String?
    /// Decks taken from `decks`, read in turn — two opened together from
    /// Files are two designs, as on the Android twin.
    @State private var waiting: [URL] = []

    func body(content: Content) -> some View {
        content
            .overlay { if working { OpeningDesignCard(label: tr("Opening the PowerPoint…")) } }
            .onAppear { take() }
            .onChange(of: decks) { _, _ in take() }
            .sheet(item: $opened, onDismiss: afterSheet) { shown in
                PowerPointSheet(opened: shown) {
                    opening = shown.design
                    opened = nil
                }
            }
            .alert("Couldn't open that file", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { afterFailure() } })) {
                Button("OK") { afterFailure() }
            } message: {
                Text(failure ?? "")
            }
    }

    /// Every deck handed over moved to `waiting` and the hand-off emptied,
    /// so each is served once; then the first read if nothing else is.
    private func take() {
        guard !decks.isEmpty else { return }
        waiting.append(contentsOf: decks)
        decks = []
        next()
    }

    private func start(_ url: URL) {
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
        if let design = opening {
            opening = nil
            onOpen(design)
        }
        next()
    }

    private func afterFailure() {
        guard failure != nil else { return }
        failure = nil
        next()
    }

    /// The next deck waiting, once nothing is being read or said.
    private func next() {
        guard !waiting.isEmpty, !working, opened == nil, opening == nil, failure == nil else { return }
        start(waiting.removeFirst())
    }
}
