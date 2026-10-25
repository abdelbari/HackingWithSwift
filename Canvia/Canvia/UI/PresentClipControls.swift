// A clip's own controls in Present (Videos): a tap on a clip brings up Play
// or Pause and a scrubber across its trimmed part, at its foot, every
// control at least 44 points, gone three seconds after the last touch; a
// clip whose Autoplay is off waits on its first frame with a Play button
// over it. Drawn over the page on the phone, fitted as PresentStage fits
// it; what they do is the session's (PresentSession.toggleClip, scrubClip),
// so the screen attached plays it too.

import SwiftUI

struct PresentClipControls: View {
    let session: PresentSession
    /// The space the page is fitted to, as PresentStage fits it.
    let size: CGSize
    /// A control touched: the controls stay up another three seconds.
    let touched: () -> Void

    var body: some View {
        let pageSize = session.design.size(for: session.page)
        let scale = min(size.width / max(pageSize.width, 1), size.height / max(pageSize.height, 1))
        let origin = CGPoint(x: (size.width - pageSize.width * scale) / 2, y: (size.height - pageSize.height * scale) / 2)
        ZStack(alignment: .topLeading) {
            ForEach(session.clips, id: \.id) { el in
                let frame = CGRect(x: origin.x + el.x * scale, y: origin.y + el.y * scale,
                                   width: el.w * scale, height: el.h * scale)
                if session.controlsClip == el.id {
                    ClipControlBar(session: session, element: el, touched: touched)
                        .frame(width: max(frame.width, 220))
                        .position(x: frame.midX, y: max(frame.maxY - Videos.target, Videos.target))
                } else if waits(el) {
                    playBadge(el)
                        .position(x: frame.midX, y: frame.midY)
                }
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }

    /// Whether `el` waits on its first frame for Play: Autoplay off, and
    /// nothing done to it yet.
    private func waits(_ el: Element) -> Bool {
        session.clipOverrides[el.id] == nil && el.clip?.autoplay == false
    }

    private func playBadge(_ el: Element) -> some View {
        Button {
            session.toggleClip(el.id)
            touched()
        } label: {
            Image(systemName: "play.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: Videos.target * 1.4, height: Videos.target * 1.4)
                .background(Color.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel(Videos.spokenAction(el, moving: false))
    }
}

/// Play or Pause and the scrubber for one clip, on a dark band.
private struct ClipControlBar: View {
    let session: PresentSession
    let element: Element
    let touched: () -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 8) {
                playButton
                scrubber
            }
            .padding(.horizontal, 8)
            .background(Color.black.opacity(0.6), in: Capsule())
        }
    }

    private var moving: Bool { session.clipMoves(element.id) }

    private var playButton: some View {
        Button {
            session.toggleClip(element.id)
            touched()
        } label: {
            Image(systemName: moving ? "pause.fill" : "play.fill")
                .foregroundStyle(.white)
                .frame(width: Videos.target, height: Videos.target)
        }
        .accessibilityLabel(Videos.spokenAction(element, moving: moving))
    }

    @ViewBuilder
    private var scrubber: some View {
        if let range = Videos.trimRange(element, duration: PresentSession.length(of: element)) {
            Slider(value: position(in: range), in: range) { editing in
                if editing { touched() }
            }
            .tint(.white)
            .frame(minHeight: Videos.target)
            .accessibilityLabel(Text("Video position"))
            .accessibilityValue(VideoStore.timeLabel(now))
        } else {
            Spacer(minLength: 0)
        }
    }

    /// Where the clip is now, in its file.
    private var now: Double {
        Videos.presentTime(element, pageMoment: session.pageMoment, override: session.clipOverrides[element.id],
                           duration: PresentSession.length(of: element))
    }

    private func position(in range: ClosedRange<Double>) -> Binding<Double> {
        Binding(get: { min(max(now, range.lowerBound), range.upperBound) },
                set: { value in
                    session.scrubClip(element.id, to: value)
                    touched()
                })
    }
}
