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

/// A single photograph in the profile scroll, with its own like affordance. The
/// affordance belongs to this photo — that is the whole point of the pattern.
struct PhotoCard: View {
    let photo: Photo
    var affordance: CardAffordance = .none
    /// Where this photo sits in the profile, for VoiceOver.
    var position: Int = 1

    var body: some View {
        PhotoPlaceholder(toneIndex: photo.toneIndex)
            .aspectRatio(4.0 / 5.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.photo, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                CardAffordanceView(affordance: affordance, subject: "photo \(position)")
                    .padding(ArchSpacing.xs)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo \(position)")
    }
}

#Preview("Photo card") {
    ScrollView {
        VStack(spacing: ArchSpacing.cardGap) {
            PhotoCard(
                photo: MockData.nadia.photos[0],
                affordance: .like(isLiked: false, action: {}),
                position: 1
            )
            PhotoCard(
                photo: MockData.nadia.photos[1],
                affordance: .like(isLiked: true, action: {}),
                position: 2
            )
            PhotoCard(
                photo: MockData.you.photos[0],
                affordance: .edit(action: {}),
                position: 1
            )
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
