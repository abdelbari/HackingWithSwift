// Add's Gallery (DeviceGallery): the system's inline photo picker at the top
// of Add ▸ Photos and Add ▸ Videos, under a row of filter chips. A tap on
// one brings it in at once through the sheet's own import (`onPick`), into
// the selected empty frames first; Select turns on picking several, ticked
// in the order picked, and Add N brings them in in that order. Held and
// dragged out of the picker onto the page, a photo or a clip lands there, or
// in the frame it is let go over, through the page's own drop (CanvasDrop).
// It asks for no permission: the picker shows the library in its own process
// and hands over only what is picked. The sheet's Add photos or video button
// stays beside it as the fallback.

import PhotosUI
import SwiftUI

struct DeviceGallerySection: View {
    /// Add ▸ Videos: it opens on Videos.
    var videosTab = false
    /// Picked ones, in the order picked, to bring in.
    var onPick: ([PhotosPickerItem]) -> Void

    @State private var filter: DeviceGallery.Choice?
    @State private var picks: [PhotosPickerItem] = []
    @State private var selecting = false

    private var shown: DeviceGallery.Choice { filter ?? DeviceGallery.startFilter(videosTab: videosTab) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            chips
            picker
            if selecting && !picks.isEmpty {
                Button(DeviceGallery.addLabel(picks.count)) { bringIn() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: picks) {
            // A tap brings one in at once; while selecting, they wait for Add.
            if !selecting && !picks.isEmpty { bringIn() }
        }
    }

    private var header: some View {
        HStack {
            InsertSheet.header(tr("Gallery"))
            Spacer()
            Button(selecting ? tr("Done") : tr("Select")) {
                selecting.toggle()
                picks = []
            }
            .font(.subheadline)
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DeviceGallery.filters(favourites: false)) { option in chip(option) }
            }
        }
    }

    private func chip(_ option: DeviceGallery.Choice) -> some View {
        let on = option == shown
        return Button {
            filter = option
            picks = []
        } label: {
            Text(tr(option.label))
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(on ? Theme.accent : Theme.card, in: Capsule())
                .foregroundStyle(on ? Color.white : Theme.ink)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The library, newest first, inline: one at a time, or — selecting —
    /// up to ten, ticked in the order picked.
    private var picker: some View {
        PhotosPicker(selection: $picks, maxSelectionCount: selecting ? DeviceGallery.maxPicks : 1,
                     selectionBehavior: .ordered, matching: matching, photoLibrary: .shared()) {
            Text("Gallery")
        }
        .photosPickerStyle(.inline)
        .photosPickerDisabledCapabilities([.selectionActions])
        .photosPickerAccessoryVisibility(.hidden, edges: .all)
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var matching: PHPickerFilter {
        switch shown {
        case .photos: return .images
        case .videos: return .videos
        case .all, .favourites: return .any(of: [.images, .videos])
        }
    }

    private func bringIn() {
        let items = picks
        picks = []
        selecting = false
        onPick(items)
    }
}
