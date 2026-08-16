import Foundation
import Supabase

/// Maps real, known failure modes to copy someone would actually
/// understand — `error.localizedDescription` alone is fine for most
/// `URLError`s (Foundation's own text is already reasonable), but a raw
/// `PostgrestError` reads as "the app broke" rather than something
/// actionable: a unique-constraint violation shows Postgres's own
/// constraint name, a row-level-security rejection shows "new row
/// violates row-level security policy for table X." Neither means
/// anything to someone who didn't write the schema.
enum ErrorPresentation {
    static func message(for error: Error) -> String {
        if let postgrestError = error as? PostgrestError {
            return message(for: postgrestError)
        }
        if let urlError = error as? URLError {
            return message(for: urlError)
        }
        return error.localizedDescription
    }

    private static func message(for error: PostgrestError) -> String {
        switch error.code {
        case "23505":
            return "That already exists — try a different value."
        case "42501":
            return "You don't have permission to do that."
        case "23503":
            return "That can't be done — something it depends on no longer exists."
        default:
            return error.message
        }
    }

    private static func message(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "You're offline — check your connection and try again."
        case .timedOut:
            return "That took too long — try again."
        default:
            return error.localizedDescription
        }
    }
}
