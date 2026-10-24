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
//  - after each page's picture, a visually hidden text layer of its words
//    as a screen reader wants them (`textLayer`): headings <h1>–<h3>,
//    paragraphs, quotes, captions, lists and tables, in reading order, by
//    the same roles as a tagged PDF's (PdfTags);
//  - CSS that scales each section to the window's width, and with
//    `mobileStack` wraps the menu on a narrow screen.
//
// With `layout` "slides" the same sections are a slide player (Tests/
// Fixtures/slides.html is its shared golden page): each page fills the
// window, scaled to fit and letterboxed on black, one at a time, with no
// menu. A small inline script (`slidesJS`) goes on and back with ← → Space
// Page Up and Page Down, a swipe, or a click on the right or left half;
// shows a progress bar; follows and sets #page-N, so a page link still
// jumps; has a full-screen button, and Escape leaves full screen; and with
// `autoplay` seconds goes on by itself, round to the first after the last
// with `loop`. Each page changes by its own transition (PageTransitions.
// transitionKind, as long as Present takes) — a fade, slide, push or zoom
// in CSS; a wipe or a circle fades, a cut is instant — and its elements'
// simple entrances (fade, rise, pan, pop, wipe; SVGExporter.entranceClass)
// play as it arrives; under prefers-reduced-motion nothing moves.

import Foundation
import SwiftUI
import UIKit

enum HTMLExporter {

    /// The file the page is written as, alone or in its .zip.
    static let index = "index.html"

    /// The folder beside it the clips go in.
    static let media = "media"

    /// The export sheet's HTML settings, as the last export keeps them
    /// under "html": {"nav": true, "mobileStack": true, "embedMedia": true,
    /// "layout": "scroll", "autoplay": 0.0, "loop": false} — `layout`
    /// scroll (the website) or slides (the slide player), `autoplay` the
    /// seconds each slide shows before the next, 0 for by hand, and `loop`
    /// whether the last goes on to the first.
    struct Settings: Codable, Equatable {
        var nav = true
        var mobileStack = true
        var embedMedia = true
        var layout = HTMLExporter.scroll
        var autoplay = 0.0
        var loop = false

        init(nav: Bool = true, mobileStack: Bool = true, embedMedia: Bool = true,
             layout: String = HTMLExporter.scroll, autoplay: Double = 0, loop: Bool = false) {
            self.nav = nav
            self.mobileStack = mobileStack
            self.embedMedia = embedMedia
            self.layout = layout
            self.autoplay = autoplay
            self.loop = loop
        }

        /// Missing, or not a true or false, is on; a missing layout is the
        /// scrolling site, as a file from before reads, with no autoplay and
        /// no loop.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            nav = (try? c.decode(Bool.self, forKey: .nav)) ?? true
            mobileStack = (try? c.decode(Bool.self, forKey: .mobileStack)) ?? true
            embedMedia = (try? c.decode(Bool.self, forKey: .embedMedia)) ?? true
            layout = (try? c.decode(String.self, forKey: .layout)) ?? HTMLExporter.scroll
            autoplay = (try? c.decode(Double.self, forKey: .autoplay)) ?? 0
            loop = (try? c.decode(Bool.self, forKey: .loop)) ?? false
        }

        private enum CodingKeys: String, CodingKey { case nav, mobileStack, embedMedia, layout, autoplay, loop }

        /// Whether it is the slide player.
        var slides: Bool { layout == HTMLExporter.slides }

