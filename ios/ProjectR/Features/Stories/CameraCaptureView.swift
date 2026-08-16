import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Wraps `UIImagePickerController`'s camera source — nothing else in the
/// app drives the camera today (everything else is `PhotosPicker`, which
/// only reaches the library), so this is genuinely new. Handles both
/// still photos and video capture in one picker, matching the
/// "camera, photos, or files" source list stories are meant to offer.
struct CameraCaptureView: UIViewControllerRepresentable {
    var onCapture: (Data, StoryMediaKind) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = [UTType.image.identifier, UTType.movie.identifier]
        picker.videoQuality = .typeHigh
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraCaptureView
        init(_ parent: CameraCaptureView) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data, .image)
            } else if let url = info[.mediaURL] as? URL, let data = try? Data(contentsOf: url) {
                parent.onCapture(data, .video)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
