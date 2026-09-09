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
}

/// Four tabs, no more. The icons are drawn rather than borrowed: SF Symbols would
/// give Arch the same crown-and-heart vocabulary as every other dating app, and
/// the Daily 5 tab in particular has to be the mark itself.
///
/// All four are drawn at the same stroke weight with the same caps, so the set
/// reads as one hand.
struct TabBar: View {
    @Binding var selection: ArchTab
    var unreadCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(ArchTab.allCases) { tab in
                TabBarItem(
                    tab: tab,
                    isActive: selection == tab,
                    badge: tab == .messages ? unreadCount : 0
                ) {
                    selection = tab
                }
            }
        }
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.xxs)
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(ArchColor.hairline)
                .frame(height: ArchSpacing.hairline)
        }
    }
}

private struct TabBarItem: View {
    let tab: ArchTab
    let isActive: Bool
    let badge: Int
    let action: () -> Void

    private var tint: Color { isActive ? ArchColor.lamp : ArchColor.mortar }
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityValue(badge > 0 ? "\(badge) unread" : "")
        .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var glyph: some View {
        let style = StrokeStyle(lineWidth: weight, lineCap: .round, lineJoin: .round)
        switch tab {
        case .premium:
            KeystoneShape()
                .strokeBorder(tint, style: style)
                .frame(width: 20, height: 24)
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
            .foregroundStyle(ArchColor.night)
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
