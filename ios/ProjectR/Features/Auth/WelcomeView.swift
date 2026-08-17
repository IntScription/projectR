import SwiftUI

/// Shown before `SignInView`, not instead of it — the interactive
/// centerpiece is a live marquee of real trending projects (public,
/// anon-readable `project_feed`, no auth needed), because "see what
/// people are building" is the actual product hook, not a generic splash.
struct WelcomeView: View {
    let auth: AuthViewModel

    @State private var projects: [DiscoverProject] = []
    @State private var isPresentingSignIn = false
    @State private var contentAppeared = false

    /// Falls back to a handful of illustrative example cards — clearly
    /// generic, not claiming to be real people — so the marquee always has
    /// something to show rather than going blank. That matters most right
    /// after launch, before enough real projects exist to fill a trending
    /// feed, and it's also what every anonymous visitor sees today against
    /// an empty local dev database.
    private var displayProjects: [DiscoverProject] {
        projects.isEmpty ? Self.exampleProjects : projects
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                // On a phone-sized canvas this ends up functionally
                // identical to the old fixed layout (a 320pt marquee,
                // content pinned near the bottom third). On an iPad's much
                // taller canvas, sizing the marquee off the real available
                // height — and giving both sides of `content` an equal,
                // fully flexible Spacer instead of one small fixed gap and
                // one large one — keeps the whole composition looking
                // deliberately centered instead of leaving a dead zone
                // below the button.
                VStack(spacing: 0) {
                    // A bold, unmissable wordmark of its own — separate
                    // from the small caption that used to live inline with
                    // the headline below — so the brand reads clearly even
                    // though the marquee behind it is full of (real or
                    // illustrative) project names competing for attention.
                    Text("PROJECTR")
                        .font(.system(.title3, design: .monospaced).weight(.heavy))
                        .tracking(3)
                        .foregroundStyle(Color.accentColor)
                        .padding(.top, 8)

                    Spacer(minLength: 12)

                    // A blur keeps the marquee readable as texture —
                    // "there's real activity behind this" — without its
                    // project names competing for attention with the
                    // actual headline below. `.clipped()` matters here:
                    // blur otherwise renders past its own frame's edges,
                    // which is what was leaving the row closest to
                    // `content` reading fully sharp.
                    marquee
                        .frame(height: min(max(geo.size.height * 0.32, 260), 420))
                        .blur(radius: 3)
                        .clipped()

                    Spacer(minLength: 24)

                    content
                        .frame(maxWidth: 480)
                        // A solid scrim right behind the text, independent
                        // of the blur above — text over a busy background
                        // needs a guaranteed-legible ground, not just a
                        // softened one.
                        .background {
                            Color(.systemBackground)
                                .opacity(0.92)
                                .blur(radius: 20)
                                .padding(-40)
                        }
                        .opacity(contentAppeared ? 1 : 0)
                        .offset(y: contentAppeared ? 0 : 16)

                    Spacer(minLength: 24)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .task { await loadProjects() }
        .task {
            try? await Task.sleep(for: .milliseconds(200))
            withAnimation(.easeOut(duration: 0.5)) { contentAppeared = true }
        }
        .navigationBarHidden(true)
        .navigationDestination(isPresented: $isPresentingSignIn) {
            SignInView(auth: auth)
        }
    }

    /// Wrapped in `GeometryReader` deliberately: the tripled card `HStack`
    /// inside each row has a genuinely large intrinsic width (real content,
    /// no flexible frame), and a bare `VStack` would propose that same huge
    /// width to every sibling in its final layout pass — including
    /// `content` below, which is what was silently blowing the "Get
    /// Started" button out past the screen edges. `GeometryReader` reports
    /// a small/flexible ideal size of its own, so the marquee's true width
    /// never leaks upward; each row then explicitly clips to the measured
    /// screen width.
    private var marquee: some View {
        GeometryReader { geo in
            VStack(spacing: 14) {
                MarqueeRow(projects: displayProjects, speed: 24, reverse: false, rowWidth: geo.size.width)
                MarqueeRow(
                    projects: Array(displayProjects.reversed()), speed: 19, reverse: true,
                    rowWidth: geo.size.width)
                MarqueeRow(projects: displayProjects, speed: 27, reverse: false, rowWidth: geo.size.width)
            }
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.15),
                        .init(color: .black, location: 0.85),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
    }

    private var content: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("See what people are building.")
                    .font(.system(size: 30, weight: .bold, design: .serif))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
                Text("Then show them what you're building.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                isPresentingSignIn = true
            } label: {
                Text("Get Started")
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 40)
        }
    }

    private func loadProjects() async {
        projects =
            (try? await SupabaseManager.shared.client
                .from("project_feed")
                .select()
                .order("trending_score", ascending: false)
                .limit(16)
                .execute()
                .value) ?? []
    }

    /// No cover images on purpose — `MarqueeCard` already has a clean
    /// gradient-plus-category placeholder for projects without one, so
    /// these read as obviously illustrative examples rather than an
    /// attempt to pass off stock photography as real screenshots.
    private static let exampleProjects: [DiscoverProject] = [
        ("Weekend Habit Tracker", "weekend-habit-tracker", .software, "buildwithkai"),
        ("Terminal Themes", "terminal-themes", .design, "devmaya"),
        ("Recipe Vault", "recipe-vault", .software, "sam_codes"),
        ("Pixel Quest", "pixel-quest", .games, "arjunbuilds"),
        ("Synth Sketchpad", "synth-sketchpad", .music, "noalabs"),
        ("Field Notes", "field-notes", .writing, "priya_writes"),
    ].map { name, slug, category, username in
        DiscoverProject(
            id: UUID(), slug: slug, name: name, description: nil, category: category,
            status: .building, createdAt: .now, ownerID: UUID(), ownerUsername: username,
            ownerDisplayName: username, ownerAvatarURL: nil, likeCount: 0, commentCount: 0,
            trendingScore: 0, coverImageURL: nil, coverVideoURL: nil)
    }
}

