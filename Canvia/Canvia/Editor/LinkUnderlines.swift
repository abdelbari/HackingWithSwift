// Settings ▸ Accessibility's Underline links: a line under each linked word
// on a page (WordLinks), in the words' own colour, a fifteenth of their size
// thick, turned with their box — over the canvas and Present only, never an
// export, as the Android twin's PageRenderer.drawLinkUnderlines draws it.

import SwiftUI

struct LinkUnderlines: View {
    let design: Design
    let page: Page

    var body: some View {
        let size = design.size(for: page)
        ZStack(alignment: .topLeading) {
            ForEach(linked) { el in underlines(el) }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The page's texts with linked words, the master's behind them too.
    private var linked: [Element] {
        design.drawnElements(on: page).filter { el in el.type == .text && el.liveSpans.contains { $0.link != nil } }
    }

    private func underlines(_ el: Element) -> some View {
        let thick = max(1, (el.fontSize ?? 42) / 15)
        let rects = WordLinks.rects(for: el).map { $0.rect }
        let ink = Color(hex: el.color ?? "#000000")
        return ZStack(alignment: .topLeading) {
            ForEach(rects.indices, id: \.self) { i in
                Rectangle()
                    .fill(ink)
                    .frame(width: rects[i].width, height: thick)
                    .offset(x: rects[i].minX, y: rects[i].maxY - thick)
            }
        }
        .frame(width: el.w, height: el.h, alignment: .topLeading)
        .rotationEffect(.degrees(el.rotation))
        .position(x: el.x + el.w / 2, y: el.y + el.h / 2)
    }
}
