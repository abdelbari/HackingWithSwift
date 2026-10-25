// A design as one file: the document plus every photo, clip and animated
// picture it uses, its music, and the fonts of your own its texts are set in.
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
        /// The music of every audio track, by the AudioStore id its `src`
        /// names, those small enough and of a type both phones play, within
        /// a total (Soundtrack.packed). Optional like `videos`, so older
        /// files read, and older readers pass over it.
        var audio: [String: Media]?
        /// The fonts of your own the texts are set in, by their hash —
        /// {"<sha12>": {"data", "ext"}}, each at most CustomFonts.maxBytes;
        /// one past it stays behind, and its texts fall back where they
        /// arrive. Optional like `videos`, and left out when there are none.
        var fonts: [String: Media]?
        /// The animated GIFs and WebPs the design shows, by the id its
        /// "anim:" sources name — {"<id>": {"data", "ext"}}, at most
        /// AnimStore.maxPackedBytes each and maxPackedTotalBytes in all;
        /// the rest travel as their first frame (`packingAnimations`).
        /// Optional like `videos`, and left out when there are none.
        var animations: [String: Media]?
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
    /// a still — and the clips an audio track plays the sound of
    /// (AudioTracks.detached). Counted as the Android twin counts them, so the two phones
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
        for track in design.audioTracks { if let id = AudioTrack.videoId(of: track.src) { ids.insert(id) } }
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
        packingClips(design, media: &media, whole: packedVideoIDs) { id, url in
            // Mapped rather than read: the clips a file carries can come to
            // a hundred megabytes, and a mapped file's pages are the file's
            // own rather than more of the app's memory.
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
            videos[id] = Media(ext: url.pathExtension.lowercased(), data: data)
            return true
        }
    }

    /// As a backup packs: every clip that reads goes in whole, whatever its
    /// length or type, as the Android twin's backup packs them — left as
    /// its file in `clipFiles`, by id, rather than read in, for
    /// `stream(_:clips:into:)` to write a piece at a time. Only a clip that
    /// does not read becomes a still.
    static func packingClipFiles(_ design: Design, media: inout [String: Media],
                                 clipFiles: inout [String: URL]) -> Design {
        packingClips(design, media: &media, whole: { Set($0.keys) }) { id, url in
            guard FileManager.default.isReadableFile(atPath: url.path) else { return false }
            clipFiles[id] = url
            return true
        }
    }

    /// The design's clips, those `whole` picks (from each one's size and
    /// type, by id) handed to `take` with their files — and any it does not
    /// pick, or `take` turns away, replaced by its first frame packed as a
    /// photo. Present and record's cameras (Recordings) are weighed with the
    /// clips, as the Android twin weighs them, so the same design makes the
    /// same file on either phone; a camera not picked stays behind, with no
    /// still, and its talk plays voice-only.
    private static func packingClips(_ design: Design, media: inout [String: Media],
                                     whole wholeIDs: ([String: (bytes: Int, ext: String)]) -> Set<String>,
                                     take: (String, URL) -> Bool) -> Design {
        var files: [String: URL] = [:]
        var clips: [String: (bytes: Int, ext: String)] = [:]
        let cameras = Recordings.cameraIds(design)
        for id in videoIDs(in: design).union(cameras) {
            guard let url = VideoStore.url(for: id) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max
            files[id] = url
            clips[id] = (bytes: size, ext: url.pathExtension.lowercased())
        }
        let whole = wholeIDs(clips)
        var stills: [String: String] = [:]
        for id in files.keys.sorted() {
            guard let url = files[id] else { continue }
            if whole.contains(id), take(id, url) {
                continue
            } else if cameras.contains(id) {
                continue
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
                if var letters = out.pages[p].elements[i].textFill, letters.kind == "image", let moved = still(letters.src) {
                    letters.src = moved
                    out.pages[p].elements[i].textFill = letters
                }
            }
        }
        return out
    }

    /// The design with each animated picture `whole` picks (from each one's
    /// size and type, by id) packed into `animations`, and every other —
    /// past the limits, or whose file does not read — shown by its first
    /// frame packed as a photo, "media:still-<id>", wherever it appears, as
    /// the Android twin packs them.
    static func packingAnimations(_ design: Design, media: inout [String: Media],
                                  animations: inout [String: Media],
                                  whole wholeIDs: ([String: (bytes: Int, ext: String)]) -> Set<String>) -> Design {
        var files: [String: URL] = [:]
        var sizes: [String: (bytes: Int, ext: String)] = [:]
        for id in AnimStore.ids(in: design) {
            guard let url = AnimStore.url(for: id) else { continue }
            files[id] = url
            sizes[id] = (bytes: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? Int.max,
                         ext: url.pathExtension.lowercased())
        }
        let whole = wholeIDs(sizes)
        var stills = Set<String>()
        for id in files.keys.sorted() {
            guard let url = files[id] else { continue }
            if whole.contains(id), let data = try? Data(contentsOf: url) {
                animations[id] = Media(ext: url.pathExtension.lowercased(), data: data)
            } else if let still = AnimStore.poster(id)?.pngData() {
                // PNG, so a sticker's see-through surround stays clear.
                media[AnimStore.stillID(id)] = Media(ext: "png", data: still)
                stills.insert(id)
            }
        }
        guard !stills.isEmpty else { return design }
        /// The still an animated source becomes; nil for anything else.
        func still(_ src: String?) -> String? {
            guard let src, let parts = AnimStore.split(src), stills.contains(parts.id) else { return nil }
            return "media:" + AnimStore.stillID(parts.id)
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
                if var fill = out.pages[p].elements[i].fill, fill.kind == "image", let moved = still(fill.src) {
                    fill.src = moved
                    out.pages[p].elements[i].fill = fill
                }
                if var letters = out.pages[p].elements[i].textFill, letters.kind == "image", let moved = still(letters.src) {
                    letters.src = moved
                    out.pages[p].elements[i].textFill = letters
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
                // A photo poured into a text's letters.
                if let src = el.textFill?.src, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
                // The picture before a Cut out, which Restore paints back.
                if let src = el.mask?.base, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
                // The picture an expanded photo was grown from, which Undo
                // expand and Change fill go back to.
                if let src = el.expandedFrom?.src, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
                // A QR code's logo, a photo of its own.
                if let src = el.qrLogo, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
            }
        }
        // A Doc's photos, which live in its image blocks, not on its pages.
        for block in design.blocks ?? [] where block.type == Docs.image {
            if let src = block.src, src.hasPrefix("media:") { ids.insert(String(src.dropFirst(6))) }
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
        let drawn = withLibraryPhotos(design)
        return gathered(drawn.design, media: drawn.media, mediaDirectory: mediaDirectory)
    }

    /// The first part of `contents(of:)`, the one that stays on the main
    /// actor: the record of fonts of your own as a save writes it, so the
    /// other phone can name one it cannot draw, and every library photo
    /// drawn. A photo from the app's own library is drawn by this app on
    /// demand and exists nowhere else — not on the other platform, not on
    /// an older install. The file carries it as a picture like any other,
    /// under a fresh id, and only the exported copy is re-pointed.
    static func withLibraryPhotos(_ design: Design) -> (design: Design, media: [String: Media]) {
        var media: [String: Media] = [:]
        let synced = CustomFonts.synced(design, installed: FontStore.record, faces: FontStore.faces())
        let drawn = packingLibraryPhotos(synced, into: &media)
        return (drawn, media)
    }

    /// The rest of `contents(of:)`: the clips, photos, music and fonts the
    /// design (from `withLibraryPhotos`) shows, read from their files.
    static func gathered(_ drawn: Design, media drawnMedia: [String: Media],
                         mediaDirectory: URL = MediaStore.directory) -> Package {
        var media = drawnMedia
        var videos: [String: Media] = [:]
        var animations: [String: Media] = [:]
        let clipped = packingVideos(drawn, media: &media, videos: &videos)
        let design = packingAnimations(clipped, media: &media, animations: &animations, whole: AnimStore.packedIDs)
        return packed(design, media: media, videos: videos, animations: animations, mediaDirectory: mediaDirectory)
    }

    /// `gathered`, as a backup packs a design, away from the main actor:
    /// every clip whole, left as its file (`packingClipFiles`), for
    /// `stream(_:clips:into:)` to write in — never read in whole, nor its
    /// base64, however long it is — and every animated picture whole too,
    /// each no more than AnimStore.maxBytes.
    static func gatheredForBackup(_ drawn: Design, media drawnMedia: [String: Media],
                                  mediaDirectory: URL = MediaStore.directory) -> (package: Package, clips: [String: URL]) {
        var media = drawnMedia
        var clips: [String: URL] = [:]
        var animations: [String: Media] = [:]
        let clipped = packingClipFiles(drawn, media: &media, clipFiles: &clips)
        let design = packingAnimations(clipped, media: &media, animations: &animations, whole: { Set($0.keys) })
        return (packed(design, media: media, videos: [:], animations: animations, mediaDirectory: mediaDirectory), clips)
    }

    /// The package of a design whose clips and animated pictures are
    /// settled: its photos read in, and its music and fonts.
    private static func packed(_ design: Design, media drawnMedia: [String: Media], videos: [String: Media],
                               animations: [String: Media], mediaDirectory: URL) -> Package {
        var media = drawnMedia
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
                       audio: packedAudio(of: design), fonts: packedFonts(of: design),
                       animations: animations.isEmpty ? nil : animations)
    }

    /// Whether a font file of `bytes` travels in a package: one past the
    /// limit stays behind, and its texts fall back where they arrive.
    static func packsFont(bytes: Int) -> Bool {
        (1...CustomFonts.maxBytes).contains(bytes)
    }

    /// The fonts of your own the design's texts are set in, and the other
    /// faces of their families here (a bold word draws from the Bold file),
    /// packed, those on this phone that travel; none when there are none.
    static func packedFonts(of design: Design) -> [String: Media]? {
        var fonts: [String: Media] = [:]
        for sha in CustomFonts.used(in: design, faces: FontStore.faces()) {
            guard let url = FontStore.url(for: sha) else { continue }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            guard packsFont(bytes: size), let data = try? Data(contentsOf: url) else { continue }
            fonts[sha] = Media(ext: url.pathExtension.lowercased(), data: data)
        }
        return fonts.isEmpty ? nil : fonts
    }

    /// The music of the design's tracks and its talks' voices, packed,
    /// those on this phone that travel (Soundtrack.packed); none when none
    /// does. A track whose file
    /// stays behind names music only the phone it was chosen on has, as the
    /// soundtrack always did. A built-in sound effect is in every copy of
    /// the app, so it is never packed.
    static func packedAudio(of design: Design) -> [String: Media]? {
        var files: [String: URL] = [:]
        var sizes: [String: (bytes: Int, ext: String)] = [:]
        let ids = design.audioTracks.compactMap(\.storedAudioId) + Recordings.of(design).map(\.audio)
        for id in ids {
            guard files[id] == nil, let url = AudioStore.url(for: id) else { continue }
            files[id] = url
            sizes[id] = (bytes: (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0,
                         ext: url.pathExtension.lowercased())
        }
        var audio: [String: Media] = [:]
        for id in Soundtrack.packed(sizes) {
            guard let url = files[id], let data = try? Data(contentsOf: url) else { continue }
            audio[id] = Media(ext: url.pathExtension.lowercased(), data: data)
        }
        return audio.isEmpty ? nil : audio
    }

    /// The file's bytes. The slow part of an export — every photo and clip
    /// written out as base64 — and it touches nothing but the package, so
    /// it can run away from the main actor.
    static func encode(_ contents: Package) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(contents)
    }

    /// The file `encode` makes of `contents`, with each clip in `clips`
    /// (by id) put among its videos, handed to `write` a piece at a time:
    /// each clip read from its file and turned to base64 `pieceBytes` at a
    /// time, so neither a clip nor its text is ever held whole — as the
    /// Android twin's DesignPackage.writeTo streams them. Keys are sorted,
    /// as `encode` sorts them; it reads back as any package does.
    static func stream(_ contents: Package, clips: [String: URL], pieceBytes: Int = ZipStore.pieceBytes,
                       into write: (Data) throws -> Void) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Everything but the clips first, in one piece: the design and the
        // photos, animated pictures, music and fonts it holds already.
        var members: [(key: String, json: Data)] = try [
            ("design", encoder.encode(contents.design)),
            ("format", encoder.encode(contents.format)),
            ("media", encoder.encode(contents.media)),
            ("version", encoder.encode(contents.version)),
        ]
        if let animations = contents.animations { try members.append(("animations", encoder.encode(animations))) }
        if let audio = contents.audio { try members.append(("audio", encoder.encode(audio))) }
        if let fonts = contents.fonts { try members.append(("fonts", encoder.encode(fonts))) }
        var head = Data("{".utf8)
        for (n, member) in members.sorted(by: { $0.key < $1.key }).enumerated() {
            if n > 0 { head.append(Data(",".utf8)) }
            head.append(Data("\"\(member.key)\":".utf8))
            head.append(member.json)
        }
        try write(head)
        // Then the clips, last as "videos" sorts after every other key.
        let held = contents.videos ?? [:]
        let ids = Set(held.keys).union(clips.keys).sorted()
        if !ids.isEmpty {
            try write(Data(",\"videos\":{".utf8))
            for (n, id) in ids.enumerated() {
                let key = try encoder.encode(id)
                try write(Data((n > 0 ? "," : "").utf8) + key + Data(":".utf8))
                if let url = clips[id] {
                    try write(Data("{\"data\":\"".utf8))
                    try base64(of: url, pieceBytes: pieceBytes, into: write)
                    let ext = try encoder.encode(url.pathExtension.lowercased())
                    try write(Data("\",\"ext\":".utf8) + ext + Data("}".utf8))
                } else if let media = held[id] {
                    try write(encoder.encode(media))
                }
            }
            try write(Data("}".utf8))
        }
        try write(Data("}".utf8))
    }

    /// The file at `url` as base64, a piece at a time: each piece's bytes
    /// that do not make a whole three are carried on to the next, so the
    /// pieces join into the base64 of the whole file.
    private static func base64(of url: URL, pieceBytes: Int, into write: (Data) throws -> Void) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var carry = Data()
        try ZipStore.readPieces(of: handle, size: pieceBytes) { piece in
            var bytes = carry
            bytes.append(piece)
            let whole = bytes.count - bytes.count % 3
            if whole > 0 { try write(bytes.prefix(whole).base64EncodedData()) }
            carry = Data(bytes.suffix(bytes.count - whole))
        }
        if !carry.isEmpty { try write(carry.base64EncodedData()) }
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
                if var letters = out.pages[p].elements[i].textFill, letters.kind == "image" {
                    letters.src = moved(letters.src)
                    out.pages[p].elements[i].textFill = letters
                }
                if var mask = out.pages[p].elements[i].mask, mask.base != nil {
                    mask.base = moved(mask.base)
                    out.pages[p].elements[i].mask = mask
                }
                if var origin = out.pages[p].elements[i].expandedFrom {
                    origin.src = moved(origin.src) ?? origin.src
                    out.pages[p].elements[i].expandedFrom = origin
                }
                if let logo = out.pages[p].elements[i].qrLogo {
                    out.pages[p].elements[i].qrLogo = moved(logo)
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
            case .notAPackage: return tr("This file is not a Canvia design.")
            case .tooBig: return tr("That design file is too big to open.")
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

    /// Whether a name from a file is safe to keep a file under: letters,
    /// digits, "_", "-" and ".", and no way out of the folder.
    static func isSafeFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("..")
            && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "_-.".contains($0)) }
    }

    /// A package's files stored under the ids it names — each only when no
    /// file of that id is here yet, as the same photo is the same file — and
    /// its design returned as it is, ids, dates and all: how a backup brings
    /// a design back. Text boxes are left unmeasured, for a caller off the
    /// main thread.
    static func storeKeepingIds(_ package: Package, mediaDirectory: URL = MediaStore.directory) -> Design {
        let fm = FileManager.default
        for (id, item) in package.media where isSafeFileName(id) && isSafeFileName(item.ext) {
            let here = MediaStore.extensions.contains {
                fm.fileExists(atPath: mediaDirectory.appendingPathComponent("\(id).\($0)").path)
            }
            if !here { try? item.data.write(to: mediaDirectory.appendingPathComponent("\(id).\(item.ext)")) }
        }
        for (id, item) in package.videos ?? [:] where isSafeFileName(id) && isSafeFileName(item.ext) {
            if VideoStore.url(for: id) == nil {
                try? item.data.write(to: VideoStore.directory.appendingPathComponent("\(id).\(item.ext.lowercased())"))
            }
        }
        for (id, item) in package.animations ?? [:] where isSafeFileName(id) && isSafeFileName(item.ext) {
            if AnimStore.url(for: id) == nil {
                try? item.data.write(to: AnimStore.directory.appendingPathComponent("\(id).\(item.ext.lowercased())"))
            }
        }
        for (sha, item) in package.fonts ?? [:] where CustomFonts.sha12(item.data) == sha {
            _ = FontStore.add(item.data)
        }
        for (id, item) in package.audio ?? [:] where isSafeFileName(id) && AudioStore.url(for: id) == nil {
            try? item.data.write(to: AudioStore.directory.appendingPathComponent(id))
        }
        return package.design
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
        // And each animated picture, its moments kept likewise.
        var animated: [String: String] = [:]
        for (oldId, item) in package.animations ?? [:] {
            if let newId = AnimStore.write(item.data, ext: item.ext) { animated[oldId] = newId }
        }
        // A font of your own under its own hash, which is what the texts
        // name: stored only when its bytes are the file the key names, and
        // one this phone has already is the same file. One left out draws
        // in Modern Sans.
        for (sha, item) in package.fonts ?? [:] where CustomFonts.sha12(item.data) == sha {
            _ = FontStore.add(item.data)
        }
        // The music under a fresh id too, each track that plays it pointed
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
            if let parts = AnimStore.split(src) {
                guard let newId = animated[parts.id] else { return src }
                return AnimStore.src(newId, at: parts.time)
            }
            guard src.hasPrefix("media:"), let newId = remap[String(src.dropFirst(6))] else { return src }
            return "media:\(newId)"
        }
        var design = package.design
        design.id = UID.make("doc")
        // A new document is a copy, and a copy is not starred, as on the
        // Android twin; a backup, which keeps ids, keeps the star.
        design.isStarred = false
        design.updatedAt = Date().timeIntervalSince1970 * 1000
        var pageIds: [String: String] = [:]
        for p in design.pages.indices {
            let fresh = UID.make("page")
            pageIds[design.pages[p].id] = fresh
            design.pages[p].id = fresh
            if case .image(let src) = design.pages[p].background, let moved = rewrite(src) {
                // A clip behind the page moves with its picture, which is its
                // own source, so it still plays from where it was stored.
                let clip = design.pages[p].backgroundClip.map { was -> BackgroundClip in
                    var next = was
                    next.src = rewrite(was.src) ?? was.src
                    return next
                }
                design.pages[p].background = .image(moved)
                design.pages[p].backgroundClip = clip
            }
            for i in design.pages[p].elements.indices {
                design.pages[p].elements[i].src = rewrite(design.pages[p].elements[i].src)
                if var fill = design.pages[p].elements[i].fill, fill.kind == "image" {
                    fill.src = rewrite(fill.src)
                    design.pages[p].elements[i].fill = fill
                }
                // A photo poured into the letters moves as a shape's does.
                if var letters = design.pages[p].elements[i].textFill, letters.kind == "image" {
                    letters.src = rewrite(letters.src)
                    design.pages[p].elements[i].textFill = letters
                }
                if var mask = design.pages[p].elements[i].mask, mask.base != nil {
                    mask.base = rewrite(mask.base)
                    design.pages[p].elements[i].mask = mask
                }
                // An expanded photo's original moves as its picture does.
                if var origin = design.pages[p].elements[i].expandedFrom {
                    origin.src = rewrite(origin.src) ?? origin.src
                    design.pages[p].elements[i].expandedFrom = origin
                }
                // A QR code's logo moves as a photo does.
                if let logo = design.pages[p].elements[i].qrLogo {
                    design.pages[p].elements[i].qrLogo = rewrite(logo)
                }
            }
        }
        // The master page is named by its id, which was just renewed: follow
        // it, or an imported design silently loses its master.
        if let master = design.masterPageId {
            design.masterPageId = pageIds[master]
        }
        // A Doc's image blocks move as a photo does.
        design.blocks = design.blocks.map { blocks in
            blocks.map { block -> DocBlock in
                guard block.type == Docs.image else { return block }
                var next = block
                next.src = rewrite(block.src)
                return next
            }
        }
        // A new document's posts are not planned: the original keeps them.
        design.plannedPosts = nil
        design.audioTracks = design.audioTracks.map { track in
            var next = track
            // A clip's sound follows its clip.
            if let old = AudioTrack.videoId(of: track.src) {
                if let moved = clips[old] { next.src = VideoStore.src(moved, at: nil) }
                return next
            }
            guard let old = track.audioId, let moved = music[old] else { return track }
            next.src = AudioTrack.src(moved)
            return next
        }
        // What names a page by its id follows it: the talks' pages and the
        // holds Beat Sync keeps, and the links to pages.
        design = Links.withPageIds(BeatSync.withPageIds(Recordings.withPageIds(design, pageIds), pageIds), pageIds)
        // The talks pointed at where their voices and cameras went.
        design = Recordings.remapped(design, audio: music, video: clips)
        if normalize { design.normalizeTextHeights() }
        return design
    }
}
