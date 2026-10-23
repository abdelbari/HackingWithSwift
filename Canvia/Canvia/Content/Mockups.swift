// The mockup scenes — a page shown on a phone, a laptop, a framed print, a
// poster, a business card, a T-shirt, a mug and the rest, some twenty —
// each drawn in vectors by tools/generate_mockups.py into the Android twin's
// templates/mockups.json, bundled here as Mockups.json byte for byte, so no
// photograph is downloaded. See the generator for the file's keys.
//
// And where a page goes in one (MockupGeometry): the part of the page a
// window shows, the scene fitted to a box, its window's corners there, and
// for a mug the mesh the page is stretched over — the Android twin's
// MockupGeometry, with the same rows (MockupGeometryTests).

import CoreGraphics
import Foundation

enum MockupScenes {

    /// The categories, in the order the scene grid shows them.
    static let categories = ["Devices", "Print", "Apparel", "Home"]

    /// A scene's paint as the file writes it — {"kind": "solid", "color"}
    /// or {"kind": "gradient", "angle", "stops": [{"color", "position"}]}
    /// — read into the design's own Paint, to be drawn as a fill is.
    struct Fill: Decodable, Equatable {
        var paint: Paint

        private enum CodingKeys: String, CodingKey { case kind, color, angle, stops }

        private struct Stop: Decodable {
            var color: String
            var position: Double

            private enum CodingKeys: String, CodingKey { case color, position, offset }

            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                color = try c.decode(String.self, forKey: .color)
                position = (try? c.decode(Double.self, forKey: .position))
                    ?? (try? c.decode(Double.self, forKey: .offset)) ?? 0
            }
        }

        init(paint: Paint) {
            self.paint = paint
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let kind = (try? c.decode(String.self, forKey: .kind)) ?? "solid"
            let stops = (try? c.decode([Stop].self, forKey: .stops)) ?? []
            if kind == "gradient", !stops.isEmpty {
                paint = Paint(kind: "gradient", color: nil, angle: (try? c.decode(Double.self, forKey: .angle)) ?? 180,
                              stops: stops.map { GradientStop(offset: $0.position, color: $0.color) })
            } else {
                paint = .solid((try? c.decode(String.self, forKey: .color)) ?? "#000000")
            }
        }
    }

    /// One shape of a scene, drawn under the design: its path in scene
    /// pixels, filled — with the scene's tint when `tinted` — softened by
    /// `blur` (a shadow) and at `opacity`.
    struct Layer: Decodable, Equatable {
        var path: String
        var fill: Fill
        var blur: Double?
        var opacity: Double?
        var tinted: Bool?
    }

    /// How a mug's print wraps: the half-turn it spans either side of its
    /// middle, in radians, and how far its top and bottom bow down there.
    struct Cylinder: Decodable, Equatable {
        var angle: Double
        var sag: Double
    }

    /// Where the design goes: the window's four corners, its corner radius
    /// and its shape seen flat, width over height.
    struct Screen: Decodable, Equatable {
        var quad: [[Double]]
        var radius: Double = 0
        var aspect: Double
        var cylinder: Cylinder?

        private enum CodingKeys: String, CodingKey { case quad, radius, aspect, cylinder }

        init(quad: [[Double]], radius: Double = 0, aspect: Double, cylinder: Cylinder? = nil) {
            self.quad = quad
            self.radius = radius
            self.aspect = aspect
            self.cylinder = cylinder
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            quad = try c.decode([[Double]].self, forKey: .quad)
            radius = (try? c.decode(Double.self, forKey: .radius)) ?? 0
            aspect = try c.decode(Double.self, forKey: .aspect)
            cylinder = try? c.decode(Cylinder.self, forKey: .cylinder)
        }

        /// The four corners: top left, top right, bottom right, bottom left.
        var corners: [CGPoint] {
            quad.map { CGPoint(x: $0.first ?? 0, y: $0.count > 1 ? $0[1] : 0) }
        }
    }

    /// What is drawn over the design, inside its window: the glass's glare.
    struct Overlay: Decodable, Equatable {
        var fill: Fill
        var opacity: Double

        private enum CodingKeys: String, CodingKey { case fill, opacity }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            fill = try c.decode(Fill.self, forKey: .fill)
            opacity = (try? c.decode(Double.self, forKey: .opacity)) ?? 1
        }
    }

    struct Scene: Decodable, Equatable, Identifiable {
        var id: String
        var name: String
        var category: String
        var size: [Double]
        var background: Fill
        var layers: [Layer]
        var screen: Screen
        var overlay: Overlay?
        /// The colour tinted layers take until one is chosen; nil for a
        /// scene with none.
        var tint: String?

        private enum CodingKeys: String, CodingKey { case id, name, category, size, background, layers, screen, overlay, tint }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(String.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            category = try c.decode(String.self, forKey: .category)
            size = try c.decode([Double].self, forKey: .size)
            background = try c.decode(Fill.self, forKey: .background)
            layers = (try? c.decode([Layer].self, forKey: .layers)) ?? []
            screen = try c.decode(Screen.self, forKey: .screen)
            overlay = try? c.decode(Overlay.self, forKey: .overlay)
            tint = try? c.decode(String.self, forKey: .tint)
        }

        var width: Double { size.first ?? 0 }
        var height: Double { size.count > 1 ? size[1] : 0 }
    }

    /// Read once, on first use.
    static let all: [Scene] = {
        guard let url = Bundle.main.url(forResource: "Mockups", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Scene].self, from: data) else {
            assertionFailure("Mockups.json missing or invalid")
            return []
        }
        return decoded
    }()

    static func scene(_ id: String?) -> Scene? {
        all.first { $0.id == id }
    }

    /// The scenes in `category`, or all of them for nil, in file order.
    static func inCategory(_ category: String?) -> [Scene] {
        guard let category else { return all }
        return all.filter { $0.category == category }
    }
}

