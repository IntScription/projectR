import SwiftUI

/// Generic report sheet — used for profiles, projects, comments, and
/// updates alike, distinguished only by `targetType`/`targetID`.
struct ReportSheet: View {
    let targetType: ReportTargetType
    let targetID: UUID

    @State private var reason: ReportReason = .spam
    @State private var details = ""
    @State private var isSubmitting = false
    @State private var didSubmit = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                if didSubmit {
                    ContentUnavailableView(
                        "Report submitted", systemImage: "checkmark.circle.fill",
                        description: Text("Thanks — we'll take a look."))
                } else {
                    Section("Reason") {
                        Picker("Reason", selection: $reason) {
                            ForEach(ReportReason.allCases) { reason in
                                Text(reason.label).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                    Section("Additional details (optional)") {
                        TextField("What happened?", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                    }
                }
            }
            .navigationTitle("Report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSubmit ? "Done" : "Cancel") { dismiss() }
                }
                if !didSubmit {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Submit") { Task { await submit() } }
                            .disabled(isSubmitting)
                    }
                }
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        let succeeded = await ModerationService.report(
            targetType: targetType, targetID: targetID, reason: reason,
            details: details.trimmingCharacters(in: .whitespacesAndNewlines))
        if succeeded {
            withAnimation { didSubmit = true }
        }
    }
}
