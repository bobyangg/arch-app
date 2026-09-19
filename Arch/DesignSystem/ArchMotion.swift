import SwiftUI

/// Motion in Arch responds to what the reader does. There is no ambient animation,
/// no fade-and-rise on scroll, no shimmer.
///
/// The whole orchestrated budget is spent on one moment, and that moment is a
/// **loss**: when you dismiss someone, their card collapses and their stone drops
/// out of the arch, leaving a gap. Dismissing costs you a slot until tomorrow, and
/// the motion should say so.
///
/// Arrivals are never animated. Tomorrow's person is simply there when you open the
/// app — no reveal, no celebration.
///
/// Changing tabs and choosing a card are things the reader does, so they move:
/// the glass pill slides under the tab you chose, the old screen gives way to the
/// new one, a selection glow arrives. All of it settles rather than bounces —
/// glass does not spring.
enum ArchMotion {

    /// 150ms — a control acknowledging a tap.
    static let quick = Animation.easeOut(duration: 0.15)

    /// 250ms — a surface appearing, a row changing state.
    static let standard = Animation.easeOut(duration: 0.25)

    /// Glass settling: the pill under the active tab, a selection glow, one tab
    /// giving way to the next. A smooth spring with no bounce, so it reads as
    /// glass coming to rest.
    static let glass = Animation.smooth(duration: 0.34)

    /// The same curve as `glass`, on purpose. The pill sliding and the page
    /// changing are one gesture, and two curves would make them two.
    static let tabSwitch = glass

    /// A stone falling out of the arch. Ease-*in* on purpose: it reads as gravity
    /// rather than as a bounce, and nothing about losing a slot should feel springy.
    static let stoneFall = Animation.easeIn(duration: 0.30)

    /// The dismissed card collapsing out of the list, alongside the stone.
    static let cardCollapse = Animation.easeIn(duration: 0.26)

    /// The replacement open slot settling in underneath, once the card has gone.
    static let slotOpens = Animation.easeOut(duration: 0.20).delay(0.26)

    /// The launch mark drawing itself in, once.
    static let launchDraw = Animation.easeInOut(duration: 0.85)

    /// The other way the bridge goes up at launch. The piers rise and stop --
    /// stone does not bounce. The deck is the one piece that settles: it lands
    /// on the piers with a little give, which is what makes it read as having
    /// weight.
    static let pierRises = Animation.easeOut(duration: 0.40)
    static let deckLands = Animation.spring(duration: 0.42, bounce: 0.28)

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
