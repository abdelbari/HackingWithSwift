// A whole SVG brought in as a graphic: every shape it draws, each its own
// shape element in its own colours, grouped, so it moves as one and each
// colour can be changed on its own (see ColourSwap) — how a logo or an
// illustration from another tool comes in.
//
// Drawn: <path>, <rect> (with rx/ry), <circle>, <ellipse>, <line>,
// <polyline> and <polygon>, inside any depth of <g> (and <a>, <switch>, a
// nested <svg>) with their transforms — matrix, translate, scale, rotate,
// skewX and skewY. The root's viewBox frames the graphic; with
// preserveAspectRatio="none" and a width and height it is stretched to them
// first. Fill, stroke, stroke-width, opacity, fill-opacity, stroke-opacity
// and fill-rule are read from attributes, then from simple <style> rules
// (".class" or "#id", several selectors to a rule allowed), then from the
// inline style, each overriding the one before, and the inheritable ones
// passed down. A linearGradient or radialGradient fill becomes a gradient
// Paint with the same stops: a linear one's angle is its direction, its
// ends are not kept. <text>, <image>, <use>, masks, filters and clipPaths
// are left out — what they would have drawn is not drawn — and the graphic
// says so (`skipped`).
//
// Each part is a shape whose path is normalised into its own 0…100 box by
// the same writer as every path (TextOutliner.svgPathData), placed on the
// page with the whole graphic fitted to 0.4 of the page's shorter side and
// centred. Every part shares one `group` and takes its SVG id, when it has
// one, as its `layerName`; an even-odd one writes `fillRule`. The Android
// twin reads the same files to the same elements; SvgImportTests holds the
// shared files.

import CoreGraphics
import Foundation

enum SvgImport {

    /// The largest file read, in bytes.
    static let maxBytes = 2 * 1024 * 1024
    /// The most parts one graphic keeps; those past it are left out.
    static let maxParts = 600
    /// The graphic's longer side, as a share of the page's shorter one.
    static let fitShare = 0.4
    /// What the phone says when anything was left out.
    static let partialNote = "Some parts of this SVG couldn't be brought in"

    struct Graphic {
        var elements: [Element]
        /// Something was left out: words, a picture, a mask, a filter, a
        /// clip, a reuse or parts past the limit.
        var skipped: Bool
    }

