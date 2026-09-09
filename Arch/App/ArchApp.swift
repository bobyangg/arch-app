import SwiftUI

@main
struct ArchApp: App {
    @State private var hasLaunched = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootTabView()

                if !hasLaunched {
                    LaunchView { hasLaunched = true }
                        .transition(.opacity)
                }
            }
            // Arch is a dark app. There is no light variant and nothing here is
            // designed to survive one.
            .preferredColorScheme(.dark)
        }
    }
}
