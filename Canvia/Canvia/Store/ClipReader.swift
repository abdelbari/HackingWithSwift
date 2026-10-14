// Clips read in order, for smooth video. VideoStore.frame seeks for every
// frame it is asked for — AVAssetImageGenerator decoding again from the key
// frame before it — so each frame of a video export cost a whole group of
// pictures, and what played live dropped frames while it waited. That
// random-access frame stays for posters, thumbnails, the trimmer's
// filmstrip and a trim handle dragged; a clip played through is read in
// order instead:
//
// - A video export reads each clip with a ClipReader: one AVAssetReader
//   kept open on it, read on from the frame it last gave while the moment
//   asked is at or after it and at most a second ahead (`readsOn`), and
//   started again at the moment asked — decoding on from the key frame
//   before it — only otherwise.
// - Present, and Play in the editor, play each clip in a ClipPlayer: an
//   AVPlayer, muted (the clip's sound is PageSound's), whose frames a
//   CADisplayLink takes from an AVPlayerItemVideoOutput as the screen shows
//   them; it plays on at the clip's speed while the page's moment moves on,
//   and is sought to that moment when it goes back or the two drift apart.
//   Each element showing the clip has its own player, as a clip on a page
//   twice, trimmed two ways, plays two parts of it at once; and the
//   player plays only while the page's clock runs, never for a scrub.
//
// Either way the moment is the one VideoStore.clipTime stamps from the
// page's time, so a clip's trim, speed and loop are kept as before. Each
// clip has its own reader or player, so no clip waits on another; at most
// four of each are open (ClipPool), and all are closed when another page
// comes up and when the phone runs short of memory. The design's JSON does
// not change.

import AVFoundation
import CoreImage
import QuartzCore
import UIKit

/// The clips each pool keeps open, the least recently used let go first.
enum ClipPool {

    /// How many clips each pool keeps open at once.
    static let limit = 4

    /// `order` — the clips open, the least recently used first — once `id`
    /// has been used: moved to the end, or put there, and those past
    /// `limit` taken off the front to be closed.
    static func touched(_ order: [String], _ id: String) -> (order: [String], dropped: [String]) {
        var out = order.filter { $0 != id }
        out.append(id)
        let excess = max(0, out.count - limit)
        return (Array(out.dropFirst(excess)), Array(out.prefix(excess)))
    }
}

/// One clip read in order, for a video export.
final class ClipReader {

    /// How far ahead of where a reader stands a moment can be and still be
    /// read on to, in seconds: at most a second's frames decoded and passed
    /// over, never more than a seek costs.
    static let reach = 1.0

    /// The longest side a frame is read at, as VideoStore.frame reads it.
    static let maxSide: CGFloat = 1920

    /// Whether the frame at `t` seconds into the clip is read on to from
    /// where the reader stands — `t` at or after `position`, `reach` ahead
    /// at most — rather than sought: a moment behind it, or further on,
    /// starts the reader again there, and so does a reader that stands
    /// nowhere yet (nil). The Android twin's ClipReader keeps the same rule.
    static func readsOn(from position: Double?, to t: Double) -> Bool {
        guard let position else { return false }
        return t >= position && t - position <= reach
    }

    /// Whether the frame showing `t` seconds into the clip is the first
    /// after it rather than the last at or before it — `before` and `after`
    /// their times, nil where there is none: the nearer of the two, the
    /// earlier on a tie, as the Android twin's reader and its random-access
    /// frame pick it, so both phones export the same frames. No tolerance
    /// for a stamp's rounding is needed: a frame stamped a hair after the
    /// moment is nearer than the one a whole frame before.
    static func showsAhead(before: Double?, after: Double?, at t: Double) -> Bool {
        guard let after else { return false }
        guard let before else { return true }
        return after - t < t - before
    }

