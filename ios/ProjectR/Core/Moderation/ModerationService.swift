import Foundation

enum ModerationService {
    /// Bidirectional — true whether the caller blocked the target or the
    /// target blocked the caller. Used to decide whether to show Follow/
    /// Message at all (the backend rejects either direction regardless).
    static func isBlocked(profileID: UUID) async -> Bool {
        (try? await SupabaseManager.shared.client
            .rpc("is_blocked", params: TargetProfileParams(targetProfileID: profileID))
            .execute()
            .value) ?? false
    }

    /// Directed — only true if *I* blocked them. `blocked_profiles`' RLS
    /// permits selecting your own outgoing blocks directly, so this is a
    /// plain table read rather than another RPC. Used to decide whether a
    /// menu should read "Block" or "Unblock."
    static func haveIBlocked(profileID: UUID) async -> Bool {
        guard let myID = SupabaseManager.shared.client.auth.currentSession?.user.id else { return false }
        let rows: [BlockRow]? =
            try? await SupabaseManager.shared.client
            .from("blocked_profiles")
            .select("blocker_id")
            .eq("blocker_id", value: myID)
            .eq("blocked_id", value: profileID)
            .execute()
            .value
        return !(rows ?? []).isEmpty
    }

    static func block(profileID: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.client
                .rpc("block_profile", params: TargetProfileParams(targetProfileID: profileID))
                .execute()
            return true
        } catch {
            AppLogger.moderation.error("block_profile failed: \(error.localizedDescription)")
            return false
        }
    }

    static func unblock(profileID: UUID) async -> Bool {
        do {
            try await SupabaseManager.shared.client
                .rpc("unblock_profile", params: TargetProfileParams(targetProfileID: profileID))
                .execute()
            return true
        } catch {
            AppLogger.moderation.error("unblock_profile failed: \(error.localizedDescription)")
            return false
        }
    }

    static func report(
        targetType: ReportTargetType, targetID: UUID, reason: ReportReason, details: String?
    ) async -> Bool {
        do {
            try await SupabaseManager.shared.client
                .rpc(
                    "submit_report",
                    params: SubmitReportParams(
                        targetType: targetType.rawValue, targetID: targetID, reason: reason.rawValue,
                        details: (details?.isEmpty ?? true) ? nil : details)
                )
                .execute()
            return true
        } catch {
            AppLogger.moderation.error("submit_report failed: \(error.localizedDescription)")
            return false
        }
    }
}

/// A submitted report, as an admin sees it in `ModerationQueueView` — the
/// same `content_reports` row `ModerationService.report` writes, joined
/// with who filed it. Regular users never see this shape; RLS only lets
/// `is_admin` profiles select more than their own submissions.
struct ContentReport: Decodable, Identifiable, Hashable {
    let id: UUID
    var targetType: String
    var targetID: UUID
    var reason: String
    var details: String?
    var status: String
    var createdAt: Date
    var reporter: UserSummary?

    enum CodingKeys: String, CodingKey {
        case id
        case targetType = "target_type"
        case targetID = "target_id"
        case reason, details, status
        case createdAt = "created_at"
        case reporter
    }
}

enum ReportTargetType: String {
    case profile, project, comment, update, story
}

enum ReportReason: String, CaseIterable, Identifiable {
    case spam, harassment, inappropriate, impersonation, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: "Spam"
        case .harassment: "Harassment or abuse"
        case .inappropriate: "Inappropriate content"
        case .impersonation: "Impersonation"
        case .other: "Other"
        }
    }
}

private struct BlockRow: Decodable {
    let blockerID: UUID
    enum CodingKeys: String, CodingKey { case blockerID = "blocker_id" }
}

private struct TargetProfileParams: Encodable {
    let targetProfileID: UUID
    enum CodingKeys: String, CodingKey { case targetProfileID = "target_profile_id" }
}

private struct SubmitReportParams: Encodable {
    let targetType: String
    let targetID: UUID
    let reason: String
    let details: String?
    enum CodingKeys: String, CodingKey {
        case targetType = "p_target_type"
        case targetID = "p_target_id"
        case reason = "p_reason"
        case details = "p_details"
    }
}
