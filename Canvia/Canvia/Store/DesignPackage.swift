// A design as one file: the document plus every photo and clip it uses,
// and its music.
//
// The JSON on disk points at media by id, which means nothing outside this
// app. A package inlines those files, so the design can be sent to someone,
// backed up, or opened on another device — and importing one stores the
// media under fresh ids and rewrites the references, so two imports of the
// same package never share a file.

import Foundation

enum DesignPackage {

    static let format = "canvia-package"
    static let version = 1
    static let ext = "canvia.json"

    struct Media: Codable {
        var ext: String
        var data: Data
    }

    struct Package: Codable {
        var format: String = DesignPackage.format
        var version: Int = DesignPackage.version
        var design: Design
        var media: [String: Media]
        /// The video clips the design shows, by id. Optional, so a file made
        /// before clips travelled — or with none — still reads; the Android
        /// twin writes and reads the same.
        var videos: [String: Media]?
        /// The soundtrack, by the id the design's `motion.soundtrack` names,
        /// when it is small enough and of a type both phones play
        /// (Soundtrack.packs). Optional like `videos`, so older files read,
        /// and older readers pass over it.
        var audio: [String: Media]?
    }

    /// The longest clip a file carries, in bytes; a longer one travels as
    /// its first frame, a still, so the design still looks as it did.
    static let maxPackedVideoBytes = 30 * 1024 * 1024

    /// The most a file carries of clips in all, in bytes. Past it the rest
    /// travel as stills too: every clip goes in as base64, a third larger
    /// again, and the Android twin turns away a design file over 200 MB —
    /// six clips just under the single limit made a file it would not open,
    /// even one it had written itself.
    static let maxPackedVideoTotalBytes = 100 * 1024 * 1024

    /// The clip types a file carries whole: ones both phones play. A WebM or
    /// Matroska clip, which Android plays and AVFoundation cannot read,
    /// travels as its first frame.
    static let packableVideoTypes: Set<String> = ["mp4", "m4v", "mov", "3gp"]

    /// Ids of the clips a design shows: on a photo, filling a shape, or
    /// behind a page — each of which the file has to carry, as a clip or as
    /// a still. Counted as the Android twin counts them, so the two phones
    /// weigh the same clips against the total.
    static func videoIDs(in design: Design) -> Set<String> {
        var ids = Set<String>()
        for page in design.pages {
            if case .image(let src) = page.background, let parts = VideoStore.split(src) { ids.insert(parts.id) }
            for el in page.elements {
                if let src = el.src, let parts = VideoStore.split(src) { ids.insert(parts.id) }
                if let fill = el.fill, fill.kind == "image", let src = fill.src, let parts = VideoStore.split(src) {
                    ids.insert(parts.id)
                }
            }
        }
        return ids
    }

    /// Of the clips listed — each one's size in bytes and file type, by id —
    /// the ones a file carries whole: taken in id order, each no longer than
    /// `maxPackedVideoBytes` and of a packable type, while the running total
    /// stays within `maxPackedVideoTotalBytes`. The Android twin chooses by
    /// the same rule, so a design packs the same on either phone; the rest
    /// travel as stills.
    static func packedVideoIDs(_ clips: [String: (bytes: Int, ext: String)]) -> Set<String> {
        var packed = Set<String>()
        var total = 0
        for id in clips.keys.sorted() {
            guard let clip = clips[id] else { continue }
            guard clip.bytes <= maxPackedVideoBytes,
                  packableVideoTypes.contains(clip.ext.lowercased()) else { continue }
            guard total + clip.bytes <= maxPackedVideoTotalBytes else { continue }
            total += clip.bytes
            packed.insert(id)
        }
        return packed
    }

    /// The design with each clip packed into `videos`, or — too long to
    /// carry, past the total, of a type the other phone cannot play, or
    /// unreadable — replaced by its first frame packed as a photo.
    static func packingVideos(_ design: Design, media: inout [String: Media], videos: inout [String: Media]) -> Design {
        var files: [String: URL] = [:]
        var clips: [String: (bytes: Int, ext: String)] = [:]
        for id in videoIDs(in: design) {
            guard let url = VideoStore.url(for: id) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            files[id] = url
            clips[id] = (bytes: size, ext: url.pathExtension.lowercased())
        }
        let whole = packedVideoIDs(clips)
        var stills: [String: String] = [:]
        for id in files.keys.sorted() {
            guard let url = files[id] else { continue }
            // Mapped rather than read: the clips a file carries can come to
            // a hundred megabytes, and a mapped file's pages are the file's
            // own rather than more of the app's memory.
            if whole.contains(id), let data = try? Data(contentsOf: url, options: .mappedIfSafe) {
                videos[id] = Media(ext: url.pathExtension.lowercased(), data: data)
            } else if let still = VideoStore.poster(id)?.jpegData(compressionQuality: 0.9) {
                let newId = UID.make("img")
                media[newId] = Media(ext: "jpg", data: still)
                stills[id] = newId
            }
        }
        guard !stills.isEmpty else { return design }
        /// The still a clip source becomes; nil for anything else.
        func still(_ src: String?) -> String? {
            guard let src, let parts = VideoStore.split(src), let newId = stills[parts.id] else { return nil }
            return "media:\(newId)"
        }
        var out = design
        for p in out.pages.indices {
            if case .image(let src) = out.pages[p].background, let moved = still(src) {
                out.pages[p].background = .image(moved)
            }
            for i in out.pages[p].elements.indices {
                if let moved = still(out.pages[p].elements[i].src) {
                    out.pages[p].elements[i].src = moved
                }
                // A shape filled with a clip shows its still too, whether or
                // not the element is itself a clip — left alone, the fill
                // would point at a clip the file does not carry.
                if var fill = out.pages[p].elements[i].fill, fill.kind == "image", let moved = still(fill.src) {
                    fill.src = moved
                    out.pages[p].elements[i].fill = fill
                }
            }
        }
        return out
    }