    /// The way up a clip filmed with `transform` is drawn, as
    /// AVAssetImageGenerator's appliesPreferredTrackTransform turns it: a
    /// phone held upright films a quarter turn.
    static func orientation(_ transform: CGAffineTransform) -> CGImagePropertyOrientation {
        switch (transform.a, transform.b, transform.c, transform.d) {
        case (0, 1, -1, 0): return .right
        case (0, -1, 1, 0): return .left
        case (-1, 0, 0, -1): return .down
        default: return .up
        }
    }

    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A decoded frame the way up it is drawn, its longest side `maxSide`
    /// at most.
    static func picture(_ pixels: CVPixelBuffer, orientation: CGImagePropertyOrientation) -> CGImage? {
        var image = CIImage(cvPixelBuffer: pixels).oriented(orientation)
        let longest = max(image.extent.width, image.extent.height)
        if longest > maxSide {
            let scale = maxSide / longest
            image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }
        return context.createCGImage(image, from: image.extent)
    }

    private let asset: AVURLAsset
    private let track: AVAssetTrack
    private let turn: CGImagePropertyOrientation
    private var reader: AVAssetReader?
    private var output: AVAssetReaderTrackOutput?
    /// Where the reader stands: the moment last asked.
    private var position: Double?
    /// The frame last given, and its time.
    private var shown: CGImage?
    private var shownTime: Double?
    /// The last frame read at or before the moment last asked.
    private var behind: CMSampleBuffer?
    /// The frame read past the moment last asked, kept for the next.
    private var ahead: CMSampleBuffer?
    /// A clip whose reader would not start is not tried again.
    private var failed = false
    private let lock = NSLock()

    /// Nil for a file with no picture to read.
    init?(url: URL) {
        let asset = AVURLAsset(url: url)
        guard let track = asset.tracks(withMediaType: .video).first else { return nil }
        self.asset = asset
        self.track = track
        turn = Self.orientation(track.preferredTransform)
    }

    /// The frame showing `t` seconds into the clip: the nearer of the last
    /// whose time is at or before `t` and the first after it (showsAhead),
    /// the first there when a seek lands after the moment; past the end,
    /// the last. Nil when the clip cannot be read.
    func frame(at time: Double) -> CGImage? {
        lock.lock(); defer { lock.unlock() }
        let t = max(0, time)
        if reader == nil || !Self.readsOn(from: position, to: t) { start(at: t) }
        guard let output else { return nil }
        // Read on to the first frame after the moment, keeping the one
        // before it; nothing is read while that frame is still ahead.
        while ahead.map({ Self.seconds($0) <= t }) ?? true {
            if let next = ahead {
                behind = next
                ahead = nil
            }
            guard let sample = output.copyNextSampleBuffer() else { break }
            if CMSampleBufferGetImageBuffer(sample) != nil { ahead = sample }
        }
        let after = Self.showsAhead(before: behind.map(Self.seconds), after: ahead.map(Self.seconds), at: t)
        if let chosen = after ? ahead : behind, Self.seconds(chosen) != shownTime,
           let pixels = CMSampleBufferGetImageBuffer(chosen),
           let image = Self.picture(pixels, orientation: turn) {
            shown = image
            shownTime = Self.seconds(chosen)
        }
        position = t
        return shown
    }

    /// Lets the clip go.
    func close() {
        lock.lock(); defer { lock.unlock() }
        reader?.cancelReading()
        reader = nil
        output = nil
        behind = nil
        ahead = nil
    }

    /// A fresh reader from `t` on; nothing shown yet.
    private func start(at t: Double) {
        reader?.cancelReading()
        reader = nil
        output = nil
        behind = nil
        ahead = nil
        shown = nil
        shownTime = nil
        position = t
        guard !failed else { return }
        guard let reading = try? AVAssetReader(asset: asset) else { failed = true; return }
        let out = AVAssetReaderTrackOutput(track: track, outputSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        out.alwaysCopiesSampleData = false
        guard reading.canAdd(out) else { failed = true; return }
        reading.add(out)
        reading.timeRange = CMTimeRange(start: CMTime(seconds: t, preferredTimescale: 600), duration: .positiveInfinity)
        guard reading.startReading() else { failed = true; return }
        reader = reading
        output = out
    }

    private static func seconds(_ sample: CMSampleBuffer) -> Double {
        CMSampleBufferGetPresentationTimeStamp(sample).seconds
    }
}

/// The readers a video export reads its clips with, one a clip.
enum ClipReaders {

