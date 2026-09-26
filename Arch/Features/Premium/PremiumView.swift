import SwiftUI

/// Arch Premium.
///
/// A paywall built like the rest of the app rather than bolted onto it: no
/// countdown, no "only today", no gradient wash, no crossed-out prices. It says
/// what you get, what it costs per month, and what happens when you tap the button.
///
/// **`lamp` appears once, on the subscribe button.** The recommended plan is marked
/// by surface and a word, not by colour — if the accent were used to sell as well
/// as to act, it would stop meaning "this is the action".
///
/// Nothing here sells scores, rankings, or information about who has looked at you.
/// None of that exists in Arch, and a paywall is the easiest place to accidentally
/// invent it.
///
/// **Nobody scrolls to be sold to.** The benefits used to be a list at full length,
/// which put the plans and the button about a screen and a half down: buying was
/// something you arrived at rather than something you could do. They are a rail of
/// bubbles now -- one at a time, pushed sideways -- so the price and the button sit
/// on the first screen at the app's smallest size. The page is still a scroll, and
/// that is deliberate: at the largest Dynamic Type sizes the column is taller than
/// any phone, and clipping the button would be worse than scrolling to it.
struct PremiumView: View {
    var benefits: [PremiumBenefit] = MockData.premiumBenefits
    var plans: [PremiumPlan] = MockData.premiumPlans
    var isSubscribed: Bool = false
    /// Design-only: flips the subscription so the difference is visible.
    var onSubscribe: () -> Void = {}

    @State private var selectedPlanID: String?
    /// Which bubble the rail has settled on. Drives the dots, and nothing else.
    @State private var currentBenefitID: String?

    private var selectedPlan: PremiumPlan? {
        plans.first { $0.id == selectedPlanID }
            ?? plans.first { $0.isRecommended }
            ?? plans.first
    }

    var body: some View {
        TopBarScroll {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                    .padding(.horizontal, ArchSpacing.screenMargin)
                // The rail is the one thing that reaches the screen's edges: a
                // bubble cut off by the margin is what tells you to push it.
                benefitRail
                dots
                    .padding(.horizontal, ArchSpacing.screenMargin)
                planList
                    .padding(.horizontal, ArchSpacing.screenMargin)
                footer
                    .padding(.horizontal, ArchSpacing.screenMargin)
            }
            .padding(.bottom, ArchSpacing.l)
        }
        .background(ArchColor.night)
    }

    // MARK: Pieces

    private var masthead: some View {
        // No mark in the masthead. The bar above carries the one lock-up every tab
        // gets; a second mark down here, in `lamp`, is exactly what a paywall cannot
        // afford — it would compete with the one thing on the screen that is an
        // action. The serif title carries the brand.
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Arch Premium")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            Text("More room in your roster, and a clearer view of your own profile.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ArchSpacing.xs)
        .padding(.bottom, ArchSpacing.l)
    }

    /// The benefits, one at a time, on a rail that snaps.
    ///
    /// Every benefit is still here and still in full: a carousel that quietly drops
    /// two of the five would be the paywall lying by layout. What it saves is the
    /// vertical space five of them at once were spending.
    ///
    /// The bubbles are cards rather than a new shape -- the roster card's anatomy,
    /// a subhead over a footnote, at a third the size -- and each is a little
    /// narrower than the screen so the next one shows past the margin. That peek is
    /// the affordance; there is no arrow and no "swipe" label.
    private var benefitRail: some View {
        ScrollView(.horizontal) {
            // Five cards: an HStack, not a lazy one. Laziness on a list this
            // short buys nothing and costs the rail its measured width.
            HStack(spacing: ArchSpacing.s) {
                ForEach(benefits) { benefit in
                    BenefitBubble(benefit: benefit)
                        .containerRelativeFrame(.horizontal, alignment: .center) { width, _ in
                            width * Self.bubbleWidth
                        }
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $currentBenefitID, anchor: .center)
        .safeAreaPadding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.s)
    }

    /// How much of the screen's width one bubble takes. The remainder is what the
    /// next bubble shows by.
    private static let bubbleWidth: CGFloat = 0.78

    /// Where you are on the rail. The one the rail has settled on is a bar rather
    /// than a dot, so the row reads at a glance and does not need colour to do it.
    ///
    /// Hidden from VoiceOver: it is a picture of the rail's state, and the rail
    /// itself already announces each bubble as you reach it.
    private var dots: some View {
        HStack(spacing: ArchSpacing.xxs + 2) {
            ForEach(benefits) { benefit in
                let isCurrent = (currentBenefitID ?? benefits.first?.id) == benefit.id
                Capsule(style: .continuous)
                    .fill(isCurrent ? ArchColor.lamp : ArchColor.quietBorder)
                    .frame(width: isCurrent ? 16 : 6, height: 6)
                    .animation(ArchMotion.standard, value: isCurrent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, ArchSpacing.l)
        .accessibilityHidden(true)
    }

    private var planList: some View {
        VStack(spacing: ArchSpacing.s) {
            ForEach(plans) { plan in
                PlanRow(
                    plan: plan,
                    isSelected: selectedPlan?.id == plan.id,
                    onSelect: { selectedPlanID = plan.id }
                )
            }
        }
    }

    private var footer: some View {
        VStack(spacing: ArchSpacing.s) {
            ArchButton(title: subscribeTitle, isEnabled: !isSubscribed, action: onSubscribe)
                .padding(.top, ArchSpacing.m)

            Text(MockData.premiumFootnote)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            ArchTextButton(title: "Restore purchases") {}
        }
    }

    private var subscribeTitle: String {
        if isSubscribed { return "You have Arch Premium" }
        guard let plan = selectedPlan else { return "Subscribe" }
        return "Subscribe for \(plan.total)"
    }
}

/// One benefit, as a card on the rail.
///
/// A fixed height rather than a hugging one, so the rail does not change shape as
/// it moves and the dots below it never shift. The tallest of the five sets it;
/// the shorter ones carry air at the bottom, which is the price of a rail that
/// holds still.
struct BenefitBubble: View {
    let benefit: PremiumBenefit

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text(benefit.title)
                .archText(.subhead)
                .foregroundStyle(ArchColor.limestone)
            Text(benefit.detail)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
        .padding(ArchSpacing.m)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
        )
        .accessibilityElement(children: .combine)
    }
}

/// One plan.
///
/// The recommended plan is marked by a raised surface and the word "Recommended",
/// never by the accent — and every plan shows its per-month cost, so the long ones
/// cannot hide behind a bigger total.
struct PlanRow: View {
    let plan: PremiumPlan
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text(plan.duration)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Text(plan.perMonth)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }

                Spacer(minLength: ArchSpacing.m)

                VStack(alignment: .trailing, spacing: ArchSpacing.xxs) {
                    Text(plan.total)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    if plan.isRecommended {
                        // The one place the second accent appears. It marks the
                        // thing you can buy, which is what it has always been for.
                        Text("Recommended")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.ember)
                    }
                }
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(isSelected ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .archSelected(isSelected, radius: ArchRadius.control, tint: ArchColor.limestone)
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityLabel("\(plan.duration), \(plan.total), \(plan.perMonth)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Previews

#Preview("Premium") {
    PremiumView()
        .preferredColorScheme(.dark)
}

#Preview("Premium, subscribed") {
    PremiumView(isSubscribed: true)
        .preferredColorScheme(.dark)
}
