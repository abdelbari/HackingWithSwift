// A first draft of alt text, from the picture itself.
//
// Vision's image classifier runs on the device and names what it sees —
// "dog", "beach", "coffee" — which is a better starting point than an empty
// field, and the person can always rewrite it. Only ever a suggestion;
// nothing is stored without being asked.

import UIKit
import Vision

enum AltText {

    /// "Photo of a dog, grass and sky", from the strongest classifications;
    /// nil when the classifier is unsure of everything.
    static func describe(_ image: UIImage, maxLabels: Int = 3, minConfidence: Float = 0.3) -> String? {
        guard let cg = image.cgImage else { return nil }
        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cg, orientation: .up)
        do { try handler.perform([request]) } catch { return nil }
        let labels = (request.results ?? [])
            .filter { $0.confidence >= minConfidence }
            .sorted { $0.confidence > $1.confidence }
            .prefix(maxLabels)
            .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        return sentence(from: Array(labels))
    }

    /// "Photo of a dog", "Photo of a dog and grass", "Photo of a dog, grass and sky".
    static func sentence(from labels: [String]) -> String? {
        guard let first = labels.first else { return nil }
        let article = "aeiou".contains(first.first?.lowercased() ?? "x") ? "an" : "a"
        switch labels.count {
        case 1: return "Photo of \(article) \(first)"
        case 2: return "Photo of \(article) \(first) and \(labels[1])"
        default: return "Photo of \(article) \(first), \(labels.dropFirst().dropLast().joined(separator: ", ")) and \(labels.last!)"
        }
    }
}
