// Saving exports straight into the Photos library.
//
// The share sheet can do this too, three taps later. A design tool's exports
// are pictures; the place people keep pictures is Photos; the button belongs
// next to the export.
//
// Add-only access is all that is asked for. Reading the library is neither
// needed nor wanted, and the narrower permission is the one people say yes
// to.

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

    /// What Photos will accept, by file extension. PDF and SVG are documents,
    /// and Photos refuses them outright rather than storing them as files.
    static func canSave(_ url: URL) -> Bool {
        ["png", "jpg", "jpeg", "gif", "mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    static func isVideo(_ url: URL) -> Bool {
        ["mp4", "mov"].contains(url.pathExtension.lowercased())
    }

    static func save(_ urls: [URL]) async throws {
        let eligible = urls.filter(canSave)
        guard !eligible.isEmpty else { throw Failure.unsupported }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else { throw Failure.denied }

        do {
            try await PHPhotoLibrary.shared().performChanges {
                for url in eligible {
                    if isVideo(url) {
                        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
                    } else {
                        PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url)
                    }
                }
            }
        } catch {
            throw Failure.failed(error.localizedDescription)
        }
    }
}
