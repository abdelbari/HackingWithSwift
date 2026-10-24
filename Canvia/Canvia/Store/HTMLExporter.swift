// A design as a web page — the export sheet's "HTML", the Website type's
// own — written as the Android twin's HtmlWriter writes it (Tests/Fixtures/
// website.html is the shared golden page):
//
//  - one <section id="page-N"> for each page exported, N counting them from
//    1 in order, labelled by its title or "Page N", holding the page's SVG
//    (SVGExporter, links and all — one to a page held here an anchor to
//    its section — alt text as each group's aria-label);
//  - a sticky <nav> of the same labels, one link a section, with `nav`;
//  - each clip — with `embedMedia` — a <video> over its place, its first
//    frame as the poster and its file beside the page (media/<id>.<ext>),
//    so the export is a .zip; without it a clip is its still and the page
//    is one self-contained index.html. The design's soundtrack is left out;
//  - CSS that scales each section to the window's width, and with
//    `mobileStack` wraps the menu on a narrow screen.

import Foundation
import SwiftUI
import UIKit

enum HTMLExporter {

    /// The file the page is written as, alone or in its .zip.
    static let index = "index.html"

    /// The folder beside it the clips go in.
    static let media = "media"

    /// The export sheet's HTML settings, as the last export keeps them
    /// under "html": {"nav": true, "mobileStack": true, "embedMedia": true}.
    struct Settings: Codable, Equatable {
        var nav = true
        var mobileStack = true
        var embedMedia = true

        init(nav: Bool = true, mobileStack: Bool = true, embedMedia: Bool = true) {
            self.nav = nav
            self.mobileStack = mobileStack
            self.embedMedia = embedMedia
        }

        /// Missing, or not a true or false, is on.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nav = (try? c.decode(Bool.self, forKey: .nav)) ?? true
            mobileStack = (try? c.decode(Bool.self, forKey: .mobileStack)) ?? true
            embedMedia = (try? c.decode(Bool.self, forKey: .embedMedia)) ?? true
        }

        private enum CodingKeys: String, CodingKey { case nav, mobileStack, embedMedia }

