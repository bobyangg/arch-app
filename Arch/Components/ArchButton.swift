import SwiftUI

// MARK: - Full-width buttons

/// Arch has exactly two button weights. `lamp` is the only colour that invites
/// action, so only the primary button carries it; everything secondary is a quiet
/// outline that stays clearly available without competing.
struct ArchButton: View {
    enum Kind {
        case primary
        case quiet
    }

    let title: String
    var kind: Kind = .primary
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ArchButtonStyle(kind: kind))
    }
}

struct ArchButtonStyle: ButtonStyle {
    var kind: ArchButton.Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .archText(.subhead)
            .foregroundStyle(kind == .primary ? ArchColor.night : ArchColor.mortar)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(kind == .primary ? ArchColor.lamp : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .strokeBorder(
                        kind == .quiet ? ArchColor.quietBorder : Color.clear,
                        lineWidth: 1
                    )
            )
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(ArchMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - The like affordance

/// You do not like a person in Arch, you like one specific photo or one specific
/// answer — so this button belongs to a card, never to a screen.
///
/// It is a keystone, not a heart. Liking something is setting a stone; when both
/// people have set one, the arch closes. Unset it reads as an outlined stone
/// waiting to be placed; set, it fills with lamplight.
struct KeystoneLikeButton: View {
    var isLiked: Bool
    /// Completes the sentence "Like ..." for VoiceOver.
    var subject: String = "this"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            KeystoneShape()
                .fill(isLiked ? ArchColor.lamp : ArchColor.stone)
                .overlay(
                    KeystoneShape()
                        .strokeBorder(isLiked ? Color.clear : ArchColor.lamp, lineWidth: 1.5)
                )
                .frame(width: 34, height: 38)
                .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeystonePressStyle())
        .accessibilityLabel(isLiked ? "Liked \(subject)" : "Like \(subject)")
        .accessibilityAddTraits(isLiked ? [.isSelected] : [])
    }
}

private struct KeystonePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(ArchMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Card affordances

/// What sits in the bottom-right corner of a photo or prompt card. The same two
/// cards serve the day's five and your own profile; only this changes.
enum CardAffordance {
    /// Someone else's card: set a stone on it.
    case like(isLiked: Bool, action: () -> Void)
    /// Your own card: edit it.
    case edit(action: () -> Void)
    /// A card pinned for context, in a message thread. Nothing to do.
    case none
}

struct CardAffordanceView: View {
    let affordance: CardAffordance
    var subject: String = "this"

    var body: some View {
        switch affordance {
        case .like(let isLiked, let action):
            KeystoneLikeButton(isLiked: isLiked, subject: subject, action: action)
        case .edit(let action):
            Button(action: action) {
                Image(systemName: "pencil")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(ArchColor.stoneRaised))
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeystonePressStyle())
            .accessibilityLabel("Edit \(subject)")
        case .none:
            EmptyView()
        }
    }
}

// MARK: - Previews

#Preview("Buttons") {
    VStack(spacing: ArchSpacing.m) {
        ArchButton(title: "Send a message", action: {})
        ArchButton(title: "Not for me", kind: .quiet, action: {})

        HStack(spacing: ArchSpacing.xl) {
            KeystoneLikeButton(isLiked: false, subject: "this photo", action: {})
            KeystoneLikeButton(isLiked: true, subject: "this photo", action: {})
            CardAffordanceView(affordance: .edit(action: {}), subject: "this photo")
        }
        .padding(.top, ArchSpacing.xl)
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
