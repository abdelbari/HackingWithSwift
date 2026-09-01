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

enum ImageFilterEngine {
    private static let context = CIContext()
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 48
        return c
    }()

    static func apply(_ preset: ImageFilterPreset, to image: UIImage, cacheKey: String) -> UIImage {
        if preset == .none { return image }
        let key = "\(cacheKey)|\(preset.rawValue)"
        if let cached = cache.object(forKey: key as NSString) { return cached }
        guard let input = CIImage(image: image) else { return image }
        let output = filtered(input, preset: preset)
        guard let cg = context.createCGImage(output, from: input.extent) else { return image }
        let result = UIImage(cgImage: cg, scale: image.scale, orientation: image.imageOrientation)
        cache.setObject(result, forKey: key as NSString)
        return result
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
