// The page, spoken: every text element in reading order, and pictures by
// their alt text. For proofing a poster by ear, and for anyone who would
// rather listen.

import AVFoundation
import Foundation

final class ReadAloud: NSObject, AVSpeechSynthesizerDelegate {

    static let shared = ReadAloud()

    private let synthesizer = AVSpeechSynthesizer()
    private(set) var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// What the page says, top to bottom and left to right, page-number
    /// tokens resolved, each part ending in a full stop so the voice pauses.
    static func script(for page: Page, in design: Design) -> String {
        let number = (design.pages.firstIndex { $0.id == page.id } ?? 0) + 1
        let elements = design.masterElements(behind: page) + page.elements
        let order = CanvasAccessibility.readingOrder(elements, pageHeight: design.height)
        let byId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var parts: [String] = []
        for id in order {
            guard let el = byId[id] else { continue }
            switch el.type {
            case .text:
                let text = FontLibrary.displayText(for: el, pageNumber: number, pageCount: design.pages.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { parts.append(text) }
            case .image:
                if let alt = el.altText?.trimmingCharacters(in: .whitespacesAndNewlines), !alt.isEmpty {
                    parts.append("Picture: \(alt)")
                }
            default:
                break
            }
        }
        return sentences(parts)
    }

    /// Joined with a full stop after any part that does not already end
    /// one, so "SALE" and "50% off" are two sentences, not one run-on.
    static func sentences(_ parts: [String]) -> String {
        parts.map { part -> String in
            guard let last = part.last else { return part }
            return ".!?:;…".contains(last) ? part : part + "."
        }.joined(separator: " ")
    }

    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
