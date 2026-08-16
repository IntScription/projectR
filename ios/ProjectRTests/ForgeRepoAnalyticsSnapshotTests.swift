import XCTest

@testable import ProjectR

/// Regression guard for a real, non-obvious bug avoided during
/// development: `captured_at` is a plain SQL `date` column
/// (`"2026-08-16"`, no time component), and Supabase's default
/// `JSONDecoder` only understands full ISO 8601 timestamps — decoding
/// this field as `Date` directly would throw on every real row. It's
/// decoded as `String` instead, with a dedicated formatter for the
/// `capturedAt` computed property.
final class ForgeRepoAnalyticsSnapshotTests: XCTestCase {
    func testDecodesARealSupabaseRowIncludingTheBareDateColumn() throws {
        let json = """
            {"captured_at": "2026-08-16", "stars": 3770, "open_issues": 6889, "forks": 6499, "watchers": 1737}
            """
        // A plain decoder is exactly the point: `captured_at` decoding as
        // `String` means no date-parsing strategy is involved at all here
        // — if it were typed `Date` instead, Supabase's real client-side
        // decoder (which only understands full ISO-8601 timestamps) would
        // throw on this exact bare-date value.
        let snapshot = try JSONDecoder().decode(ForgeRepoAnalyticsSnapshot.self, from: Data(json.utf8))

        XCTAssertEqual(snapshot.stars, 3770)
        XCTAssertEqual(snapshot.capturedAtRaw, "2026-08-16")
        let date = try XCTUnwrap(snapshot.capturedAt)
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date)
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 8)
        XCTAssertEqual(components.day, 16)
    }
}
