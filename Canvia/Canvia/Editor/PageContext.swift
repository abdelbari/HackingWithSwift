// Which page a view is drawing, for the things a page needs to know about
// itself: its number, and how many there are.

import SwiftUI

struct PageNumberKey: EnvironmentKey {
    static let defaultValue: (number: Int, count: Int)? = nil
}

/// Seconds into the page for previews and video frames, and the page's
/// hold so Ken Burns knows how far along it is. nil draws everything
/// settled — the editor's normal state.
struct AnimationTimeKey: EnvironmentKey {
    static let defaultValue: (time: Double, hold: Double)? = nil
}

/// The moment the page's exits are played at, when it is not the page's
/// own time: Present holds them where they begin until the person goes on,
/// while loops, clips, drifts and entrances play on. nil plays them by
/// `animationTime`.
struct ExitTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

/// Whether the page is being played live — Present, or Play in the editor
/// — rather than rendered for export. Live, a clip shows the latest frame
/// it has while the next is decoded off the main thread, and never makes
/// the screen wait; an export, which has nobody watching it, waits for
/// every frame so no frame of a movie is a stale one.
struct LiveVideoKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether the page's clock is running — Play, a play through the film,
/// Present — rather than standing where a scrub of the timeline put it:
/// only then does a clip played live play on in a player of its own
/// (ClipPlayers); a scrub shows the frame at each moment.
struct ClipsPlayKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether clips are asked for frame after frame, in order — a video
/// export — so each is read on from its last frame by a reader of its own
/// (ClipReader) rather than sought for every one.
struct ClipsInOrderKey: EnvironmentKey {
    static let defaultValue: ClipReaders? = nil
}

/// Whether the page is on a screen that draws it again when slow work lands
/// — the editor's canvas, its page strip, Present — rather than drawn once
/// for a file. On screen, a photo whose focus keeps its subject sharp shows
/// the focus circle while the subject is found off the main thread, and the
/// subject once it is; a file waits for it.
struct OnScreenKey: EnvironmentKey {
    static let defaultValue = false
}

/// Whether animated pictures play where the page is drawn though it is not
/// playing: the editor's canvas, with Play in the editor on. Each such picture
/// keeps its own clock, so nothing else on the page is drawn again for it.
struct PlaysPicturesKey: EnvironmentKey {
    static let defaultValue = false
}

/// The moment a caption box at rest shows — the editor's timeline
/// playhead, in seconds into the page — or nil for its first cue, as a
/// still export shows it. While the page plays, its clock decides instead
/// (Captions.shown).
struct CaptionTimeKey: EnvironmentKey {
    static let defaultValue: Double? = nil
}

extension EnvironmentValues {
    var captionTime: Double? {
        get { self[CaptionTimeKey.self] }
        set { self[CaptionTimeKey.self] = newValue }
    }

    var pageNumber: (number: Int, count: Int)? {
        get { self[PageNumberKey.self] }
        set { self[PageNumberKey.self] = newValue }
    }

    var animationTime: (time: Double, hold: Double)? {
        get { self[AnimationTimeKey.self] }
        set { self[AnimationTimeKey.self] = newValue }
    }

    var exitTime: Double? {
        get { self[ExitTimeKey.self] }
        set { self[ExitTimeKey.self] = newValue }
    }

    var liveVideo: Bool {
        get { self[LiveVideoKey.self] }
        set { self[LiveVideoKey.self] = newValue }
    }

    var clipsPlay: Bool {
        get { self[ClipsPlayKey.self] }
        set { self[ClipsPlayKey.self] = newValue }
    }

    /// The readers a video export reads the page's clips with, in order;
    /// nil anywhere else.
    var clipsInOrder: ClipReaders? {
        get { self[ClipsInOrderKey.self] }
        set { self[ClipsInOrderKey.self] = newValue }
    }

    var onScreen: Bool {
        get { self[OnScreenKey.self] }
        set { self[OnScreenKey.self] = newValue }
    }

    var playsPictures: Bool {
        get { self[PlaysPicturesKey.self] }
        set { self[PlaysPicturesKey.self] = newValue }
    }
}