    /// Ids of the media files a design references.
    static func mediaIDs(in design: Design) -> Set<String> {
        var ids = Set<String>()
        for page in design.pages {
            if case .image(let src) = page.background, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
            for el in page.elements {
                if let src = el.src, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
                if let src = el.fill?.src, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
            }
        }
        return ids
    }

    static func export(_ design: Design, mediaDirectory: URL = MediaStore.directory) throws -> Data {
        try encode(contents(of: design, mediaDirectory: mediaDirectory))
    }

    /// Everything the file carries, gathered: the photos and clips read in,
    /// library photos drawn and clips too big to carry turned to stills.
    /// Stays where the caller is, since drawing a library photo does.
    static func contents(of design: Design, mediaDirectory: URL = MediaStore.directory) -> Package {
        var media: [String: Media] = [:]
        // A photo from the app's own library is drawn by this app on demand
        // and exists nowhere else — not on the other platform, not on an
        // older install. The file carries it as a picture like any other,
        // under a fresh id, and only the exported copy is re-pointed.
        var videos: [String: Media] = [:]
        let withClips = packingVideos(design, media: &media, videos: &videos)
        let design = packingLibraryPhotos(withClips, into: &media)
        for id in mediaIDs(in: design) {
            for ext in MediaStore.extensions {
                let url = mediaDirectory.appendingPathComponent("\(id).\(ext)")
                if let data = try? Data(contentsOf: url) {
                    media[id] = Media(ext: ext, data: data)
                    break
                }
            }
        }
        return Package(design: design, media: media, videos: videos.isEmpty ? nil : videos,
                       audio: packedAudio(of: design))
    }

    /// The design's music, packed, when it is on this phone and travels;
    /// otherwise none, and the design names music only the phone it was
    /// chosen on has, as it always did.
    static func packedAudio(of design: Design) -> [String: Media]? {
        guard let id = design.motion?.soundtrack, let url = AudioStore.url(for: id) else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        let ext = url.pathExtension.lowercased()
        guard Soundtrack.packs(bytes: size, ext: ext), let data = try? Data(contentsOf: url) else { return nil }
        return [id: Media(ext: ext, data: data)]
    }

