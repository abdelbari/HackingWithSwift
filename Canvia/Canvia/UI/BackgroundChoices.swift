// What a page's background can be, as the Background sheet and the Add
// sheet's Background tab both offer it: the default colours, a colour of
// your own, the brand kit's, the gradients, your own photos and the built-in
// pictures — and a picture already behind the page, taken back out as a
// photo. As the Android twin's background panel offers them.

import SwiftUI
import PhotosUI

struct BackgroundChoices: View {
    @Bindable var store: DesignStore
    private let columns = [GridItem(.adaptive(minimum: 40), spacing: 10)]
    private let photoColumns = [GridItem(.adaptive(minimum: 90), spacing: 10)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
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

            Text("Photos").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
            LazyVGrid(columns: photoColumns, spacing: 10) {
                ForEach(PhotoLibrary.photos) { photo in
                    BackgroundPhotoTile(store: store, photo: photo)
                }
            }
        }
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
        let brand = BrandKit.load().colors
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
                ColorPickerSheet(store: store, title: "Background colour", current: current,
                                 onPick: { hex in store.setBackground(.color(hex)) },
                                 onPickTransient: { hex in store.setBackgroundTransient(.color(hex)) })
            }
            if !brand.isEmpty {
                Text("Brand colours").font(.footnote.weight(.bold)).foregroundStyle(.secondary)
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(brand, id: \.self) { hex in
                        BackgroundSwatch(store: store, hex: hex)
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
                Label(loading ? "Bringing it in…" : "Choose a photo", systemImage: "photo.badge.plus")
                    .frame(maxWidth: .infinity)
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
            }
            .disabled(loading)
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
                store.announce("Couldn't open that photo", undoable: false)
                return
            }
            store.setBackground(.image(src))
            store.buzz(.confirm)
        }
    }

    /// Kept among your uploads, as a photo picked in the Add sheet is, so
    /// the launch sweep never takes it once the background changes.
    private static func stored(_ item: PhotosPickerItem) async -> String? {
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
