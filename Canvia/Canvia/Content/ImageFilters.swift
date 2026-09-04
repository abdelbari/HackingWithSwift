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
        if preset == .none && adjustments.isNeutral { return image }
        let key = "\(cacheKey)|\(preset.rawValue)\(adjustments.signature)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let input = CIImage(image: image) else { return image }
        // Preset first, adjustments second: the preset is the look, the dials
        // are the correction on top of it. The other order would have a dial
        // silently undone by whichever preset was picked afterwards.
        let output = adjusted(filtered(input, preset: preset), adjustments, extent: input.extent)
        guard let cg = context.createCGImage(output, from: input.extent) else { return image }
        let result = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        cache.setObject(result, forKey: key as NSString)
        return result
    }

    /// The dials, in the order a photographer would reach for them.
    private static func adjusted(_ input: CIImage, _ a: Adjustments,
                                 extent: CGRect) -> CIImage {
        guard !a.isNeutral else { return input }
        var image = input

        if a.warmth != 0 {
            let f = CIFilter.temperatureAndTint()
            f.inputImage = image
            // 6500K is the neutral the filter is defined against; pushing the
            // *target* neutral warmer makes the picture warmer.
            f.neutral = CIVector(x: 6500, y: 0)
            f.targetNeutral = CIVector(x: 6500 + a.warmth * 2500, y: 0)
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
