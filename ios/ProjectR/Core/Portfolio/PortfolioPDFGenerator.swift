import Foundation
import WebKit

/// Renders a real, "official use"-ready portfolio PDF entirely on-device:
/// an HTML document built from the profile's/projects' real data, printed
/// to PDF via `WKWebView`'s native PDF export (the same underlying
/// rendering pipeline as AirPrint/"Print to PDF" — long content paginates
/// automatically). Saved to Documents, not Application Support — unlike
/// Forge's local git clones, this is meant to be visible/exportable, and
/// `ActivityShareSheet` (already built) is what actually gets it onto the
/// user's device via Save to Files/AirDrop/Mail.
enum PortfolioPDFGenerator {
    struct ProjectMetrics {
        var stars: Int?
        var contributors: Int?
    }

    static let fileName = "Portfolio.pdf"

    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
    }

    static var lastGeneratedAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.modificationDate]) as? Date
    }

    @MainActor
    static func generate(
        profile: Profile, level: ProfileLevel?, achievement: Achievement?, projects: [Project],
        metrics: [UUID: ProjectMetrics]
    ) async throws -> URL {
        let html = PortfolioHTMLTemplate.build(
            profile: profile, level: level, achievement: achievement, projects: projects, metrics: metrics)
        let data = try await renderPDF(html: html)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    @MainActor
    private static func renderPDF(html: String) async throws -> Data {
        // US Letter at 72dpi. Content taller than one page paginates
        // automatically — no manual page-splitting needed.
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792))
        let delegate = PortfolioPDFNavigationDelegate()
        webView.navigationDelegate = delegate

        return try await withCheckedThrowingContinuation { continuation in
            delegate.onFinish = {
                Task { @MainActor in
                    do {
                        let data = try await webView.pdf(configuration: WKPDFConfiguration())
                        continuation.resume(returning: data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            delegate.onFail = { error in continuation.resume(throwing: error) }
            webView.loadHTMLString(html, baseURL: nil)
        }
    }
}

/// Kept outside `PortfolioPDFGenerator` since `WKNavigationDelegate`
/// conformance needs a real class instance the delegate callbacks can
/// hold a reference to for the continuation's lifetime.
private final class PortfolioPDFNavigationDelegate: NSObject, WKNavigationDelegate {
    var onFinish: (() -> Void)?
    var onFail: ((Error) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onFail?(error)
    }
    func webView(
        _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error
    ) {
        onFail?(error)
    }
}
