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
struct PremiumView: View {
    var benefits: [PremiumBenefit] = MockData.premiumBenefits
    var plans: [PremiumPlan] = MockData.premiumPlans
    var isSubscribed: Bool = false

    @State private var selectedPlanID: String?

    private var selectedPlan: PremiumPlan? {
        plans.first { $0.id == selectedPlanID }
            ?? plans.first { $0.isRecommended }
            ?? plans.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                masthead
                benefitList
                planList
                footer
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .background(ArchColor.night)
        .scrollIndicators(.hidden)
    }

    // MARK: Pieces

    private var masthead: some View {
        // No mark here. The mark is drawn in `lamp`, and a paywall is exactly the
        // screen where a second piece of accent would start competing with the one
        // thing on it that is an action. The serif title carries the brand.
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            Text("Arch Premium")
                .archText(.titleL)
                .foregroundStyle(ArchColor.limestone)

            Text("More room in your roster, and more room to say who you are.")
                .archText(.body)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, ArchSpacing.m)
        .padding(.bottom, ArchSpacing.sectionGap)
    }

    /// Hairlines rather than bullets. A marker on every row would either be a fifth
    /// use of `lamp` or a piece of decoration; a rule is structure.
    private var benefitList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.element.id) { index, benefit in
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text(benefit.title)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Text(benefit.detail)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, ArchSpacing.m)

                if index < benefits.count - 1 {
                    Rectangle()
                        .fill(ArchColor.hairline)
                        .frame(height: ArchSpacing.hairline)
                }
            }
        }
        .padding(.bottom, ArchSpacing.sectionGap)
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
            ArchButton(title: subscribeTitle, isEnabled: !isSubscribed) {}
                .padding(.top, ArchSpacing.l)

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
                        Text("Recommended")
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                    }
                }
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(isSelected ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .overlay(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .strokeBorder(
                        isSelected ? ArchColor.limestone.opacity(0.30) : Color.clear,
                        lineWidth: 1
                    )
            )
            .animation(ArchMotion.quick, value: isSelected)
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
