// Document model. Value types throughout: the whole design is a struct, so
// undo/redo snapshots are plain copies. JSON keys match the Canvia web
// schema so the validated template gallery decodes verbatim.

import SwiftUI

enum UID {
    static func make(_ prefix: String = "el") -> String {
        "\(prefix)_" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
    }
}

// MARK: - Paint (solid or linear gradient)

struct GradientStop: Codable, Equatable, Hashable {
    var offset: Double
    var color: String
}

struct Paint: Codable, Equatable, Hashable {
    var kind: String              // "solid" | "gradient"
    var color: String?            // solid
    var angle: Double?            // gradient, CSS convention: 0° = up, 90° = right
    var stops: [GradientStop]?

    static func solid(_ color: String) -> Paint {
        Paint(kind: "solid", color: color, angle: nil, stops: nil)
    }

    var primaryColor: String {
        if kind == "gradient" { return stops?.first?.color ?? "#000000" }
        return color ?? "#000000"
    }

    /// SwiftUI gradient endpoints for the CSS angle convention, in unit space.
    var unitPoints: (start: UnitPoint, end: UnitPoint) {
        let rad = ((angle ?? 0) - 90) * .pi / 180
        let dx = cos(rad) / 2, dy = sin(rad) / 2
        return (UnitPoint(x: 0.5 - dx, y: 0.5 - dy), UnitPoint(x: 0.5 + dx, y: 0.5 + dy))
    }

    @ViewBuilder
    func fillView() -> some View {
        if kind == "gradient", let stops {
            let pts = unitPoints
            LinearGradient(
                stops: stops.map { .init(color: Color(hex: $0.color), location: $0.offset) },
                startPoint: pts.start, endPoint: pts.end)
        } else {
            Color(hex: color ?? "#000000")
        }
    }
}

// MARK: - Background

enum Background: Codable, Equatable {
    case color(String)
    case gradient(Paint)
    case image(String)            // "asset:<photo id>" or user image key

    private enum CodingKeys: String, CodingKey { case type, value }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "gradient": self = .gradient(try c.decode(Paint.self, forKey: .value))
        case "image": self = .image(try c.decode(String.self, forKey: .value))
        default: self = .color((try? c.decode(String.self, forKey: .value)) ?? "#ffffff")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .color(let v):
            try c.encode("color", forKey: .type)
            try c.encode(v, forKey: .value)
        case .gradient(let p):
            try c.encode("gradient", forKey: .type)
            try c.encode(p, forKey: .value)
        case .image(let v):
            try c.encode("image", forKey: .type)
            try c.encode(v, forKey: .value)
        }
    }
}

// MARK: - Page / Design

struct Page: Codable, Equatable, Identifiable {
    var id: String = UID.make("page")
    var background: Background = .color("#ffffff")
    var elements: [Element] = []

    init(id: String = UID.make("page"), background: Background = .color("#ffffff"), elements: [Element] = []) {
        self.id = id
        self.background = background
        self.elements = elements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make("page")
        background = (try? c.decode(Background.self, forKey: .background)) ?? .color("#ffffff")
        elements = (try? c.decode([Element].self, forKey: .elements)) ?? []
    }

    private enum CodingKeys: String, CodingKey { case id, background, elements }
}

struct Design: Codable, Equatable, Identifiable {
    var version: Int = 1
    var id: String = UID.make("doc")
    var title: String = "Untitled design"
    var width: Double = 1080
    var height: Double = 1080
    var createdAt: Double = Date().timeIntervalSince1970 * 1000
    var updatedAt: Double = Date().timeIntervalSince1970 * 1000
    var pages: [Page] = [Page()]

    var size: CGSize { CGSize(width: width, height: height) }

    init(title: String = "Untitled design", width: Double = 1080, height: Double = 1080) {
        self.title = title
        self.width = width
        self.height = height
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = (try? c.decode(Int.self, forKey: .version)) ?? 1
        id = (try? c.decode(String.self, forKey: .id)) ?? UID.make("doc")
        title = (try? c.decode(String.self, forKey: .title)) ?? "Untitled design"
        width = (try? c.decode(Double.self, forKey: .width)) ?? 1080
        height = (try? c.decode(Double.self, forKey: .height)) ?? 1080
        createdAt = (try? c.decode(Double.self, forKey: .createdAt)) ?? Date().timeIntervalSince1970 * 1000
        updatedAt = (try? c.decode(Double.self, forKey: .updatedAt)) ?? createdAt
        let pages = (try? c.decode([Page].self, forKey: .pages)) ?? []
        self.pages = pages.isEmpty ? [Page()] : pages
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, title, width, height, createdAt, updatedAt, pages
    }
}

// MARK: - Color hex helpers

extension Color {
    init(hex: String) {
        self.init(uiColor: UIColor(hex: hex))
    }
}

extension UIColor {
    convenience init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        var value: UInt64 = 0
        Scanner(string: s).scanHexInt64(&value)
        if s.count == 8 {
            self.init(
                red: CGFloat((value >> 24) & 0xff) / 255,
                green: CGFloat((value >> 16) & 0xff) / 255,
                blue: CGFloat((value >> 8) & 0xff) / 255,
                alpha: CGFloat(value & 0xff) / 255)
        } else {
            self.init(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1)
        }
    }

    /// sRGB components clamped to 0...1 (ColorPicker often yields extended
    /// sRGB / Display-P3 values outside the unit range).
    private var srgbComponents: (r: CGFloat, g: CGFloat, b: CGFloat) {
        var color = self
        if let space = CGColorSpace(name: CGColorSpace.sRGB),
           let converted = cgColor.converted(to: space, intent: .defaultIntent, options: nil) {
            color = UIColor(cgColor: converted)
        }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (min(1, max(0, r)), min(1, max(0, g)), min(1, max(0, b)))
    }

    var hexString: String {
        let c = srgbComponents
        return String(format: "#%02x%02x%02x",
                      Int(round(c.r * 255)), Int(round(c.g * 255)), Int(round(c.b * 255)))
    }

    var isLight: Bool {
        let c = srgbComponents
        return (0.299 * c.r + 0.587 * c.g + 0.114 * c.b) > 0.62
    }
}
