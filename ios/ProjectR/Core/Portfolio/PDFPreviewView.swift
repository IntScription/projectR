import PDFKit
import SwiftUI

/// A real preview of the generated portfolio before it goes anywhere —
/// `PortfolioBuilderView` used to jump straight from "Generate PDF" to
/// the share sheet, with no way to actually see the document first. Owns
/// its own share sheet rather than relying on the presenter to chain a
/// second sheet after dismissing this one, which is flaky in SwiftUI.
struct PDFPreviewView: View {
    let url: URL

    @State private var isPresentingShareSheet = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PDFKitRepresentable(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("Portfolio Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPresentingShareSheet = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share portfolio")
                }
            }
            .sheet(isPresented: $isPresentingShareSheet) {
                ActivityShareSheet(items: [url]) {}
            }
    }
}

private struct PDFKitRepresentable: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // The file at `url` is overwritten in place on every "Generate
        // PDF" (same filename, `Portfolio.pdf`) — reloading unconditionally
        // is what picks up a regenerated document if this view happens to
        // stick around across a re-generate.
        uiView.document = PDFDocument(url: url)
    }
}
