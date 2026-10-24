// What a page's background can be, as the Background sheet and the Add
// sheet's Background tab both offer it: the default colours, a colour of
// your own, the brand kit's, the gradients, your own photos, the built-in
// pictures and the generated motion loops, which play behind the page as it
// does — and a picture already behind the page, taken back out as a photo;
// a clip playing behind the page, its Clip controls — trim, speed, loop, volume —
// over the rest. As the Android twin's background panel offers them.

import SwiftUI
import PhotosUI

struct BackgroundChoices: View {
    @Bindable var store: DesignStore
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    private let photoColumns = [GridItem(.adaptive(minimum: 90), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let clip = store.page.backgroundClip, clip.isVideo {
                BackgroundClipControls(store: store, clip: clip)
            }
            BackgroundDetachButton(store: store)

            Text("Solid colours").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(ContentLibrary.defaultSwatches, id: \.self) { hex in
                    BackgroundSwatch(store: store, hex: hex)
                }
            }
            BackgroundColourChoices(store: store, columns: columns)

            Text("Gradients").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            BackgroundGradients(store: store, columns: columns)

            BackgroundYourPhotos(store: store, columns: photoColumns)

            // One child of the stack (ViewBuilder's limit), laid out as two.
            Group {
                Text("Photos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: photoColumns, spacing: 10) {
                    ForEach(PhotoLibrary.photos) { photo in
                        BackgroundPhotoTile(store: store, photo: photo)
                    }
                }
            }
            BackgroundVideos(store: store)
        }
    }
}

/// The generated motion loops as the page's background, the one behind it
/// ringed.
struct BackgroundVideos: View {
    @Bindable var store: DesignStore

    var body: some View {
        Text("Videos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
        MotionGrid(loops: MotionLibrary.loops, current: current) { loop in
            store.setBackground(.image(MotionLibrary.src(loop.id, at: nil)))
        }
    }

    private var current: String? {
        if case .image(let src) = store.page.background { return src }
        return nil
    }
}

/// One colour as the page's background: named for VoiceOver, ringed when it
/// is the one behind the page, and not applied again when it already is.
struct BackgroundSwatch: View {
    @Bindable var store: DesignStore
    let hex: String

    var body: some View {
        let chosen = store.page.background == .color(hex)
        Button {
            store.setBackground(.color(hex))
        } label: {
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(hex: hex))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .stroke(chosen ? Theme.accent : Color.black.opacity(0.12), lineWidth: chosen ? 3 : 1))
                .frame(height: 40)
        }
        .accessibilityLabel(ElementNames.spokenColour(hex))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A colour of your own, through the colour sheet — its wheel, eyedropper,
/// recents and companions — and the brand kit's colours when it has any.
struct BackgroundColourChoices: View {
    @Bindable var store: DesignStore
    var columns: [GridItem]
    @State private var choosing = false

    /// The page's colour, when its background is one.
    private var current: String? {
        if case .color(let hex) = store.page.background { return hex }
        return nil
    }

    var body: some View {
        let kit = BrandKit.load()
        VStack(alignment: .leading, spacing: 10) {
            Button {
                choosing = true
            } label: {
                Label("Custom colour", systemImage: "paintpalette")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
            .sheet(isPresented: $choosing) {
                // The wheel changes the page as it turns, and the sheet keeps
                // the whole turn as one step when it closes.
                ColorPickerSheet(store: store, title: tr("Background colour"), current: current,
                                 onPick: { hex in store.setBackground(.color(hex)) },
                                 onPickTransient: { hex in store.setBackgroundTransient(.color(hex)) })
            }
            // The active brand kit's palettes, each by name.
            ForEach(Array(kit.palettes.enumerated()), id: \.offset) { _, palette in
                if !palette.colors.isEmpty {
                    Text(kit.title(of: palette)).font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(palette.colors, id: \.self) { hex in
                            BackgroundSwatch(store: store, hex: hex)
                        }
                    }
                }
            }
        }
    }
}

/// Your own photos behind the page: every picture brought in so far, and a
/// new one picked from the library, stored as a media: source as any photo
/// is and made the background.
struct BackgroundYourPhotos: View {
    @Bindable var store: DesignStore
    var columns: [GridItem]
    @State private var picked: PhotosPickerItem?
    @State private var loading = false

    var body: some View {
        let uploads = MediaStore.all()
        VStack(alignment: .leading, spacing: 10) {
            Text("Your photos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            PhotosPicker(selection: $picked, matching: .images) {
                Label(loading ? tr("Bringing it in…") : tr("Choose a photo"), systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
            .disabled(loading)
            // A photo taken now, behind the page; a background is no clip.
            CameraTiles(video: false) { outcome in takePhoto(outcome) }
            if !uploads.isEmpty {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(uploads.enumerated()), id: \.element) { index, id in
                        tile(id, index: index, count: uploads.count)
                    }
                }
            }
        }
        .onChange(of: picked) { _, item in
            guard let item else { return }
            picked = nil
            bringIn(item)
        }
    }

