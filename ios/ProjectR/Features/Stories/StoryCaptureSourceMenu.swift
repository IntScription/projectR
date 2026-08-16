import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Attach with `.storyCaptureSourceMenu(isPresented:onCaptured:)` — offers
/// Camera / Photo Library / Files, and hands back raw bytes plus which
/// kind of media it was, regardless of which source was picked, so the
/// caller (the composer) doesn't need to know how the media arrived.
extension View {
    func storyCaptureSourceMenu(
        isPresented: Binding<Bool>, onCaptured: @escaping (Data, StoryMediaKind) -> Void
    ) -> some View {
        modifier(StoryCaptureSourceMenuModifier(isPresented: isPresented, onCaptured: onCaptured))
    }
}

private struct StoryCaptureSourceMenuModifier: ViewModifier {
    @Binding var isPresented: Bool
    let onCaptured: (Data, StoryMediaKind) -> Void

    @State private var isPresentingCamera = false
    @State private var isPresentingLibraryPicker = false
    @State private var isPresentingFileImporter = false
    @State private var selectedLibraryItem: PhotosPickerItem?

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Add to Story", isPresented: $isPresented, titleVisibility: .visible) {
                Button("Camera") { isPresentingCamera = true }
                Button("Photo Library") { isPresentingLibraryPicker = true }
                Button("Files") { isPresentingFileImporter = true }
                Button("Cancel", role: .cancel) {}
            }
            .fullScreenCover(isPresented: $isPresentingCamera) {
                CameraCaptureView(onCapture: onCaptured)
                    .ignoresSafeArea()
            }
            .photosPicker(
                isPresented: $isPresentingLibraryPicker, selection: $selectedLibraryItem,
                matching: .any(of: [.images, .videos]))
            .task(id: selectedLibraryItem) {
                guard let selectedLibraryItem else { return }
                defer { self.selectedLibraryItem = nil }
                let kind: StoryMediaKind =
                    selectedLibraryItem.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })
                    ? .video : .image
                if let data = try? await selectedLibraryItem.loadTransferable(type: Data.self) {
                    onCaptured(data, kind)
                }
            }
            .fileImporter(isPresented: $isPresentingFileImporter, allowedContentTypes: [.image, .movie]) { result in
                guard case .success(let url) = result else { return }
                let isVideo = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
                    .contentType?.conforms(to: .movie) ?? false
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    onCaptured(data, isVideo ? .video : .image)
                }
            }
    }
}
