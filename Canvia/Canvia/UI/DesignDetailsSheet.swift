// Details — Canva's File ▸ Design details — from a Home card's menu or the
// editor's More: what the design is (DesignFacts), read only. Its type and
// size, in its unit and in pixels; its pages, the hidden ones apart; how
// long it plays; when it was made and last edited; the room it takes here
// (DesignStorage, read off the main thread); the fonts it uses with their
// weights, one missing from this phone said so with Replace… — the font
// picker in replace mode, the font picker's Replace everywhere — its
// photos, clips and songs with Show in Uploads; the brand kit it follows;
// and its last export. The Android twin's DesignDetailsSheet, in the same
// words.

import SwiftUI

struct DesignDetailsSheet: View {
    @Bindable var store: DesignStore
    /// Show in Uploads, for photos, clips or songs.
    var onShowUploads: (Uploads.Kind) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss
    /// The room it takes here; nil while it is being counted.
    @State private var bytes: Int64?
    @State private var kit: BrandKit?
    @State private var fontsHere: Set<String> = []
    /// The missing font Replace… was tapped for.
    @State private var replacing: MissingFont?

    private struct MissingFont: Identifiable {
        var id: String
    }

    private var facts: DesignFacts { DesignFacts.of(store.design, fontsAvailable: fontsHere) }

    var body: some View {
        NavigationStack {
            List {
                factsSection(facts)
                fontsSection(facts)
                mediaSection(facts)
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents(sheetDetents)
        .sheet(item: $replacing) { target in replaceSheet(target.id) }
        .task(id: store.design.id) { await read() }
    }

    /// The fonts here, the brand kit, then the storage, which reads every
    /// design.
    @MainActor
    private func read() async {
        fontsHere = Set(FontStore.faces().map { CustomFonts.key($0.id) })
        kit = DesignFacts.brandKit(store.design, kits: BrandKits.load().kits)
        let design = store.design
        bytes = await Task.detached(priority: .utility) { DesignStorage.bytes(of: design) }.value
    }

    private func factsSection(_ facts: DesignFacts) -> some View {
        Section {
            LabeledContent(tr("Type", context: "design type"), value: facts.typeName)
            LabeledContent("Size", value: ([facts.size] + [facts.pixels].compactMap { $0 }).joined(separator: " · "))
            LabeledContent("Pages", value: DesignFacts.pagesLine(facts))
            if let seconds = facts.seconds {
                LabeledContent("Duration", value: VideoStore.timeLabel(seconds))
            }
            LabeledContent("Created", value: Self.dated(facts.createdAt))
            LabeledContent("Edited", value: Self.dated(facts.updatedAt))
            LabeledContent("Storage", value: bytes.map(StorageReport.text) ?? tr("Counting…"))
            LabeledContent("Brand kit", value: kit?.name ?? tr("None"))
            LabeledContent("Last export", value: lastExport)
        } header: {
            Text(store.design.title)
        }
    }

    /// "PNG, 3 days ago", or "Not exported yet".
    private var lastExport: String {
        guard let last = DesignFacts.lastExports()[store.design.id] else { return tr("Not exported yet") }
        // One that failed says so, not its type.
        let what = last.failure == nil ? DesignFacts.exportType(last.type) : ExportChoices.failedTitle
        return tr("%@, %@", what, RelativeTime.text(ms: Double(last.at)))
    }

    /// "3 days ago · 21 Oct 2026": when, as Home's cards say it, then the
    /// date.
    static func dated(_ ms: Double) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        return RelativeTime.text(ms: ms) + " · " + date.formatted(date: .abbreviated, time: .omitted)
    }

    private func fontsSection(_ facts: DesignFacts) -> some View {
        Section {
            if facts.fonts.isEmpty {
                Text("No text in this design")
                    .foregroundStyle(.secondary)
            }
            ForEach(facts.fonts, id: \.key) { font in fontRow(font) }
        } header: {
            Text("Fonts used")
        }
    }

    private func fontRow(_ font: DesignFacts.Font) -> some View {
        let weights = DesignFacts.weightsLine(font)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(font.name)
                Text(font.missing ? tr("%@ · Not on this phone", weights) : weights)
                    .font(.footnote)
                    .foregroundStyle(font.missing ? Color.red : Color.secondary)
            }
            Spacer(minLength: 8)
            if font.missing {
                Button("Replace…") { replacing = MissingFont(id: font.key) }
                    .buttonStyle(.borderless)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// The picker in replace mode: the font chosen takes `from`'s place
    /// everywhere it is used, as one step.
    private func replaceSheet(_ from: String) -> some View {
        let name = FontStore.displayName(from, in: store.design)
        let pick: (String?) -> Void = { to in
            if let to { store.replaceFontEverywhere(from: from, to: to) }
        }
        return FontSheet(store: store, choice: FontSheet.Choice(title: tr("Replace %@ with", name), current: from,
                                                                onPick: pick, none: false))
    }

    private func mediaSection(_ facts: DesignFacts) -> some View {
        Section {
            mediaRow(trn("%d photo|%d photos", facts.photos), count: facts.photos, kind: .image)
            mediaRow(trn("%d video|%d videos", facts.videos), count: facts.videos, kind: .video)
            mediaRow(trn("%d audio file|%d audio files", facts.audio), count: facts.audio, kind: .audio)
        } header: {
            Text("Media")
        }
    }

    private func mediaRow(_ label: String, count: Int, kind: Uploads.Kind) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 8)
            if count > 0 {
                Button("Show in Uploads") { onShowUploads(kind) }
                    .buttonStyle(.borderless)
            }
        }
    }
}
