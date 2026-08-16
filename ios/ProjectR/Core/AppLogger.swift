import OSLog

/// Centralized logging so failures that were previously swallowed silently
/// with `try?` at least land in the device console / Console.app and
/// Xcode's Organizer crash-adjacent logs in production, instead of
/// vanishing with zero trace. Not a replacement for a real crash/error
/// reporting service (Sentry, etc.) — that needs an account and a DSN key,
/// which is a "before launch" task for a human, not something to wire up
/// blind. This is the free, no-account baseline every call site should at
/// least have.
enum AppLogger {
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let upload = Logger(subsystem: subsystem, category: "upload")
    static let github = Logger(subsystem: subsystem, category: "github")
    static let moderation = Logger(subsystem: subsystem, category: "moderation")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let stories = Logger(subsystem: subsystem, category: "stories")

    private static let subsystem = "com.mrk.projectr"
}
