import Foundation

/// Real metadata (`og:` tags a site itself published), not fabricated —
/// used as a fallback enrichment source for a project's website link when
/// there's no GitHub URL to pull from instead. Simple regex extraction
/// rather than a full HTML parser: `og:*` meta tags are single, predictable
/// self-closing elements, not something that needs a DOM to read reliably.
enum WebsiteMetadataService {
    struct Metadata {
        var title: String?
        var description: String?
        var imageURL: String?
    }

    static func fetch(url: String) async -> Metadata? {
        guard let requestURL = URL(string: url) else { return nil }
        var request = URLRequest(url: requestURL)
        request.setValue(
            "Mozilla/5.0 (compatible; ProjectRBot/1.0)", forHTTPHeaderField: "User-Agent")

        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
            let html = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        let metadata = Metadata(
            title: metaContent(in: html, property: "og:title") ?? titleTag(in: html),
            description: metaContent(in: html, property: "og:description")
                ?? metaContent(in: html, property: "description", attribute: "name"),
            imageURL: metaContent(in: html, property: "og:image")
        )
        guard metadata.title != nil || metadata.description != nil || metadata.imageURL != nil
        else { return nil }
        return metadata
    }

    private static func metaContent(
        in html: String, property: String, attribute: String = "property"
    ) -> String? {
        // Matches both attribute orderings a site might use:
        //   <meta property="og:title" content="...">
        //   <meta content="..." property="og:title">
        let patterns = [
            #"<meta[^>]*\#(attribute)=["']\#(property)["'][^>]*content=["']([^"']*)["']"#,
            #"<meta[^>]*content=["']([^"']*)["'][^>]*\#(attribute)=["']\#(property)["']"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            else { continue }
            let range = NSRange(html.startIndex..., in: html)
            if let match = regex.firstMatch(in: html, range: range),
                let contentRange = Range(match.range(at: 1), in: html)
            {
                return decodeHTMLEntities(String(html[contentRange]))
            }
        }
        return nil
    }

    private static func titleTag(in html: String) -> String? {
        guard
            let regex = try? NSRegularExpression(
                pattern: "<title[^>]*>([^<]*)</title>", options: .caseInsensitive)
        else { return nil }
        let range = NSRange(html.startIndex..., in: html)
        guard let match = regex.firstMatch(in: html, range: range),
            let titleRange = Range(match.range(at: 1), in: html)
        else { return nil }
        return decodeHTMLEntities(String(html[titleRange]))
    }

    private static func decodeHTMLEntities(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
