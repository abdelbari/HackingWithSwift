// Home ▸ Uploads: everything brought in — photos, clips, songs and fonts
// of your own — in a grid, filtered by kind and sorted newest or largest
// first, each tile with its size and what it is. A tap previews one, a
// clip or a song playing; its ⋯ menu starts a new design from it (as a
// share into Canvia does), says and lists the designs that use it, shares
// it or deletes it. Select deletes several at once. The header's figure is
// Settings' "Your uploads" (StorageReport.uploadsBytes). The Android
// twin's home/UploadsSheet.kt.

import AVKit
import SwiftUI

/// An upload as Home's Uploads grid shows it: what the list says of it,
/// its file and how big that is, and what it is — pixels for a photo or a
/// clip, seconds for a clip or a song, and a song's or a font's name.
struct UploadItem: Identifiable, Equatable {
    var listed: Uploads.Listed
    var file: URL
    var bytes: Int64
    var pixels: CGSize?
    var seconds: Double?
    var label: String?

    var id: String { listed.id }
    var kind: String { listed.kind }

    /// A photo or a clip: a picture to show, and to start a design from.
    var pictured: Bool { kind == Uploads.Kind.image.rawValue || kind == Uploads.Kind.video.rawValue }

    /// "1.2 MB · 4000 × 3000", "3.4 MB · 0:12", "120 KB · Lora": the line
    /// under the tile.
    var caption: String {
        let size = StorageReport.text(bytes)
        let what: String?
        if let pixels {
            what = "\(Int(pixels.width)) × \(Int(pixels.height))"
        } else if let seconds {
            what = Self.clock(seconds)
        } else {
            what = label
        }
        return what.map { tr("%@ · %@", size, $0) } ?? size
    }

    /// "0:12", "1:05:09": a length as a clock says it.
    static func clock(_ seconds: Double) -> String {
        let s = Int(max(0, seconds).rounded())
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }

    /// The upload's name, for VoiceOver and the preview.
    var name: String {
        if let label { return label }
        return kind == Uploads.Kind.video.rawValue ? tr("Clip") : tr("Photo")
    }
}

/// Home's uploads, read from the disk: every photo, clip, song and font of
/// your own whose file is still here, with what each is. Off the main
/// thread.
enum UploadsHome {
    static func items() async -> [UploadItem] {
        var out: [UploadItem] = []
        for entry in Uploads.all() {
            guard let file = StorageReport.file(of: entry) else { continue }
            let listed = Uploads.Listed(id: entry.id, kind: entry.kind.rawValue, added: entry.added)
            var item = UploadItem(listed: listed, file: file, bytes: StorageReport.bytes(of: file))
            switch entry.kind {
            case .image:
                item.pixels = MediaStore.pixelSize(entry.id)
            case .video:
                let pixels = await videoPixels(file)
                let seconds = await VideoStore.loadedDuration(of: entry.id)
                item.pixels = pixels
                item.seconds = seconds
            case .audio:
                let seconds = await AudioStore.duration(of: entry.id)
                item.seconds = seconds
                item.label = AudioStore.label(for: entry.id)
            }
            out.append(item)
        }
        for font in Uploads.fonts() {
            let file = FontStore.directory.appendingPathComponent(font.file)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            let listed = Uploads.Listed(id: font.id, kind: Uploads.fontKind, added: font.added)
            out.append(UploadItem(listed: listed, file: file, bytes: StorageReport.bytes(of: file), label: font.family))
        }
        return out
    }

    /// A clip's picture size as it plays, turned as it is shown.
    private static func videoPixels(_ file: URL) async -> CGSize? {
        let asset = AVURLAsset(url: file)
        guard let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first,
              let natural = try? await track.load(.naturalSize),
              let turn = try? await track.load(.preferredTransform) else { return nil }
        let shown = natural.applying(turn)
        return CGSize(width: abs(shown.width), height: abs(shown.height))
    }

