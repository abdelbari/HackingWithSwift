// Add's Videos tab: the generated motion loops (MotionLibrary), each tile
// playing its loop only while it is on screen — and not at all with Reduce
// Motion on, when it shows its first frame — as the Android twin's tiles
// do. Small frames are drawn straight from the recipe at each tick, rather
// than kept, so a scrolled-past tile holds nothing.

import SwiftUI

struct MotionPreview: View {
    let loop: MotionDef
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Whether the tile is on screen.
    @State private var visible = false

    /// The size a tile's frames are drawn at.
    static let size = (width: 96, height: 72)

    var body: some View {
        let plays = visible && !reduceMotion
        TimelineView(.animation(minimumInterval: 1.0 / 12, paused: !plays)) { context in
            picture(at: plays ? context.date.timeIntervalSinceReferenceDate : 0)
        }
        .onAppear { visible = true }
        .onDisappear { visible = false }
    }

    @ViewBuilder
    private func picture(at seconds: Double) -> some View {
        let t = MotionLibrary.frameTime(seconds.truncatingRemainder(dividingBy: 3600), period: loop.period)
        if let frame = MotionArt.image(loop, t: t, width: Self.size.width, height: Self.size.height) {
            Image(uiImage: frame)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(.systemGray5)
        }
    }
}

/// The loops a search finds, as tiles; a tap hands the chosen one back.
struct MotionGrid: View {
    let loops: [MotionDef]
    /// The loop in the frame being replaced, ringed.
    var current: String?
    let pick: (MotionDef) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 10) {
            ForEach(Array(loops.enumerated()), id: \.element.id) { index, loop in
                tile(loop, said: tr("%@, video %d of %d", loop.name, index + 1, loops.count))
            }
        }
    }

    /// A loop's tile, named for VoiceOver as Android's tiles are.
    private func tile(_ loop: MotionDef, said: String) -> some View {
        let ringed = current == MotionLibrary.src(loop.id, at: nil)
        return Button { pick(loop) } label: {
            VStack(alignment: .leading, spacing: 4) {
                MotionPreview(loop: loop)
                    .frame(height: 72)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                    .overlay {
                        if ringed { RoundedRectangle(cornerRadius: 9).stroke(Theme.accent, lineWidth: 3) }
                    }
                Text(loop.name)
                    .font(.caption)
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(said)
        .accessibilityAddTraits(ringed ? [.isButton, .isSelected] : .isButton)
    }
}
