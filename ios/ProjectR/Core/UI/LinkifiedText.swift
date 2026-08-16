import SwiftUI

/// Plain `Text(someString)` never makes URLs tappable — that only happens
/// with an `AttributedString` carrying `.link` attributes, or a Markdown
/// literal. Chat messages are plain `String`s from the database, so shared
/// project links (see `ShareSheet`) would otherwise just sit there as
/// inert text. This finds URLs with `NSDataDetector` and links them,
/// leaving everything else as normal text.
struct LinkifiedText: View {
    let text: String

    var body: some View {
        Text(Self.attributedString(for: text))
    }

    private static func attributedString(for text: String) -> AttributedString {
        var attributed = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return attributed }

        let nsText = text as NSString
        let matches = detector.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches {
            guard let url = match.url, let range = Range(match.range, in: text) else { continue }
            let lower = text.distance(from: text.startIndex, to: range.lowerBound)
            let upper = text.distance(from: text.startIndex, to: range.upperBound)
            guard
                let attrLower = attributed.characters.index(
                    attributed.startIndex, offsetBy: lower, limitedBy: attributed.endIndex),
                let attrUpper = attributed.characters.index(
                    attributed.startIndex, offsetBy: upper, limitedBy: attributed.endIndex)
            else { continue }
            attributed[attrLower..<attrUpper].link = url
        }
        return attributed
    }
}
