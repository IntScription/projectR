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

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                if !projects.isEmpty {
                    marquee
                        .frame(height: 320)
                        .padding(.top, 24)
                } else {
                    Spacer(minLength: 320)
                }

                Spacer(minLength: 16)

                content
                    .opacity(contentAppeared ? 1 : 0)
                    .offset(y: contentAppeared ? 0 : 16)

                Spacer(minLength: 32)
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
                MarqueeRow(projects: projects, speed: 24, reverse: false, rowWidth: geo.size.width)
                MarqueeRow(
                    projects: Array(projects.reversed()), speed: 19, reverse: true,
                    rowWidth: geo.size.width)
                MarqueeRow(projects: projects, speed: 27, reverse: false, rowWidth: geo.size.width)
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
                Text("PROJECTR")
                    .font(.system(.caption, design: .monospaced))
                    .fontWeight(.semibold)
                    .tracking(4)
                    .foregroundStyle(Color.accentColor)
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
