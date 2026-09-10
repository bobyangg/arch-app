import SwiftUI

/// The first thing a stranger sees.
///
/// It exists because opening an app straight onto "enter your phone number" asks
/// for something before explaining what the thing is. One screen, the premise, one
/// button. No progress rule — nothing has been asked yet, so there is no progress
/// to report.
struct OnboardingWelcome: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            ArchMark(lineWidth: 4)
                .stroke(
                    ArchColor.lamp,
                    style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round)
                )
                .frame(width: 84, height: 76)

            Text("Arch")
                .archText(.display)
                .foregroundStyle(ArchColor.limestone)
                .padding(.top, ArchSpacing.m)

            Spacer()

            Text(MockData.onboardingHeadline)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)

            Text(MockData.onboardingBody)
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, ArchSpacing.s)

            Spacer()

            ArchButton(title: "Get started", action: onStart)
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.vertical, ArchSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

#Preview("Welcome") {
    OnboardingWelcome {}
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
