import Foundation
import Sentry

/// Thin wrapper over the Sentry SDK — call sites never reference
/// `SentrySDK` directly, so a future vendor swap only touches this file.
/// Configured but a documented no-op (logs locally instead of sending
/// anywhere) until `SENTRY_DSN` is set in the active xcconfig — same
/// "blank secret = graceful no-op" pattern already used for
/// APNS_KEY_ID/ANTHROPIC_API_KEY, rather than crashing or silently doing
/// nothing.
enum CrashReporter {
    // `configure()` runs exactly once, synchronously, from the app's
    // `init()` before anything else touches this — genuinely safe despite
    // being mutable global state, which is what this attribute is for.
    nonisolated(unsafe) private static var isConfigured = false

    static func configure() {
        guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String, !dsn.isEmpty else {
            print("CrashReporter: SENTRY_DSN not configured — crash reporting is a local no-op.")
            return
        }
        SentrySDK.start { options in
            options.dsn = dsn
            options.tracesSampleRate = 0.2
            // Debug builds always run against the local Supabase stack
            // (Config.local.xcconfig), Release always against production
            // (Config.production.xcconfig) — the same signal already
            // decides which backend a build talks to, so it's the correct
            // one for this too. Without this, a crash from your own
            // simulator during development is indistinguishable in
            // Sentry from a real user's.
            #if DEBUG
                options.environment = "development"
            #else
                options.environment = "production"
            #endif
            // Sentry's own convention: "<bundle-id>@<version>+<build>" —
            // lets a crash be pinned to the exact build that produced it,
            // not just "some version of the app."
            let bundle = Bundle.main
            let bundleID = bundle.bundleIdentifier ?? "unknown"
            let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
            let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            options.releaseName = "\(bundleID)@\(version)+\(build)"
        }
        isConfigured = true
    }

    /// Sentry captures unhandled crashes automatically once `configure()`
    /// has run — this is for the other half: real failures a `catch`
    /// block already recovered from, which would otherwise be invisible
    /// (the user sees an inline error message; nobody else ever finds
    /// out it happened).
    static func capture(_ error: Error, context: String? = nil) {
        guard isConfigured else {
            print("CrashReporter (no-op): \(context.map { "[\($0)] " } ?? "")\(error)")
            return
        }
        SentrySDK.capture(error: error) { scope in
            if let context { scope.setTag(value: context, key: "context") }
        }
    }
}
