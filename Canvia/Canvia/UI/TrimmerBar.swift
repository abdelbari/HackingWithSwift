// The trimmer bar the Clip sheet and a track's view share (see Trimming):
// the clip's frames or the track's waveform under two handles, the parts
// left out dimmed, and the trim read out above. A handle follows the finger
// and says where it is while dragged (`scrub`) and hands the trim over when
// let go (`commit`), which writes it as one undo step; VoiceOver moves it a
// tenth of a second a swipe, each one a step. As the Android twin's.

import SwiftUI
import UIKit

struct TrimmerBar<Strip: View>: View {
    /// The file's length, and the trim as written, in seconds.
    let length: Double
    let start: Double
    let end: Double
    /// The shortest the trim may be.
    let minLength: Double
    /// Each moment a handle is dragged to; nil once it is let go.
    var scrub: (Double?) -> Void
    /// The trim when a handle is let go, or moved by VoiceOver.
    var commit: (Double, Double) -> Void
    let strip: Strip

    /// The trim while a handle is dragged; nil at rest.
    @State private var draftStart: Double?
    @State private var draftEnd: Double?
    /// Where the dragged handle was when the finger came down.
    @State private var grabbed: Double?

    /// How wide a handle is drawn, and how far past it a finger still takes
    /// it.
    /// (Computed: a generic type cannot hold stored statics.)
    private static var gripWidth: Double { 14 }
    private static var reach: Double { 12 }

    init(length: Double, start: Double, end: Double, minLength: Double,
         scrub: @escaping (Double?) -> Void = { _ in }, commit: @escaping (Double, Double) -> Void,
         @ViewBuilder strip: () -> Strip) {
        self.length = length
        self.start = start
        self.end = end
        self.minLength = minLength
        self.scrub = scrub
        self.commit = commit
        self.strip = strip()
    }

    var body: some View {
        let shownStart = draftStart ?? start
        let shownEnd = draftEnd ?? end
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Trim")
                Spacer()
                Text(Trimming.readout(start: shownStart, end: shownEnd))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            GeometryReader { geo in
                bar(width: Double(geo.size.width), start: shownStart, end: shownEnd)
            }
            .frame(height: Trimming.barHeight)
        }
    }

    private func bar(width: Double, start: Double, end: Double) -> some View {
        let left = Trimming.x(of: start, length: length, width: width)
        let right = Trimming.x(of: end, length: length, width: width)
        let height = Trimming.barHeight
        return ZStack(alignment: .topLeading) {
            strip
                .frame(width: width, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .accessibilityHidden(true)
            dimmed(width: left, at: 0)
            dimmed(width: max(0, width - right), at: right)
            RoundedRectangle(cornerRadius: 4)
                .stroke(Theme.accent, lineWidth: 3)
                .frame(width: max(0, right - left), height: height)
                .offset(x: left)
                .allowsHitTesting(false)
            handle(.start, x: left, width: width)
            handle(.end, x: right - Self.gripWidth, width: width)
        }
        .frame(width: width, height: height, alignment: .topLeading)
    }

    /// A part left out of the trim, darkened.
    private func dimmed(width: Double, at x: Double) -> some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .frame(width: width, height: Trimming.barHeight)
            .offset(x: x)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func handle(_ which: Trimming.Grip, x: Double, width: Double) -> some View {
        gripShape
            .contentShape(Rectangle().inset(by: -Self.reach))
            .offset(x: x)
            .gesture(drag(which, width: width))
            .accessibilityElement()
            .modifier(HandleAccessibility(name: which == .start ? tr("Trim start") : tr("Trim end"),
                                          time: which == .start ? start : end) { by in
                let t = (which == .start ? start : end) + by
                let moved = Trimming.moved(which, to: t, start: start, end: end, length: length, minLength: minLength)
                commit(moved.start, moved.end)
            })
    }

    private var gripShape: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Theme.accent)
            .overlay(Capsule().fill(Color.white).frame(width: 3, height: 18))
            .frame(width: Self.gripWidth, height: Trimming.barHeight)
    }

    /// The handle following the finger: from where it was, by as far as the
    /// finger has gone along the bar, kept within the file and the shortest
    /// trim.
    private func drag(_ which: Trimming.Grip, width: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let s = draftStart ?? start, e = draftEnd ?? end
                let from = grabbed ?? (which == .start ? s : e)
                grabbed = from
                let t = from + Double(value.translation.width) / max(width, 1) * length
                let moved = Trimming.moved(which, to: t, start: s, end: e, length: length, minLength: minLength)
                draftStart = moved.start
                draftEnd = moved.end
                scrub(which == .start ? moved.start : moved.end)
            }
            .onEnded { _ in
                let s = draftStart ?? start, e = draftEnd ?? end
                draftStart = nil
                draftEnd = nil
                grabbed = nil
                scrub(nil)
                if s != start || e != end { commit(s, e) }
            }
    }
}

/// A handle as VoiceOver has it: its name, where it is, and a swipe up or
/// down moving it a tenth of a second.
private struct HandleAccessibility: ViewModifier {
    let name: String
    let time: Double
    let move: (Double) -> Void

    func body(content: Content) -> some View {
        content
            .accessibilityLabel(name)
            .accessibilityValue(VideoStore.timeLabel(time))
            .accessibilityAdjustableAction { direction in
                move(direction == .increment ? Trimming.step : -Trimming.step)
            }
    }
}

/// A clip's frames across its bar, side by side; grey until they are read.
struct FilmstripView: View {
    let frames: [UIImage]

    var body: some View {
        GeometryReader { geo in
            let each = geo.size.width / CGFloat(max(frames.count, 1))
            HStack(spacing: 0) {
                ForEach(frames.indices, id: \.self) { i in
                    Image(uiImage: frames[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: each, height: geo.size.height)
                        .clipped()
                }
            }
        }
        .background(Color(.systemGray5))
    }
}

/// A track's waveform across its bar: a bar for each part's loudness, as a
/// share of the loudest; grey until it is read.
struct WaveformView: View {
    let peaks: [Float]

    var body: some View {
        let levels = Peaks.normalised(peaks)
        Canvas { context, size in
            guard !levels.isEmpty else { return }
            let step = size.width / CGFloat(levels.count)
            for (i, level) in levels.enumerated() {
                let h = max(2, CGFloat(level) * size.height * 0.9)
                let bar = CGRect(x: CGFloat(i) * step + step * 0.2, y: (size.height - h) / 2,
                                 width: max(1, step * 0.6), height: h)
                context.fill(Path(roundedRect: bar, cornerRadius: 1), with: .color(Theme.accent))
            }
        }
        .background(Color(.systemGray6))
    }
}
