import Foundation
import Supabase

/// Follows, likes, and saves are all the same shape underneath: check
/// whether a row exists for (actor, target), then insert or delete it and
/// keep a count in sync. Column names differ per table (`follower_id` vs
/// `user_id`, `followee_project_id` vs `project_id`), so call sites pass
/// those in rather than this trying to know every table's schema.
enum Engagement {
    static func count(table: String, filters: [String: any PostgrestFilterValue]) async throws -> Int {
        var query = SupabaseManager.shared.client.from(table).select("id", head: true, count: .exact)
        for (column, value) in filters {
            query = query.eq(column, value: value)
        }
        let response = try await query.execute()
        return response.count ?? 0
    }

    static func exists(table: String, filters: [String: any PostgrestFilterValue]) async throws -> Bool {
        try await count(table: table, filters: filters) > 0
    }

    static func insert(table: String, values: [String: UUID]) async throws {
        try await SupabaseManager.shared.client.from(table).insert(values).execute()
    }

    static func remove(table: String, filters: [String: any PostgrestFilterValue]) async throws {
        var query = SupabaseManager.shared.client.from(table).delete()
        for (column, value) in filters {
            query = query.eq(column, value: value)
        }
        try await query.execute()
    }
}
