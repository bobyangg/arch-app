import SwiftUI

enum ArchTab: Int, CaseIterable, Identifiable, Hashable {
    case premium
    case daily
    case messages
    case you

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .premium:  return "Premium"
        case .daily:    return "Daily 5"
        case .messages: return "Messages"
        case .you:      return "You"
        }
    }

    /// What a UI test addresses this tab by.
    ///
    /// Deliberately not the title. Two screens already put their own name on a
    /// heading — Messages and You — so a test looking for a control called
    /// "Messages" finds the tab and the heading and cannot say which it meant.
    /// The title is also the one thing here anybody might reword, and a test that
    /// breaks when a word improves teaches people to stop improving words.
    var identifier: String {
        switch self {
        case .premium:  return "tab.premium"
        case .daily:    return "tab.daily"
        case .messages: return "tab.messages"
        case .you:      return "tab.you"
        }
    }
}

/// Four tabs, no more. The icons are drawn rather than borrowed: SF Symbols would
/// give Arch the same crown-and-heart vocabulary as every other dating app, and
/// the Daily 5 tab in particular has to be the mark itself.
///
/// All four are drawn at the same stroke weight with the same caps, so the set
/// reads as one hand.
///
/// A frosted pill sits behind the active tab and slides to whichever one you
/// choose. One pill, moved, rather than one lit per tab: the motion is what says
/// "you went from here to there", and it is the only thing in the bar that moves.
struct TabBar: View {
    @Binding var selection: ArchTab
    var unreadCount: Int = 0

    @Namespace private var pill
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ArchTab.allCases) { tab in
                TabBarItem(
                    tab: tab,
                    isActive: selection == tab,
                    badge: tab == .messages ? unreadCount : 0,
                    pill: pill
                ) {
                    withAnimation(ArchMotion.honouring(reduceMotion, ArchMotion.glass)) {
                        selection = tab
                    }
                }
            }
        }
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.xxs)
        // Also covers a change that did not come from a tap -- "Open your
        // messages" from the roster sets the selection directly -- so the pill
        // glides there too rather than jumping.
        .animation(ArchMotion.honouring(reduceMotion, ArchMotion.glass), value: selection)
        .archBar(.bottom)
    }
}

private struct TabBarItem: View {
    let tab: ArchTab
    let isActive: Bool
    let badge: Int
    let pill: Namespace.ID
    let action: () -> Void

    /// Every tab lights the same accent, and inactive is `mortar` for all four,
    /// so the bar reads as one set both at rest and in use.
    ///
    /// Premium's star used to light `ember` instead: the seam between the palette's
    /// two accents, amber for the thing you can buy against terracotta for the
    /// things you do. The distinction is real but the bar is the wrong place to
    /// draw it -- one tab in a different colour reads as a tab that is broken, not
    /// as a category -- so the second accent moved to the paywall's recommended
    /// plan, where the thing you can buy actually is.
    private var tint: Color {
        isActive ? ArchColor.lamp : ArchColor.mortar
    }
    private var weight: CGFloat { isActive ? 2.25 : ArchSpacing.glyphStroke }

    var body: some View {
        Button(action: action) {
            VStack(spacing: ArchSpacing.xxs) {
                glyph
                    .frame(width: 26, height: 26)
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            UnreadBadge(count: badge)
                                .offset(x: 9, y: -5)
                        }
                    }
                Text(tab.title)
                    .archText(.caption)
                    .foregroundStyle(tint)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, ArchSpacing.xxs)
            .background {
                if isActive {
                    // `limestone` at a whisper: dark on paper, pale at night, so
                    // it reads as frost on the glass in either world.
                    RoundedRectangle(cornerRadius: ArchGlass.pillRadius, style: .continuous)
                        .fill(ArchColor.limestone.opacity(ArchGlass.pillWash))
                        .padding(.horizontal, ArchSpacing.xs)
                        .matchedGeometryEffect(id: "pill", in: pill)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(ArchMotion.glass, value: isActive)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier(tab.identifier)
        .accessibilityLabel(tab.title)
        .accessibilityValue(badge > 0 ? "\(badge) unread" : "")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var glyph: some View {
        let style = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
        switch tab {
        case .premium:
            StarGlyph(lineWidth: weight)
                .stroke(tint, style: style)
                .frame(width: 24, height: 24)
        case .daily:
            ArchMark(lineWidth: weight)
                .stroke(tint, style: style)
        case .messages:
            MessageGlyph(lineWidth: weight)
                .stroke(tint, style: style)
                .frame(width: 24, height: 24)
        case .you:
            PersonGlyph(lineWidth: weight)
                .stroke(tint, style: style)
                .frame(width: 24, height: 24)
        }
    }
}

/// A count, not a dot — you should know how many conversations are waiting before
/// you decide to open the tab.
struct UnreadBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .archText(.badge)
            .foregroundStyle(ArchColor.onLamp)
            .padding(.horizontal, count > 9 ? 5 : 0)
            .frame(minWidth: 16, minHeight: 16)
            .background(Capsule().fill(ArchColor.lamp))
    }
}

#Preview("Tab bar") {
    TabBarDemo()
}

private struct TabBarDemo: View {
    @State private var selection: ArchTab = .daily

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Text(selection.title)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
            Spacer()
            TabBar(selection: $selection, unreadCount: MockData.unreadCount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
    }
}
