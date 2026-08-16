import SwiftUI

/// Shown on `ProjectDetailView`. Owners can add/remove; a collaborator
/// viewing the project can remove themselves ("leave"). Everyone else
/// just sees who's building it — collaborators are public, like
/// everything except saves.
struct CollaboratorsSection: View {
    let projectID: UUID
    let isOwner: Bool

    @State private var collaborators: [ProjectCollaborator] = []
    @State private var isPresentingAdd = false

    private var currentUserID: UUID? {
        SupabaseManager.shared.client.auth.currentSession?.user.id
    }

    var body: some View {
        if !collaborators.isEmpty || isOwner {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Collaborators")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if isOwner {
                        Button {
                            isPresentingAdd = true
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .accessibilityLabel("Add collaborator")
                    }
                }

                if collaborators.isEmpty {
                    Text("Just you so far.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(collaborators) { collaborator in
                                collaboratorChip(collaborator)
                            }
                        }
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $isPresentingAdd) {
                AddCollaboratorSheet(projectID: projectID) {
                    Task { await load() }
                }
            }
        }
    }

    private func collaboratorChip(_ collaborator: ProjectCollaborator) -> some View {
        NavigationLink(value: CreatorRoute(userID: collaborator.userID)) {
            VStack(spacing: 6) {
                AsyncImage(url: collaborator.user.avatarURL.flatMap(URL.init)) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.accentColor.opacity(0.2)).overlay(
                        Text(collaborator.user.displayName.prefix(1).uppercased())
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Color.accentColor)
                    )
                }
                .frame(width: 44, height: 44)
                .clipShape(Circle())

                Text("@\(collaborator.user.username)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 64)
            .contextMenu {
                if isOwner || collaborator.userID == currentUserID {
                    Button(role: .destructive) {
                        Task { await remove(collaborator) }
                    } label: {
                        Label(
                            collaborator.userID == currentUserID ? "Leave" : "Remove",
                            systemImage: "person.badge.minus")
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        collaborators =
            (try? await SupabaseManager.shared.client
                .from("project_collaborators")
                .select("*, user:profiles!project_collaborators_user_id_fkey(username,display_name,avatar_url)")
                .eq("project_id", value: projectID)
                .order("added_at")
                .execute()
                .value) ?? []
    }

    private func remove(_ collaborator: ProjectCollaborator) async {
        try? await SupabaseManager.shared.client
            .from("project_collaborators")
            .delete()
            .eq("project_id", value: projectID)
            .eq("user_id", value: collaborator.userID)
            .execute()
        await load()
    }
}

private struct AddCollaboratorSheet: View {
    let projectID: UUID
    var onAdded: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var results: [Profile] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
                ForEach(results) { profile in
                    Button {
                        Task { await add(profile) }
                    } label: {
                        HStack {
                            Text(profile.displayName)
                            Text("@\(profile.username)").foregroundStyle(.secondary)
                            Spacer()
                            Image(systemName: "plus.circle")
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .searchable(text: $searchText, prompt: "Search by username")
            .navigationTitle("Add Collaborator")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task(id: searchText) { await search() }
        }
        .presentationDetents([.medium, .large])
    }

    private func search() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        results =
            (try? await SupabaseManager.shared.client
                .from("profiles")
                .select()
                .ilike("username", pattern: "%\(trimmed)%")
                .limit(15)
                .execute()
                .value) ?? []
    }

    private func add(_ profile: Profile) async {
        errorMessage = nil
        do {
            try await SupabaseManager.shared.client
                .from("project_collaborators")
                .insert(["project_id": projectID.uuidString, "user_id": profile.id.uuidString])
                .execute()
            onAdded()
            dismiss()
        } catch {
            errorMessage = ErrorPresentation.message(for: error)
        }
    }
}
