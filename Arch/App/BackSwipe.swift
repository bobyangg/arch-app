import SwiftUI
import UIKit

/// Swiping in from the left edge goes back a screen.
///
/// Every pushed screen in Arch hides the system navigation bar to draw its own
/// back control, and hiding the bar quietly disables the interactive pop gesture
/// that comes with `NavigationStack` — UIKit hangs the gesture's delegate off the
/// bar, so no bar, no delegate, no swipe. This puts a delegate back and lets the
/// gesture begin whenever there is somewhere to go back to.
///
/// **Not an override of `UINavigationController`.** The first version of this was
/// the snippet everybody copies — `viewDidLoad` overridden in an extension — and it
/// hung the app at launch. An override in an extension is a category override: it
/// *replaces* UIKit's own `viewDidLoad` for every navigation controller, including
/// the one `NavigationStack` builds, so its setup never ran. This one is a hidden,
/// zero-size controller placed in each tab's root; it finds the navigation
/// controller above it and becomes the gesture's delegate, and touches nothing of
/// UIKit's.
///
/// One rule, kept: the gesture only ever *pops*. It does not fire on a tab root,
/// where a swipe would have nothing to return to and would instead fight the
/// scroll, and it does not touch sheets, which already come down on their own.
extension View {
    /// Put on the root screen of a `NavigationStack`, once.
    func archBackSwipe() -> some View {
        background(BackSwipeEnabler().frame(width: 0, height: 0))
    }
}

private struct BackSwipeEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) {}

    final class Controller: UIViewController, UIGestureRecognizerDelegate {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            attach()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            attach()
        }

        /// Idempotent, and tried more than once: the navigation controller is
        /// not always in the parent chain the first time this is asked.
        private func attach() {
            guard let navigation = navigationController,
                  let gesture = navigation.interactivePopGestureRecognizer else { return }
            if gesture.delegate !== self {
                gesture.delegate = self
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            (navigationController?.viewControllers.count ?? 0) > 1
        }
    }
}
