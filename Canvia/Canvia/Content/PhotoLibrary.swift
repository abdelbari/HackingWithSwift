// Procedural photo library: every artwork is drawn with CoreGraphics into a
// cached UIImage, so the gallery is rich yet fully offline. Blob meshes use
// radial gradients (soft-blob look), waves and stripes are paths, plus a
// few handcrafted scenes. User photos are stored in Documents/media and
// referenced as "media:<id>"; library art as "asset:<id>".

import UIKit

struct PhotoDef: Identifiable {
    var id: String
    var name: String
    var category: String
}

// Deterministic PRNG matching the web generator (LCG).
private struct SeededRandom {
    private var state: UInt32
    init(seed: Double) { state = UInt32(truncatingIfNeeded: Int(seed)) }
    mutating func next() -> Double {
        state = state &* 1664525 &+ 1013904223
        return Double(state) / 4294967296
    }
}

enum PhotoLibrary {
    static let size = CGSize(width: 1200, height: 900)

    // NSCache, not a Dictionary: generated artwork is large (1200x900 RGBA
    // is ~4 MB each) and the system evicts it under memory pressure.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 24
        return c
    }()
    private static var builders: [String: (id: String, name: String, category: String, build: () -> UIImage)] = [:]
    private static var order: [String] = []
    private static var loaded = false

    static var photos: [PhotoDef] {
        ensureLoaded()
        return order.compactMap { builders[$0].map { PhotoDef(id: $0.id, name: $0.name, category: $0.category) } }
    }

    static func image(id: String) -> UIImage? {
        ensureLoaded()
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let builder = builders[id] else { return nil }
        let img = builder.build()
        cache.setObject(img, forKey: id as NSString)
        return img
    }

    /// Resolve an element src: "asset:<id>" -> library, "media:<id>" -> user
    /// file, "qr:<payload>" -> a generated code.
    ///
    /// Every branch is synchronous and deterministic in the src alone. That is
    /// what ElementView's Equatable conformance rests on — see the note above
    /// it — so a source that had to be fetched or awaited would have to be
    /// resolved somewhere else entirely.
    static func resolve(_ src: String?) -> UIImage? {
        guard let src else { return nil }
        if src.hasPrefix("asset:") { return image(id: String(src.dropFirst(6))) }
        if src.hasPrefix("media:") { return MediaStore.load(String(src.dropFirst(6))) }
        if let payload = CodeGenerator.payload(from: src) { return CodeGenerator.qr(payload) }
        return nil
    }

    private static let previewCache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 24
        return c
    }()

    /// A downscaled copy, for filter thumbnails and other small previews.
    /// Cached under `key`: a row of ten filter tiles re-renders often, and
    /// rescaling a 1200x900 source ten times per pass is not free.
    static func preview(_ image: UIImage, key: String, maxEdge: CGFloat = 220) -> UIImage {
        let cacheKey = "\(key)|\(Int(maxEdge))" as NSString
        if let cached = previewCache.object(forKey: cacheKey) { return cached }
        let longest = max(image.size.width, image.size.height)
        guard longest > maxEdge else { return image }
        let s = maxEdge / longest
        let size = CGSize(width: image.size.width * s, height: image.size.height * s)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scaled = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        previewCache.setObject(scaled, forKey: cacheKey)
        return scaled
    }

    private static func register(_ id: String, _ name: String, _ category: String,
                                 _ build: @escaping () -> UIImage) {
        guard builders[id] == nil else { return }
        builders[id] = (id, name, category, build)
        order.append(id)
    }

    private static func ensureLoaded() {
        guard !loaded else { return }
        loaded = true

        // Built-in meshes (parity with the web set templates reference).
        register("mesh-sunset", "Sunset Mesh", "Gradients") { mesh(["#ff9a8b", "#ff6a88", "#ff99ac", "#fbc2eb", "#f6d365"], seed: 7) }
        register("mesh-ocean", "Ocean Mesh", "Gradients") { mesh(["#2b5876", "#4e4376", "#00c6fb", "#005bea", "#43e97b"], seed: 21) }
        register("mesh-candy", "Candy Mesh", "Gradients") { mesh(["#a18cd1", "#fbc2eb", "#fad0c4", "#ff9a9e", "#fecfef"], seed: 33) }
        register("mesh-forest", "Forest Mesh", "Gradients") { mesh(["#134e5e", "#71b280", "#2af598", "#009efd", "#0f3443"], seed: 55) }
        register("mesh-ember", "Ember Mesh", "Gradients") { mesh(["#1a1a2e", "#e94560", "#903749", "#53354a", "#ff7b54"], seed: 91) }
        register("mesh-gold", "Golden Hour", "Gradients") { mesh(["#f8b500", "#fceabb", "#e96443", "#904e95", "#ffd194"], seed: 13) }

        // Patterns + scenes.
        register("geo-triangles", "Triangle Mosaic", "Patterns") { triangles() }
        register("geo-waves", "Layered Waves", "Patterns") { waves(["#03045e", "#0077b6", "#00b4d8", "#90e0ef", "#caf0f8"]) }
        register("geo-dots", "Dot Grid", "Patterns") { dots() }
        register("geo-arcs", "Art Deco Arcs", "Patterns") { arcs() }
        register("scene-mountains", "Mountain Dusk", "Scenes") { mountains() }
        register("scene-sunwave", "Retro Sun", "Scenes") { sunwave() }

        // Generated specs from the content bundle.
        for spec in ContentLibrary.bundle.photoSpecs.meshes {
            register(spec.id, spec.name, "Gradients") { mesh(spec.colors, seed: spec.seed) }
        }
        for spec in ContentLibrary.bundle.photoSpecs.waves {
            register(spec.id, spec.name, "Patterns") { waves(spec.colors) }
        }
        for spec in ContentLibrary.bundle.photoSpecs.stripes {
            register(spec.id, spec.name, "Patterns") { stripes(spec.colors, angle: spec.angle) }
        }
    }

    // MARK: drawing helpers

    private static func draw(_ body: (CGContext) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            body(ctx.cgContext)
        }
    }

    private static func linearGradient(_ ctx: CGContext, colors: [String],
                                       from: CGPoint, to: CGPoint, in rect: CGRect) {
        let cgColors = colors.map { UIColor(hex: $0).cgColor } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: cgColors, locations: nil) else { return }
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient, start: from, end: to, options: [])
        ctx.restoreGState()
    }

    private static func softBlob(_ ctx: CGContext, center: CGPoint, radius: Double, color: String, alpha: Double) {
        let ui = UIColor(hex: color)
        let cgColors = [ui.withAlphaComponent(alpha).cgColor,
                        ui.withAlphaComponent(0).cgColor] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: cgColors, locations: [0, 1]) else { return }
        ctx.drawRadialGradient(gradient, startCenter: center, startRadius: 0,
                               endCenter: center, endRadius: radius, options: [])
    }

    // MARK: generators

    private static func mesh(_ colors: [String], seed: Double) -> UIImage {
        draw { ctx in
            let rect = CGRect(origin: .zero, size: size)
            linearGradient(ctx, colors: [colors[0], colors.count > 1 ? colors[1] : colors[0]],
                           from: .zero, to: CGPoint(x: size.width, y: size.height), in: rect)
            var rng = SeededRandom(seed: seed)
            let blobs = Array(colors.dropFirst()) + [colors[0]]
            for color in blobs {
                let cx = rng.next() * size.width
                let cy = rng.next() * size.height
                let radius = 260 + rng.next() * 420
                softBlob(ctx, center: CGPoint(x: cx, y: cy), radius: radius, color: color, alpha: 0.85)
            }
        }
    }

    private static func waves(_ colors: [String]) -> UIImage {
        draw { ctx in
            ctx.setFillColor(UIColor(hex: colors[0]).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            let layers = Array(colors.dropFirst())
            for (i, color) in layers.enumerated() {
                let baseY = 300 + Double(i) * (450 / Double(max(1, layers.count - 1)))
                let amp = 70 - Double(i) * 10
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: baseY))
                var x = 0.0
                while x <= size.width {
                    let y = baseY + sin(x / size.width * .pi * 3 + Double(i) * 1.4) * amp
                    path.addLine(to: CGPoint(x: x, y: y))
                    x += 50
                }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
                ctx.setFillColor(UIColor(hex: color).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
    }

    private static func stripes(_ colors: [String], angle: Double) -> UIImage {
        draw { ctx in
            ctx.setFillColor(UIColor(hex: colors[0]).cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.saveGState()
            ctx.translateBy(x: size.width / 2, y: size.height / 2)
            ctx.rotate(by: angle * .pi / 180)
            let stripeW = 140.0
            let span = 1600.0
            var i = 0
            var x = -span
            while x < span {
                ctx.setFillColor(UIColor(hex: colors[i % colors.count]).cgColor)
                ctx.fill(CGRect(x: x, y: -span, width: stripeW, height: span * 2))
                x += stripeW
                i += 1
            }
            ctx.restoreGState()
        }
    }

    private static func triangles() -> UIImage {
        draw { ctx in
            let palette = ["#22223b", "#4a4e69", "#9a8c98", "#c9ada7", "#f2e9e4"]
            var rng = SeededRandom(seed: 42)
            let cell = 150.0
            var y = 0.0
            while y < size.height {
                var x = 0.0
                while x < size.width {
                    let c1 = UIColor(hex: palette[Int(rng.next() * Double(palette.count)) % palette.count])
                    let c2 = UIColor(hex: palette[Int(rng.next() * Double(palette.count)) % palette.count])
                    let flip = rng.next() > 0.5
                    let p1 = CGMutablePath(), p2 = CGMutablePath()
                    if flip {
                        p1.addLines(between: [CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y), CGPoint(x: x, y: y + cell)])
                        p2.addLines(between: [CGPoint(x: x + cell, y: y), CGPoint(x: x + cell, y: y + cell), CGPoint(x: x, y: y + cell)])
                    } else {
                        p1.addLines(between: [CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y), CGPoint(x: x + cell, y: y + cell)])
                        p2.addLines(between: [CGPoint(x: x, y: y), CGPoint(x: x + cell, y: y + cell), CGPoint(x: x, y: y + cell)])
                    }
                    ctx.setFillColor(c1.cgColor); ctx.addPath(p1); ctx.fillPath()
                    ctx.setFillColor(c2.cgColor); ctx.addPath(p2); ctx.fillPath()
                    x += cell
                }
                y += cell
            }
        }
    }

    private static func dots() -> UIImage {
        draw { ctx in
            ctx.setFillColor(UIColor(hex: "#10002b").cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setFillColor(UIColor(hex: "#e0aaff").withAlphaComponent(0.8).cgColor)
            var y = 30.0
            while y < size.height {
                var x = 30.0
                while x < size.width {
                    ctx.fillEllipse(in: CGRect(x: x - 6, y: y - 6, width: 12, height: 12))
                    x += 60
                }
                y += 60
            }
        }
    }

    private static func arcs() -> UIImage {
        draw { ctx in
            ctx.setFillColor(UIColor(hex: "#1d3557").cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.setLineWidth(10)
            var y = 0.0
            while y < size.height {
                var x = 0.0
                while x < size.width {
                    for i in stride(from: 5, through: 1, by: -1) {
                        let color = i % 2 == 1 ? "#e63946" : "#f1faee"
                        ctx.setStrokeColor(UIColor(hex: color).cgColor)
                        let r = Double(i) * 20
                        ctx.strokeEllipse(in: CGRect(x: x + 100 - r, y: y + 200 - r, width: r * 2, height: r * 2))
                    }
                    x += 200
                }
                y += 200
            }
        }
    }

    private static func mountains() -> UIImage {
        draw { ctx in
            let rect = CGRect(origin: .zero, size: size)
            linearGradient(ctx, colors: ["#ff9e7d", "#845ec2", "#2c2a4a"],
                           from: .zero, to: CGPoint(x: 0, y: size.height), in: rect)
            ctx.setFillColor(UIColor(hex: "#fff1c1").withAlphaComponent(0.95).cgColor)
            ctx.fillEllipse(in: CGRect(x: 790, y: 170, width: 180, height: 180))
            let layers: [(String, [CGPoint])] = [
                ("#4b3f72", [.init(x: 0, y: 620), .init(x: 200, y: 430), .init(x: 400, y: 600), .init(x: 620, y: 380), .init(x: 860, y: 610), .init(x: 1080, y: 460), .init(x: 1200, y: 580)]),
                ("#38304f", [.init(x: 0, y: 730), .init(x: 260, y: 520), .init(x: 520, y: 720), .init(x: 760, y: 500), .init(x: 1000, y: 700), .init(x: 1200, y: 560)]),
                ("#241f36", [.init(x: 0, y: 900), .init(x: 180, y: 660), .init(x: 420, y: 850), .init(x: 700, y: 620), .init(x: 950, y: 830), .init(x: 1200, y: 680)]),
            ]
            for (color, points) in layers {
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: size.height))
                for p in points { path.addLine(to: p) }
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.closeSubpath()
                ctx.setFillColor(UIColor(hex: color).cgColor)
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
    }

    private static func sunwave() -> UIImage {
        draw { ctx in
            let bg = UIColor(hex: "#0a0e2a")
            ctx.setFillColor(bg.cgColor)
            ctx.fill(CGRect(origin: .zero, size: size))
            // Sun disc with gradient
            let sunRect = CGRect(x: 340, y: 170, width: 520, height: 520)
            ctx.saveGState()
            ctx.addEllipse(in: sunRect)
            ctx.clip()
            linearGradient(ctx, colors: ["#ffd23f", "#ee4266"],
                           from: CGPoint(x: 0, y: sunRect.minY),
                           to: CGPoint(x: 0, y: sunRect.maxY), in: sunRect)
            ctx.restoreGState()
            // Slits across the sun
            ctx.setFillColor(bg.cgColor)
            for i in 0..<6 {
                ctx.fill(CGRect(x: 300, y: 380 + Double(i) * 40, width: 600, height: 12 + Double(i) * 3))
            }
            // Perspective grid
            ctx.setStrokeColor(UIColor(hex: "#ff2d78").withAlphaComponent(0.7).cgColor)
            ctx.setLineWidth(3)
            var x = -600.0
            while x < size.width + 600 {
                ctx.move(to: CGPoint(x: 600, y: 690))
                ctx.addLine(to: CGPoint(x: x, y: size.height))
                ctx.strokePath()
                x += 120
            }
            ctx.setLineWidth(2)
            var y = 700.0
            while y < size.height {
                ctx.move(to: CGPoint(x: 0, y: y))
                ctx.addLine(to: CGPoint(x: size.width, y: y))
                ctx.strokePath()
                y += 45
            }
        }
    }
}

// MARK: user media store

enum MediaStore {
    private static let memory: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 32
        return c
    }()

    /// What we write, in the order load() looks for them. JPEG for
    /// photographs; PNG when the picture has to keep an alpha channel, which
    /// JPEG cannot carry — a background-removed cutout, most of all.
    static let extensions = ["jpg", "png"]

    static var directory: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Store a picked photo and return its "media:<id>" src.
    ///
    /// Takes bytes that are already at the size we keep. Scaling used to
    /// happen here, from a UIImage the caller had fully decoded — see
    /// ImageDownsampler for what that cost. Nothing about this function is
    /// main-actor bound, so callers should run it off the main actor.
    static func store(_ prepared: ImageDownsampler.Prepared) -> String? {
        let id = UID.make("img")
        let url = directory.appendingPathComponent("\(id).\(prepared.ext)")
        do {
            try prepared.encoded.write(to: url)
            // NSCache is thread-safe, so seeding it from a background task is
            // fine and saves the first draw a round trip to disk.
            memory.setObject(prepared.image, forKey: id as NSString)
            return "media:\(id)"
        } catch {
            return nil
        }
    }

    /// Store an image that has to keep its transparency, as PNG.
    static func storeTransparent(_ image: UIImage) -> String? {
        guard let data = image.pngData() else { return nil }
        let id = UID.make("img")
        let url = directory.appendingPathComponent("\(id).png")
        do {
            try data.write(to: url)
            memory.setObject(image, forKey: id as NSString)
            return "media:\(id)"
        } catch {
            return nil
        }
    }

    static func load(_ id: String) -> UIImage? {
        if let cached = memory.object(forKey: id as NSString) { return cached }
        for ext in extensions {
            let url = directory.appendingPathComponent("\(id).\(ext)")
            guard let data = try? Data(contentsOf: url),
                  let img = UIImage(data: data) else { continue }
            memory.setObject(img, forKey: id as NSString)
            return img
        }
        return nil
    }
}
