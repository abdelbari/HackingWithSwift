// Saved text styles: named, and linked.
//
// The style painter copies a look once. A saved style keeps it: "Heading",
// "Caption", "Price" — apply it to any text, and when the style is updated
// from one element every element that follows it changes too, across every
// page. Kept in Documents, because a style belongs to the person, not to
// one design.

import Foundation

struct TextStyle: Codable, Identifiable, Equatable {
    var id: String = UID.make("style")
    var name: String
    var style: DesignStore.Style
}

enum TextStyles {

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("textstyles.json")
    }

    static func load(from url: URL = fileURL) -> [TextStyle] {
        guard let data = try? Data(contentsOf: url),
              let styles = try? JSONDecoder().decode([TextStyle].self, from: data) else { return [] }
        return styles
    }

    static func save(_ styles: [TextStyle], to url: URL = fileURL) {
        if let data = try? JSONEncoder().encode(styles) { try? data.write(to: url) }
    }

    /// Only what a text style is: the type, its colour and effects. Nothing
    /// about the box or the picture fields the Style struct also carries.
    static func textOnly(_ style: DesignStore.Style) -> DesignStore.Style {
        var s = DesignStore.Style(opacity: 1)
        s.color = style.color; s.fontFamily = style.fontFamily; s.fontSize = style.fontSize
        s.fontWeight = style.fontWeight; s.italic = style.italic; s.underline = style.underline
        s.align = style.align; s.lineHeight = style.lineHeight; s.letterSpacing = style.letterSpacing
        s.listStyle = style.listStyle; s.indent = style.indent; s.textFill = style.textFill
        s.vAlign = style.vAlign; s.paragraphSpacing = style.paragraphSpacing
        s.effect = style.effect; s.curve = style.curve; s.shadow = style.shadow
        return s
    }

    @discardableResult
    static func add(named name: String, from element: Element, url: URL = fileURL) -> TextStyle {
        var styles = load(from: url)
        let style = TextStyle(name: name, style: textOnly(DesignStore.style(of: element)))
        styles.append(style)
        save(styles, to: url)
        return style
    }

    static func update(_ id: String, from element: Element, url: URL = fileURL) {
        var styles = load(from: url)
        guard let i = styles.firstIndex(where: { $0.id == id }) else { return }
        styles[i].style = textOnly(DesignStore.style(of: element))
        save(styles, to: url)
    }

    static func remove(_ id: String, url: URL = fileURL) {
        save(load(from: url).filter { $0.id != id }, to: url)
    }

    /// The style poured into a text element, which then follows it.
    static func apply(_ style: TextStyle, to el: inout Element) {
        guard el.type == .text else { return }
        let opacity = el.opacity
        var s = style.style
        s.opacity = opacity
        DesignStore.apply(s, to: &el)
        el.textStyleId = style.id
    }
}
