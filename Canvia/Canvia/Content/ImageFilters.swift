// Image filter presets applied with Core Image, mirroring the web preset
// names. Filtered images are cached per (source, preset).

import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

enum ImageFilterPreset: String, CaseIterable, Identifiable {
    case none, vivid, warm, cool, mono, noir, fade, retro, dramatic, dreamy

    var id: String { rawValue }
    var displayName: String { rawValue == "none" ? "None" : rawValue.capitalized }

    static func from(_ key: String?) -> ImageFilterPreset {
        ImageFilterPreset(rawValue: key ?? "none") ?? .none
    }
}

/// Free-hand adjustments on top of a preset.
///
/// One struct rather than six fields on Element: a preset is a look someone
/// picks, an adjustment is a dial they turn, and the two compose. Every value
/// is centred on zero so "no adjustment" is the zero value and a document that
/// predates this decodes as untouched.
struct Adjustments: Codable, Equatable, Hashable {
    /// All in -1…1 except vignette, which only darkens.
    var brightness: Double = 0
    var contrast: Double = 0
    var saturation: Double = 0
    /// Positive is warmer (more orange), negative cooler (more blue).
    var warmth: Double = 0
    /// Positive sharpens, negative blurs.
    var sharpness: Double = 0
    /// 0…1.
    var vignette: Double = 0

    static let neutral = Adjustments()
    var isNeutral: Bool { self == Adjustments.neutral }

    /// Short and stable, for cache keys — and it only lengthens for the dials
    /// actually moved, so an untouched image keys the same as before.
    var signature: String {
        guard !isNeutral else { return "" }
        func f(_ label: String, _ value: Double) -> String {
            value == 0 ? "" : "\(label)\(Int((value * 100).rounded()))"
        }
        return "adj" + f("b", brightness) + f("c", contrast) + f("s", saturation)
            + f("w", warmth) + f("k", sharpness) + f("v", vignette)
    }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, warmth, sharpness, vignette
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        brightness = (try? c.decode(Double.self, forKey: .brightness)) ?? 0
        contrast = (try? c.decode(Double.self, forKey: .contrast)) ?? 0
        saturation = (try? c.decode(Double.self, forKey: .saturation)) ?? 0
        warmth = (try? c.decode(Double.self, forKey: .warmth)) ?? 0
        sharpness = (try? c.decode(Double.self, forKey: .sharpness)) ?? 0
        vignette = (try? c.decode(Double.self, forKey: .vignette)) ?? 0
    }
}

/// Two colours a photo is mapped onto by luminance.
///
/// The one photo treatment that makes an image belong to a brand rather than
/// merely sit next to it — which is why it is a pair of colours rather than a
/// preset: the whole point is that they are *your* colours.
struct Duotone: Codable, Equatable, Hashable {
    /// Where the photo is darkest, and where it is lightest.
    var dark: String
    var light: String

    static let presets: [(name: String, tone: Duotone)] = [
        ("Ink", Duotone(dark: "#0b1020", light: "#e9edff")),
        ("Ultraviolet", Duotone(dark: "#2a0a5e", light: "#ffd6f2")),
        ("Sunset", Duotone(dark: "#3d1436", light: "#ffc773")),
        ("Forest", Duotone(dark: "#0d2b1d", light: "#c9f2a0")),
        ("Steel", Duotone(dark: "#131a22", light: "#9fd4ff")),
        ("Rose", Duotone(dark: "#3b0d20", light: "#ffd9d0")),
    ]

    private enum CodingKeys: String, CodingKey { case dark, light }

    init(dark: String, light: String) {
        self.dark = dark
        self.light = light
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dark = (try? c.decode(String.self, forKey: .dark)) ?? "#000000"
        light = (try? c.decode(String.self, forKey: .light)) ?? "#ffffff"
    }
}

