import SwiftUI

/// Small transient confirmation banner for actions (like a copy button)
/// that don't otherwise show any visible result — the copy icon swapping
/// to a checkmark is easy to miss entirely if you're not looking right at
/// it; an explicit "Link copied to clipboard" message is not. Auto-
/// dismisses; there's nothing to manually dismiss.
private struct CopyToastModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if isPresented {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.85), in: Capsule())
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task {
                        try? await Task.sleep(for: .seconds(1.6))
                        withAnimation(.easeOut(duration: 0.25)) { isPresented = false }
                    }
            }
        }
        .animation(.spring(duration: 0.3), value: isPresented)
        // One central spot for this rather than every call site adding its
        // own — every `.copyToast` use (copy-link buttons, Forge sync)
        // gets a consistent light tap confirming the action landed.
        .sensoryFeedback(.success, trigger: isPresented) { _, newValue in newValue }
    }
}

extension View {
    func copyToast(_ message: String, isPresented: Binding<Bool>) -> some View {
        modifier(CopyToastModifier(isPresented: isPresented, message: message))
    }
}
