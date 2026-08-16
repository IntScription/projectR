import Supabase
import XCTest

@testable import ProjectR

final class ErrorPresentationTests: XCTestCase {
    func testUniqueConstraintViolationGetsRealCopy() {
        let error = PostgrestError(code: "23505", message: "duplicate key value violates unique constraint \"projects_slug_key\"")
        XCTAssertEqual(ErrorPresentation.message(for: error), "That already exists — try a different value.")
    }

    func testRowLevelSecurityViolationGetsRealCopy() {
        let error = PostgrestError(
            code: "42501", message: "new row violates row-level security policy for table \"comments\"")
        XCTAssertEqual(ErrorPresentation.message(for: error), "You don't have permission to do that.")
    }

    func testForeignKeyViolationGetsRealCopy() {
        let error = PostgrestError(code: "23503", message: "insert or update on table violates foreign key constraint")
        XCTAssertEqual(
            ErrorPresentation.message(for: error),
            "That can't be done — something it depends on no longer exists.")
    }

    func testUnknownPostgrestCodeFallsBackToTheRealMessage() {
        let error = PostgrestError(code: "99999", message: "some other real failure")
        XCTAssertEqual(ErrorPresentation.message(for: error), "some other real failure")
    }

    func testOfflineGetsRealCopy() {
        let error = URLError(.notConnectedToInternet)
        XCTAssertEqual(
            ErrorPresentation.message(for: error), "You're offline — check your connection and try again.")
    }

    func testTimeoutGetsRealCopy() {
        let error = URLError(.timedOut)
        XCTAssertEqual(ErrorPresentation.message(for: error), "That took too long — try again.")
    }

    func testUnrelatedErrorFallsBackToLocalizedDescription() {
        struct SomeOtherError: LocalizedError {
            var errorDescription: String? { "a totally different kind of failure" }
        }
        XCTAssertEqual(ErrorPresentation.message(for: SomeOtherError()), "a totally different kind of failure")
    }
}