    /// The file's bytes. The slow part of an export — every photo and clip
    /// written out as base64 — and it touches nothing but the package, so
    /// it can run away from the main actor.
    static func encode(_ contents: Package) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(contents)
    }

    /// The design with every library photo (`asset:<id>`) that this app can
    /// draw replaced by a packed copy (`media:<new id>`), one copy per photo
    /// however often it is used. A library id it cannot draw is left as it is.
    static func packingLibraryPhotos(_ design: Design, into media: inout [String: Media]) -> Design {
        var packed: [String: String] = [:]
        func moved(_ src: String?) -> String? {
            guard let src, src.hasPrefix("asset:") else { return src }
            let assetId = String(src.dropFirst(6))
            if let newId = packed[assetId] { return "media:\(newId)" }
            guard let data = PhotoLibrary.image(id: assetId)?.jpegData(compressionQuality: 0.9) else { return src }
            let newId = UID.make("img")
            media[newId] = Media(ext: "jpg", data: data)
            packed[assetId] = newId
            return "media:\(newId)"
        }
        var out = design
        for p in out.pages.indices {
            if case .image(let src) = out.pages[p].background, let next = moved(src) {
                out.pages[p].background = .image(next)
            }
            for i in out.pages[p].elements.indices {
                out.pages[p].elements[i].src = moved(out.pages[p].elements[i].src)
                if var fill = out.pages[p].elements[i].fill, fill.kind == "image" {
                    fill.src = moved(fill.src)
                    out.pages[p].elements[i].fill = fill
                }
            }
        }
        return out
    }

    enum ImportError: LocalizedError {
        case notAPackage
        case tooBig
        var errorDescription: String? {
            switch self {
            case .notAPackage: return "This file is not a Canvia design."
            case .tooBig: return "That design file is too big to open."
            }
        }
    }

    /// The largest design file either phone opens, as the Android twin draws
    /// the line.
    static let maxFileBytes = 200 * 1024 * 1024

    /// A design file at `url` — picked in the app, or handed over by Files,
    /// Mail or another app's share sheet — read in as a new design, named so
    /// it repeats no title in `taken` ("Poster" beside a "Poster" becomes
    /// "Poster 2"). What is inside decides, not the type it came as.
    ///
    /// `normalize: false` leaves the text boxes unmeasured, for a caller off
    /// the main thread: the type measurer's caches are the main thread's.
    static func importFile(at url: URL, taken: [String], normalize: Bool = true) throws -> Design {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard size <= maxFileBytes else { throw ImportError.tooBig }
        // Mapped rather than read in whole: a file carrying clips can run to
        // a hundred megabytes and more, and mapped, its pages are the file's
        // rather than the app's memory.
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var design = try `import`(data, normalize: normalize)
        design.title = Titles.unique(design.title, taken: taken)
        return design
    }

    /// importFile, away from the main thread: decoding a package of up to
    /// 200 MB and writing out every photo and clip in it takes long enough
    /// to freeze the screen that asked for it.
    /// The text boxes are measured back on the main actor, where the type
    /// measurer keeps its caches.
    @MainActor
    static func importFileInBackground(at url: URL, taken: [String]) async throws -> Design {
        var design = try await Task.detached(priority: .userInitiated) {
            try DesignPackage.importFile(at: url, taken: taken, normalize: false)
        }.value
        design.normalizeTextHeights()
        return design
    }

    /// The copy the system puts in Documents/Inbox when a file is handed
    /// over, deleted once it has been read in: it is not the app's to keep.
    static func discardInboxCopy(_ url: URL) {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let inbox = documents.appendingPathComponent("Inbox", isDirectory: true).resolvingSymlinksInPath().path
        guard url.resolvingSymlinksInPath().path.hasPrefix(inbox + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// The design inside, as a new document (new id, fresh media ids, the
    /// title marked as imported so it is not mistaken for the original).
    static func `import`(_ data: Data, mediaDirectory: URL = MediaStore.directory,
                         normalize: Bool = true) throws -> Design {
        guard let package = try? JSONDecoder().decode(Package.self, from: data),
              package.format == format else { throw ImportError.notAPackage }
        var remap: [String: String] = [:]
        for (oldId, item) in package.media {
            let newId = UID.make("img")
            let url = mediaDirectory.appendingPathComponent("\(newId).\(item.ext)")
            try item.data.write(to: url)
            remap[oldId] = newId
        }
        // Each clip under a fresh id too, its moments kept where a source
        // carries one.
        var clips: [String: String] = [:]
        for (oldId, item) in package.videos ?? [:] {
            if let newId = VideoStore.store(item.data, ext: item.ext) { clips[oldId] = newId }
        }
        // The music under a fresh id too, the design's soundtrack pointed
        // at it.
        var music: [String: String] = [:]
        for (oldId, item) in package.audio ?? [:] {
            if let newId = AudioStore.store(item.data, ext: item.ext) { music[oldId] = newId }
        }
        func rewrite(_ src: String?) -> String? {
            guard let src else { return nil }
            if let parts = VideoStore.split(src) {
                guard let newId = clips[parts.id] else { return src }
                return VideoStore.src(newId, at: parts.time)
            }
            guard src.hasPrefix("media:"), let newId = remap[String(src.dropFirst(6))] else { return src }
            return "media:\(newId)"
        }
        var design = package.design
        design.id = UID.make("doc")
        design.updatedAt = Date().timeIntervalSince1970 * 1000
        var pageIds: [String: String] = [:]
        for p in design.pages.indices {
            let fresh = UID.make("page")
            pageIds[design.pages[p].id] = fresh
            design.pages[p].id = fresh
            if case .image(let src) = design.pages[p].background, let moved = rewrite(src) {
                design.pages[p].background = .image(moved)
            }
            for i in design.pages[p].elements.indices {
                design.pages[p].elements[i].src = rewrite(design.pages[p].elements[i].src)
                if var fill = design.pages[p].elements[i].fill, fill.kind == "image" {
                    fill.src = rewrite(fill.src)
                    design.pages[p].elements[i].fill = fill
                }
            }
        }
        // The master page is named by its id, which was just renewed: follow
        // it, or an imported design silently loses its master.
        if let master = design.masterPageId {
            design.masterPageId = pageIds[master]
        }
        if let old = design.motion?.soundtrack, let moved = music[old] {
            design.motion?.soundtrack = moved
        }
        if normalize { design.normalizeTextHeights() }
        return design
    }
}
