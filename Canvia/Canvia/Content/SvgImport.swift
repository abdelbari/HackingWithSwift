// A whole SVG brought in as a graphic: every shape it draws, each its own
// shape element in its own colours, grouped, so it moves as one and each
// colour can be changed on its own (see ColourSwap) — how a logo or an
// illustration from another tool comes in.
//
// Drawn: <path>, <rect> (with rx/ry), <circle>, <ellipse>, <line>,
// <polyline> and <polygon>, inside any depth of <g> (and <a>, <switch>, a
// nested <svg>) with their transforms — matrix, translate, scale, rotate,
// skewX and skewY; the root's own transform aside. Fill, stroke,
// stroke-width, opacity, fill-opacity, stroke-opacity and fill-rule are read
// from attributes, then from simple <style> rules (".class" rules, then
// "#id" rules, each in the sheet's order), then from the inline style, each
// overriding the one before, and the inheritable ones passed down. A
// linearGradient or radialGradient fill becomes a gradient Paint with the
// same stops (see `angle`). Anything else — <defs>, <symbol>, an unused
// <clipPath> — is not entered.
//
// What is fitted to the page: the root's viewBox (stretched to its width
// and height first only for preserveAspectRatio="none"), else its width and
// height, else the box round what it draws — its longer side at 0.4 of the
// page's shorter side, centred. Each part is then a shape in its own tight
// box on the page (a flat one widened to its stroke, or to one unit), its
// path stretched into 0…100 across that box by the same writer as every
// path (TextOutliner.svgPathData); x, y, w, h, border width, opacity and
// gradient offsets to the hundredth. Two or more parts share one `group`;
// each takes its SVG id, when it has one, as its `layerName`; an even-odd
// one writes `fillRule`.
//
// Said to be left out (`skipped`): a <text>, <image>, <use> or
// <foreignObject> that would show, a mask, filter or clip path named by
// something drawn (drawn without it), a fill or stroke naming no gradient
// and giving no fallback colour, and parts past the limit. The Android twin
// (SvgGraphic) reads the same files to the same elements by these rules;
// SvgImportTests and its SvgImportTest share the files and the numbers.

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
    static let partialNote = tr("Some parts of this SVG couldn't be brought in")

    struct Graphic {
        var elements: [Element]
        /// Something was left out: words, a picture, a reuse, a mask, a
        /// filter or a clip, a paint that is not there, or parts past the
        /// limit.
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
            if root.attributes["preserveAspectRatio"]?.trimmingCharacters(in: .whitespacesAndNewlines) == "none",
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
        var elements = reader.parts.compactMap { part in
            element(part, placing: part.transform.concatenating(frame).concatenating(fit))
        }
        guard !elements.isEmpty else { return nil }
        // One part is not a group.
        if elements.count >= 2 {
            let group = UID.make("grp")
            for i in elements.indices { elements[i].group = group }
        }
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
    /// its path stretched into that box. A part that is only a point is
    /// none.
    static func element(_ part: Drawable, placing: CGAffineTransform) -> Element? {
        var t = placing
        guard let placed = part.path.copy(using: &t) else { return nil }
        var box = placed.boundingBoxOfPath
        guard !box.isNull, box.width.isFinite, box.height.isFinite else { return nil }
        guard box.width >= 0.01 || box.height >= 0.01 else { return nil }
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
        /// The style sheets' plain ".class" and "#id" rules, in their order.
        let classRules: [(name: String, declarations: [String: String])]
        let idRules: [(name: String, declarations: [String: String])]
        let gradients: [String: Node]

        init(root: Node) {
            self.root = root
            var css: [String] = []
            var gradients: [String: Node] = [:]
            var stack = [root]
            while let node = stack.popLast() {
                if node.name == "style" { css.append(node.text) }
                // The first of an id is the one used.
                if node.name == "linearGradient" || node.name == "radialGradient", let id = node.attributes["id"],
                   gradients[id] == nil {
                    gradients[id] = node
                }
                stack.append(contentsOf: node.children.reversed())
            }
            var classes: [(name: String, declarations: [String: String])] = []
            var ids: [(name: String, declarations: [String: String])] = []
            for rule in SvgImport.styleRules(css.joined(separator: "\n")) {
                for selector in rule.selectors {
                    guard let name = SvgImport.plainName(selector) else { continue }
                    if selector.hasPrefix(".") {
                        classes.append((name, rule.declarations))
                    } else {
                        ids.append((name, rule.declarations))
                    }
                }
            }
            classRules = classes
            idRules = ids
            self.gradients = gradients
        }

        /// What a node says of a property: its attribute, then its classes'
        /// rules, its id's rules, then its inline style.
        func properties(of node: Node) -> [String: String] {
            var out: [String: String] = [:]
            for key in SvgImport.styledKeys {
                if let value = node.attributes[key] { out[key] = value }
            }
            let classes = (node.attributes["class"] ?? "").split(whereSeparator: { $0.isWhitespace }).map(String.init)
            for rule in classRules where classes.contains(rule.name) {
                out.merge(rule.declarations) { $1 }
            }
            if let id = node.attributes["id"] {
                for rule in idRules where rule.name == id {
                    out.merge(rule.declarations) { $1 }
                }
            }
            out.merge(SvgImport.declarations(node.attributes["style"] ?? "")) { $1 }
            return out.mapValues {
                $0.replacingOccurrences(of: "!important", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        mutating func walk(_ node: Node, inherited: Inherited, transform: CGAffineTransform, isRoot: Bool = false) {
            let name = node.name
            guard isRoot || SvgImport.containers.contains(name) || SvgImport.shapes.contains(name)
                || SvgImport.skippedNames.contains(name) else { return }
            let props = properties(of: node)
            if props["display"] == "none" { return }
            if SvgImport.skippedNames.contains(name) {
                skipped = true
                return
            }
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
            if let visibility = props["visibility"], visibility != "inherit" { style.visible = visibility == "visible" }
            if let opacity = props["opacity"].flatMap(SvgImport.fraction) { style.opacity *= opacity }
            if node.attributes["mask"] != nil || node.attributes["filter"] != nil || node.attributes["clip-path"] != nil
                || props["mask"] != nil || props["filter"] != nil || props["clip-path"] != nil {
                // Drawn without them.
                skipped = true
            }
            // A nested svg is a group; the root's own place is the frame's.
            let own = isRoot ? CGAffineTransform.identity : SvgImport.transform(node.attributes["transform"] ?? "")
            let here = own.concatenating(transform)
            if SvgImport.shapes.contains(name) {
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
            let fill = node.name == "line" ? Paint.clear
                : paint(style.fill, opacity: fillOpacity, color: style.color, transform: transform)
            var stroke: String?
            switch SvgImport.Ink.read(style.stroke, color: style.color, gradients: gradients) {
            case .solid(let hex)?:
                stroke = SvgImport.visibleColour(SvgImport.hex(hex, alpha: strokeOpacity))
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

        /// A fill as a Paint: none (a colour wholly see-through among
        /// them), a colour with its opacity as alpha, or a gradient's stops;
        /// `transform` is the shape's, which turns a gradient in user space.
        mutating func paint(_ raw: String, opacity: Double, color: String, transform: CGAffineTransform) -> Paint {
            switch SvgImport.Ink.read(raw, color: color, gradients: gradients) {
            case .solid(let hex)?:
                return SvgImport.visibleColour(SvgImport.hex(hex, alpha: opacity)).map { Paint.solid($0) } ?? Paint.clear
            case .gradient(let node)?:
                let stops = SvgImport.stops(node, gradients: gradients, opacity: opacity)
                if stops.count == 1 {
                    return SvgImport.visibleColour(stops[0].color).map { Paint.solid($0) } ?? Paint.clear
                }
                guard stops.count >= 2 else { return Paint.clear }
                // A radial one has no angle.
                let radial = node.name == "radialGradient"
                return Paint(kind: "gradient", color: nil,
                             angle: radial ? nil : SvgImport.angle(node, gradients: gradients, transform: transform),
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
                // xlink:href and href alike, href itself first.
                if key.hasSuffix(":href") {
                    if attributeDict["href"] == nil { attributes["href"] = value }
                } else {
                    attributes[key] = value
                }
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

    /// What is drawn; what holds what is drawn; what is left out, and said
    /// to be, when it would show.
    static let shapes: Set<String> = ["path", "rect", "circle", "ellipse", "line", "polyline", "polygon"]
    static let containers: Set<String> = ["svg", "g", "a", "switch"]
    static let skippedNames: Set<String> = ["text", "image", "use", "foreignObject"]
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
            let path = SVGPath.parse(d)
            // One that only moves draws nothing.
            return drawsSegment(path) ? path : nil
        case "rect":
            let w = value("width"), h = value("height")
            guard w > 0, h > 0 else { return nil }
            var rx = length(a["rx"]), ry = length(a["ry"])
            if rx == nil { rx = ry }
            if ry == nil { ry = rx }
            let cornerX = min(max(rx ?? 0, 0), w / 2), cornerY = min(max(ry ?? 0, 0), h / 2)
            return rectPath(x: value("x"), y: value("y"), width: w, height: h, rx: cornerX, ry: cornerY)
        case "circle":
            let r = value("r")
            guard r > 0 else { return nil }
            return ellipsePath(cx: value("cx"), cy: value("cy"), rx: r, ry: r)
        case "ellipse":
            let rx = value("rx"), ry = value("ry")
            guard rx > 0, ry > 0 else { return nil }
            return ellipsePath(cx: value("cx"), cy: value("cy"), rx: rx, ry: ry)
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

    /// Whether a path draws anything past its moves.
    static func drawsSegment(_ path: CGPath) -> Bool {
        var found = false
        path.applyWithBlock { element in
            if element.pointee.type != .moveToPoint { found = true }
        }
        return found
    }

    /// The share of a radius a quarter circle's control points sit at.
    static let kappa = 0.5522847498307936

    /// An ellipse as four curves from its right end, clockwise on the page,
    /// built point for point as the Android twin builds it.
    static func ellipsePath(cx: Double, cy: Double, rx: Double, ry: Double) -> CGPath {
        let kx = rx * kappa, ky = ry * kappa
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }
        let path = CGMutablePath()
        path.move(to: p(cx + rx, cy))
        path.addCurve(to: p(cx, cy + ry), control1: p(cx + rx, cy + ky), control2: p(cx + kx, cy + ry))
        path.addCurve(to: p(cx - rx, cy), control1: p(cx - kx, cy + ry), control2: p(cx - rx, cy + ky))
        path.addCurve(to: p(cx, cy - ry), control1: p(cx - rx, cy - ky), control2: p(cx - kx, cy - ry))
        path.addCurve(to: p(cx + rx, cy), control1: p(cx + kx, cy - ry), control2: p(cx + rx, cy - ky))
        path.closeSubpath()
        return path
    }

    /// A rectangle from its top left corner, clockwise on the page, its
    /// corners rounded by `rx` and `ry` unless either is 0, built as the
    /// Android twin builds it.
    static func rectPath(x: Double, y: Double, width w: Double, height h: Double, rx: Double, ry: Double) -> CGPath {
        func p(_ px: Double, _ py: Double) -> CGPoint { CGPoint(x: px, y: py) }
        let path = CGMutablePath()
        guard rx > 0, ry > 0 else {
            path.move(to: p(x, y))
            path.addLine(to: p(x + w, y))
            path.addLine(to: p(x + w, y + h))
            path.addLine(to: p(x, y + h))
            path.closeSubpath()
            return path
        }
        let kx = rx * kappa, ky = ry * kappa
        path.move(to: p(x + rx, y))
        path.addLine(to: p(x + w - rx, y))
        path.addCurve(to: p(x + w, y + ry), control1: p(x + w - rx + kx, y), control2: p(x + w, y + ry - ky))
        path.addLine(to: p(x + w, y + h - ry))
        path.addCurve(to: p(x + w - rx, y + h), control1: p(x + w, y + h - ry + ky), control2: p(x + w - rx + kx, y + h))
        path.addLine(to: p(x + rx, y + h))
        path.addCurve(to: p(x, y + h - ry), control1: p(x + rx - kx, y + h), control2: p(x, y + h - ry + ky))
        path.addLine(to: p(x, y + ry))
        path.addCurve(to: p(x + rx, y), control1: p(x, y + ry - ky), control2: p(x + rx - kx, y))
        path.closeSubpath()
        return path
    }

    // MARK: styles

    /// The name in a plain ".class" or "#id" selector, or nil for anything
    /// more — a tag, a combinator, a pseudo-class.
    static func plainName(_ selector: String) -> String? {
        guard selector.hasPrefix(".") || selector.hasPrefix("#") else { return nil }
        let name = selector.dropFirst()
        func plain(_ c: Character) -> Bool { c.isASCII && (c.isLetter || c.isNumber || c == "-" || c == "_") }
        guard let first = name.first, first.isASCII, first.isLetter || first == "_", name.allSatisfy(plain) else {
            return nil
        }
        return String(name)
    }

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
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if value.hasPrefix("url(") {
                let inside = value.dropFirst(4).prefix(while: { $0 != ")" })
                let id = inside.trimmingCharacters(in: CharacterSet(charactersIn: "#'\" "))
                if let node = gradients[id] { return .gradient(node) }
                // A fallback after the reference is drawn instead.
                let rest = value.drop(while: { $0 != ")" }).dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
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
    /// right — to the hundredth: from x1, y1 to x2, y2 (by default left to
    /// right; a percentage as its share), through its gradientTransform,
    /// and, when its gradientUnits are userSpaceOnUse, through the shape's
    /// own transforms (`shape`) too. Each of those is read from it or the
    /// first gradient in its href chain to give it. No direction is 90.
    static func angle(_ node: Node, gradients: [String: Node], transform shape: CGAffineTransform) -> Double {
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
        func coordinate(_ key: String, _ fallback: Double) -> Double {
            guard let raw = attribute(key), let n = numbers(raw).first else { return fallback }
            return raw.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("%") ? n / 100 : n
        }
        var dx = coordinate("x2", 1) - coordinate("x1", 0)
        var dy = coordinate("y2", 0) - coordinate("y1", 0)
        let own = transform(attribute("gradientTransform") ?? "")
        let inUserSpace = attribute("gradientUnits")?.trimmingCharacters(in: .whitespacesAndNewlines) == "userSpaceOnUse"
        let t = inUserSpace ? own.concatenating(shape) : own
        (dx, dy) = (Double(t.a) * dx + Double(t.c) * dy, Double(t.b) * dx + Double(t.d) * dy)
        guard dx != 0 || dy != 0 else { return 90 }
        var degrees = atan2(dx, -dy) * 180 / .pi
        if degrees < 0 { degrees += 360 }
        let hundredths = rounded(degrees)
        return hundredths >= 360 ? hundredths - 360 : hundredths
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
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.hasSuffix("%"),
              let value = numbers(text).first else { return nil }
        let units: [(String, Double)] = [("pt", 96.0 / 72), ("pc", 16), ("mm", 96 / 25.4), ("cm", 96 / 2.54), ("in", 96)]
        for (unit, factor) in units where text.hasSuffix(unit) { return value * factor }
        return value
    }

    /// An opacity or an offset: a number, or a percentage of one, kept
    /// within 0…1.
    static func fraction(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = numbers(trimmed).first else { return nil }
        return min(max(trimmed.hasSuffix("%") ? value / 100 : value, 0), 1)
    }

    /// A colour as lowercase "#rrggbb" with its own alpha after it when it
    /// has one: "#rgb", "#rgba", "#rrggbb", "#rrggbbaa", rgb() and rgba(),
    /// a name, or currentColor (`current`); nil for none or transparent.
    static func colour(_ text: String, current: String) -> String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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

    /// A solid colour as drawn: nil when it is wholly see-through.
    static func visibleColour(_ hex: String) -> String? {
        hex.count == 9 && hex.hasSuffix("00") ? nil : hex
    }

    /// Two places, as every number a part is written with.
    static func rounded(_ v: Double) -> Double { (v * 100).rounded() / 100 }

    /// The colour names SVG files use most, as CSS defines them; the
    /// Android twin knows the same ones.
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
        "orangered": "#ff4500", "hotpink": "#ff69b4",
    ]
}
