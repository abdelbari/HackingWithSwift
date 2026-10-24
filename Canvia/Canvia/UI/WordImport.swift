// Word documents — picked from Import, tapped in Files or opened in Canvia
// from another app — each made a new Doc (WordDocs) under an "Opening the
// Word document…" card, and opened; one that does not open is said. As the
// PowerPoint import serves its decks.

import SwiftUI

extension View {
    /// The Word documents put in `documents` read in as new Docs, one at a
    /// time, each handed to `onOpen`. The host empties `documents` as it
    /// takes them, so each is served once.
    func wordImport(_ documents: Binding<[URL]>, onOpen: @escaping (Design) -> Void) -> some View {
        modifier(WordImportHost(documents: documents, onOpen: onOpen))
    }
}

private struct WordImportHost: ViewModifier {
    @Binding var documents: [URL]
    var onOpen: (Design) -> Void
    @State private var working = false
    @State private var failure: String?
    @State private var waiting: [URL] = []

    func body(content: Content) -> some View {
        content
            .overlay { if working { OpeningDesignCard(label: tr("Opening the Word document…")) } }
            .onAppear { take() }
            .onChange(of: documents) { _, _ in take() }
            .alert("Couldn't open that file", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { afterFailure() } })) {
                Button("OK") { afterFailure() }
            } message: {
                Text(failure ?? "")
            }
    }

    private func take() {
        guard !documents.isEmpty else { return }
        waiting.append(contentsOf: documents)
        documents = []
        next()
    }

    private func start(_ url: URL) {
        working = true
        let taken = DesignLibrary.recents().map(\.title)
        Task { @MainActor in
            do {
                onOpen(try await WordDocs.importFile(at: url, taken: taken))
            } catch {
                failure = error.localizedDescription
            }
            working = false
            DesignPackage.discardInboxCopy(url)
            next()
        }
    }

    private func afterFailure() {
        guard failure != nil else { return }
        failure = nil
        next()
    }

    /// The next document waiting, once nothing is being read or said.
    private func next() {
        guard !waiting.isEmpty, !working, failure == nil else { return }
        start(waiting.removeFirst())
    }
}

/// Home's Word documents and Docs: Import's Word document picker, the
/// documents it and the design file picker hand over made Docs, and a
/// card's Turn into a Doc — asked whether the notes come too, then the Doc
/// made beside the design and opened. Apart from Home's body, so its chain
/// type-checks in reasonable time.
struct WordDocsOnHome: ViewModifier {
    @Binding var picking: Bool
    @Binding var documents: [URL]
    @Binding var turning: RecentDesign?
    var onOpen: (Design) -> Void
    var changed: () -> Void
    @State private var failure: String?

    func body(content: Content) -> some View {
        content
            .background {
                Color.clear.fileImporter(isPresented: $picking, allowedContentTypes: [WordDocs.contentType]) { result in
                    if case .success(let url) = result { documents.append(url) }
                }
            }
            .wordImport($documents, onOpen: onOpen)
            .sheet(item: $turning) { recent in
                TurnIntoDocSheet { notes in turn(recent, notes: notes) }
            }
            .alert("Couldn't make the Doc", isPresented: Binding(
                get: { failure != nil }, set: { if !$0 { failure = nil } })) {
                Button("OK") { failure = nil }
            }
    }

    /// The card's design made a new Doc beside it, which opens.
    @MainActor
    private func turn(_ recent: RecentDesign, notes: Bool) {
        guard let design = DesignLibrary.load(id: recent.id),
              let doc = WordDocs.turnIntoDoc(design, notes: notes, taken: DesignLibrary.recents().map(\.title)) else {
            failure = tr("Couldn't make the Doc")
            return
        }
        changed()
        // Once the sheet has gone, or the editor would not come up.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            onOpen(doc)
        }
    }
}