/// Seamless infinite scroll via `TimelineView` rather than a restarting
/// `Animation` — offset is a pure function of elapsed time modulo the
/// looped content width, so there's no jump when it wraps. Clipped to
/// `rowWidth` (the real screen width, measured by the parent
/// `GeometryReader`) so the row's true, much larger intrinsic width never
/// influences layout above it.
private struct MarqueeRow: View {
    let projects: [DiscoverProject]
    let speed: Double
    let reverse: Bool
    let rowWidth: CGFloat

    private let cardWidth: CGFloat = 150
    private let spacing: CGFloat = 12

    var body: some View {
        guard !projects.isEmpty else { return AnyView(EmptyView()) }
        let unit = cardWidth + spacing
        let loopWidth = unit * Double(projects.count)
        let tripled = Array(0..<(projects.count * 3))

        return AnyView(
            TimelineView(.animation) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let raw = (t * speed).truncatingRemainder(dividingBy: loopWidth)
                let offset = reverse ? raw - loopWidth : -raw

                HStack(spacing: spacing) {
                    ForEach(tripled, id: \.self) { index in
                        MarqueeCard(project: projects[index % projects.count])
                            .frame(width: cardWidth)
                    }
                }
                .offset(x: offset)
                .frame(width: rowWidth, alignment: .leading)
                .clipped()
            }
        )
    }
}

private struct MarqueeCard: View {
    let project: DiscoverProject

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                if let url = project.coverImageURL.flatMap(URL.init) {
                    AsyncImage(url: url) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        placeholder
                    }
                } else {
                    placeholder
                }
            }
            .frame(height: 100)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("@\(project.ownerUsername)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.top, 6)
        }
    }

    private var placeholder: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.35), Color.accentColor.opacity(0.12)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )
        .overlay {
            Text(project.category.rawValue.uppercased())
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
