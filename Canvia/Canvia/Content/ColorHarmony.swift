// Colours derived from a colour.
//
// Picking a second colour that goes with the first is the hardest part of
// making something look designed, and it is the part a computer can actually
// do: rotate the hue by a fixed angle and the result is a relationship people
// have used since Itten. Tints and shades are the same idea on lightness —
// the ramp a brand needs for hovers, borders and disabled states.
//
// All of it is arithmetic on HSL, so all of it is assertable.

import Foundation
import UIKit

enum ColorHarmony: String, CaseIterable, Identifiable {
    case complementary, analogous, triadic, splitComplementary, tetradic, monochrome

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .complementary: return "Complementary"
        case .analogous: return "Analogous"
        case .triadic: return "Triadic"
        case .splitComplementary: return "Split"
        case .tetradic: return "Tetradic"
        case .monochrome: return "Monochrome"
        }
    }

    /// Hue rotations in degrees, seed first.
    var rotations: [Double] {
        switch self {
        case .complementary: return [0, 180]
        case .analogous: return [0, -30, 30, -60, 60]
        case .triadic: return [0, 120, 240]
        case .splitComplementary: return [0, 150, 210]
        case .tetradic: return [0, 90, 180, 270]
        case .monochrome: return [0]
        }
    }
}

enum ColorTheory {

    // MARK: conversion

    /// Hue in 0..<360, saturation and lightness in 0...1.
    static func hsl(_ hex: String) -> (h: Double, s: Double, l: Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(hex: hex).getRed(&r, green: &g, blue: &b, alpha: &a)
        let red = Double(min(1, max(0, r))), green = Double(min(1, max(0, g)))
        let blue = Double(min(1, max(0, b)))
        let high = max(red, green, blue), low = min(red, green, blue)
        let lightness = (high + low) / 2
        guard high > low else { return (0, 0, lightness) }
        let delta = high - low
        let saturation = lightness > 0.5 ? delta / (2 - high - low) : delta / (high + low)
        var hue: Double
        switch high {
        case red: hue = (green - blue) / delta + (green < blue ? 6 : 0)
        case green: hue = (blue - red) / delta + 2
        default: hue = (red - green) / delta + 4
        }
        hue *= 60
        return (hue, saturation, lightness)
    }

    static func hex(h: Double, s: Double, l: Double) -> String {
        let hue = ((h.truncatingRemainder(dividingBy: 360)) + 360)
            .truncatingRemainder(dividingBy: 360)
        let saturation = min(1, max(0, s)), lightness = min(1, max(0, l))
        guard saturation > 0 else {
            let v = Int((lightness * 255).rounded())
            return String(format: "#%02x%02x%02x", v, v, v)
        }
        let q = lightness < 0.5 ? lightness * (1 + saturation)
                                : lightness + saturation - lightness * saturation
        let p = 2 * lightness - q
        func channel(_ offset: Double) -> Double {
            var t = (hue / 360) + offset
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        return String(format: "#%02x%02x%02x",
                      Int((channel(1.0 / 3) * 255).rounded()),
                      Int((channel(0) * 255).rounded()),
                      Int((channel(-1.0 / 3) * 255).rounded()))
    }

    // MARK: derivation

    /// The seed and its companions, seed first.
    static func harmony(_ kind: ColorHarmony, from seed: String) -> [String] {
        let base = hsl(seed)
        if kind == .monochrome { return ramp(from: seed, steps: 5) }
        // A grey has no hue to rotate, so every rotation would return the same
        // colour. Give it the lightness ramp instead of five identical chips.
        guard base.s > 0.04 else { return ramp(from: seed, steps: kind.rotations.count) }
        return kind.rotations.map { hex(h: base.h + $0, s: base.s, l: base.l) }
    }

    /// Tints and shades of one colour, light to dark, with the seed's own
    /// lightness in the middle of the range rather than at one end.
    static func ramp(from seed: String, steps: Int = 5) -> [String] {
        guard steps > 0 else { return [] }
        guard steps > 1 else { return [seed] }
        let base = hsl(seed)
        return (0..<steps).map { index in
            let t = Double(index) / Double(steps - 1)
            // 0.90 down to 0.20: light enough to be a tint, dark enough to be
            // a shade, and never the pure white or black that a naive 0...1
            // sweep hands back at the ends.
            return hex(h: base.h, s: base.s, l: 0.90 - t * 0.70)
        }
    }

    /// The colour text should be in front of this one — the same decision the
    /// canvas already makes for the highlight effect, exposed so a palette can
    /// show it.
    static func readableInk(on background: String) -> String {
        UIColor(hex: background).isLight ? "#16181d" : "#ffffff"
    }
}

/// The colours this person actually used, most recent first.
///
/// Small, durable and boring on purpose: a design tool where the colour you
/// used thirty seconds ago is three taps away is a design tool people fight.
enum RecentColors {
    static let limit = 18
    private static let key = "canvia.recentColors"

    static var all: [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    static func record(_ hex: String) {
        let normalised = normalise(hex)
        guard !normalised.isEmpty else { return }
        var list = all.filter { normalise($0) != normalised }
        list.insert(normalised, at: 0)
        UserDefaults.standard.set(Array(list.prefix(limit)), forKey: key)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    /// Lower-cased and hashed, so "#FFF", "#ffffff" and "ffffff" are one
    /// colour rather than three entries in the list.
    static func normalise(_ hex: String) -> String {
        var s = hex.trimmingCharacters(in: .whitespaces).lowercased()
        if s.hasPrefix("#") { s.removeFirst() }
        guard !s.isEmpty, s.allSatisfy({ $0.isHexDigit }) else { return "" }
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6 || s.count == 8 else { return "" }
        return "#" + s.prefix(6)
    }
}