    private static var open: [String: ClipReader] = [:]
    private static var order: [String] = []
    private static let lock = NSLock()

    /// The frame showing `time` seconds into clip `id`, read in order by
    /// the clip's own reader; nil when it cannot be read that way.
    static func frame(_ id: String, at time: Double) -> CGImage? {
        lock.lock()
        var reader = open[id]
        if reader == nil, let url = VideoStore.url(for: id), let made = ClipReader(url: url) {
            open[id] = made
            reader = made
        }
        var dropped: [ClipReader] = []
        if reader != nil {
            let touched = ClipPool.touched(order, id)
            order = touched.order
            dropped = touched.dropped.compactMap { open.removeValue(forKey: $0) }
        }
        lock.unlock()
        ClipPlayers.watchMemory()
        dropped.forEach { $0.close() }
        return reader?.frame(at: time)
    }

    /// Lets every clip go.
    static func closeAll() {
        lock.lock()
        let all = Array(open.values)
        open.removeAll()
        order.removeAll()
        lock.unlock()
        all.forEach { $0.close() }
    }
}

/// One clip played live — Present, Play in the editor — on the main thread.
final class ClipPlayer {

    /// How far the player and the page's moment may drift apart, in
    /// seconds, before the player is sought back to the page.
    static let drift = 0.3
    /// How long the page's moment may stand still, in seconds, before the
    /// player stops.
    static let idle = 0.25

    private let player: AVPlayer
    private let output: AVPlayerItemVideoOutput
    private var turn: CGImagePropertyOrientation = .up
    /// Whether the clip's way up has been read; no frame is shown before.
    private var oriented = false
    /// The moment the page last asked of the clip, and when that moment
    /// last moved on.
    private var wanted: Double?
    private(set) var askedAt: CFTimeInterval = 0
    /// Where the clip's trim ends, which the player stops at.
    private var end: Double?
    private var seeking = false
    /// The latest frame out of the player, and where in the clip it is.
    private(set) var latest: (image: UIImage, time: Double)?