        /// As the twin writes it, keys in this order.
        var json: String {
            "{\"nav\":\(nav),\"mobileStack\":\(mobileStack),\"embedMedia\":\(embedMedia)}"
        }
    }

    static let css = "*{box-sizing:border-box}"
        + "body{margin:0;background:#ffffff;font-family:system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif}"
        + "main{display:block}"
        + "section{position:relative;width:100%;scroll-margin-top:56px}"
        + "section>svg{display:block;width:100%;height:auto}"
        + "section>video{position:absolute;object-fit:cover}"

    static let navCSS = "nav{position:sticky;top:0;z-index:10;display:flex;gap:4px;padding:8px 16px;"
        + "background:rgba(255,255,255,0.94);border-bottom:1px solid #e3e5ea;overflow-x:auto}"
        + "nav a{padding:8px 12px;border-radius:8px;color:#16181d;text-decoration:none;white-space:nowrap}"
        + "nav a:hover,nav a:focus{background:#eef0f4}"

    static let stackCSS = "@media (max-width:600px){nav{flex-wrap:wrap;overflow-x:visible}"
        + "nav a{flex:1 1 40%;text-align:center}}"

    /// A section's label: its page's title, else "Page N" by its place
    /// among those exported.
    static func label(_ design: Design, pageIndex: Int, number: Int) -> String {
        if design.pages.indices.contains(pageIndex), let title = design.pages[pageIndex].title.flatMap(PageTitles.kept) {
            return title
        }
        return tr("Page %d", number)
    }

    /// The clips on `pages` — those that become <video>s — in page and
    /// layer order, the master's behind first; a hidden one is left out,
    /// as the SVG leaves it.
    static func clips(_ design: Design, pages: [Int]) -> [Element] {
        pages.filter { design.pages.indices.contains($0) }.flatMap { i in
            design.drawnElements(on: design.pages[i]).filter { $0.type == .image && VideoStore.isVideo($0.src) }
        }
    }

    /// Whether the export is a .zip: `embedMedia` and a clip to put in it.
    static func zipped(_ design: Design, pages: [Int], settings: Settings) -> Bool {
        settings.embedMedia && !clips(design, pages: pages).isEmpty
    }

    /// What a clip's file is called beside the page: media/<id>.<ext>.
    static func mediaPath(_ id: String, ext: String) -> String { "\(media)/\(id).\(ext)" }

    /// Pages `pages` of `design`, in that order, as one web page. `clipFile`
    /// gives a clip's file as the page links it ("media/<id>.mp4"), or nil
    /// for one that cannot be had, which stays its still. `svg` draws a
    /// page and `poster` a clip's first frame as PNG bytes; the tests give
    /// their own.
    @MainActor
    static func html(_ design: Design, pages: [Int], settings: Settings,
                     clipFile: (Element) -> String? = { _ in nil },
                     svg: ((Page) -> String)? = nil,
                     poster: ((Element) -> Data?)? = nil) -> String {
        let shown = pages.filter { design.pages.indices.contains($0) }
        let labels = shown.enumerated().map { label(design, pageIndex: $0.element, number: $0.offset + 1) }
        // A link to a page held here goes to its section.
        var anchors: [String: Int] = [:]
        for (n, index) in shown.enumerated() where anchors[design.pages[index].id] == nil {
            anchors[design.pages[index].id] = n + 1
        }
        var out = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        out += "<title>\(SVGExporter.escape(design.title))</title>\n"
        out += "<style>" + css
        if settings.nav { out += navCSS }
        if settings.nav && settings.mobileStack { out += stackCSS }
        out += "</style>\n</head>\n<body>\n"
        if settings.nav && !shown.isEmpty {
            out += "<nav aria-label=\"\(SVGExporter.escape(tr("Pages")))\">"
            for (n, label) in labels.enumerated() {
                out += "<a href=\"#page-\(n + 1)\">\(SVGExporter.escape(label))</a>"
            }
            out += "</nav>\n"
        }
        out += "<main>\n"
        for (n, index) in shown.enumerated() {
            let page = design.pages[index]
            out += "<section id=\"page-\(n + 1)\" aria-label=\"\(SVGExporter.escape(labels[n]))\">"
            out += svg?(page) ?? SVGExporter.svg(design: design, page: page, aria: true, anchors: anchors)
            if settings.embedMedia {
                let size = design.size(for: page)
                for clip in clips(design, pages: [index]) {
                    guard let file = clipFile(clip) else { continue }
                    let still = poster?(clip) ?? posterPNG(clip)
                    out += video(clip, file: file, pageW: Double(size.width), pageH: Double(size.height), poster: still)
                }
            }
            out += "</section>\n"
        }
        out += "</main>\n</body>\n</html>\n"
        return out
    }

    /// A clip over its place in the page, a share of the page's size so it
    /// scales with the section; turned as it is turned; its first frame as
    /// the poster.
    static func video(_ el: Element, file: String, pageW: Double, pageH: Double, poster: Data?) -> String {
        func pc(_ v: Double, of: Double) -> String { SVGExporter.num(of > 0 ? v / of * 100 : 0) + "%" }
        var style = "left:\(pc(el.x, of: pageW));top:\(pc(el.y, of: pageH));"
            + "width:\(pc(el.w, of: pageW));height:\(pc(el.h, of: pageH))"
        if el.rotation != 0 { style += ";transform:rotate(\(SVGExporter.num(el.rotation))deg)" }
        if el.opacity < 1 { style += ";opacity:\(SVGExporter.num(el.opacity))" }
        var tag = "<video src=\"\(SVGExporter.escape(file))\" controls playsinline preload=\"none\""
        if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
            tag += " aria-label=\"\(SVGExporter.escape(alt))\""
        }
        if let poster { tag += " poster=\"data:image/png;base64,\(poster.base64EncodedString())\"" }
        return tag + " style=\"\(style)\"></video>"
    }

    /// A clip's still at rest, upright, as PNG bytes.
    @MainActor
    static func posterPNG(_ el: Element) -> Data? {
        var still = el
        still.src = VideoStore.atRest(el)
        still.x = 0
        still.y = 0
        still.rotation = 0
        still.opacity = 1
        guard still.w > 0, still.h > 0 else { return nil }
        let renderer = ImageRenderer(content: ElementView(element: still))
        renderer.scale = 1
        return renderer.uiImage?.pngData()
    }

    // MARK: the file

    /// The clip's id and its file on this phone, for `media/<id>.<ext>`.
    static func clipSource(_ el: Element) -> (id: String, url: URL)? {
        guard let src = el.src, let id = VideoStore.split(src)?.id, let url = VideoStore.url(for: id) else { return nil }
        return (id, url)
    }

    /// The page written for sharing: index.html, or with a clip to embed, a
    /// .zip of index.html and media/ — named after the design. The page is
    /// drawn here, on the main actor; the file is written, each clip read
    /// through the zip's checksum, away from it, as a large clip took
    /// seconds — as the Android twin writes it off the main thread.
    @MainActor
    static func export(_ design: Design, pages: [Int], settings: Settings) async throws -> URL {
        let zip = zipped(design, pages: pages, settings: settings)
        var files: [String: URL] = [:]
        let page = html(design, pages: pages, settings: settings, clipFile: { el in
            guard zip, let source = clipSource(el) else { return nil }
            let ext = source.url.pathExtension.isEmpty ? "mp4" : source.url.pathExtension.lowercased()
            let path = mediaPath(source.id, ext: ext)
            files[path] = source.url
            return path
        })
        let data = Data(page.utf8)
        let clips = zip ? files : [:]
        let url = DesignExporter.fileURL(for: design, ext: clips.isEmpty ? "html" : "zip")
        return try await Task.detached(priority: .userInitiated) {
            try HTMLExporter.writeSite(data, clips: clips, to: url)
        }.value
    }

    /// index.html alone at `url`, or with clips, a .zip of it and them.
    private static func writeSite(_ page: Data, clips: [String: URL], to url: URL) throws -> URL {
        guard !clips.isEmpty else {
            try page.write(to: url, options: .atomic)
            return url
        }
        try? FileManager.default.removeItem(at: url)
        let writer = try ZipStore.Writer(url: url)
        try writer.add(index, page)
        for path in clips.keys.sorted() {
            guard let clip = clips[path] else { continue }
            try writer.add(path, try Data(contentsOf: clip, options: .mappedIfSafe))
        }
        try writer.finish()
        return url
    }

    /// The page alone, for Preview: index.html in a folder of its own with
    /// its clips beside it, so the web view can read them from the file —
    /// the clips copied and the page written away from the main actor.
    @MainActor
    static func preview(_ design: Design, pages: [Int], settings: Settings) async throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("site-preview", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent(media), withIntermediateDirectories: true)
        var copies: [(from: URL, to: URL)] = []
        let page = html(design, pages: pages, settings: settings, clipFile: { el in
            guard settings.embedMedia, let source = clipSource(el) else { return nil }
            let ext = source.url.pathExtension.isEmpty ? "mp4" : source.url.pathExtension.lowercased()
            let path = mediaPath(source.id, ext: ext)
            copies.append((from: source.url, to: folder.appendingPathComponent(path)))
            return path
        })
        let url = folder.appendingPathComponent(index)
        let data = Data(page.utf8)
        let pairs = copies
        try await Task.detached(priority: .userInitiated) {
            for pair in pairs { try? FileManager.default.copyItem(at: pair.from, to: pair.to) }
            try data.write(to: url, options: .atomic)
        }.value
        return url
    }
}
