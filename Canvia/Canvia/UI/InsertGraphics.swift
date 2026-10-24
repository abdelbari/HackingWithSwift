// Add's Graphics: the illustrated pack (GraphicsLibrary), a chip for each
// of its thirteen categories over a row of tiles, each drawn by the page's own
// renderer as it goes on a page (GraphicThumb). A tap puts the graphic on
// the page as an SVG graphic goes on — its shapes in their own colours, one
// group, selected — and into Recently used, as the Android twin's Add panel
// does. The search above the tabs finds the graphics by their tags
// (ElementSearch). The Animated category's chip holds every graphic that
// moves, each tile marked, and one goes on already animated
// (GraphicsLibrary.elements).

import SwiftUI
import UIKit

struct GraphicsSection: View {
    let onAdd: (GraphicDef) -> Void
    /// The category chosen; nil is all of them.
    @State private var category: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            InsertSheet.header(tr("Graphics"))
            chips
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(GraphicsLibrary.inCategory(category)) { graphic in tile(graphic) }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, tr("All"))
                ForEach(GraphicsLibrary.categories, id: \.self) { name in chip(name, tr(name)) }
            }
        }
    }

    private func chip(_ name: String?, _ title: String) -> some View {
        let selected = category == name
        return Button { category = name } label: {
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

    private func tile(_ graphic: GraphicDef) -> some View {
        Button { onAdd(graphic) } label: {
            GraphicThumb(graphic: graphic)
                .padding(6)
                .frame(width: 64, height: 64)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(.systemGray6)))
                .overlay(alignment: .bottomTrailing) { motionBadge(graphic) }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(graphic.motion == nil ? tr("%@ graphic", graphic.name) : tr("%@ graphic, animated", graphic.name))
    }

    /// A graphic that moves is marked so on its tile.
    @ViewBuilder
    private func motionBadge(_ graphic: GraphicDef) -> some View {
        if graphic.motion != nil {
            Image(systemName: "sparkles")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(4)
                .accessibilityHidden(true)
        }
    }
}

/// A graphic from the pack as its tile shows it: drawn by the page's own
/// renderer, as it goes on a page, and kept (GraphicThumbCache).
struct GraphicThumb: View {
    let graphic: GraphicDef
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.clear
            }
        }
        .task(id: graphic.id) {
            image = GraphicThumbCache.thumbnail(for: graphic)
        }
    }
}

@MainActor
enum GraphicThumbCache {
    /// NSCache, as the other thumbnail caches, so a memory warning gives
    /// them back.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 240
        return c
    }()

    /// The side of the square a graphic is drawn in, in page units.
    private static let side = 100.0

    static func thumbnail(for graphic: GraphicDef) -> UIImage? {
        let key = graphic.id as NSString
        if let cached = cache.object(forKey: key) { return cached }
        // Laid on a page it takes `fitShare` of, centred, then moved so it
        // fills a page of its own size.
        let page = side / SvgImport.fitShare
        let inset = (page - side) / 2
        var elements = GraphicsLibrary.elements(graphic, pageWidth: page, pageHeight: page)
        for i in elements.indices {
            elements[i].x -= inset
            elements[i].y -= inset
        }
        var design = Design(title: graphic.name, width: side, height: side)
        design.pages = [Page(background: .color("#00000000"), elements: elements)]
        let renderer = ImageRenderer(content: PageRenderView(design: design, page: design.pages[0]))
        renderer.scale = 1.6
        renderer.isOpaque = false
        let image = renderer.uiImage
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}

extension DesignStore {

    /// One of the illustrated graphics on the page, as an SVG graphic goes
    /// on (addGraphic): its shapes in their own colours, one group, fitted
    /// to this page and selected — one step; onto the next unlocked page
    /// when this one is locked. False when it went nowhere.
    @discardableResult
    func addPackGraphic(_ graphic: GraphicDef) -> Bool {
        guard landsOnUnlockedPage() else { return false }
        let elements = GraphicsLibrary.elements(graphic, pageWidth: pageWidth, pageHeight: pageHeight)
        guard !elements.isEmpty else { return false }
        addGraphic(SvgImport.Graphic(elements: elements, skipped: false))
        return true
    }
}
