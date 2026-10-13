// Fonts of your own on this phone (see CustomFonts): kept as
// Documents/fonts/<sha12>.<ext> and listed in uploads.json with kind "font"
// and the family's name. Added from the font picker, or stored as a design
// file brings them in; registered with CoreText for this process and drawn
// through FontLibrary. The Android twin's FontStore.

import CoreText
import Foundation
import UIKit

enum FontStore {

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("fonts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Guards the two below: a save records fonts, and text is measured,
    /// off the main thread as well as on it.
    private static let lock = NSLock()
    /// The fonts listed whose files are here, by hash, as last read: what a
    /// save records a newly used font under, and what the picker calls it.
    private static var names: [String: Uploads.FontEntry]?
    /// The faces read so far, by hash: a layout asks for its face every
    /// time, and the disk once. One not found is asked again next time, so
    /// a font arriving in a design draws as soon as it is stored.
    private static var descriptors: [String: CTFontDescriptor] = [:]

    // MARK: what is here

    /// The fonts of your own whose files are here, newest first. Reads the
    /// disk, and keeps their names for record and name.
    @discardableResult
    static func installed() -> [Uploads.FontEntry] {
        let folder = directory
        let fonts = Uploads.fonts().filter {
            FileManager.default.fileExists(atPath: folder.appendingPathComponent($0.file).path)
        }
        lock.lock()
        names = Dictionary(fonts.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        lock.unlock()
        return fonts
    }

    private static func known() -> [String: Uploads.FontEntry] {
        lock.lock()
        let cached = names
        lock.unlock()
        if let cached { return cached }
        return Dictionary(installed().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// How a design records the font `sha` when this phone has it: called
    /// by each save (CustomFonts.synced).
    static func record(_ sha: String) -> CustomFonts.Record? {
        known()[sha].map { CustomFonts.Record(id: CustomFonts.key(sha), name: $0.name, file: $0.file) }
    }

    /// The family name of the font `sha`, when this phone has it.
    static func name(_ sha: String) -> String? {
        known()[sha]?.name
    }

    /// A font of your own's file on this phone, or nil when it has none.
    static func url(for sha: String) -> URL? {
        for ext in ["ttf", "otf"] {
            let url = directory.appendingPathComponent("\(sha).\(ext)")
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// What the picker and the text controls call the font `key` names: the
    /// family's name, or a font of your own's — this phone's, else the name
    /// the design records, else its hash.
    static func displayName(_ key: String?, in design: Design?) -> String {
        guard let sha = CustomFonts.sha(key) else { return FontLibrary.of(key).name }
        return name(sha) ?? design.flatMap { CustomFonts.name(in: $0, of: key) } ?? sha
    }

    /// "Font missing: <name>" when `key` is a font of your own this phone
    /// does not have — its text is drawn in Modern Sans — else nil.
    static func missingNote(_ key: String?, in design: Design?) -> String? {
        guard let sha = CustomFonts.sha(key), url(for: sha) == nil else { return nil }
        return CustomFonts.missing(displayName(key, in: design))
    }

    // MARK: drawing

    /// A font of your own at `size`, or nil when it is not on this phone —
    /// the text is then drawn in Modern Sans.
    static func uiFont(_ key: String?, size: Double) -> UIFont? {
        guard let sha = CustomFonts.sha(key) else { return nil }
        lock.lock()
        var found = descriptors[sha]
        lock.unlock()
        if found == nil, let url = url(for: sha) {
            register(url)
            found = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor])?.first
            if let read = found {
                lock.lock()
                descriptors[sha] = read
                lock.unlock()
            }
        }
        guard let descriptor = found else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil) as UIFont
    }

    /// Every font of your own here registered for this process: called at
    /// launch, so the faces are known before the first design opens.
    static func registerInstalled() {
        for entry in installed() {
            if let url = url(for: entry.id) { register(url) }
        }
    }

    /// One registered already says so, and is left as it is.
    private static func register(_ url: URL) {
        _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    // MARK: adding

    /// Whether the phone can draw the bytes: a CGFont reads them, and
    /// CoreText makes a face of them — how a font is validated before it is
    /// kept.
    static func loads(_ data: Data) -> Bool {
        guard let provider = CGDataProvider(data: data as CFData), CGFont(provider) != nil else { return false }
        return CTFontManagerCreateFontDescriptorFromData(data as CFData) != nil
    }

    /// The bytes kept as a font of your own, after checking them (too big, a
    /// collection, not a font) and loading them as a face: its key
    /// "custom:<sha12>", or what was wrong. The same file twice is the same
    /// font, stored once; one that cannot be written is refused as one the
    /// phone cannot use, since it cannot.
    static func add(_ data: Data, now: Date = Date()) -> Result<String, CustomFonts.Problem> {
        let checked: CustomFonts.Checked
        switch CustomFonts.check(data) {
        case .success(let ok): checked = ok
        case .failure(let problem): return .failure(problem)
        }
        let sha = CustomFonts.sha12(data)
        let url = directory.appendingPathComponent("\(sha).\(checked.ext)")
        if !FileManager.default.fileExists(atPath: url.path) {
            guard loads(data), (try? data.write(to: url, options: .atomic)) != nil else { return .failure(.notAFont) }
        }
        Uploads.recordFont(sha, name: checked.name, file: url.lastPathComponent, now: now)
        installed()
        register(url)
        // Texts already set in it, drawn in Modern Sans while it was
        // missing, are measured and drawn again in it.
        FontLibrary.fontsChanged()
        return .success(CustomFonts.key(sha))
    }

    /// The font `sha` gone from this phone and from the list: its texts
    /// fall back to Modern Sans.
    static func remove(_ sha: String) {
        if let url = url(for: sha) {
            _ = CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            try? FileManager.default.removeItem(at: url)
        }
        Uploads.remove(sha)
        lock.lock()
        descriptors[sha] = nil
        lock.unlock()
        installed()
        FontLibrary.fontsChanged()
    }
}
