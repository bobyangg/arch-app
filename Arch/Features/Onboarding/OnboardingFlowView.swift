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
    /// Shown on the welcome screen. Never red, and never Apple's own wording --
    /// their errors are for a log, not for somebody at the front door of an app
    /// they have not joined yet.
    @State private var problem: String?

    var body: some View {
        ZStack {
            ArchColor.night.ignoresSafeArea()

            if showingWelcome {
                // The real Apple button needs an entitlement and a signed build,
                // and the demo path fills in the name Apple would have supplied.
                // Which one appears is decided by whether there is a backend to
                // sign in to at all, not by a build flag somebody has to remember.
                OnboardingWelcome(
                    onSignIn: { identity in
                        Task { await signIn(identity) }
                    },
                    demoSignIn: ArchConfig.isConfigured ? nil : {
                        store.apply(
                            AppleIdentity(
                                userID: "001234.abcdef", name: "Sam",
                                email: "sam@privaterelay.appleid.com", identityToken: nil
                            )
                        )
                        showingWelcome = false
                    },
                    externalProblem: problem,
                    onEmailSignIn: { address in
                        guard ArchConfig.isConfigured else {
                            // Same reasoning as `demoSignIn` above: with nothing to
                            // register against, walk straight into the flow.
                            store.apply(AppleIdentity(
                                userID: "", name: nil, email: address, identityToken: nil
                            ))
                            showingWelcome = false
                            return
                        }
                        Task { await signedInByEmail(address) }
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

    /// The email path, after `EmailSignInSheet` already has a session.
    ///
    /// It goes through exactly the same `register` call as Apple, which matters
    /// more here than there: `register` is where DeviceCheck runs, and with an
    /// email address costing nothing to invent, the device is the only thing left
    /// making a throwaway account expensive. An email signup that skipped
    /// attestation would be the cheap door Safety says does not exist.
    ///
    /// Apple hands over a name on the first authorization; email hands over
    /// nothing, so the identity carries the address alone and onboarding asks for
    /// the name on the very next screen — which it does for Apple users too
    /// whenever Apple declines to share one.
    private func signedInByEmail(_ address: String) async {
        let identity = AppleIdentity(
            userID: "", name: nil, email: address, identityToken: nil
        )
        do {
            let outcome = try await ArchBackend.register(identity: identity)
            switch outcome {
            case .ok(_, let needsOnboarding, _):
                guard needsOnboarding else {
                    onFinish(ProfileStore(), true)
                    return
                }
                store.apply(identity)
                showingWelcome = false
            case .removed:
                problem = "This account is not available."
            }
        } catch {
            problem = "Arch could not reach the network just now."
        }
    }

    /// Apple has said who somebody is. Two things still have to happen before the
    /// questionnaire is worth filling in.
    ///
    /// Supabase verifies Apple's token against Apple's own keys and issues the
    /// session, so who the caller is is settled by the first call. The second adds
    /// what Supabase does not do: attestation, and the check for whether this
    /// device has been removed before.
    private func signIn(_ identity: AppleIdentity) async {
        guard let token = identity.identityToken,
              let jwt = String(data: token, encoding: .utf8) else {
            problem = "Apple did not send anything Arch could use."
            return
        }
        do {
            _ = try await ArchBackend.signInWithApple(identityToken: jwt)
            let outcome = try await ArchBackend.register(identity: identity)
            switch outcome {
            case .ok(_, let needsOnboarding, _):
                guard needsOnboarding else {
                    // Signing back in is not signing up. Somebody reinstalling the
                    // app already has a profile, and walking them through sixteen
                    // questions again would be asking for what Arch already holds.
                    onFinish(ProfileStore(), true)
                    return
                }
                // Name and email arrive from Apple on the *first* authorization
                // only, so they are put into the draft here and persisted by the
                // register call -- never fetched again later, because there is no
                // later.
                store.apply(identity)
                showingWelcome = false
            case .removed:
                // Handled by the session at the next launch; nothing useful can be
                // said from inside onboarding without repeating that whole screen.
                problem = "This account is not available."
            }
        } catch {
            problem = "Arch could not reach the network just now."
        }
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
        case .questions:     return "Start"
        case .notifications: return "Allow notifications"
        default:             return "Continue"
        }
    }

    // MARK: Steps

    @ViewBuilder
    private var content: some View {
        switch store.step {
        case .birthday:
            OnboardingBirthday(store: store)
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
        guard ArchConfig.isConfigured else {
            onFinish(store.profile, notifications)
            return
        }
        Task {
            await commit(allowing: notifications)
            onFinish(store.profile, notifications)
        }
    }

    /// Everything onboarding collected, written before the app opens.
    ///
    /// **The profile row goes first.** Every other table references it, and an
    /// account with answers but no profile is invisible to the matcher in a way
    /// that looks like nothing happened. If a later write fails the reader lands in
    /// the app with a profile missing a piece, which the You tab already knows how
    /// to show — that is a better failure than being held at a spinner on the last
    /// screen of onboarding with no way forward.
    private func commit(allowing notifications: Bool) async {
        let person = store.profile.person
        try? await ArchBackend.createProfile(
            PersonDetails(
                name: person.name, age: person.age, birthday: person.birthday,
                gender: person.gender, pronouns: person.pronouns,
                place: person.place, height: person.height, work: person.work
            ),
            coordinate: person.coordinate
        )
        try? await ArchBackend.savePrompts(person.prompts)
        try? await ArchBackend.saveInterests(person.interests)

        // Stored as the index of the chosen option, not its words. The grids are
        // indexed by position, and rewording an option is an ordinary copy edit
        // that must not silently rescore everybody who answered before it.
        var answers: [String: Int] = [:]
        for question in Questionnaire.questions {
            guard let chosen = store.questionnaireAnswers[question.id],
                  let index = question.options.firstIndex(of: chosen) else { continue }
            answers[question.id] = index
        }
        try? await ArchBackend.saveAnswers(answers)

        try? await ArchBackend.createDiscovery(
            seeking: store.seekingDrafts.map { ArchUnits.genderColumn($0) },
            notifyMessages: notifications
        )
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
