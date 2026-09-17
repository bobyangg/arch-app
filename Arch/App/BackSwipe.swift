import UIKit

/// Swiping in from the left edge goes back a screen.
///
/// Every pushed screen in Arch hides the system navigation bar to draw its own
/// back control, and hiding the bar quietly disables the interactive pop gesture
/// that comes with `NavigationStack` — UIKit hangs the gesture's delegate off the
/// bar, so no bar, no delegate, no swipe. This puts the delegate back and lets the
/// gesture begin whenever there is somewhere to go back to.
///
/// One rule, kept: the gesture only ever *pops*. It does not fire on a tab root,
/// where a swipe would have nothing to return to and would instead fight the
/// scroll, and it does not touch sheets, which already come down on their own.
// A retroactive conformance on a UIKit class. The Swift 6 compiler notes it as a
// warning in 5.9 mode; the `@retroactive` attribute that silences it does not
// exist on older toolchains, so the warning is kept and the build is not.
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