        /// As the twin writes it, keys in this order.
        var json: String {
            let looks = "{\"nav\":\(nav),\"mobileStack\":\(mobileStack),\"embedMedia\":\(embedMedia),"
            return looks + "\"layout\":\"\(layout)\",\"autoplay\":\(autoplay),\"loop\":\(loop)}"
        }
    }

    static let scroll = "scroll"
    static let slides = "slides"
    static let layouts = [scroll, slides]

    /// The seconds a slide may show itself on autoplay, 0 for off.
    static let autoplayChoices: [Double] = [0, 3, 5, 10]

    /// A page's transition as the slide player plays it: a fade, slide,
    /// push or zoom in CSS; a wipe or a circle as a fade; a cut, or none, at
    /// once.
    static func slideTransition(_ kind: String) -> String {
        ["slide", "push", "zoom", "cut"].contains(kind) ? kind : "fade"
    }

    static let css = "*{box-sizing:border-box}"
        + "body{margin:0;background:#ffffff;font-family:system-ui,-apple-system,\"Segoe UI\",Roboto,sans-serif}"
        + "main{display:block}"
        + "section{position:relative;width:100%;scroll-margin-top:56px}"
        + "section>svg{display:block;width:100%;height:auto}"
        + "section>video{position:absolute;object-fit:cover}"
        + ".sr{position:absolute;width:1px;height:1px;margin:-1px;padding:0;overflow:hidden;clip:rect(0 0 0 0);border:0}"

    /// A graphic drawing itself on, and one twinkling (SVGExporter.moving):
    /// written only on a web page that has one.
    static let motionCSS = "@keyframes cv-draw{from{clip-path:inset(0 100% 0 0)}to{clip-path:inset(0 0 0 0)}}"
        + "@keyframes cv-twinkle{0%,100%{transform:scale(1);opacity:1}25%{transform:scale(1.15)}"
        + "75%{transform:scale(0.85);opacity:0.4}}"

    static let navCSS = "nav{position:sticky;top:0;z-index:10;display:flex;gap:4px;padding:8px 16px;"
        + "background:rgba(255,255,255,0.94);border-bottom:1px solid #e3e5ea;overflow-x:auto}"
        + "nav a{padding:8px 12px;border-radius:8px;color:#16181d;text-decoration:none;white-space:nowrap}"
        + "nav a:hover,nav a:focus{background:#eef0f4}"

    /// The slide player: every page a fixed layer over the window, its
    /// picture fitted inside it; the controls; the transitions; the
    /// entrances; and nothing moving for a reader who asks for less.
    static let slidesCSS = [
        "html,body{height:100%;overflow:hidden;background:#000}.slide{position:fixed;inset:0;display:flex;",
        "align-items:center;justify-content:center;visibility:hidden;animation-fill-mode:both;animation-timing-function:cubic-bezier(.33,",
        "1,.68,1)}.slide.on{visibility:visible;z-index:2}.slide.off{visibility:visible;z-index:1}.frame{",
        "position:relative;max-width:100vw;max-height:100vh}.frame>svg{display:block;width:100%;height:100%}",
        ".frame>video{position:absolute;object-fit:cover}#bar{position:fixed;left:0;top:0;height:4px;",
        "background:#5a31f4;z-index:5;transition:width .3s}#fs{position:fixed;right:12px;bottom:12px;",
        "z-index:5;padding:8px 12px;border:0;border-radius:8px;background:rgba(255,255,255,.85);font:inherit;",
        "cursor:pointer}@keyframes t-fade{from{opacity:0}}@keyframes t-slide{from{transform:translateX(100%)}",
        "}@keyframes t-slide-b{from{transform:translateX(-100%)}}@keyframes t-push-out{to{transform:translateX(-100%)}",
        "}@keyframes t-push-out-b{to{transform:translateX(100%)}}@keyframes t-zoom{from{opacity:0;transform:scale(.85)}",
        "}.in-fade{animation-name:t-fade}.in-slide{animation-name:t-slide}.in-slide.back{animation-name:t-slide-b}",
        ".in-push{animation-name:t-slide}.in-push.back{animation-name:t-slide-b}.out-push{animation-name:t-push-out}",
        ".out-push.back{animation-name:t-push-out-b}.in-zoom{animation-name:t-zoom}@keyframes canvia-in-fade{",
        "from{opacity:0}}@keyframes canvia-in-rise{from{opacity:0;transform:translateY(30%)}}@keyframes canvia-in-pan-left{",
        "from{opacity:0;transform:translateX(100%)}}@keyframes canvia-in-pan-right{from{opacity:0;transform:translateX(-100%)}",
        "}@keyframes canvia-in-pop{from{opacity:0;transform:scale(.4)}}@keyframes canvia-in-wipe{from{",
        "clip-path:inset(0 100% 0 0)}to{clip-path:inset(0 0 0 0)}}.canvia-in{transform-box:fill-box;transform-origin:center}",
        ".on .canvia-in{animation-fill-mode:both;animation-timing-function:cubic-bezier(.33,1,.68,1)}",
        ".on .canvia-in-fade{animation-name:canvia-in-fade}.on .canvia-in-rise{animation-name:canvia-in-rise}",
        ".on .canvia-in-pan-left{animation-name:canvia-in-pan-left}.on .canvia-in-pan-right{animation-name:canvia-in-pan-right}",
        ".on .canvia-in-pop{animation-name:canvia-in-pop}.on .canvia-in-wipe{animation-name:canvia-in-wipe}",
        "@media (prefers-reduced-motion:reduce){.slide,.canvia-in,.on .canvia-in{animation:none!important}",
        "}",
    ].joined()

    /// The slide player's script, about 3 KB: which slide is on, and every
    /// way of going on, back or to one. Read from the page — the sections'
    /// data-t (transition) and data-s (its seconds) and the body's
    /// data-auto and data-loop — so it is the same for every design.
    static let slidesJS = [
        "(function(){var s=[].slice.call(document.querySelectorAll('.slide')),n=s.length,i=-1,b=document.body,",
        "auto=+b.dataset.auto||0,loop=b.dataset.loop==='true',bar=document.getElementById('bar'),timer=0,",
        "still=window.matchMedia&&matchMedia('(prefers-reduced-motion:reduce)').matches;function clean(e){",
        "e.className='slide';e.style.animationDuration=''}function go(k,back){if(!n)return;if(k<0||k>=n){",
        "if(!loop)return;k=(k+n)%n}if(k===i)return;var from=s[i],to=s[k],t=from?(back?to:from).dataset.t:'cut',",
        "sec=from?+(back?to:from).dataset.s:0;s.forEach(function(e){if(e!==from)clean(e)});if(from){clean(from);",
        "if(t!=='cut'&&!still){from.className='slide off'+(t==='push'?' out-push':'')+(back?' back':'');",
        "from.style.animationDuration=sec+'s';setTimeout(function(){if(from!==s[i])clean(from)},sec*1000)}",
        "}to.className='slide on'+(t!=='cut'&&!still&&from?' in-'+t:'')+(back?' back':'');to.style.animationDuration=sec+'s';",
        "i=k;bar.style.width=((k+1)/n*100)+'%';if(location.hash!=='#'+to.id)history.replaceState(null,",
        "'','#'+to.id);clearTimeout(timer);if(auto>0)timer=setTimeout(function(){go(i+1)},auto*1000)}",
        "function next(){go(i+1)}function prev(){go(i-1,true)}function fromHash(){var m=/^#page-(\\d+)$/.exec(location.hash),",
        "k=m?+m[1]-1:0;if(k>=0&&k<n&&k!==i)go(k,k<i)}document.addEventListener('keydown',function(e){",
        "var k=e.key;if(k==='ArrowRight'||k==='PageDown'||k===' '){e.preventDefault();next()}else if(k==='ArrowLeft'||k==='PageUp'){",
        "e.preventDefault();prev()}else if(k==='Escape'&&document.fullscreenElement)document.exitFullscreen()}",
        ");document.addEventListener('click',function(e){if(e.target.closest('a,button,video'))return;",
        "if(e.clientX<innerWidth/2)prev();else next()});var x0=null;document.addEventListener('touchstart',",
        "function(e){x0=e.touches[0].clientX},{passive:true});document.addEventListener('touchend',function(e){",
        "if(x0===null)return;var dx=e.changedTouches[0].clientX-x0;x0=null;if(Math.abs(dx)>40){if(dx<0)next();",
        "else prev()}});window.addEventListener('hashchange',fromHash);document.getElementById('fs').addEventListener('click',",
        "function(){if(document.fullscreenElement)document.exitFullscreen();else if(document.documentElement.requestFullscreen)document.documentElement.requestFullscreen()}",
        ");fromHash();if(i<0)go(0)})();",
    ].joined()

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
        if settings.slides {
            return slidePlayer(design, pages: pages, settings: settings, clipFile: clipFile, poster: poster,
                               standIns: nil)
        }
        let shown = pages.filter { design.pages.indices.contains($0) }
        let labels = shown.enumerated().map { label(design, pageIndex: $0.element, number: $0.offset + 1) }
        let anchors = sectionAnchors(design, shown: shown)
        var out = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        out += "<title>\(SVGExporter.escape(design.title))</title>\n"
        out += "<style>" + css
        if settings.nav { out += navCSS }
        if settings.nav && settings.mobileStack { out += stackCSS }
        if shown.contains(where: { SVGExporter.moves(design, page: design.pages[$0]) }) { out += motionCSS }
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
            out += svg?(page) ?? SVGExporter.svg(design: design, page: page, aria: true, anchors: anchors, moving: true)
            out += textLayer(design, page: page)
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

    /// A link to a page held here goes to its section (or slide): each
    /// page's id to its number among those shown, the first of a page
    /// shown twice.
    static func sectionAnchors(_ design: Design, shown: [Int]) -> [String: Int] {
        var anchors: [String: Int] = [:]
        for (n, index) in shown.enumerated() where anchors[design.pages[index].id] == nil {
            anchors[design.pages[index].id] = n + 1
        }
        return anchors
    }

    /// The slide player: see the comment at the top. Every page's own
    /// animation is played into its elements first (PageAnimation.playing),
    /// so its entrances come in as Present plays them. `standIns` draw the
    /// words and pictures in the tests, as the website's do.
    @MainActor
    static func slidePlayer(_ design: Design, pages: [Int], settings: Settings,
                            clipFile: (Element) -> String?, poster: ((Element) -> Data?)?,
                            standIns: SVGExporter.StandIns?) -> String {
        let shown = pages.filter { design.pages.indices.contains($0) }
        let labels = shown.enumerated().map { label(design, pageIndex: $0.element, number: $0.offset + 1) }
        let anchors = sectionAnchors(design, shown: shown)
        var out = "<!DOCTYPE html>\n<html>\n<head>\n<meta charset=\"utf-8\">\n"
        out += "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
        out += "<title>\(SVGExporter.escape(design.title))</title>\n"
        out += "<style>" + css + slidesCSS
        if shown.contains(where: { SVGExporter.moves(design, page: design.pages[$0]) }) { out += motionCSS }
        out += "</style>\n</head>\n"
        out += "<body data-auto=\"\(SVGExporter.num(max(settings.autoplay, 0)))\" data-loop=\"\(settings.loop)\">\n"
        out += "<div id=\"bar\" role=\"progressbar\" aria-label=\"\(SVGExporter.escape(tr("Pages")))\"></div>\n"
        out += "<main>\n"
        for (n, index) in shown.enumerated() {
            out += slide(design, index: index, number: n + 1, label: labels[n], anchors: anchors,
                         settings: settings, clipFile: clipFile, poster: poster, standIns: standIns)
        }
        out += "</main>\n"
        out += "<button id=\"fs\" type=\"button\">\(SVGExporter.escape(tr("Full screen")))</button>\n"
        out += "<script>" + slidesJS + "</script>\n"
        out += "</body>\n</html>\n"
        return out
    }

    /// One page of the slide player: a full-window section that knows how
    /// it changes, its picture in a frame as wide as the window or as the
    /// window is tall, whichever leaves the whole page in it.
    @MainActor
    private static func slide(_ design: Design, index: Int, number: Int, label: String, anchors: [String: Int],
                              settings: Settings, clipFile: (Element) -> String?,
                              poster: ((Element) -> Data?)?, standIns: SVGExporter.StandIns?) -> String {
        let page = PageAnimation.playing(design.pages[index])
        let size = design.size(for: page)
        let kind = slideTransition(PageTransitions.transitionKind(after: page, in: design))
        let seconds = PageTransitions.presentSeconds(kind, own: page.transitionSeconds)
        var out = "<section class=\"slide\" id=\"page-\(number)\" aria-label=\"\(SVGExporter.escape(label))\" "
        out += "data-t=\"\(kind)\" data-s=\"\(SVGExporter.num(seconds))\">"
        let w = SVGExporter.num(size.width)
        let h = SVGExporter.num(size.height)
        out += "<div class=\"frame\" style=\"width:min(100vw,calc(100vh*\(w)/\(h)));aspect-ratio:\(w)/\(h)\">"
        out += SVGExporter.svg(design: design, page: page, aria: true, standIns: standIns, anchors: anchors,
                               moving: true, entrances: true)
        if settings.embedMedia {
            for clip in clips(design, pages: [index]) {
                guard let file = clipFile(clip) else { continue }
                let still = poster?(clip) ?? posterPNG(clip)
                out += video(clip, file: file, pageW: Double(size.width), pageH: Double(size.height), poster: still)
            }
        }
        out += "</div>"
        out += textLayer(design, page: page)
        out += "</section>\n"
        return out
    }

    /// `page`'s words for a screen reader, hidden from sight: a
    /// `<div class="sr">` of its structure (PdfTags.page) as HTML — /H1–/H3
    /// as <h1>–<h3>, /P as <p>, /BlockQuote as <blockquote>, a /Caption as
    /// a <figure>'s <figcaption>, a list as <ul> and a table as <table>
    /// with <th> and <td>. Figures are left to the picture's own labels.
    /// Nothing for a page with no words. The Android twin's
    /// HtmlWriter.textLayer, tag for tag.
    static func textLayer(_ design: Design, page: Page) -> String {
        let all = design.masterElements(behind: page) + page.elements
        let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let numbering = design.pageNumbering(shownOn: page)
        func words(_ node: PdfTags.StructNode) -> String {
            if let text = node.text { return text }
            return node.ids.compactMap { byId[$0] }.map { el in
                var raw = el.text ?? ""
                if let numbering {
                    raw = raw.replacingOccurrences(of: "{page}", with: String(numbering.number))
                        .replacingOccurrences(of: "{pages}", with: String(numbering.count))
                }
                return RichText.strip(raw).trimmingCharacters(in: .whitespacesAndNewlines)
            }.joined(separator: " ")
        }
        func esc(_ s: String) -> String { SVGExporter.escape(s).replacingOccurrences(of: "\n", with: "<br>") }
        var out = ""
        for node in PdfTags.page(design, page) {
            switch node.role {
            case PdfTags.h1, PdfTags.h2, PdfTags.h3:
                let tag = node.role.lowercased()
                out += "<\(tag)>" + esc(words(node)) + "</\(tag)>"
            case PdfTags.p: out += "<p>" + esc(words(node)) + "</p>"
            case PdfTags.blockQuote: out += "<blockquote>" + esc(words(node)) + "</blockquote>"
            case PdfTags.caption: out += "<figure><figcaption>" + esc(words(node)) + "</figcaption></figure>"
            case PdfTags.l:
                let items = node.kids.map { "<li>" + esc($0.kids.first?.text ?? "") + "</li>" }
                out += "<ul>" + items.joined() + "</ul>"
            case PdfTags.table:
                let rows = node.kids.map { row -> String in
                    let cells = row.kids.map { cell -> String in
                        let tag = cell.role.lowercased()
                        return "<\(tag)>" + esc(cell.text ?? "") + "</\(tag)>"
                    }
                    return "<tr>" + cells.joined() + "</tr>"
                }
                out += "<table>" + rows.joined() + "</table>"
            default: break
            }
        }
        return out.isEmpty ? "" : "<div class=\"sr\">" + out + "</div>"
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