    private func tile(_ id: String, index: Int, count: Int) -> some View {
        let src = "media:\(id)"
        let chosen = store.page.background == .image(src)
        return Button {
            store.setBackground(.image(src))
        } label: {
            Group {
                if let ui = MediaStore.load(id) {
                    Image(uiImage: PhotoLibrary.preview(ui, key: src))
                        .resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color(.systemGray5)
                }
            }
            .frame(height: 68)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 9))
            .overlay { if chosen { RoundedRectangle(cornerRadius: 9).stroke(Theme.accent, lineWidth: 3) } }
        }
        .accessibilityLabel("Background, \(AddSheetNames.upload(index, of: count))")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The picked photo stored — decoded, scaled and encoded off the main
    /// actor, as the Add sheet stores one — and made the background.
    private func bringIn(_ item: PhotosPickerItem) {
        loading = true
        let store = self.store
        Task {
            let saved = await Self.stored(item)
            loading = false
            guard let src = saved else {
                store.buzz(.reject)
                store.announce(tr("Couldn't open that photo"), undoable: false)
                return
            }
            store.setBackground(.image(src))
            store.buzz(.confirm)
        }
    }

    /// A photo from the camera, kept among your uploads as one picked is,
    /// and made the background.
    private func takePhoto(_ outcome: CameraCapture.Outcome) {
        let store = self.store
        if case .cancelled = outcome {
            store.announce(CameraCapture.cancelledNote, undoable: false)
            return
        }
        loading = true
        Task {
            let saved = await CameraCapture.store(outcome)
            loading = false
            guard let saved, !saved.isVideo else {
                store.buzz(.reject)
                store.announce(CameraCapture.failedNote, undoable: false)
                return
            }
            store.setBackground(.image(saved.src))
            store.buzz(.confirm)
        }
    }

    /// Kept among your uploads, as a photo picked in the Add sheet is, so
    /// the launch sweep never takes it once the background changes. The
    /// Text controls' Photo pours one picked the same way (ContextToolbar).
    static func stored(_ item: PhotosPickerItem) async -> String? {
        guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> String? in
            guard let prepared = ImageDownsampler.prepare(data),
                  let src = MediaStore.store(prepared) else { return nil }
            Uploads.record(source: src)
            return src
        }.value
    }
}

/// The page's background picture, when it has one, taken back out as a
/// photo covering the page — to move, crop, filter or frame like any other.
struct BackgroundDetachButton: View {
    @Bindable var store: DesignStore
    @Environment(\.dismiss) private var dismiss

    private var hasPicture: Bool {
        if case .image = store.page.background { return true }
        return false
    }

    var body: some View {
        if hasPicture {
            Button {
                store.detachBackground()
                // Out of the way, so the photo it made is seen, selected.
                dismiss()
            } label: {
                Label("Detach from background", systemImage: "square.on.square.dashed")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
        }
    }
}

/// A clip playing behind the page (BackgroundClip): its trim over the clip's
/// length, its speed, its volume and sound — each change one step, as the
/// Clip sheet makes them for a clip on the page.
struct BackgroundClipControls: View {
    @Bindable var store: DesignStore
    let clip: BackgroundClip
    /// The clip's length in seconds, once read.
    @State private var length: Double?
    @State private var draftVolume: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clip").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            trim
            speed
            Toggle("Loop", isOn: Binding(get: { clip.playback.loop },
                                         set: { on in store.updateBackgroundClip { $0.loop = on } }))
            StepSlider(label: tr("Volume"), stored: min(max(clip.playback.volume, 0), 1), range: 0...1, step: 0.1,
                       draft: $draftVolume, readout: ClipSheet.percentLabel) { v in
                store.updateBackgroundClip { $0.volume = (min(max(v, 0), 1) * 100).rounded() / 100 }
            }
            Toggle("Mute", isOn: Binding(get: { clip.playback.muted },
                                         set: { on in store.updateBackgroundClip { $0.muted = on } }))
        }
        .font(.subheadline)
        .task(id: clip.src) {
            guard let id = VideoStore.split(clip.src)?.id else { return }
            length = await VideoStore.loadedDuration(of: id)
        }
    }

    @ViewBuilder
    private var trim: some View {
        if let length, length > ClipPlayback.minLength {
            let start = min(max(0, clip.playback.start), length)
            let end = min(clip.playback.end ?? length, length)
            TrimmerBar(length: length, start: start, end: end, minLength: ClipPlayback.minLength,
                       commit: { s, e in commitTrim(s, e, length: length) }) {
                Rectangle().fill(Color(.systemGray5))
            }
            .accessibilityLabel("Trim")
        }
    }

    private var speed: some View {
        Picker("Speed", selection: Binding(get: { clip.playback.speed },
                                           set: { v in store.updateBackgroundClip { $0.speed = v } })) {
            ForEach(ClipPlayback.speeds, id: \.self) { Text(MotionPath.speedLabel($0)).tag($0) }
        }
        .pickerStyle(.menu)
    }

    /// The trim let go at, to a tenth, an end at the clip's own end kept as
    /// none, as one step.
    private func commitTrim(_ start: Double, _ end: Double, length: Double) {
        let kept = Timeline.trimmed(from: start, to: end, duration: length)
        store.updateBackgroundClip { playback in
            playback.start = kept.start
            playback.end = kept.end
        }
    }
}
