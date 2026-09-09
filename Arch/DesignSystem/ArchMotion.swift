import SwiftUI

/// Motion in Arch responds to what the reader does — opening, liking, connecting.
/// There is no ambient animation, no fade-and-rise on scroll, no shimmer.
///
/// The entire orchestrated budget is spent on one moment: the keystone locking
/// when a connection is made. Everything else is quick and functional.
enum ArchMotion {

    /// 150ms — a control acknowledging a tap.
    static let quick = Animation.easeOut(duration: 0.15)

    /// 250ms — a surface appearing, a row changing state.
    static let standard = Animation.easeOut(duration: 0.25)

    /// The keystone dropping into place. The one memorable moment in the app.
    static let keystoneLock = Animation.spring(response: 0.42, dampingFraction: 0.62)

    /// The two segments either side of the keystone settling against it.
    static let settle = Animation.spring(response: 0.36, dampingFraction: 0.70).delay(0.09)

    /// Verdigris washing outward across the completed band.
    static let wash = Animation.easeInOut(duration: 0.38)

    /// The launch mark drawing itself in, once.
    static let launchDraw = Animation.easeInOut(duration: 0.85)

    /// Under Reduce Motion every orchestrated animation collapses to a plain
    /// cross-fade — the moment still reads, nothing moves.
    static func honouring(_ reduceMotion: Bool, _ animation: Animation) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.2) : animation
    }

    /// Displacement that should be dropped entirely under Reduce Motion.
    static func offset(_ reduceMotion: Bool, _ value: CGFloat) -> CGFloat {
        reduceMotion ? 0 : value
    }
}