enum MockupGeometry {

    /// The part of a `width` × `height` page a window `aspect` wide to 1 high
    /// shows: the largest rectangle of that shape, centred — cut from the
    /// sides of a page wider than the window, from the top and bottom of a
    /// taller one.
    static func cover(width: Double, height: Double, aspect: Double) -> CGRect {
        guard width > 0, height > 0, aspect > 0 else {
            return CGRect(x: 0, y: 0, width: max(0, width), height: max(0, height))
        }
        if width / height > aspect {
            let w = height * aspect
            return CGRect(x: (width - w) / 2, y: 0, width: w, height: height)
        }
        let h = width / aspect
        return CGRect(x: 0, y: (height - h) / 2, width: width, height: h)
    }

    /// How a scene is drawn into a box: whole, as large as fits, centred —
    /// its scale, then where its top left goes.
    struct Fit: Equatable {
        var scale: Double
        var x: Double
        var y: Double

        func map(_ p: CGPoint) -> CGPoint {
            CGPoint(x: x + Double(p.x) * scale, y: y + Double(p.y) * scale)
        }
    }

    static func fit(sceneWidth: Double, sceneHeight: Double, boxWidth: Double, boxHeight: Double) -> Fit {
        guard sceneWidth > 0, sceneHeight > 0 else { return Fit(scale: 1, x: 0, y: 0) }
        let scale = min(boxWidth / sceneWidth, boxHeight / sceneHeight)
        return Fit(scale: scale, x: (boxWidth - sceneWidth * scale) / 2, y: (boxHeight - sceneHeight * scale) / 2)
    }

    /// A screen's corners drawn at `fit`.
    static func mapped(_ screen: MockupScenes.Screen, fit: Fit) -> [CGPoint] {
        screen.corners.map { fit.map($0) }
    }

    /// The columns and rows of a mug's mesh.
    static let meshColumns = 24
    static let meshRows = 8

    /// The points a page's picture is stretched over to wrap round a
    /// cylinder, (columns + 1) × (rows + 1) of them, row by row from the top,
    /// in the scene's pixels. Across, the picture's u (0…1) is turned through
    /// −angle…+angle and seen from in front: it lands sin(θ)/sin(angle) of the
    /// way from the middle to an edge, so it crowds towards the sides. Down,
    /// each column runs from the quad's top edge to its bottom edge, and both
    /// edges bow down by sag·(cos θ − cos angle)/(1 − cos angle): nothing at
    /// the sides, sag in the middle, as a rim seen from a little above does.
    static func mesh(_ corners: [CGPoint], cylinder: MockupScenes.Cylinder,
                     columns: Int = MockupGeometry.meshColumns, rows: Int = MockupGeometry.meshRows) -> [CGPoint] {
        guard corners.count == 4, columns > 0, rows > 0 else { return [] }
        let tl = corners[0], tr = corners[1], br = corners[2], bl = corners[3]
        let angle = min(max(cylinder.angle, 0.05), Double.pi / 2)
        let edge = cos(angle)
        var out: [CGPoint] = []
        out.reserveCapacity((columns + 1) * (rows + 1))
        for r in 0...rows {
            let v = Double(r) / Double(rows)
            for c in 0...columns {
                let u = Double(c) / Double(columns)
                let theta = -angle + 2 * angle * u
                let across = (sin(theta) / sin(angle) + 1) / 2
                let top = lerp(tl, tr, across)
                let bottom = lerp(bl, br, across)
                let sag = cylinder.sag * (cos(theta) - edge) / (1 - edge)
                let p = lerp(top, bottom, v)
                out.append(CGPoint(x: Double(p.x), y: Double(p.y) + sag))
            }
        }
        return out
    }

    private static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: Double) -> CGPoint {
        CGPoint(x: Double(a.x) + Double(b.x - a.x) * t, y: Double(a.y) + Double(b.y - a.y) * t)
    }
}
