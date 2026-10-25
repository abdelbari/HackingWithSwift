// What the export sheet works out before it makes anything, for the parts
// of round 32 the Android twin's ExportPlan has too, name for name and rule
// for rule (ExportPlanTests): the ZIP several files go into and the names
// inside it, when a compressed PNG is worth keeping and the sizes said
// before and after, and which file types are worth a word about
// accessibility first — a film about its captions alone. And round 34's:
// a carousel cut into slides.

import CoreGraphics
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

    // MARK: a carousel cut into slides

    /// The slides a picture `size` pixels across is cut into, `columns`
    /// across and `rows` down, left to right and then top to bottom: each
    /// edge at its share of the whole, rounded to a whole pixel, halves up —
    /// floor(width × i / columns + 0.5) — so every slide is a whole number of
    /// pixels, together they cover the picture exactly, and none differs
    /// from another by more than a pixel: 3240 into three is 1080 each,
    /// 1000 into three is 333, 334 and 333. The picture's own size is taken
    /// to the nearest whole pixel first. None for no column or row. The
    /// Android twin's ExportPlan.tiles, with the shared fixture
    /// carousel-tiles.json.
    static func tiles(size: CGSize, columns: Int, rows: Int = 1) -> [CGRect] {
        guard columns >= 1, rows >= 1 else { return [] }
        let width = (Double(size.width) + 0.5).rounded(.down)
        let height = (Double(size.height) + 0.5).rounded(.down)
        func edge(_ total: Double, _ parts: Int, _ i: Int) -> Double {
            (total * Double(i) / Double(parts) + 0.5).rounded(.down)
        }
        var out: [CGRect] = []
        for r in 0..<rows {
            let top = edge(height, rows, r)
            let bottom = edge(height, rows, r + 1)
            for c in 0..<columns {
                let left = edge(width, columns, c)
                out.append(CGRect(x: left, y: top, width: edge(width, columns, c + 1) - left, height: bottom - top))
            }
        }
        return out
    }

    /// The image types a carousel is cut into slides for: a picture.
    static let splittable: Set<String> = ["png", "jpg"]

    /// Whether "Split into slides" is offered: a picture of pages of which
    /// one at least is cut (PageSplit).
    static func offersSplit(format: String, design: Design, pages: [Int]) -> Bool {
        splittable.contains(format)
            && pages.contains { design.pages.indices.contains($0) && design.pages[$0].split != nil }
    }

    /// How many files a picture of `pages` makes: a file a slide of each
    /// carousel page when `split`, else a file a page.
    static func fileCount(design: Design, pages: [Int], split: Bool) -> Int {
        guard split else { return pages.count }
        return pages.reduce(0) { count, i in
            let cut = design.pages.indices.contains(i) ? design.pages[i].split : nil
            return count + (cut.map { $0.columns * $0.rows } ?? 1)
        }
    }

    /// A slide's file name: the page's own name (fileBaseName, and "-n"
    /// when there are several pages) and "_n", n its slide's place from 1 —
    /// "Lisbon_1.png", "Lisbon_2.png", … for a carousel alone,
    /// "Lisbon-2_1.png" for the second page's first slide — so they sort,
    /// and are picked, in order.
    static func slideName(_ title: String, pageIndex: Int, files: Int, slide: Int, ext: String) -> String {
        let page = files > 1 ? "-\(pageIndex + 1)" : ""
        return DesignExporter.fileBaseName(title) + page + "_\(slide + 1).\(ext)"
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
    /// (captionFormats) — and, for any file, a photo or clip whose file is
    /// gone (missingMedia), which goes out missing whatever the type, as
    /// the Android twin's nudgeFindings counts it.
    static func nudgeFindings(_ findings: [AccessibilityAudit.Finding], format: String) -> [AccessibilityAudit.Finding] {
        if checkedFormats.contains(format) { return findings }
        if captionFormats.contains(format) { return findings.filter { $0.kind == .captions || $0.kind == .missingMedia } }
        return findings.filter { $0.kind == .missingMedia }
    }

    /// Whether the sheet shows the accessibility row for `format`: the
    /// setting on (`remind`), something found that it counts
    /// (`nudgeFindings`, already counted for the type — for most types,
    /// only what is missing), and not put away since the design last
    /// changed (`dismissed`, the revision it was put away at). The Android
    /// twin's showsNudge.
    static func showsA11yNudge(format: String, findings: Int, remind: Bool, revision: Int64,
                               dismissed: Int64?) -> Bool {
        remind && findings > 0 && dismissed != revision
    }
}
