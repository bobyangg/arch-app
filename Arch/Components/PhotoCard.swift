import SwiftUI

/// Stands in for a photograph. Nothing is fetched and nothing is stock: each block
/// is a quarry tone from the palette with a four-to-six percent fall-off top to
/// bottom, so it reads as a lit surface rather than as a coloured rectangle.
struct PhotoPlaceholder: View {
    let toneIndex: Int

    var body: some View {
        let material = ArchColor.material(toneIndex)
        Rectangle()
            .fill(
                LinearGradient(
                    colors: [material.top, material.bottom],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
    }
}

/// A single photograph in a profile scroll.
///
/// There is no like button here. In the profile detail, tapping the card selects
/// it, and the selection is carried into the message composer as quoted context —
/// the card is the control, so no per-item buttons exist anywhere in the app.
struct PhotoCard: View {
    /// The shape every profile photograph is drawn in, and the shape the crop step
    /// cuts to. One number, so the two cannot disagree.
    ///
    /// Square. The 4:5 it replaced was a fifth taller, and at a phone's width a
    /// lead photo at 4:5 is most of the screen before a name appears; a profile
    /// should show a face and whose it is in one glance. Square also makes the
    /// thumbnails in the arrange grid an honest preview of the photo rather than a
    /// crop of it.
    static let aspect: CGFloat = 1

    let photo: Photo
    /// Editing, on your own profile. Never a like.
    var affordance: CardAffordance = .none
    /// Where this photo sits in the profile, for VoiceOver.
    var position: Int = 1
    var aspectRatio: CGFloat = PhotoCard.aspect
    /// Selected as the thing the first message will be about.
    var isSelected: Bool = false
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) { card }
                .buttonStyle(PressScaleStyle(scale: 0.985))
                .accessibilityLabel("Photo \(position)")
                .accessibilityHint("Write your message about this photo")
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        } else {
            card
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Photo \(position)")
        }
    }

    private var card: some View {
        PhotoPlaceholder(toneIndex: photo.toneIndex)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous)
                    .strokeBorder(isSelected ? ArchColor.lampQuiet : Color.clear, lineWidth: 1)
            )
            .overlay(alignment: .bottomTrailing) {
                CardAffordanceView(affordance: affordance, subject: "photo \(position)")
                    .padding(ArchSpacing.xs)
            }
            .animation(ArchMotion.quick, value: isSelected)
    }
}

#Preview("Photo card") {
    ScrollView {
        VStack(spacing: ArchSpacing.cardGap) {
            PhotoCard(photo: MockData.nadia.photos[0], position: 1)
            PhotoCard(photo: MockData.nadia.photos[1], position: 2, isSelected: true, onTap: {})
            PhotoCard(photo: MockData.you.photos[0], affordance: .edit(action: {}), position: 1)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xxl)
    }
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

#Preview("Quarry tones") {
    VStack(spacing: 0) {
        ForEach(Array(ArchColor.materials.enumerated()), id: \.offset) { index, material in
            HStack(spacing: ArchSpacing.m) {
                PhotoPlaceholder(toneIndex: index)
                    .frame(width: 88, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.detail, style: .continuous))
                Text(material.name)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Spacer()
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.vertical, ArchSpacing.xs)
        }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
