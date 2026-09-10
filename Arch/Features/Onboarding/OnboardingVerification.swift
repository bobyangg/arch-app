import SwiftUI

/// Your number.
///
/// The reason is stated on the screen rather than buried in a privacy policy,
/// because "why does a dating app want my phone number" is a fair question and the
/// answer is a good one.
struct OnboardingPhone: View {
    let store: OnboardingStore
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Your number",
                detail: "Arch verifies every number. It is the main thing keeping this from filling up with accounts that are not people."
            )

            HStack(spacing: ArchSpacing.xs) {
                Text("+1")
                    .archText(.callout)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.horizontal, ArchSpacing.s)
                    .padding(.vertical, ArchSpacing.s)
                    .background(
                        RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                            .fill(ArchColor.stone)
                    )

                ArchField(
                    text: Binding(get: { store.phone }, set: { store.phone = $0 }),
                    placeholder: "917 555 0142",
                    keyboard: .phonePad,
                    surface: ArchColor.stone,
                    isFocused: $focused
                )
            }

            Text("Your number is never shown to anyone and never appears on your profile.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onAppear { focused = true }
    }
}

/// The code.
///
/// Six boxes over an invisible field — one text binding, six glyphs. The number is
/// repeated above them so a typo is obvious now rather than after waiting for a
/// message that was never going to arrive.
struct OnboardingCode: View {
    let store: OnboardingStore
    @FocusState private var focused: Bool
    @State private var resent = false

    private var digits: [String] {
        let characters = Array(store.code.prefix(6))
        return (0..<6).map { index in
            index < characters.count ? String(characters[index]) : ""
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xl) {
            StepHeading(
                title: "Check your messages",
                detail: "We sent a six-digit code to +1 \(store.phone)."
            )

            ZStack {
                TextField("", text: Binding(
                    get: { store.code },
                    set: { store.code = String($0.filter(\.isNumber).prefix(6)) }
                ))
                .keyboardType(.numberPad)
                .focused($focused)
                .opacity(0.01)

                HStack(spacing: ArchSpacing.xs) {
                    ForEach(Array(digits.enumerated()), id: \.offset) { _, digit in
                        Text(digit)
                            .archText(.titleM)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                                    .fill(ArchColor.stone)
                            )
                    }
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onTapGesture { focused = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Six-digit code")

            Button { resent = true } label: {
                Text(resent ? "Code sent again" : "Send it again")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            .buttonStyle(PressScaleStyle(scale: 1))
            .disabled(resent)
        }
        .onAppear { focused = true }
    }
}

#Preview("Phone number") {
    OnboardingPhone(store: OnboardingStore())
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}

#Preview("Code") {
    OnboardingCode(store: .configured {
        $0.phone = "917 555 0142"
        $0.code = "4192"
    })
        .padding(ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.night)
        .preferredColorScheme(.dark)
}