    /// The graphic an SVG document draws, placed on a page `pageWidth` by
    /// `pageHeight`; nil when it is too big, cannot be read or draws
    /// nothing.
    static func graphic(_ svg: String, pageWidth: Double, pageHeight: Double) -> Graphic? {
        guard svg.utf8.count <= maxBytes, let root = parse(svg), root.name == "svg" else { return nil }
        var reader = Reader(root: root)
        reader.walk(root, inherited: Inherited(), transform: .identity, isRoot: true)
        guard !reader.parts.isEmpty else { return nil }

        // What is fitted to the page: the root's viewBox, stretched first
        // when it asks to be; else its width and height; else what it draws.
        var frame = CGAffineTransform.identity
        var box: CGRect
        let size = (length(root.attributes["width"]), length(root.attributes["height"]))
        let viewBox = numbers(root.attributes["viewBox"] ?? "")
        if viewBox.count == 4, viewBox[2] > 0, viewBox[3] > 0 {
            box = CGRect(x: viewBox[0], y: viewBox[1], width: viewBox[2], height: viewBox[3])
            if root.attributes["preserveAspectRatio"]?.trimmingCharacters(in: .whitespaces) == "none",
               let w = size.0, let h = size.1, w > 0, h > 0 {
                frame = CGAffineTransform(translationX: -box.minX, y: -box.minY)
                    .concatenating(CGAffineTransform(scaleX: w / box.width, y: h / box.height))
                box = CGRect(x: 0, y: 0, width: w, height: h)
            }
        } else if let w = size.0, let h = size.1, w > 0, h > 0 {
            box = CGRect(x: 0, y: 0, width: w, height: h)
        } else {
            box = reader.parts.reduce(CGRect.null) { sum, part in
                var t = part.transform
                return sum.union(part.path.copy(using: &t)?.boundingBoxOfPath ?? .null)
            }
        }
        guard !box.isNull, box.width > 0 || box.height > 0 else { return nil }

        let scale = fitShare * min(pageWidth, pageHeight) / max(box.width, box.height)
        let fit = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                    tx: (pageWidth - box.width * scale) / 2 - box.minX * scale,
                                    ty: (pageHeight - box.height * scale) / 2 - box.minY * scale)
        let group = UID.make("grp")
        let elements = reader.parts.compactMap { part -> Element? in
            var el = element(part, placing: part.transform.concatenating(frame).concatenating(fit))
            el?.group = group
            return el
        }
        guard !elements.isEmpty else { return nil }
        return Graphic(elements: elements, skipped: reader.skipped)
    }

    // MARK: parts

    /// One shape to draw: its outline in its own user space, the transform
    /// to the root's, and how it is painted.
    struct Drawable {
        var path: CGPath
        var transform: CGAffineTransform
        var fill: Paint
        var stroke: String?
        var strokeWidth: Double
        var opacity: Double
        var evenOdd: Bool
        var name: String?
    }

    /// A part as a shape on the page: placed by `placing`, its box the
    /// outline's bounds (a flat one widened to its stroke, or to one unit),
    /// its path normalised into that box.
    static func element(_ part: Drawable, placing: CGAffineTransform) -> Element? {
        var t = placing
        guard let placed = part.path.copy(using: &t) else { return nil }
        var box = placed.boundingBoxOfPath
        guard !box.isNull, box.width.isFinite, box.height.isFinite else { return nil }
        let widthScale = abs(Double(placing.a * placing.d - placing.b * placing.c)).squareRoot()
        let strokeWidth = part.strokeWidth * widthScale
        let flat = max(strokeWidth, 1)
        if box.width < 0.01 { box = box.insetBy(dx: -flat / 2, dy: 0) }
        if box.height < 0.01 { box = box.insetBy(dx: 0, dy: -flat / 2) }
        var unit = CGAffineTransform(translationX: -box.minX, y: -box.minY)
            .concatenating(CGAffineTransform(scaleX: 100 / box.width, y: 100 / box.height))
        guard let normalised = placed.copy(using: &unit) else { return nil }
        var el = Element.shape("rect", w: rounded(box.width), h: rounded(box.height))
        el.x = rounded(box.minX)
        el.y = rounded(box.minY)
        el.pathData = TextOutliner.svgPathData(normalised)
        el.radius = 0
        el.fill = part.fill
        if let stroke = part.stroke, strokeWidth > 0 {
            el.stroke = stroke
            el.strokeWidth = rounded(strokeWidth)
        }
        if part.opacity < 1 { el.opacity = rounded(part.opacity) }
        if part.evenOdd { el.fillRule = "evenodd" }
        el.layerName = part.name.flatMap(LayerNames.cleaned)
        return el
    }

    /// The properties passed down from a group to what is in it, as
    /// written; opacity is multiplied down instead.
    struct Inherited {
        var fill = "#000000"
        var stroke = "none"
        var strokeWidth = "1"
        var fillOpacity = "1"
        var strokeOpacity = "1"
        var fillRule = "nonzero"
        var color = "#000000"
        var visible = true
        var opacity = 1.0
    }

    /// Walks the document, collecting parts.
    struct Reader {
        let root: Node
        var parts: [Drawable] = []
        var skipped = false
        let classRules: [String: [String: String]]
        let idRules: [String: [String: String]]
        let gradients: [String: Node]

        init(root: Node) {
            self.root = root
            var classes: [String: [String: String]] = [:]
            var ids: [String: [String: String]] = [:]
            var gradients: [String: Node] = [:]
            var stack = [root]
            while let node = stack.popLast() {
                if node.name == "style" {
                    for rule in SvgImport.styleRules(node.text) {
                        for selector in rule.selectors {
                            if selector.hasPrefix(".") {
                                classes[String(selector.dropFirst()), default: [:]].merge(rule.declarations) { $1 }
                            } else if selector.hasPrefix("#") {
                                ids[String(selector.dropFirst()), default: [:]].merge(rule.declarations) { $1 }
                            }
                        }
                    }
                }
                if node.name == "linearGradient" || node.name == "radialGradient", let id = node.attributes["id"] {
                    gradients[id] = node
                }
                stack.append(contentsOf: node.children.reversed())
            }
            classRules = classes
            idRules = ids
            self.gradients = gradients
        }

        /// What a node says of a property: its attribute, then its classes'
        /// rules, its id's rule, then its inline style.
        func properties(of node: Node) -> [String: String] {
            var out: [String: String] = [:]
            for key in SvgImport.styledKeys {
                if let value = node.attributes[key] { out[key] = value }
            }
            for name in (node.attributes["class"] ?? "").split(separator: " ") {
                if let rule = classRules[String(name)] { out.merge(rule) { $1 } }
            }
            if let id = node.attributes["id"], let rule = idRules[id] { out.merge(rule) { $1 } }
            out.merge(SvgImport.declarations(node.attributes["style"] ?? "")) { $1 }
            return out.mapValues { $0.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespaces) }
        }

        mutating func walk(_ node: Node, inherited: Inherited, transform: CGAffineTransform, isRoot: Bool = false) {
            if SvgImport.skippedNames.contains(node.name) { skipped = true; return }
            guard isRoot || SvgImport.containers.contains(node.name) || SvgImport.shapes.contains(node.name) else { return }
            let props = properties(of: node)
            if props["display"] == "none" { return }
            var style = inherited
            func take(_ key: String, _ path: WritableKeyPath<Inherited, String>) {
                if let value = props[key], value != "inherit" { style[keyPath: path] = value }
            }
            take("fill", \.fill)
            take("stroke", \.stroke)
            take("stroke-width", \.strokeWidth)
            take("fill-opacity", \.fillOpacity)
            take("stroke-opacity", \.strokeOpacity)
            take("fill-rule", \.fillRule)
            take("color", \.color)
            if let visibility = props["visibility"] { style.visible = visibility == "visible" }
            if let opacity = props["opacity"].flatMap(SvgImport.fraction) { style.opacity *= opacity }
            if node.attributes["mask"] != nil || node.attributes["filter"] != nil || node.attributes["clip-path"] != nil
                || props["mask"] != nil || props["filter"] != nil || props["clip-path"] != nil {
                // Drawn without them.
                skipped = true
            }
            // A nested svg is a group; the root's own place is the frame's.
            let own = isRoot ? CGAffineTransform.identity : SvgImport.transform(node.attributes["transform"] ?? "")
            let here = own.concatenating(transform)
            if SvgImport.shapes.contains(node.name) {
                addShape(node, style: style, transform: here)
                return
            }
            for child in node.children {
                walk(child, inherited: style, transform: here)
            }
        }

        mutating func addShape(_ node: Node, style: Inherited, transform: CGAffineTransform) {
            guard style.visible, let path = SvgImport.outline(node), !path.isEmpty else { return }
            guard parts.count < SvgImport.maxParts else { skipped = true; return }
            let fillOpacity = SvgImport.fraction(style.fillOpacity) ?? 1
            let strokeOpacity = SvgImport.fraction(style.strokeOpacity) ?? 1
            // A line has no inside to fill.
            let fill = node.name == "line" ? Paint.clear : paint(style.fill, opacity: fillOpacity, color: style.color)
            var stroke: String?
            switch SvgImport.Ink.read(style.stroke, color: style.color, gradients: gradients) {
            case .solid(let hex)?:
                stroke = SvgImport.hex(hex, alpha: strokeOpacity)
            case .gradient(let gradient)?:
                // A gradient border is drawn in its first colour.
                stroke = SvgImport.stops(gradient, gradients: gradients, opacity: strokeOpacity).first?.color
            case .missing?:
                skipped = true
            case nil:
                break
            }
            let width = SvgImport.length(style.strokeWidth) ?? 1
            guard fill.kind != "none" || (stroke != nil && width > 0) else { return }
            parts.append(Drawable(path: path, transform: transform, fill: fill, stroke: stroke, strokeWidth: width,
                              opacity: style.opacity, evenOdd: style.fillRule == "evenodd",
                              name: node.attributes["id"]))
        }

        /// A fill as a Paint: none, a colour with its opacity as alpha, or a
        /// gradient's stops.
        mutating func paint(_ raw: String, opacity: Double, color: String) -> Paint {
            switch SvgImport.Ink.read(raw, color: color, gradients: gradients) {
            case .solid(let hex)?:
                return .solid(SvgImport.hex(hex, alpha: opacity))
            case .gradient(let node)?:
                let stops = SvgImport.stops(node, gradients: gradients, opacity: opacity)
                if stops.count == 1 { return .solid(stops[0].color) }
                guard stops.count >= 2 else { return Paint.clear }
                let radial = node.name == "radialGradient"
                return Paint(kind: "gradient", color: nil,
                             angle: radial ? nil : SvgImport.angle(node, gradients: gradients),
                             stops: stops, gradientKind: radial ? "radial" : nil)
            case .missing?:
                skipped = true
                return Paint.clear
            case nil:
                return Paint.clear
            }
        }
    }

    // MARK: reading the document

    /// An element of the document: its name without any prefix, its
    /// attributes, what is in it, and its text (a <style>'s rules).
    final class Node {
        let name: String
        let attributes: [String: String]
        var children: [Node] = []
        var text = ""

        init(name: String, attributes: [String: String]) {
            self.name = name
            self.attributes = attributes
        }
    }

    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var root: Node?
        var stack: [Node] = []

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
            var attributes: [String: String] = [:]
            for (key, value) in attributeDict {
                // xlink:href and href alike.
                attributes[key.hasSuffix(":href") ? "href" : key] = value
            }
            let node = Node(name: name, attributes: attributes)
            if let parent = stack.last {
                parent.children.append(node)
            } else if root == nil {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            if !stack.isEmpty { stack.removeLast() }
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            stack.last?.text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            stack.last?.text += String(data: CDATABlock, encoding: .utf8) ?? ""
        }
    }

    static func parse(_ svg: String) -> Node? {
        let builder = TreeBuilder()
        let parser = XMLParser(data: Data(svg.utf8))
        parser.delegate = builder
        guard parser.parse() else { return nil }
        return builder.root
    }

    /// What is drawn; what holds what is drawn; what is left out and said
    /// to be.
    static let shapes: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]
    static let containers: Set<String> = ["svg", "g", "a", "switch"]
    static let skippedNames: Set<String> = ["text", "image", "mask", "filter", "clipPath", "use", "foreignObject"]
    /// The presentation attributes read.
    static let styledKeys = ["fill", "stroke", "stroke-width", "fill-opacity", "stroke-opacity", "fill-rule",
                             "color", "opacity", "display", "visibility"]

    /// A shape's outline in its own user space, or nil when it has none.
    static func outline(_ node: Node) -> CGPath? {
        let a = node.attributes
        func value(_ key: String) -> Double { length(a[key]) ?? 0 }
        switch node.name {
        case "path":
            guard let d = a["d"], !d.isEmpty else { return nil }
            return SVGPath.path(d)
        case "rect":
            let rect = CGRect(x: value("x"), y: value("y"), width: value("width"), height: value("height"))
            guard rect.width > 0, rect.height > 0 else { return nil }
            var rx = length(a["rx"]), ry = length(a["ry"])
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let cornerX = min(max(rx ?? 0, 0), rect.width / 2), cornerY = min(max(ry ?? 0, 0), rect.height / 2)
            guard cornerX > 0, cornerY > 0 else { return CGPath(rect: rect, transform: nil) }
            return CGPath(roundedRect: rect, cornerWidth: cornerX, cornerHeight: cornerY, transform: nil)
        case "circle":
            let r = value("r")
            guard r > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: value("cx") - r, y: value("cy") - r, width: 2 * r, height: 2 * r),
                          transform: nil)
        case "ellipse":
            let rx = value("rx"), ry = value("ry")
            guard rx > 0, ry > 0 else { return nil }
            return CGPath(ellipseIn: CGRect(x: value("cx") - rx, y: value("cy") - ry, width: 2 * rx, height: 2 * ry),
                          transform: nil)
        case "line":
            let path = CGMutablePath()
            path.move(to: CGPoint(x: value("x1"), y: value("y1")))
            path.addLine(to: CGPoint(x: value("x2"), y: value("y2")))
            return path
        case "polyline", "polygon":
            let n = numbers(a["points"] ?? "")
            guard n.count >= 4 else { return nil }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: n[0], y: n[1]))
            var i = 2
            while i + 1 < n.count {
                path.addLine(to: CGPoint(x: n[i], y: n[i + 1]))
                i += 2
            }
            if node.name == "polygon" { path.closeSubpath() }
            return path
        default:
            return nil
        }
    }

    // MARK: styles

    /// The rules of a <style>: each with its selectors and declarations.
    static func styleRules(_ css: String) -> [(selectors: [String], declarations: [String: String])] {
        // Comments out first, an unclosed one to the end.
        let text = css.replacingOccurrences(of: #"/\*[\s\S]*?(\*/|$)"#, with: "", options: .regularExpression)
        var rules: [(selectors: [String], declarations: [String: String])] = []
        for block in text.components(separatedBy: "}") {
            let halves = block.components(separatedBy: "{")
            guard halves.count == 2 else { continue }
            let selectors = halves[0].components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            rules.append((selectors, declarations(halves[1])))
        }
        return rules
    }

    /// "fill:#f00; stroke : blue" as its properties.
    static func declarations(_ text: String) -> [String: String] {
        var out: [String: String] = [:]
        for item in text.components(separatedBy: ";") {
            guard let colon = item.firstIndex(of: ":") else { continue }
            let key = item[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = item[item.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty { out[key] = value }
        }
        return out
    }

    /// What a fill or stroke names: a colour, a gradient, a reference to
    /// something that is not one (a pattern), or nothing.
    enum Ink {
        case solid(String)
        case gradient(Node)
        case missing

        static func read(_ raw: String, color: String, gradients: [String: Node]) -> Ink? {
            let value = raw.trimmingCharacters(in: .whitespaces)
            if value.hasPrefix("url(") {
                let inside = value.dropFirst(4).prefix(while: { $0 != ")" })
                let id = inside.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" "))
                if let node = gradients[id] { return .gradient(node) }
                // A fallback after the reference is drawn instead.
                let rest = value.drop(while: { $0 != ")" }).dropFirst().trimmingCharacters(in: .whitespaces)
                if let fallback = SvgImport.colour(rest, current: color) { return .solid(fallback) }
                return .missing
            }
            return SvgImport.colour(value, current: color).map { Ink.solid($0) }
        }
    }

    /// A gradient's stops, from itself or the gradient it takes them from,
    /// each colour carrying its opacity times `opacity` as alpha; offsets
    /// within 0…1 and never going back.
    static func stops(_ node: Node, gradients: [String: Node], opacity: Double) -> [GradientStop] {
        var source = node
        var hops = 0
        while !source.children.contains(where: { $0.name == "stop" }), hops < 8,
              let href = source.attributes["href"], let next = gradients[String(href.drop(while: { $0 == "#" }))] {
            source = next
            hops += 1
        }
        var out: [GradientStop] = []
        var last = 0.0
        for stop in source.children where stop.name == "stop" {
            let style = declarations(stop.attributes["style"] ?? "")
            let rawColour = style["stop-color"] ?? stop.attributes["stop-color"] ?? "#000000"
            guard let hexColour = colour(rawColour, current: "#000000") else { continue }
            let alpha = (fraction(style["stop-opacity"] ?? stop.attributes["stop-opacity"] ?? "1") ?? 1) * opacity
            let offset = max(last, min(max(fraction(stop.attributes["offset"] ?? "0") ?? 0, 0), 1))
            last = offset
            out.append(GradientStop(offset: rounded(offset), color: hex(hexColour, alpha: alpha)))
        }
        return out
    }

    /// A linear gradient's direction as a CSS angle — 0 up, 90 to the
    /// right — through its gradientTransform, from x1, y1 to x2, y2 (by
    /// default left to right), read from it or the gradient it takes them
    /// from.
    static func angle(_ node: Node, gradients: [String: Node]) -> Double {
        func attribute(_ key: String) -> String? {
            var source: Node? = node
            var hops = 0
            while let current = source, hops < 8 {
                if let value = current.attributes[key] { return value }
                source = current.attributes["href"].flatMap { href in gradients[String(href.drop(while: { $0 == "#" }))] }
                hops += 1
            }
            return nil
        }
        // A share of the box or a user-space length: only the direction
        // between the two ends is kept, so either reads the same way.
        func coordinate(_ key: String, _ fallback: Double) -> Double {
            guard let raw = attribute(key), let n = numbers(raw).first else { return fallback }
            return raw.trimmingCharacters(in: .whitespaces).hasSuffix("%") ? n / 100 : n
        }
        var dx = coordinate("x2", 1) - coordinate("x1", 0)
        var dy = coordinate("y2", 0) - coordinate("y1", 0)
        let t = transform(attribute("gradientTransform") ?? "")
        (dx, dy) = (Double(t.a) * dx + Double(t.c) * dy, Double(t.b) * dx + Double(t.d) * dy)
        guard dx != 0 || dy != 0 else { return 90 }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        return rounded(degrees)
    }

    // MARK: values

    /// A transform list as one transform, the first written outermost.
    static func transform(_ text: String) -> CGAffineTransform {
        var result = CGAffineTransform.identity
        let pattern = #"(matrix|translate|scale|rotate|skewX|skewY)\s*\(([^)]*)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return result }
        let ns = text as NSString
        for match in regex.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: match.range(at: 1))
            let v = numbers(ns.substring(with: match.range(at: 2)))
            var t = CGAffineTransform.identity
            switch name {
            case "matrix" where v.count >= 6:
                t = CGAffineTransform(a: v[0], b: v[1], c: v[2], d: v[3], tx: v[4], ty: v[5])
            case "translate" where !v.isEmpty:
                t = CGAffineTransform(translationX: v[0], y: v.count > 1 ? v[1] : 0)
            case "scale" where !v.isEmpty:
                t = CGAffineTransform(scaleX: v[0], y: v.count > 1 ? v[1] : v[0])
            case "rotate" where !v.isEmpty:
                let turn = CGAffineTransform(rotationAngle: v[0] * .pi / 180)
                if v.count >= 3 {
                    t = CGAffineTransform(translationX: -v[1], y: -v[2])
                        .concatenating(turn)
                        .concatenating(CGAffineTransform(translationX: v[1], y: v[2]))
                } else {
                    t = turn
                }
            case "skewX" where !v.isEmpty:
                t = CGAffineTransform(a: 1, b: 0, c: tan(v[0] * .pi / 180), d: 1, tx: 0, ty: 0)
            case "skewY" where !v.isEmpty:
                t = CGAffineTransform(a: 1, b: tan(v[0] * .pi / 180), c: 0, d: 1, tx: 0, ty: 0)
            default:
                break
            }
            // Each one applies inside those written before it.
            result = t.concatenating(result)
        }
        return result
    }

    /// Every number in a list, however it is separated: "1,2 3-4 5e-1".
    static func numbers(_ text: String) -> [Double] {
        let pattern = #"[-+]?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
            .compactMap { Double(ns.substring(with: $0.range)) }
    }

    /// A length in user units: a number, in px or nothing; pt, pc, mm, cm
    /// and in converted at 96 to the inch. A percentage is no length here.
    static func length(_ text: String?) -> Double? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.hasSuffix("%"),
              let value = numbers(text).first else { return nil }
        let units: [(String, Double)] = [("pt", 96.0 / 72), ("pc", 16), ("mm", 96 / 25.4), ("cm", 96 / 2.54), ("in", 96)]
        for (unit, factor) in units where text.hasSuffix(unit) { return value * factor }
        return value
    }

    /// An opacity or an offset: a number, or a percentage of one, kept
    /// within 0…1.
    static func fraction(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard let value = numbers(trimmed).first else { return nil }
        return min(max(trimmed.hasSuffix("%") ? value / 100 : value, 0), 1)
    }

    /// A colour as lowercase "#rrggbb" with its own alpha after it when it
    /// has one: "#rgb", "#rgba", "#rrggbb", "#rrggbbaa", rgb() and rgba(),
    /// a name, or currentColor (`current`); nil for none or transparent.
    static func colour(_ text: String, current: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespaces).lowercased()
        if value.isEmpty || value == "none" || value == "transparent" { return nil }
        if value == "currentcolor" { return current == text ? nil : colour(current, current: "#000000") }
        if value.hasPrefix("#") {
            let digits = String(value.dropFirst())
            guard digits.allSatisfy(\.isHexDigit) else { return nil }
            switch digits.count {
            case 3, 4:
                return "#" + digits.map { "\($0)\($0)" }.joined()
            case 6, 8:
                return "#" + digits
            default:
                return nil
            }
        }
        if value.hasPrefix("rgb") {
            let inside = value.drop(while: { $0 != "(" }).dropFirst().prefix(while: { $0 != ")" })
            let parts = inside.components(separatedBy: CharacterSet(charactersIn: ", /")).filter { !$0.isEmpty }
            guard parts.count >= 3 else { return nil }
            var channels: [Int] = []
            for part in parts.prefix(3) {
                guard let n = numbers(part).first else { return nil }
                let v = part.hasSuffix("%") ? n / 100 * 255 : n
                channels.append(Int(min(max(v, 0), 255).rounded()))
            }
            var out = "#" + channels.map { String(format: "%02x", $0) }.joined()
            if parts.count >= 4, let alpha = fraction(parts[3]), alpha < 1 {
                out += String(format: "%02x", Int((alpha * 255).rounded()))
            }
            return out
        }
        return namedColours[value]
    }

    /// `hex` ("#rrggbb" or "#rrggbbaa") with its alpha times `alpha`,
    /// written only when under 1.
    static func hex(_ hex: String, alpha: Double) -> String {
        let rgb = String(hex.prefix(7))
        var a = min(max(alpha, 0), 1)
        if hex.count == 9, let own = Int(hex.suffix(2), radix: 16) { a *= Double(own) / 255 }
        let byte = Int((a * 255).rounded())
        return byte >= 255 ? rgb : rgb + String(format: "%02x", byte)
    }

    /// Two places, as every number a part is written with.
    static func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// The colour names SVG files use most.
    static let namedColours: [String: String] = [
        "black": "#000000", "white": "#ffffff", "red": "#ff0000", "green": "#008000", "blue": "#0000ff",
        "yellow": "#ffff00", "cyan": "#00ffff", "aqua": "#00ffff", "magenta": "#ff00ff", "fuchsia": "#ff00ff",
        "gray": "#808080", "grey": "#808080", "silver": "#c0c0c0", "maroon": "#800000", "olive": "#808000",
        "lime": "#00ff00", "teal": "#008080", "navy": "#000080", "purple": "#800080", "orange": "#ffa500",
        "pink": "#ffc0cb", "brown": "#a52a2a", "gold": "#ffd700", "indigo": "#4b0082", "violet": "#ee82ee",
        "darkgray": "#a9a9a9", "darkgrey": "#a9a9a9", "lightgray": "#d3d3d3", "lightgrey": "#d3d3d3",
        "crimson": "#dc143c", "coral": "#ff7f50", "salmon": "#fa8072", "tomato": "#ff6347",
        "skyblue": "#87ceeb", "steelblue": "#4682b4", "royalblue": "#4169e1", "darkblue": "#00008b",
        "darkgreen": "#006400", "darkred": "#8b0000", "beige": "#f5f5dc", "ivory": "#fffff0",
        "khaki": "#f0e68c", "lavender": "#e6e6fa", "turquoise": "#40e0d0", "tan": "#d2b48c",
        "chocolate": "#d2691e", "orchid": "#da70d6", "plum": "#dda0dd", "slategray": "#708090",
    ]
}