    /// A small picture of a photo or a clip's first frame, for its tile.
    static func thumbnail(_ item: UploadItem) async -> UIImage? {
        if item.kind == Uploads.Kind.video.rawValue {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: item.file))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)
            guard let frame = try? await generator.image(at: .zero) else { return nil }
            return UIImage(cgImage: frame.image)
        }
        guard item.kind == Uploads.Kind.image.rawValue, let data = try? Data(contentsOf: item.file) else { return nil }
        return ImageDownsampler.downsample(data, maxEdge: 320)
    }
}

struct UploadsSheet: View {
    /// A design that uses an upload, to open.
    var onOpen: (Design) -> Void
    /// Import's photo and clip picker.
    var onImport: () -> Void
    /// A new design from the upload's file, as a share into Canvia starts
    /// one.
    var onNewDesign: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var items: [UploadItem]?
    @State private var totalBytes: Int64 = 0
    /// Every design on the shelf read once, for what each upload is used
    /// in, and the brand kits, whose photos are a use too.
    @State private var usages: [String: [Design]] = [:]
    @State private var kits: BrandKits?
    @State private var filter: String?
    @State private var largest = false
    @State private var selecting = false
    @State private var picked: Set<String> = []
    @State private var previewing: UploadItem?
    @State private var listing: UploadItem?
    @State private var sharing: ShareURL?
    @State private var deleting: [UploadItem]?

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Uploads")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .safeAreaInset(edge: .bottom, spacing: 0) { if selecting { selectBar } }
        }
        .task { await load() }
        .sheet(item: $previewing) { UploadPreview(item: $0) }
        .sheet(item: $sharing) { ShareSheet(urls: [$0.url]) }
        .sheet(item: $listing) { item in usageList(item) }
        .confirmationDialog(deleteQuestion.title, isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { chosen in
            Button("Delete", role: .destructive) { delete(chosen) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            if let text = deleteQuestion.text { Text(text) }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let items {
            if items.isEmpty { emptyState } else { grid }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            if selecting {
                Button(allPicked ? "Deselect all" : "Select all") { picked = allPicked ? [] : Set(shown.map(\.id)) }
                    .disabled(shown.isEmpty)
            } else {
                Button("Done") { dismiss() }
            }
        }
        ToolbarItem(placement: .primaryAction) {
            if selecting {
                Button("Done") { endSelect() }
            } else if !(items ?? []).isEmpty {
                Button("Select") { selecting = true }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Photos, clips and sounds you add appear here")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button("Import") { onImport() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                filterChips
                if shown.isEmpty {
                    Text("Nothing of this kind yet.")
                        .foregroundStyle(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(shown) { item in tile(item) }
                }
            }
            .padding()
        }
    }

    /// The room the uploads take, as Settings says it, and Import.
    private var header: some View {
        HStack {
            Text(StorageReport.text(totalBytes))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Import") { onImport() }
        }
    }

    /// The kinds, then the order; both wrap onto more lines at the largest
    /// text sizes rather than running off the edge.
    private var filterChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { kindChips }
                VStack(alignment: .leading, spacing: 8) { kindChips }
            }
            HStack(spacing: 8) {
                chip(tr("Newest"), selected: !largest) { largest = false }
                chip(tr("Largest"), selected: largest) { largest = true }
            }
        }
    }

    @ViewBuilder
    private var kindChips: some View {
        chip(tr("All"), selected: filter == nil) { filter = nil }
        ForEach(Uploads.filters, id: \.self) { kind in
            chip(Self.filterName(kind), selected: filter == kind) { filter = kind }
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

    /// A filter's name for a kind of upload.
    static func filterName(_ kind: String) -> String {
        switch kind {
        case Uploads.Kind.image.rawValue: return tr("Photos")
        case Uploads.Kind.video.rawValue: return tr("Clips")
        case Uploads.Kind.audio.rawValue: return tr("Audio")
        default: return tr("Fonts")
        }
    }

    // MARK: tiles

    private func tile(_ item: UploadItem) -> some View {
        UploadTile(item: item, picked: picked.contains(item.id), selecting: selecting,
                   used: usages[item.id]?.count ?? 0, inBrandKit: inBrandKit(item)) {
            if selecting {
                if picked.contains(item.id) { picked.remove(item.id) } else { picked.insert(item.id) }
            } else {
                previewing = item
            }
        } menu: {
            menu(item)
        }
    }

    @ViewBuilder
    private func menu(_ item: UploadItem) -> some View {
        if item.pictured {
            Button { start(item) } label: { Label("New design from this", systemImage: "plus.square.on.square") }
        }
        Button { listing = item } label: {
            Label(Uploads.usedIn(usages[item.id]?.count ?? 0, brandKit: inBrandKit(item)), systemImage: "doc.on.doc")
        }
        Button { sharing = ShareURL(url: item.file) } label: { Label("Share", systemImage: "square.and.arrow.up") }
        Button(role: .destructive) { deleting = [item] } label: { Label("Delete", systemImage: "trash") }
    }

    private var selectBar: some View {
        let chosen = (items ?? []).filter { picked.contains($0.id) }
        return HStack {
            Text(trn("%d selected|%d selected", chosen.count))
                .font(.subheadline.weight(.semibold))
            Spacer()
            Button("Delete", role: .destructive) { deleting = chosen }
                .disabled(chosen.isEmpty)
        }
        .padding()
        .background(.bar)
    }

    // MARK: what is shown

    private var shown: [UploadItem] {
        let all = items ?? []
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return Uploads.sorted(all.map(\.listed), kind: filter, largest: largest) { byId[$0.id]?.bytes ?? 0 }
            .compactMap { byId[$0.id] }
    }

    /// Whether a brand kit shows `item`'s photo.
    private func inBrandKit(_ item: UploadItem) -> Bool {
        kits.map { Uploads.inBrandKit($0, id: item.id) } ?? false
    }

    private var allPicked: Bool { !shown.isEmpty && picked.count == shown.count }

    private func endSelect() {
        selecting = false
        picked = []
    }

    /// The question for what is being deleted: every design any of them is
    /// in, once each.
    private var deleteQuestion: (title: String, text: String?) {
        let chosen = deleting ?? []
        var designs = Set<String>()
        for item in chosen { for design in usages[item.id] ?? [] { designs.insert(design.id) } }
        return Uploads.deletingFromHome(max(chosen.count, 1), designs: designs.count,
                                        brandKit: chosen.contains { inBrandKit($0) })
    }

    // MARK: work

    private func load() async {
        let read = await UploadsHome.items()
        let total = await Task.detached(priority: .userInitiated) { StorageReport.uploadsBytes() }.value
        items = read
        totalBytes = total
        usages = await Task.detached(priority: .utility) { Uploads.usageIndex(DesignLibrary.shelfDesigns()) }.value
        kits = await Task.detached(priority: .utility) { BrandKits.load() }.value
    }

    /// The designs that use it, each opening.
    private func usageList(_ item: UploadItem) -> some View {
        let designs = usages[item.id] ?? []
        return NavigationStack {
            List(designs, id: \.id) { design in
                Button(design.title) {
                    listing = nil
                    onOpen(design)
                }
            }
            .navigationTitle(Uploads.usedIn(designs.count, brandKit: inBrandKit(item)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { listing = nil } }
            }
        }
        .presentationDetents([.medium])
    }

    private func start(_ item: UploadItem) {
        onNewDesign(item.file)
    }

    /// Off the list, and unstarred — or the star would keep their files —
    /// as the editor's Add sheet deletes one; a font's file goes too. The
    /// designs that used them show an empty frame once the sweep has taken
    /// the files.
    private func delete(_ chosen: [UploadItem]) {
        deleting = nil
        endSelect()
        let gone = Set(chosen.map(\.id))
        items = items?.filter { !gone.contains($0.id) }
        for item in chosen {
            if item.kind == Uploads.fontKind {
                FontStore.remove(item.id)
            } else {
                Uploads.remove(item.id)
                if Favorites.isFavorite("upload", item.id) { Favorites.toggle("upload", item.id) }
            }
        }
        Task { await load() }
    }
}

/// One upload: its picture — a photo, a clip's first frame, a note for a
/// song, a font's name — with its size and what it is under it, and its ⋯
/// menu. Picked with a tick while selecting.
private struct UploadTile<Actions: View>: View {
    var item: UploadItem
    var picked: Bool
    var selecting: Bool
    var used: Int
    var inBrandKit: Bool
    var onTap: () -> Void
    @ViewBuilder var menu: () -> Actions
    @State private var picture: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: onTap) { face }
                .buttonStyle(.plain)
                .contextMenu { if !selecting { menu() } }
            HStack(alignment: .top, spacing: 2) {
                Text(item.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer(minLength: 0)
                if !selecting {
                    Menu { menu() } label: {
                        Image(systemName: "ellipsis")
                            .frame(minWidth: 28, minHeight: 28)
                    }
                    .accessibilityLabel("More")
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(picked ? tr("%@, %@, selected", item.name, item.caption) : tr("%@, %@", item.name, item.caption))
        .accessibilityHint(Uploads.usedIn(used, brandKit: inBrandKit))
        .task(id: item.id) { if item.pictured { picture = await UploadsHome.thumbnail(item) } }
    }

    private var face: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Theme.card)
            .aspectRatio(1, contentMode: .fit)
            .overlay { picturePart }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay {
                if picked { RoundedRectangle(cornerRadius: 10).stroke(Theme.accent, lineWidth: 3) }
            }
            .overlay(alignment: .topTrailing) {
                if selecting {
                    Image(systemName: picked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(picked ? Theme.accent : Color.white)
                        .padding(6)
                }
            }
    }

    @ViewBuilder
    private var picturePart: some View {
        if let picture {
            Image(uiImage: picture).resizable().scaledToFill()
        } else if item.kind == Uploads.Kind.audio.rawValue {
            Image(systemName: "music.note").font(.title).foregroundStyle(.secondary)
        } else if item.kind == Uploads.fontKind {
            Text(item.label ?? "Aa").font(.headline).lineLimit(2).padding(6)
        } else {
            Image(systemName: item.kind == Uploads.Kind.video.rawValue ? "film" : "photo").foregroundStyle(.secondary)
        }
    }
}

/// An upload seen whole: a photo, a clip or a song playing, a font's name.
private struct UploadPreview: View {
    var item: UploadItem
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var picture: UIImage?
    @State private var playing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                shown
                Text(item.caption).font(.footnote).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task(id: item.id) { await prepare() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var shown: some View {
        switch item.kind {
        case Uploads.Kind.video.rawValue:
            if let player { VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit) }
        case Uploads.Kind.audio.rawValue:
            Button {
                if playing { player?.pause() } else { player?.play() }
                playing.toggle()
            } label: {
                Label(playing ? "Pause" : "Play", systemImage: playing ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title)
            }
        case Uploads.fontKind:
            Text(item.label ?? "").font(.title)
        default:
            if let picture {
                Image(uiImage: picture).resizable().scaledToFit()
                    .accessibilityLabel(item.name)
            } else {
                ProgressView()
            }
        }
    }

    private func prepare() async {
        switch item.kind {
        case Uploads.Kind.video.rawValue, Uploads.Kind.audio.rawValue:
            let made = AVPlayer(url: item.file)
            player = made
            // A clip plays as it opens; a song waits for Play.
            if item.kind == Uploads.Kind.video.rawValue { made.play() }
        case Uploads.Kind.image.rawValue:
            let file = item.file
            picture = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: file)).flatMap { ImageDownsampler.downsample($0, maxEdge: 2048) }
            }.value
        default:
            break
        }
    }
}
