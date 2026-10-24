// What the export sheet works out before it makes anything, for the parts
// of round 32 the Android twin's ExportPlan has too, name for name and rule
// for rule (ExportPlanTests): the ZIP several files go into and the names
// inside it, when a compressed PNG is worth keeping and the sizes said
// before and after, and which file types are worth a word about
// accessibility first — a film about its captions alone.

import Foundation

enum ExportPlan {

    // MARK: one ZIP

    /// The file types that write a file a page, which Save as one ZIP can
    /// put together.
    static let zippable: Set<String> = ["png", "jpg", "svg"]

    /// Whether Save as one ZIP is offered: a type that writes a file a
    /// page, writing more than one.
    static func offersZip(format: String, files: Int) -> Bool {
        zippable.contains(format) && files > 1
    }

    /// The ZIP's name: the design's file name, as every export names its
    /// file (DesignExporter.fileBaseName), and ".zip".
    static func zipName(_ title: String) -> String {
        DesignExporter.fileBaseName(title) + ".zip"
    }

    /// The names of the files inside, in page order, as the files are named
    /// on their own: "<name>-<n>.<ext>", n the page's number from 1 — or
    /// "<name>.<ext>" for a single page.
    static func entryNames(_ title: String, ext: String, pages: [Int]) -> [String] {
        let base = DesignExporter.fileBaseName(title)
        guard pages.count > 1 else { return pages.map { _ in "\(base).\(ext)" } }
        return pages.map { "\(base)-\($0 + 1).\(ext)" }
    }

    // MARK: a compressed PNG

    /// How much smaller a compressed PNG must be to be kept: 15%.
    static let compressGain = 0.15

    /// Whether a compressed PNG `compressed` bytes long is kept over the
    /// normal one, `normal` bytes: at least compressGain smaller.
    static func keepsCompressed(compressed: Int, normal: Int) -> Bool {
        Double(compressed) <= Double(normal) * (1 - compressGain)
    }

    /// About how big a PNG of `width` × `height` pixels comes out: 12 bits
    /// a pixel as it is, 4 compressed to 256 colours (PngWriter); never
    /// under 2 KB. Android's ExportPlan.estimatedPngBytes, to the byte.
    static func estimatedPngBytes(width: Int, height: Int, compressed: Bool = false) -> Int {
        let bitsPerPixel = compressed ? 4.0 : 12.0
        return max(2048, Int(Double(max(width, 0)) * Double(max(height, 0)) * bitsPerPixel / 8))
    }

    /// The same, compressed.
    static func estimatedCompressedPngBytes(width: Int, height: Int) -> Int {
        estimatedPngBytes(width: width, height: height, compressed: true)
    }

    // MARK: accessibility first

    /// Settings ▸ Export's "Remind me to check accessibility", on unless
    /// turned off; the same key in a backup.
    static let a11yNudgeKey = "exportA11yNudge"

    static func remindsA11y(_ defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: a11yNudgeKey) as? Bool ?? true
    }

    /// The file types the sheet suggests checking accessibility before:
    /// documents and pictures people read.
    static let checkedFormats: Set<String> = ["pdf", "html", "pptx", "png", "jpg"]

    /// The films the row is about captions for: an MP4 and a GIF mention
    /// the captions findings alone — the Android twin's
    /// AccessibilityAudit.CAPTION_NUDGE_FORMATS.
    static let captionFormats: Set<String> = ["mp4", "gif"]

    /// What the row counts for an export as `format`: every finding for a
    /// type in checkedFormats, the captions ones for a film
    /// (captionFormats), none for anything else.
    static func nudgeFindings(_ findings: [AccessibilityAudit.Finding], format: String) -> [AccessibilityAudit.Finding] {
        if checkedFormats.contains(format) { return findings }
        if captionFormats.contains(format) { return findings.filter { $0.kind == .captions } }
        return []
    }

    /// Whether the sheet shows the accessibility row for `format`: the
    /// setting on (`remind`), something found that it counts
    /// (`nudgeFindings`, already counted for a film), a type people read or
    /// a film, and not put away since the design last changed
    /// (`dismissed`, the revision it was put away at).
    static func showsA11yNudge(format: String, findings: Int, remind: Bool, revision: Int64,
                               dismissed: Int64?) -> Bool {
        let counted = checkedFormats.contains(format) || captionFormats.contains(format)
        return remind && findings > 0 && counted && dismissed != revision
    }
}
