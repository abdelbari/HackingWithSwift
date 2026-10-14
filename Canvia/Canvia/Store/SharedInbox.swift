// Photos, videos, PDFs and SVGs handed to Canvia from another app.
//
// The Android twin takes them from the share sheet; here they come through
// "Open in" — the document types in Canvia-Info.plist — one file to each
// onOpenURL, so files arriving together are gathered for a moment first. A
// Share Extension, as Canva has, would be a target of its own; this needs
// none. Either way they land as the Android twin lands them: copied into
// inbox/<uuid>/ (in Application Support) with a manifest beside them,
//
//   inbox/<uuid>/manifest.json  {"version":1,"items":[{"kind":"image",
//                                "file":"0.jpg","mime":"image/jpeg"}],
//                                "createdAt":<epoch ms>}
//
// and the "New design from shared" sheet makes a design from them, or adds
// them to one. The folder goes once they are in.

import AVFoundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

enum SharedInbox {

    /// The most items one share brings in.
    static let maxItems = 20

    /// A design sized to its photo is never longer than this on either side.
    static let maxFitEdge: Double = 4000

    enum Kind: String, Codable, Sendable {
        case image, video, pdf, svg, anim
    }

    struct Item: Codable, Equatable, Sendable {
        var kind: Kind
        /// Its file in the inbox folder: "0.jpg".
        var file: String
        var mime: String

        init(kind: Kind, file: String, mime: String) {
            self.kind = kind
            self.file = file
            self.mime = mime
        }

        private enum CodingKeys: String, CodingKey { case kind, file, mime }

