// The table designs (TableDesigns) as a row of tiles swiped along: each
// design's 3x3 sample drawn in the accents it would take here, its name
// under it, the one the table has ringed. What Add > Table inserts from,
// and the Table sheet's Design row restyles with — the Android twin's
// TableDesignRow and TableTiles.

import SwiftUI

struct TableDesignRow: View {
    /// The colours "accent" and "accent2" stand for (TableDesigns.accents).
    let accents: (String, String)
    /// The design the table has, ringed; nil for none.
    let selected: String?
    let onPick: (TableDesigns.TableDesign) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 10) {
                ForEach(TableDesigns.all) { design in
                    tile(design)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func tile(_ design: TableDesigns.TableDesign) -> some View {
        let chosen = selected == design.id
        return Button {
            onPick(design)
        } label: {
            VStack(spacing: 4) {
                TableDesignThumb(design: design, accents: accents)
                    .frame(width: 112)
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(chosen ? Theme.accent : Theme.hairline, lineWidth: chosen ? 2 : 1))
                Text(design.label)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .frame(width: 112)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tr("%@ table", design.label))
        .accessibilityAddTraits(chosen ? [.isButton, .isSelected] : .isButton)
    }
}

/// A design's tile: its sample table, drawn once for its accents and kept.
struct TableDesignThumb: View {
    let design: TableDesigns.TableDesign
    let accents: (String, String)
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.white
                    .aspectRatio(TableTileCache.width / TableTileCache.height, contentMode: .fit)
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task(id: design.id + accents.0 + accents.1) {
            image = TableTileCache.thumbnail(for: design, accents: accents)
        }
    }
}

@MainActor
enum TableTileCache {
    /// A tile's size in page units, and the sample's width on it.
    static let width: Double = 240
    static let height: Double = 150
    private static let frame: Double = 216

    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 40
        return c
    }()

    static func thumbnail(for design: TableDesigns.TableDesign, accents: (String, String)) -> UIImage? {
        let key = "\(design.id)#\(accents.0)\(accents.1)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let made = DataGraphics.table(TableDesigns.sample, in: CGRect(x: (width - frame) / 2, y: 0, width: frame, height: 1),
                                      accent: accents.0)
        guard let id = made.lazy.compactMap({ $0.table?.id }).first else { return nil }
        let styled = Tables.withDesign(made, id: id, design: design, accent: accents.0, accent2: accents.1,
                                       heightFor: { FontLibrary.layoutHeight(for: $0) }) ?? made
        let bottom = styled.map { $0.y + $0.h }.max() ?? height
        let tall = max(height, bottom + 16)
        let dy = ((tall - bottom) / 2).rounded()
        var sheet = Design(title: design.name, width: width, height: tall)
        sheet.pages = [Page(elements: styled.map { el in
            var moved = el
            moved.y += dy
            return moved
        })]
        let renderer = ImageRenderer(content: PageRenderView(design: sheet, page: sheet.pages[0]))
        renderer.scale = 1.5
        renderer.isOpaque = true
        let image = renderer.uiImage
        if let image { cache.setObject(image, forKey: key) }
        return image
    }
}
