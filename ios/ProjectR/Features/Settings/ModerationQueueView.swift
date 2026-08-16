import Supabase
import SwiftUI

/// The other half of `ReportSheet`'s reporting flow, which previously had
/// nowhere to go — reports landed in `content_reports` with no UI on
/// either end to review them; the only way to act on one was querying the
/// database directly. `is_admin`-gated (see `ModerationService.swift`),
/// reached from Settings only when the signed-in profile has it set.
///
/// Deliberately doesn't deep-link into the reported content itself (a
/// project/comment/story/profile each need their own resolution, and this
/// screen has no `NavigationStack` ancestor wiring those destinations) —
/// the target type and id are shown plainly enough to look up by hand.
/// Real scope for a first pass: see what was reported and why, then mark
/// it reviewed or dismiss it.
struct ModerationQueueView: View {
    @State private var reports: [ContentReport] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if reports.isEmpty {
                ContentUnavailableView("No open reports", systemImage: "checkmark.shield")
            } else {
                List(reports) { report in
                    reportRow(report)
                }
                .refreshable { await load() }
            }
        }
        .navigationTitle("Reports")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func reportRow(_ report: ContentReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ReportReason(rawValue: report.reason)?.label ?? report.reason.capitalized)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(report.createdAt, format: .relative(presentation: .named))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(report.targetType.capitalized) · \(report.targetID.uuidString)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if let details = report.details, !details.isEmpty {
                Text(details).font(.subheadline)
            }
            if let reporter = report.reporter {
                Text("Reported by @\(reporter.username)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            HStack(spacing: 12) {
                Button("Dismiss") { Task { await resolve(report, status: "dismissed") } }
                    .buttonStyle(.bordered)
                Button("Mark Reviewed") { Task { await resolve(report, status: "reviewed") } }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 6)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            reports =
                try await SupabaseManager.shared.client
                .from("content_reports")
                .select("*, reporter:profiles!content_reports_reporter_id_fkey(username, display_name, avatar_url)")
                .eq("status", value: "open")
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }

    private func resolve(_ report: ContentReport, status: String) async {
        do {
            try await SupabaseManager.shared.client
                .from("content_reports")
                .update(["status": status])
                .eq("id", value: report.id)
                .execute()
            reports.removeAll { $0.id == report.id }
            AnalyticsService.track("report_resolved", properties: ["status": .string(status)])
        } catch {
            CrashReporter.capture(error, context: "resolve_report")
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