        /// A missing mime reads as "", as the Android twin reads it; the
        /// kind and the file are needed.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = try c.decode(Kind.self, forKey: .kind)
            file = try c.decode(String.self, forKey: .file)
            mime = (try? c.decode(String.self, forKey: .mime)) ?? ""
        }
    }

    struct ShareManifest: Codable, Equatable, Sendable {
        var version = 1
        var items: [Item] = []
        /// When it was shared, in epoch milliseconds.
        var createdAt: Int64 = 0

        init(items: [Item] = [], createdAt: Int64 = 0) {
            self.items = items
            self.createdAt = createdAt
        }

        private enum CodingKeys: String, CodingKey { case version, items, createdAt }

        /// Lenient, as the other phone or a later build may write more: an
        /// item of a kind this build does not know, or with no safe file
        /// name, is passed over.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            version = (try? c.decode(Int.self, forKey: .version)) ?? 1
            let raw = (try? c.decode([ReadableItem].self, forKey: .items)) ?? []
            items = raw.compactMap(\.item)
            createdAt = (try? c.decode(Int64.self, forKey: .createdAt))
                ?? (try? c.decode(Double.self, forKey: .createdAt)).flatMap { Int64(exactly: $0.rounded()) } ?? 0
        }

        private struct ReadableItem: Decodable {
            var item: Item?
            init(from decoder: Decoder) throws {
                guard let read = try? Item(from: decoder), DesignPackage.isSafeFileName(read.file) else { return }
                item = read
            }
        }

        static func read(_ data: Data) -> ShareManifest? {
            try? JSONDecoder().decode(ShareManifest.self, from: data)
        }

        var data: Data? {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            return try? encoder.encode(self)
        }
    }

    /// One share, landed: its folder's id and what is in it, and how many
    /// items were handed over — those that would not copy in counted among
    /// what could not be opened, as the Android twin counts what was shared.
    struct Box: Identifiable, Equatable, Sendable {
        var id: String
        var manifest: ShareManifest
        var asked: Int

        init(id: String, manifest: ShareManifest, asked: Int? = nil) {
            self.id = id
            self.manifest = manifest
            self.asked = max(asked ?? manifest.items.count, manifest.items.count)
        }

        var directory: URL { SharedInbox.directory(for: id) }

        func url(of item: Item) -> URL { directory.appendingPathComponent(item.file) }
    }

    /// In Application Support rather than Documents, whose "Inbox" the
    /// system keeps for files handed over — and may share its name with.
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("inbox", isDirectory: true)
    }

    static func directory(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    // MARK: kinds

    /// What a file is, by its type: an animated-capable GIF or WebP goes
    /// the animated pictures' way (a still one still comes in as a photo),
    /// an SVG as a shape, any other picture as a photo; nil for a file that
    /// is none of these — a design file, say.
    static func kind(for type: UTType) -> Kind? {
        if type.conforms(to: .svg) { return .svg }
        if type.conforms(to: .gif) || type.conforms(to: .webP) { return .anim }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .pdf) { return .pdf }
        return nil
    }

    static func kind(of url: URL) -> Kind? {
        UTType(filenameExtension: url.pathExtension.lowercased()).flatMap { kind(for: $0) }
    }

    // MARK: landing

    /// The files copied into a fresh inbox folder, numbered, with the
    /// manifest beside them — at most `maxItems`, and only those of a kind
    /// Canvia takes. Nil when none could be landed.
    static func land(_ urls: [URL], now: Date = Date()) -> Box? {
        let id = UUID().uuidString.lowercased()
        let dir = directory(for: id)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var items: [Item] = []
        for url in urls.prefix(maxItems) {
            guard let kind = kind(of: url) else { continue }
            let ext = url.pathExtension.lowercased()
            let file = "\(items.count).\(ext.isEmpty ? "bin" : ext)"
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard (try? FileManager.default.copyItem(at: url, to: dir.appendingPathComponent(file))) != nil else { continue }
            let mime = UTType(filenameExtension: ext)?.preferredMIMEType ?? "application/octet-stream"
            items.append(Item(kind: kind, file: file, mime: mime))
        }
        let manifest = ShareManifest(items: items, createdAt: Int64((now.timeIntervalSince1970 * 1000).rounded()))
        guard !items.isEmpty, let data = manifest.data,
              (try? data.write(to: dir.appendingPathComponent("manifest.json"), options: .atomic)) != nil else {
            remove(id)
            return nil
        }
        return Box(id: id, manifest: manifest, asked: min(urls.count, maxItems))
    }

    /// A landed share read back, as the Android twin's would be.
    static func open(_ id: String) -> Box? {
        guard DesignPackage.isSafeFileName(id),
              let data = try? Data(contentsOf: directory(for: id).appendingPathComponent("manifest.json")),
              let manifest = ShareManifest.read(data) else { return nil }
        return Box(id: id, manifest: manifest)
    }

    /// The folder gone, once its items are in (or the share was put aside).
    static func remove(_ id: String) {
        guard DesignPackage.isSafeFileName(id) else { return }
        try? FileManager.default.removeItem(at: directory(for: id))
    }

    /// Inbox folders a day old or more — a sheet never answered, the app
    /// stopped before it was — gone. Run at launch, as the Android twin's
    /// Inbox.sweep is.
    static func sweep(now: Date = Date(), in folder: URL = SharedInbox.root) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys) else { return }
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(keys)), values.isDirectory == true,
                  let changed = values.contentModificationDate,
                  now.timeIntervalSince(changed) > dayAge else { continue }
            try? fm.removeItem(at: entry)
        }
    }

    /// How old an inbox folder is let get before the sweep takes it.
    static let dayAge: TimeInterval = 24 * 3600

    // MARK: sizes

    /// The first item's size in pixels, upright: a picture's, a clip's
    /// frame, or a PDF's first page as it is drawn in. Nil when it cannot
    /// be read, or for an SVG.
    static func pixelSize(of item: Item, in box: Box) async -> CGSize? {
        let url = box.url(of: item)
        switch item.kind {
        case .image, .anim:
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
                  let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue else { return nil }
            // EXIF orientations 5 to 8 are turned a quarter.
            let orientation = (props[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
            return orientation >= 5 ? CGSize(width: h, height: w) : CGSize(width: w, height: h)
        case .video:
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let loaded = try? await track.load(.naturalSize, .preferredTransform) else { return nil }
            let turned = loaded.0.applying(loaded.1)
            return CGSize(width: abs(turned.width), height: abs(turned.height))
        case .pdf:
            guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else { return nil }
            let box = page.getBoxRect(.cropBox)
            let turned = page.rotationAngle == 90 || page.rotationAngle == 270
            let w = turned ? box.height : box.width, h = turned ? box.width : box.height
            guard w > 0, h > 0 else { return nil }
            // As PDFImporter draws a page in: 1600 on the long side.
            let scale = min(1600 / max(w, h), 4)
            return CGSize(width: (w * scale).rounded(), height: (h * scale).rounded())
        case .svg:
            return nil
        }
    }

    /// "Fit to the photo": the photo's own size, whole pixels, its long
    /// edge brought down to `maxFitEdge` when it is longer.
    static func fitSize(_ pixels: CGSize) -> CGSize {
        let w = max(Double(pixels.width), 1), h = max(Double(pixels.height), 1)
        let scale = min(1, maxFitEdge / max(w, h))
        return CGSize(width: max(1, (w * scale).rounded()), height: max(1, (h * scale).rounded()))
    }

    /// How far a design type's shape is from the photo's: the distance
    /// between their aspect ratios on a log scale, so twice as wide and
    /// twice as tall are equally far, and a square is as near to 4:5 as
    /// 5:4 is.
    static func aspectDistance(_ size: CGSize, _ preset: SizePreset) -> Double {
        let photo = log(max(Double(size.width), 1) / max(Double(size.height), 1))
        let type = log(max(preset.w, 1) / max(preset.h, 1))
        return abs(photo - type)
    }

    /// The design types nearest the photo's shape, nearest first; a tie
    /// keeps the catalogue's order. When the size is unknown — nil, as for
    /// an SVG or a picture that does not read, or not a positive size — the
    /// first types in the catalogue, as the Android twin offers them; the
    /// sheet then has no "Fit to the photo" either.
    static func suggestions(for size: CGSize?, among presets: [SizePreset] = SizePreset.all,
                            count: Int = 4) -> [SizePreset] {
        guard let size, size.width > 0, size.height > 0,
              size.width.isFinite, size.height.isFinite else { return Array(presets.prefix(count)) }
        let ranked = presets.enumerated().sorted { a, b in
            let da = aspectDistance(size, a.element), db = aspectDistance(size, b.element)
            return da != db ? da < db : a.offset < b.offset
        }
        return ranked.prefix(count).map { $0.element }
    }

    // MARK: bringing in

    /// What bringing a share in came to: a page for each photo or clip, a
    /// page for each of a PDF's pages, and how many items could not be
    /// opened.
    struct Brought: Sendable {
        var pages: [Page] = []
        var failed = 0
        var total = 0
    }

    /// "Couldn't open 1 of 3 items" — "Couldn't open that item" when it
    /// was the only one, as the Android twin says it — or nil when every one
    /// came in.
    static func failureText(failed: Int, total: Int) -> String? {
        guard failed > 0 else { return nil }
        return total <= 1 ? "Couldn't open that item" : "Couldn't open \(failed) of \(total) items"
    }

    /// Each item brought in as one element on a page of its own, fitted
    /// inside a page of `pageSize` and centred: a photo or a clip kept among
    /// your uploads, an animated GIF or WebP as it came, an SVG's first
    /// outline as a shape, a PDF a page for each of its pages. Files only,
    /// away from the main actor.
    static func bringIn(_ box: Box, pageSize: CGSize) -> Brought {
        // Those handed over that never landed are counted as not opened.
        var brought = Brought(failed: box.asked - box.manifest.items.count, total: box.asked)
        for item in box.manifest.items {
            let pages = bringIn(item, from: box, pageSize: pageSize)
            if pages.isEmpty { brought.failed += 1 }
            brought.pages += pages
        }
        return brought
    }

    private static func bringIn(_ item: Item, from box: Box, pageSize: CGSize) -> [Page] {
        let url = box.url(of: item)
        switch item.kind {
        case .image, .anim:
            guard let data = try? Data(contentsOf: url) else { return [] }
            if item.kind == .anim, let animated = AnimStore.bringIn(data) {
                return [page(src: animated.src, natural: animated.natural, size: pageSize)]
            }
            guard let prepared = ImageDownsampler.prepare(data), let src = MediaStore.store(prepared) else { return [] }
            Uploads.record(source: src)
            return [page(src: src, natural: prepared.natural, size: pageSize)]
        case .video:
            guard let data = try? Data(contentsOf: url),
                  let id = VideoStore.store(data, ext: url.pathExtension),
                  let poster = VideoStore.poster(id) else { return [] }
            Uploads.record(id, kind: .video)
            return [page(src: VideoStore.src(id, at: nil), natural: poster.size, size: pageSize)]
        case .pdf:
            guard let data = try? Data(contentsOf: url) else { return [] }
            var pages: [Page] = []
            PDFImporter.forEachPage(of: data) { image in
                if let src = MediaStore.storeOpaque(image) {
                    pages.append(page(src: src, natural: image.size, size: pageSize))
                }
            }
            return pages
        case .svg:
            guard let d = SVGPath.importFirstPath(fromFileAt: url) else { return [] }
            // Square at 0.4 of the page's shorter side and centred, as one
            // from the Add panel is, and as the Android twin brings it in.
            let side = (min(pageSize.width, pageSize.height) * 0.4).rounded()
            var el = Element.shape("rect", w: side, h: side)
            el.pathData = d
            el.x = ((pageSize.width - side) / 2).rounded()
            el.y = ((pageSize.height - side) / 2).rounded()
            return [Page(elements: [el])]
        }
    }

    /// A page holding one picture, as large as fits and centred.
    private static func page(src: String, natural: CGSize, size: CGSize) -> Page {
        let nw = max(natural.width, 1), nh = max(natural.height, 1)
        let scale = min(size.width / nw, size.height / nh)
        var el = Element.image(src, w: (nw * scale).rounded(), h: (nh * scale).rounded())
        el.x = ((size.width - el.w) / 2).rounded()
        el.y = ((size.height - el.h) / 2).rounded()
        return Page(elements: [el])
    }
}
