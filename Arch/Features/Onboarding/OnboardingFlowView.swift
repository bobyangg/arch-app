import SwiftUI

/// The container: welcome, then eight steps, then the app.
///
/// It owns the two things every step shares — the back affordance and the progress
/// rule — plus the Continue button, so the step views are just their content and
/// none of them re-implements a footer.
struct OnboardingFlowView: View {
    /// The profile, and whether notifications were allowed. The second is not the
    /// profile's business, but Settings has to know and this is where it is asked.
    let onFinish: (ProfileStore, Bool) -> Void

    @State private var store = OnboardingStore()
    @State private var showingWelcome = true

    var body: some View {
        ZStack {
            ArchColor.night.ignoresSafeArea()

            if showingWelcome {
                // Design-only: the real Apple button needs an entitlement and a
                // signed build, so this build takes the demo path and fills the
                // name Apple would have supplied.
                OnboardingWelcome(
                    onSignIn: { identity in
                        store.apply(identity)
                        showingWelcome = false
                    },
                    demoSignIn: {
                        store.apply(
                            AppleIdentity(
                                userID: "001234.abcdef", name: "Sam",
                                email: "sam@privaterelay.appleid.com", identityToken: nil
                            )
                        )
                        showingWelcome = false
                    }
                )
                    .transition(.opacity)
            } else {
                flow
                    .transition(.opacity)
            }
        }
        .animation(ArchMotion.standard, value: showingWelcome)
    }

    private var flow: some View {
        VStack(spacing: 0) {
            topBar
            ScrollView {
                content
                    .padding(.horizontal, ArchSpacing.screenMargin)
                    .padding(.top, ArchSpacing.xl)
                    .padding(.bottom, ArchSpacing.xl)
            }
            .scrollIndicators(.hidden)
            footer
        }
    }

    // MARK: Chrome

    private var topBar: some View {
        VStack(spacing: ArchSpacing.s) {
            HStack(spacing: ArchSpacing.s) {
                if store.canGoBack {
                    Button { store.back() } label: {
                        Image(systemName: "chevron.left")
                            .archText(.subhead)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(
                                width: ArchSpacing.minimumTapTarget,
                                height: ArchSpacing.minimumTapTarget
                            )
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("Back")
                } else {
                    Color.clear
                        .frame(
                            width: ArchSpacing.minimumTapTarget,
                            height: ArchSpacing.minimumTapTarget
                        )
                }
                Spacer(minLength: 0)
            }

            StepRule(total: store.ruleTotal, current: store.ruleCurrent)
                .padding(.horizontal, ArchSpacing.screenMargin)
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.s)
    }

    @ViewBuilder
    private var footer: some View {
        // The questionnaire advances on choosing an option, so it has no button to
        // press and no dead footer sitting under it.
        if store.questionIndex == nil {
            VStack(spacing: ArchSpacing.xs) {
                ArchButton(title: continueTitle, isEnabled: store.canContinue) {
                    switch store.step {
                    case .notifications: finish(allowing: true)
                    case .questions:     store.startQuestions()
                    default:             store.advance()
                    }
                }
                if store.step == .notifications {
                    ArchTextButton(title: "Not now") { finish(allowing: false) }
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.xs)
        }
    }

    private var continueTitle: String {
        switch store.step {
        case .verify:        return store.hasSentCode ? "Verify" : "Send a code"
        case .questions:     return "Start"
        case .notifications: return "Allow notifications"
        default:             return "Continue"
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch store.step {
        case .verify:
            if store.hasSentCode {
                OnboardingCode(store: store)
            } else {
                OnboardingPhone(store: store)
            }
        case .identity:
            OnboardingIdentity(store: store)
        case .about:
            OnboardingAbout(store: store)
        case .seeking:
            OnboardingSeeking(store: store)
        case .photos:
            OnboardingPhotos(store: store)
        case .answers:
            OnboardingAnswers(store: store)
        case .interests:
            OnboardingInterests(store: store)
        case .questions:
            OnboardingQuestionnaire(store: store)
        case .notifications:
            OnboardingNotifications()
        }
    }

    private func finish(allowing notifications: Bool) {
        store.allowsNotifications = notifications
        onFinish(store.profile, notifications)
    }
}

/// The title and supporting line every step opens with.
struct StepHeading: View {
    let title: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text(title)
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)
                .fixedSize(horizontal: false, vertical: true)
            if let detail {
                Text(detail)
                    .archText(.body)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Onboarding") {
    OnboardingFlowView { _, _ in }
        .preferredColorScheme(.dark)
}