    init(url: URL) {
        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ])
        item.add(output)
        player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .pause
        player.automaticallyWaitsToMinimizeStalling = false
        // The way up is read off the main thread; frames wait for it.
        Task { @MainActor [weak self] in
            guard let track = try? await asset.loadTracks(withMediaType: .video).first,
                  let transform = try? await track.load(.preferredTransform) else { return }
            self?.turn = ClipReader.orientation(transform)
            self?.oriented = true
        }
    }

    /// The page asks for the frame `t` seconds into the clip, as `clip`
    /// plays it: the player plays on at its speed while the moment moves
    /// on from the last asked by at most a second (ClipReader.readsOn) and
    /// the player is near it, and is sought to it otherwise. It stops at
    /// the trim's end, where a clip that does not loop is held; one that
    /// loops comes round to its start, and is sought there. Asked again at
    /// the same moment — drawn again for a frame that landed — it does not
    /// count as asked, so a page whose clock has stopped lets it stop.
    func want(_ t: Double, clip: ClipPlayback) {
        if clip.end != end {
            end = clip.end
            player.currentItem?.forwardPlaybackEndTime = clip.end.map { CMTime(seconds: $0, preferredTimescale: 600) } ?? .invalid
        }
        let previous = wanted
        wanted = t
        if t != previous { askedAt = CACurrentMediaTime() }
        guard !seeking else { return }
        let at = player.currentTime().seconds
        let near = at.isFinite && abs(at - t) <= Self.drift
        if ClipReader.readsOn(from: previous, to: t) && near {
            let rate = Float(clip.playbackSpeed)
            if let previous, t > previous, player.rate != rate { player.rate = rate }
        } else {
            seek(to: t)
        }
    }

    /// The player sought to `t` exactly, paused; the next moment asked
    /// plays it on.
    private func seek(to t: Double) {
        seeking = true
        player.pause()
        let time = CMTime(seconds: max(0, t), preferredTimescale: 600)
        let player = self.player
        Task { @MainActor [weak self] in
            _ = await player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            self?.seeking = false
        }
    }

    /// On each frame of the display: stopped when the page's moment has
    /// stopped moving on — sought back to that moment, so the clip shows
    /// where the page stopped — and the frame the screen shows now taken
    /// from the player when there is a new one. Whether one was.
    func tick(_ now: CFTimeInterval) -> Bool {
        if now - askedAt > Self.idle, player.rate != 0 {
            if let wanted { seek(to: wanted) } else { player.pause() }
        }
        guard oriented else { return false }
        let time = player.rate != 0 ? output.itemTime(forHostTime: now) : player.currentTime()
        guard output.hasNewPixelBuffer(forItemTime: time),
              let pixels = output.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil),
              let image = ClipReader.picture(pixels, orientation: turn) else { return false }
        latest = (UIImage(cgImage: image), time.seconds)
        return true
    }

    /// Lets the clip go.
    func close() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// The players Present and Play in the editor play their clips in, one for
/// each element showing a clip, and the display link that takes their
/// frames. Main thread only.
final class ClipPlayers: NSObject {

    static let shared = ClipPlayers()

    private var open: [String: ClipPlayer] = [:]
    private var order: [String] = []
    private var link: CADisplayLink?

    /// Every clip's reader and player are let go when the phone runs short
    /// of memory: watched from the first clip opened.
    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(memoryLow(_:)),
                                               name: UIApplication.didReceiveMemoryWarningNotification, object: nil)
    }

    /// Watches for the phone running short of memory, from now on.
    static func watchMemory() {
        _ = shared
    }

    @objc private func memoryLow(_ note: Notification) {
        VideoStore.closeClips()
    }

    /// The latest frame of clip `id` played live for `element`, and where
    /// in the clip it is, once its player has one; asking plays the clip on
    /// to `time` seconds into it as `clip` plays it (ClipPlayer.want). Each
    /// element showing the clip has a player of its own, so two showing
    /// different moments of it never take each other's frames.
    func frame(_ id: String, for element: String, at time: Double, clip: ClipPlayback) -> (image: UIImage, time: Double)? {
        let key = element + "/" + id
        var player = open[key]
        if player == nil, let url = VideoStore.url(for: id) {
            let made = ClipPlayer(url: url)
            open[key] = made
            player = made
        }
        guard let player else { return nil }
        let touched = ClipPool.touched(order, key)
        order = touched.order
        for gone in touched.dropped { open.removeValue(forKey: gone)?.close() }
        player.want(time, clip: clip)
        if link == nil {
            let made = CADisplayLink(target: self, selector: #selector(frameShown(_:)))
            made.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
            link = made
        }
        return player.latest
    }

    /// Lets every clip go, and the display link with them.
    func closeAll() {
        open.values.forEach { $0.close() }
        open.removeAll()
        order.removeAll()
        link?.invalidate()
        link = nil
    }

    /// Each frame of the display: each player's new frame taken, the views
    /// playing clips drawn again when there was one, and the display link
    /// let go once nothing has asked for a while.
    @objc private func frameShown(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var landed = false
        for player in open.values {
            if player.tick(now) { landed = true }
        }
        if landed { VideoStore.liveFrameLanded() }
        if open.values.allSatisfy({ now - $0.askedAt > 2 }) {
            link.invalidate()
            self.link = nil
        }
    }
}
