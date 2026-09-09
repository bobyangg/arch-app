import SwiftUI

/// The app shell: four tabs over one store.
///
/// All four tabs stay alive rather than being rebuilt on every switch, so a
/// half-scrolled profile or an open thread is still there when you come back —
/// which is what a tab bar is supposed to do.
struct RootTabView: View {
    @State private var selection: ArchTab = .daily
    @State private var store = DailyFiveStore()

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            TabBar(selection: $selection, unreadCount: store.unreadCount)
        }
        .background(ArchColor.night)
    }

    private var content: some View {
        ZStack {
            tab(.premium) {
                PremiumView()
            }
            tab(.daily) {
                DailyFiveView(
                    roster: store.roster,
                    onDismiss: { store.dismiss($0) },
                    onSend: { store.startConversation(with: $0, text: $1, quoting: $2) }
                )
            }
            tab(.messages) {
                MessagesListView(
                    conversations: store.conversations,
                    onOpenDaily: { selection = .daily }
                )
            }
            tab(.you) {
                YouPlaceholderView()
            }
        }
    }

    @ViewBuilder
    private func tab<Content: View>(
        _ which: ArchTab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .opacity(selection == which ? 1 : 0)
            .allowsHitTesting(selection == which)
            .accessibilityHidden(selection != which)
    }
}

#Preview("App shell") {
    RootTabView()
        .preferredColorScheme(.dark)
}
