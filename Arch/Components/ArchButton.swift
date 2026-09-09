import SwiftUI

// MARK: - Full-width buttons

/// Arch has exactly two button weights. `lamp` is the only colour that invites
/// action, so only the primary button carries it; everything secondary is a quiet
/// outline that stays clearly available without competing.
///
/// Some decisions get neither weight. Confirming a dismissal is the clearest
/// example: it is the user's to make, so the app puts no colour behind it.
struct ArchButton: View {
    enum Kind {
        case primary
        case quiet
    }

    let title: String
    var kind: Kind = .primary
    /// Reduced to an inert, low-contrast state. Used by the composer's send
    /// action while there is nothing to send.
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(title, action: action)
            .buttonStyle(ArchButtonStyle(kind: kind, isEnabled: isEnabled))
            .disabled(!isEnabled)
    }
}

struct ArchButtonStyle: ButtonStyle {
    var kind: ArchButton.Kind = .primary
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .archText(.subhead)
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(fill)
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
            .animation(ArchMotion.quick, value: isEnabled)
    }

    // An inactive primary button steps down a surface rather than dimming the
    // accent. Fading `lamp` out turns it into a muddy brown, which reads as
    // damage rather than as "not yet".
    private var fill: Color {
        guard kind == .primary else { return .clear }
        return isEnabled ? ArchColor.lamp : ArchColor.stoneRaised
    }

    private var foreground: Color {
        guard kind == .primary else { return ArchColor.mortar }
        return isEnabled ? ArchColor.night : ArchColor.mortar
    }
}

/// A text-only action, for the quietest thing on a screen: dismissing someone from
/// the profile detail, or backing out of a confirmation. Never `lamp`.
struct ArchTextButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .archText(.subhead)
                .foregroundStyle(ArchColor.mortar)
                .frame(maxWidth: .infinity)
                .frame(height: ArchSpacing.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 1))
    }
}

// MARK: - Press feedback

/// Shared press feedback: a small, quick scale. Nothing bounces.
struct PressScaleStyle: ButtonStyle {
    var scale: CGFloat = 0.92

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(ArchMotion.quick, value: configuration.isPressed)
    }
}

// MARK: - Card affordances

/// What sits in the bottom-right corner of a photo or prompt card.
///
/// There is no like. Arch has no mutual-match gate: if you want to talk to someone
/// in your five, you message them. The only card affordance left is editing your
/// own profile.
enum CardAffordance {
    /// Your own card, on the You tab.
    case edit(action: () -> Void)
    /// Someone else's card. Nothing to do to it directly.
    case none
}

struct CardAffordanceView: View {
    let affordance: CardAffordance
    var subject: String = "this"

    var body: some View {
        switch affordance {
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
            .buttonStyle(PressScaleStyle())
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
        ArchButton(title: "Send", isEnabled: false, action: {})
        ArchButton(title: "Dismiss", kind: .quiet, action: {})
        ArchTextButton(title: "Cancel", action: {})

        CardAffordanceView(affordance: .edit(action: {}), subject: "this photo")
            .padding(.top, ArchSpacing.xl)
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
