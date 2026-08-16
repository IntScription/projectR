import Foundation

enum Validation {
    /// Matches the `username_format` CHECK constraint on `profiles` in the
    /// migration — checked here too so the UI can reject bad input before a
    /// round trip, not because the client check is the source of truth.
    static func isValidUsername(_ username: String) -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        let allowedCharacters = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_")
        return (3...30).contains(trimmed.count)
            && trimmed.unicodeScalars.allSatisfy(allowedCharacters.contains)
    }
}
