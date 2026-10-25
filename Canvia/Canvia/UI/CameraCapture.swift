// The camera, straight into the design: a photo taken or a video recorded
// with the system camera, then brought in as a photo or clip picked from the
// library is — kept among your uploads, a photo at the size pictures are
// kept, a clip whole — and placed, or put in the frame being replaced, or
// behind the page. Offered only where the phone has a camera.

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraCapture: UIViewControllerRepresentable {
    enum Shot { case photo, video }

    enum Outcome {
        case photo(UIImage)
        /// The recording, copied out of the camera's own temporary file.
        case video(URL)
        case cancelled
        case failed
    }

    var mode: Shot
    /// Whether a video may be recorded at all: not for a page's background.
    var allowsVideo = true
    /// Called once, when the camera closes.
    var onFinish: (Outcome) -> Void

    /// Whether this phone has a camera to take a photo with.
    static var takesPhotos: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    /// Whether it can record a video too.
    static var recordsVideo: Bool {
        takesPhotos && (UIImagePickerController.availableMediaTypes(for: .camera) ?? []).contains(UTType.movie.identifier)
    }

    /// What is said when the camera closes with nothing taken, and when
    /// what was taken could not be kept.
    static var cancelledNote: String { tr("Nothing was taken") }
    static var failedNote: String { tr("Couldn't keep that. Your phone may be out of space.") }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        // Both kinds, so either can be switched to in the camera itself; it
        // opens on the one asked for.
        let video = allowsVideo && Self.recordsVideo
        picker.mediaTypes = video ? [UTType.image.identifier, UTType.movie.identifier] : [UTType.image.identifier]
        picker.videoQuality = .typeHigh
        picker.cameraCaptureMode = mode == .video && video ? .video : .photo
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Delegate { Delegate(onFinish: onFinish) }

    final class Delegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Outcome) -> Void
        init(onFinish: @escaping (Outcome) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let movie = info[.mediaURL] as? URL {
                // The camera's file goes when it closes: copied first.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(movie.pathExtension.isEmpty ? "mov" : movie.pathExtension)
                do {
                    try FileManager.default.copyItem(at: movie, to: copy)
                    onFinish(.video(copy))
                } catch {
                    onFinish(.failed)
                }
            } else if let image = info[.originalImage] as? UIImage {
                onFinish(.photo(image))
            } else {
                onFinish(.failed)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(.cancelled)
        }
    }

    /// What was taken, kept among your uploads as a picked photo or clip
    /// is — off the main actor — with its size and whether it is a clip;
    /// nil when it could not be kept.
    static func store(_ outcome: Outcome) async -> (src: String, natural: CGSize, isVideo: Bool)? {
        switch outcome {
        case .photo(let image):
            return await Task.detached(priority: .userInitiated) { () -> (src: String, natural: CGSize, isVideo: Bool)? in
                guard let data = image.jpegData(compressionQuality: 0.95),
                      let prepared = ImageDownsampler.prepare(data),
                      let src = MediaStore.store(prepared) else { return nil }
                Uploads.record(source: src)
                return (src, prepared.natural, false)
            }.value
        case .video(let url):
            return await Task.detached(priority: .userInitiated) { () -> (src: String, natural: CGSize, isVideo: Bool)? in
                defer { try? FileManager.default.removeItem(at: url) }
                guard let data = try? Data(contentsOf: url),
                      let id = VideoStore.store(data, ext: url.pathExtension),
                      let poster = VideoStore.poster(id) else { return nil }
                Uploads.record(id, kind: .video)
                VideoImport.optimiseSoon(id)
                return (VideoStore.src(id, at: nil), poster.size, true)
            }.value
        case .cancelled, .failed:
            return nil
        }
    }
}

/// "Take photo" and, where it can, "Record video": the tiles that open the
/// camera, in the Add sheet's style.
struct CameraTiles: View {
    /// Video too, or photos only (a page's background).
    var video = true
    var onOutcome: (CameraCapture.Outcome) -> Void
    @State private var capturing: CameraCapture.Shot?

    var body: some View {
        if CameraCapture.takesPhotos {
            HStack(spacing: 10) {
                tile(tr("Take photo"), symbol: "camera", mode: .photo)
                if video && CameraCapture.recordsVideo {
                    tile(tr("Record video"), symbol: "video", mode: .video)
                }
            }
            .fullScreenCover(isPresented: Binding(get: { capturing != nil }, set: { if !$0 { capturing = nil } })) {
                CameraCapture(mode: capturing ?? .photo, allowsVideo: video) { outcome in
                    capturing = nil
                    onOutcome(outcome)
                }
                .ignoresSafeArea()
            }
        }
    }

    private func tile(_ title: String, symbol: String, mode: CameraCapture.Shot) -> some View {
        Button {
            capturing = mode
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentSubtle))
        }
    }
}