enum ImageFilterEngine {
    private static let context = CIContext()
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        return c
    }()

    static func apply(_ preset: ImageFilterPreset, to image: UIImage, cacheKey: String) -> UIImage {
        apply(preset, adjustments: .neutral, to: image, cacheKey: cacheKey)
    }

    static func apply(_ preset: ImageFilterPreset, adjustments: Adjustments,
                      to image: UIImage, cacheKey: String) -> UIImage {
        apply(preset, adjustments: adjustments, duotone: nil, to: image, cacheKey: cacheKey)
    }

    static func apply(_ preset: ImageFilterPreset, adjustments: Adjustments,
                      duotone: Duotone?, to image: UIImage, cacheKey: String) -> UIImage {
        if preset == .none && adjustments.isNeutral && duotone == nil { return image }
        let tone = duotone.map { "|duo\($0.dark)\($0.light)" } ?? ""
        let key = "\(cacheKey)|\(preset.rawValue)\(adjustments.signature)\(tone)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let input = CIImage(image: image) else { return image }
        // Preset first, adjustments second: the preset is the look, the dials
        // are the correction on top of it. The other order would have a dial
        // silently undone by whichever preset was picked afterwards.
        var output = adjusted(filtered(input, preset: preset), adjustments, extent: input.extent)
        // Duotone last, because it replaces colour outright — running it
        // before a saturation dial would leave that dial with nothing to do.
        if let duotone { output = mapped(output, to: duotone) }
        guard let cg = context.createCGImage(output, from: input.extent) else { return image }
        let result = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        cache.setObject(result, forKey: key as NSString)
        return result
    }

    /// Luminance mapped onto two colours: darkest becomes `dark`, lightest
    /// becomes `light`, and everything between is a straight ramp.
    ///
    /// Desaturated first. CIFalseColor reads luminance, so a picture with
    /// strong colour in it would otherwise map its reds and its greens to
    /// different points of the ramp for reasons that have nothing to do with
    /// how light they are.
    private static func mapped(_ input: CIImage, to duotone: Duotone) -> CIImage {
        let mono = CIFilter.colorControls()
        mono.inputImage = input
        mono.saturation = 0
        guard let grey = mono.outputImage else { return input }
        let map = CIFilter.falseColor()
        map.inputImage = grey
        map.color0 = CIColor(color: UIColor(hex: duotone.dark))
        map.color1 = CIColor(color: UIColor(hex: duotone.light))
        return map.outputImage ?? input
    }

    /// The dials, in the order a photographer would reach for them.
    private static func adjusted(_ input: CIImage, _ a: Adjustments,
                                 extent: CGRect) -> CIImage {
        guard !a.isNeutral else { return input }
        var image = input

        if a.warmth != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            // The filter re-balances a picture lit at `neutral` as if it had
            // been lit at `targetNeutral`, so a *higher* target temperature
            // makes the picture bluer — the light it is correcting for was
            // warm. Warmer therefore means a lower target. This is the
            // direction the test pins, because the other way round looks
            // entirely plausible.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 - a.warmth * 2500, y: 0)
            image = f.outputImage ?? image
        }

        if a.brightness != 0 || a.contrast != 0 || a.saturation != 0 {
            let f = CIFilter.colorControls()
            f.inputImage = image
            // Core Image's ranges: brightness is an offset around 0, contrast
            // and saturation are multipliers around 1.
            f.brightness = Float(a.brightness * 0.35)
            f.contrast = Float(1 + a.contrast * 0.6)
            f.saturation = Float(max(0, 1 + a.saturation))
            image = f.outputImage ?? image
        }

        if a.sharpness > 0 {
            let f = CIFilter.sharpenLuminance()
            f.inputImage = image
            f.sharpness = Float(a.sharpness * 1.5)
            image = (f.outputImage ?? image).cropped(to: extent)
        } else if a.sharpness < 0 {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image.clampedToExtent()
            f.radius = Float(-a.sharpness * 12)
            image = (f.outputImage ?? image).cropped(to: extent)
        }

        if a.vignette > 0 {
            let f = CIFilter.vignette()
            f.inputImage = image
            f.intensity = Float(a.vignette * 2)
            f.radius = Float(1.4)
            image = (f.outputImage ?? image).cropped(to: extent)
        }
        return image
    }

    private static func filtered(_ input: CIImage, preset: ImageFilterPreset) -> CIImage {
        func controls(_ image: CIImage, saturation: Double = 1, brightness: Double = 0, contrast: Double = 1) -> CIImage {
            let f = CIFilter.colorControls()
            f.inputImage = image
            f.saturation = Float(saturation)
            f.brightness = Float(brightness)
            f.contrast = Float(contrast)
            return f.outputImage ?? image
        }
        func sepia(_ image: CIImage, _ intensity: Double) -> CIImage {
            let f = CIFilter.sepiaTone()
            f.inputImage = image
            f.intensity = Float(intensity)
            return f.outputImage ?? image
        }
        func hue(_ image: CIImage, degrees: Double) -> CIImage {
            let f = CIFilter.hueAdjust()
            f.inputImage = image
            f.angle = Float(degrees * .pi / 180)
            return f.outputImage ?? image
        }
        func blur(_ image: CIImage, _ radius: Double) -> CIImage {
            let f = CIFilter.gaussianBlur()
            f.inputImage = image
            f.radius = Float(radius)
            return (f.outputImage ?? image).cropped(to: image.extent)
        }

        switch preset {
        case .none: return input
        case .vivid: return controls(input, saturation: 1.6, brightness: 0.02, contrast: 1.12)
        case .warm: return controls(sepia(input, 0.35), saturation: 1.25, brightness: 0.02)
        case .cool: return controls(hue(input, degrees: -18), saturation: 1.15, brightness: 0.01)
        case .mono: return controls(input, saturation: 0, contrast: 1.08)
        case .noir: return controls(input, saturation: 0, brightness: -0.04, contrast: 1.4)
        case .fade: return controls(input, saturation: 0.65, brightness: 0.08, contrast: 0.88)
        case .retro: return controls(sepia(input, 0.5), saturation: 1.15, contrast: 0.95)
        case .dramatic: return controls(input, saturation: 1.1, brightness: -0.03, contrast: 1.35)
        case .dreamy: return controls(blur(input, 1.6), saturation: 1.15, brightness: 0.04)
        }
    }
}
