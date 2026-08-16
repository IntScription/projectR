import SwiftUI

/// The creation hub — everything you can post ties to a project, by
/// design: a brand-new one, or an update (with an optional photo/clip) on
/// one you already own. There's deliberately no path to posting content
/// that doesn't belong to a project. Two large tappable cards rather than a
/// plain list, closer to Instagram's Post/Story chooser than a settings menu.
struct AddView: View {
    let profile: Profile

    @State private var myProjects: [Project] = []
    @State private var isLoading = false
    @State private var isPresentingCreateProject = false
    @State private var isPresentingProjectPicker = false
    @State private var selectedProjectForUpdate: Project?
    @State private var isPresentingAddNote = false
    @State private var hasAppeared = false
    @State private var isPresentingStoryCaptureMenu = false
    @State private var capturedStoryMedia: Data?
    @State private var capturedStoryKind: StoryMediaKind = .image
    @State private var isPresentingStoryComposer = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HighlightsRailView(owner: profile)

                    CreateChoiceCard(
                        title: "Add to Story",
                        subtitle: "Camera, photos, or a file — gone in 24 hours unless you save it.",
                        systemImage: "sparkles.rectangle.stack.fill",
                        colors: [.yellow, .orange]
                    ) {
                        isPresentingStoryCaptureMenu = true
                    }
                    .modifier(StaggeredAppear(index: 0, hasAppeared: hasAppeared))

                    CreateChoiceCard(
                        title: "New Project",
                        subtitle: "Start something and show it off from day one.",
                        systemImage: "plus.square.on.square.fill",
                        colors: [.orange, .pink]
                    ) {
                        isPresentingCreateProject = true
                    }
                    .modifier(StaggeredAppear(index: 1, hasAppeared: hasAppeared))

                    CreateChoiceCard(
                        title: "Post an Update",
                        subtitle: myProjects.isEmpty
                            ? "Create a project first, then post updates to it."
                            : "Share progress with a photo, clip, or note.",
                        systemImage: "bolt.badge.clock.fill",
                        colors: [.blue, .purple]
                    ) {
                        isPresentingProjectPicker = true
                    }
                    .disabled(myProjects.isEmpty)
                    .opacity(myProjects.isEmpty ? 0.5 : 1)
                    .modifier(StaggeredAppear(index: 2, hasAppeared: hasAppeared))

                    CreateChoiceCard(
                        title: "Add Note",
                        subtitle: "Post a short, project-independent thought to your profile.",
                        systemImage: "note.text",
                        colors: [.mint, .teal]
                    ) {
                        isPresentingAddNote = true
                    }
                    .modifier(StaggeredAppear(index: 3, hasAppeared: hasAppeared))
                }
                .padding(20)
            }
            .background {
                // Reuses the auth screen's drifting code-glyph background —
                // same on-brand motif, dialed down since this screen has
                // real content sitting on top of it rather than being
                // mostly empty branding space. Only shows through in the
                // gaps around the cards, which is the point: ambient, not
                // distracting.
                CodeParticlesBackground()
                    .opacity(0.5)
            }
            .floatingTabBarClearance()
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMyProjects() }
            .onAppear {
                withAnimation(.spring(duration: 0.5, bounce: 0.3)) { hasAppeared = true }
            }
            .sheet(isPresented: $isPresentingCreateProject) {
                NavigationStack {
                    CreateProjectView(ownerID: profile.id) { created in
                        myProjects.insert(created, at: 0)
                    }
                }
            }
            .sheet(isPresented: $isPresentingProjectPicker) {
                ProjectPickerSheet(projects: myProjects) { project in
                    isPresentingProjectPicker = false
                    selectedProjectForUpdate = project
                }
            }
            .sheet(item: $selectedProjectForUpdate) { project in
                PostUpdateView(projectID: project.id, uploaderID: profile.id)
            }
            .sheet(isPresented: $isPresentingAddNote) {
                AddNoteView(authorID: profile.id)
            }
            .storyCaptureSourceMenu(isPresented: $isPresentingStoryCaptureMenu) { data, kind in
                capturedStoryMedia = data
                capturedStoryKind = kind
                isPresentingStoryComposer = true
            }
            .fullScreenCover(isPresented: $isPresentingStoryComposer) {
                if let capturedStoryMedia {
                    StoryComposerView(
                        uploaderID: profile.id, mediaData: capturedStoryMedia, mediaKind: capturedStoryKind)
                }
            }
        }
    }

    /// Owned projects plus anything the user collaborates on — a
    /// collaborator can post updates too (see the RLS on
    /// `project_updates`), so "Post an Update" needs to offer both.
    private func loadMyProjects() async {
        isLoading = true
        defer { isLoading = false }
        async let ownedTask: [Project] =
            SupabaseManager.shared.client
            .from("projects")
            .select()
            .eq("owner_id", value: profile.id)
            .order("created_at", ascending: false)
            .execute()
            .value
        async let collaboratedTask: [ProjectCollaboratorEntry] =
            SupabaseManager.shared.client
            .from("project_collaborators")
            .select("project:projects(*)")
            .eq("user_id", value: profile.id)
            .execute()
            .value

        let owned = (try? await ownedTask) ?? []
        let collaborated = (try? await collaboratedTask)?.map(\.project) ?? []
        var seen = Set<UUID>()
        myProjects = (owned + collaborated).filter { seen.insert($0.id).inserted }
    }
}

private struct ProjectCollaboratorEntry: Decodable {
    let project: Project
}

/// Fades + slides each card in with a small delay per index, so the three
/// choices arrive one after another instead of all popping in at once —
/// the plain instant-appear list is what made this screen feel flat.
private struct StaggeredAppear: ViewModifier {
    let index: Int
    let hasAppeared: Bool

    func body(content: Content) -> some View {
        content
            .opacity(hasAppeared ? 1 : 0)
            .offset(y: hasAppeared ? 0 : 16)
            .animation(
                .spring(duration: 0.5, bounce: 0.3).delay(Double(index) * 0.08),
                value: hasAppeared
            )
    }
}

/// Scales down slightly under a finger — `.buttonStyle(.plain)` alone
/// gives zero tap feedback, which was a big part of why this screen felt
/// inert rather than alive.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

private struct CreateChoiceCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let colors: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                ZStack {
                    LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    Image(systemName: systemImage)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 60, height: 60)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(PressableCardStyle())
    }
}

private struct ProjectPickerSheet: View {
    let projects: [Project]
    let onPick: (Project) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(projects) { project in
                Button {
                    onPick(project)
                } label: {
                    HStack {
                        Text(project.name)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .foregroundStyle(.primary)
            }
            .navigationTitle("Post an update to…")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
