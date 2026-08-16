import Foundation
import Supabase

/// Lightweight, self-hosted event log — every event lands in our own
/// `analytics_events` table via a normal authenticated insert, no new
/// vendor/SDK, no extra cost, fits an app that's otherwise entirely
/// Supabase already. Fire-and-forget: failures are swallowed (`try?`)
/// since a missed analytics row should never be visible to the user or
/// block whatever real action they were taking.
enum AnalyticsService {
    static func track(_ eventName: String, properties: [String: AnyJSON] = [:]) {
        guard let profileID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return }
        let event = NewAnalyticsEvent(profileID: profileID, eventName: eventName, properties: properties)
        Task {
            await insert(event)
        }
    }

    // Split out from `track` so the `Task { }` closure above only ever
    // awaits a plain `Void`-returning call — `PostgrestResponse<Void>`
    // (what `.execute()` produces without a decode target) isn't
    // `Sendable`, which Swift 6 only objects to when that value would
    // have to cross into the `Task`'s own `@Sendable` closure directly.
    private static func insert(_ event: NewAnalyticsEvent) async {
        try? await SupabaseManager.shared.client
            .from("analytics_events")
            .insert(event)
            .execute()
    }
}

private struct NewAnalyticsEvent: Encodable {
    let profileID: UUID
    let eventName: String
    let properties: [String: AnyJSON]

    enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case eventName = "event_name"
        case properties
    }
}
