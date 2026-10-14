// The trimmer bar's rules, as the Android twin's: one bar for a clip's trim
// and a track's, 56 points tall, two handles kept a shortest trim apart, the
// parts left out dimmed and the trim read out above it. A clip's bar shows
// eight frames spread across its file, a track's its waveform — the loudness
// of 120 equal parts of the music (Peaks.buckets). While a handle is
// dragged the canvas shows the clip's frame there; let go, the trim is
// written as one undo step and its first second and a half is heard. With
// VoiceOver each handle is adjustable, a tenth of a second a swipe.

import Foundation

enum Trimming {

    /// The bar's height, in points.
    static let barHeight = 56.0
    /// How many frames a clip's bar shows.
    static let thumbnailCount = 8
    /// How many parts a track's waveform is read in.
    static let peakCount = 120
    /// How long letting go of a handle plays, in seconds, from the start.
    static let audition = 1.5
    /// How far a VoiceOver swipe moves a handle, in seconds.
    static let step = 0.1

    enum Grip { case start, end }

    /// A clip's handle being dragged: element `elementId` shown at `time`
    /// seconds into its file.
    struct Scrub: Equatable {
        var elementId: String
        var time: Double
    }

    /// `page` with the scrubbed clip showing the frame at the handle's
    /// moment, as a time-stamped source ("video:<id>@t"); as it is when
    /// nothing is scrubbed, or the element is no clip on it.
    static func scrubbed(_ page: Page, _ scrub: Scrub?) -> Page {
        guard let scrub, let i = page.elements.firstIndex(where: { $0.id == scrub.elementId }),
              let src = page.elements[i].src, let parts = VideoStore.split(src) else { return page }
        var out = page
        out.elements[i].src = VideoStore.src(parts.id, at: max(0, scrub.time))
        return out
    }

    /// The trim with handle `grip` moved to `t` seconds, in a file `length`
    /// seconds long: the start within 0 and the end less `minLength`, the
    /// end within the start plus `minLength` and the file's end.
    static func moved(_ grip: Grip, to t: Double, start: Double, end: Double, length: Double,
                      minLength: Double) -> (start: Double, end: Double) {
        switch grip {
        case .start: return (max(0, min(t, end - minLength)), end)
        case .end: return (start, min(length, max(t, start + minLength)))
        }
    }

    /// Where a clip's frames are taken, in seconds: the middle of each of
    /// `count` equal parts of a file `length` long — so the first is never
    /// the black of a fade from nothing, nor the last past the end. None for
    /// a file of no length.
    static func thumbnailTimes(length: Double, count: Int = thumbnailCount) -> [Double] {
        guard length > 0, count > 0 else { return [] }
        return (0..<count).map { (Double($0) + 0.5) * length / Double(count) }
    }

    /// What letting go of a handle plays: from the trim's start for
    /// `audition` seconds, or to its end when that comes first.
    static func auditioned(start: Double, end: Double) -> ClosedRange<Double> {
        start...max(start, min(end, start + audition))
    }

    /// The bar's readout: the trim's start and end, and its length —
    /// "0:02.0 – 0:06.0 · 0:04.0".
    static func readout(start: Double, end: Double) -> String {
        "\(VideoStore.rangeLabel(start, end)) · \(VideoStore.timeLabel(max(0, end - start)))"
    }

    /// Where on a bar `width` points wide a time falls in a file `length`
    /// long, and back.
    static func x(of t: Double, length: Double, width: Double) -> Double {
        length > 0 ? min(max(t / length, 0), 1) * width : 0
    }

    static func time(at x: Double, length: Double, width: Double) -> Double {
        width > 0 ? min(max(x / width, 0), 1) * length : 0
    }
}
