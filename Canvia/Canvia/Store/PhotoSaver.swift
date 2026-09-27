// Saving exports straight into the Photos library.
//
// The share sheet can do this too, three taps later. A design tool's exports
// are pictures; the place people keep pictures is Photos; the button belongs
// next to the export.
//
// Add-only access is all that is asked for. Reading the library is neither
// needed nor wanted, and the narrower permission is the one people say yes
// to. The Android twin files its saves under Pictures/Canvia, which costs it
// no permission at all; here an album can only be made or added to with
// full access to the library, so a "Canvia" album is used only when the
// person has already given full access in Settings. Nobody is asked to let
// a design app read every photo they own just so its exports sit together.
//
// Each file goes in on its own and is counted, so a save that stops part way
// — one file Photos refuses, or a Cancel — says how many went in rather than
// all or nothing.

import Photos
import UniformTypeIdentifiers

enum PhotoSaver {

    enum Failure: LocalizedError {
        case denied, unsupported, failed(String)

        var errorDescription: String? {
            switch self {
            case .denied:
                return "Canvia isn't allowed to add to your photo library. You can change that in Settings."
            case .unsupported:
                return "Only PNG, JPEG, GIF and MP4 can be saved to Photos."
            case .failed(let why):
                return "Photos couldn't save it (\(why))."
            }
        }
    }

    /// The album saves go into, when the library allows one.
    static let albumTitle = "Canvia"

    /// What Photos will accept, by file extension. PDF and SVG are documents,
    /// and Photos refuses them outright rather than storing them as files.
    static func canSave(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    static func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    /// How a save went: how many of how many went in, and whether it was cut
    /// short by a Cancel.
    struct Outcome: Equatable {
        var saved: Int
        var total: Int
        var cancelled = false

        /// What the sheet says, as the Android twin words it: one photo, some
        /// of several, all of several — or nothing, when none went in. Nil
        /// after a Cancel that saved nothing, which needs no words.
        var message: String? {
            if saved == 0 { return cancelled ? nil : "Couldn't save to your photos" }
            if total == 1 { return "Saved to your photos" }
            if saved < total { return "Saved \(saved) of \(total) photos" }
            return "Saved \(total) photos"
        }

        /// True when at least one file went in.
        var anySaved: Bool { saved > 0 }
    }

    /// Saves each file in turn, counting what goes in. A Cancel stops between
    /// files and is reported in the outcome rather than thrown, so what was
    /// already saved is still said. Throws only when nothing can be saved at
    /// all: no file Photos takes, or no permission.
    static func save(_ urls: [URL]) async throws -> Outcome {
        let eligible = urls.filter(canSave)
        guard !eligible.isEmpty else { throw Failure.unsupported }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }

        let album = await canviaAlbum()
        var outcome = Outcome(saved: 0, total: eligible.count)
        for url in eligible {
            if Task.isCancelled {
                outcome.cancelled = true
                break
            }
            if await saveOne(url, into: album) { outcome.saved += 1 }
        }
        return outcome
    }

    /// One file into the library, and into the album when there is one.
    /// False when Photos refused it.
    private static func saveOne(_ url: URL, into album: PHAssetCollection?) async -> Bool {
        let video = isVideo(url)
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = video
                    ? PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    : PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                if let album,
                   let placeholder = request?.placeholderForCreatedAsset,
                   let albumChange = PHAssetCollectionChangeRequest(for: album) {
                    albumChange.addAssets([placeholder] as NSArray)
                }
            }
            return true
        } catch {
            return false
        }
    }

    /// The "Canvia" album, found or made — only with full access to the
    /// library, which is never asked for here. Nil otherwise, and the save
    /// goes on without it.
    private static func canviaAlbum() async -> PHAssetCollection? {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else { return nil }
        if let found = findAlbum() { return found }
        let made = CreatedAlbum()
        do {
            try await PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: albumTitle)
                made.identifier = request.placeholderForCreatedAssetCollection.localIdentifier
            }
        } catch {
            return nil
        }
        guard let identifier = made.identifier else { return nil }
        return PHAssetCollection.fetchAssetCollections(withLocalIdentifiers: [identifier], options: nil).firstObject
    }

    private static func findAlbum() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", albumTitle)
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular,
                                                       options: options).firstObject
    }

    /// The new album's identifier, set inside the change block.
    private final class CreatedAlbum: @unchecked Sendable {
        var identifier: String?
    }
}
