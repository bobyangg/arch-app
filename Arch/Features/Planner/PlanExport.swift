import SwiftUI
import UIKit

/// A settled plan, taken out of Arch to anybody at all, through whatever app
/// you like -- Messages, Instagram, WhatsApp. (Into your calendar is
/// `CalendarEventSheet`.)
///
/// **Only from a settled plan, and only when you ask.** Sharing a plan *into*
/// Arch stays in Messages (`ShareWithSheet`), because there it carries the
/// reasons, and the reasons quote what somebody wrote. What leaves Arch here is
/// the plan alone: the day, the times, the places. Nobody's interests, and
/// nothing about why.
enum PlanExport {

    /// The plan as words: its heading and day, then each stop.
    ///
    ///     Thursday evening with Hana
    ///     Thursday, October 22
    ///
    ///     6:30 pm · Short Fuse Coffee, Williamsburg
    static func text(for plan: SharedPlan, title: String) -> String {
        var lines = [title]
        if let day = plan.planDay { lines.append(day.long) }
        lines.append("")
        for stop in plan.stops ?? [] {
            lines.append("\(DatePlanner.clockTime(stop.start)) \u{00B7} \(stop.name), \(stop.neighbourhood)")
        }
        return lines.joined(separator: "\n")
    }

    /// The plan as a picture, for the apps that take one rather than words --
    /// Instagram above all. Drawn by the same card the app shows.
    @MainActor
    static func image(for plan: SharedPlan, title: String) -> UIImage? {
        let renderer = ImageRenderer(content: PlanExportCard(plan: plan, title: title))
        renderer.scale = 3
        return renderer.uiImage
    }

    /// What the share sheet is handed: the picture, when it could be drawn,
    /// and the words. Messages takes both; Instagram takes the picture.
    @MainActor
    static func items(for plan: SharedPlan, title: String) -> [Any] {
        let words: [Any] = [text(for: plan, title: title)]
        return (image(for: plan, title: title).map { [$0] } ?? []) + words
    }
}

/// The exported picture: the plan on the app's own colours, a card's width.
struct PlanExportCard: View {
    let plan: SharedPlan
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                if let day = plan.planDay {
                    Text(day.long)
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
            }
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                ForEach(Array((plan.stops ?? []).enumerated()), id: \.offset) { _, stop in
                    HStack(alignment: .top, spacing: ArchSpacing.s) {
                        Text(DatePlanner.clockTime(stop.start))
                            .archText(.subhead)
                            .foregroundStyle(ArchColor.limestone)
                            .frame(width: 72, alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(stop.name)
                                .archText(.subhead)
                                .foregroundStyle(ArchColor.limestone)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(stop.kind) \u{00B7} \(stop.neighbourhood)")
                                .archText(.footnote)
                                .foregroundStyle(ArchColor.mortar)
                        }
                    }
                }
            }
            Text("Planned with Arch")
                .archText(.caption)
                .foregroundStyle(ArchColor.lamp)
        }
        .padding(ArchSpacing.l)
        .frame(width: 360, alignment: .leading)
        .background(ArchColor.night)
    }
}

/// What "Export" hands the share sheet, while it is open.
struct PlanShareItems: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// The system share sheet: every app on the phone that takes words or a
/// picture. The one place Arch uses it, because this is the one thing meant to
/// leave.
struct PlanShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// What "Add to calendar" is about to add, while Apple's screen is up
/// (`CalendarEventSheet`).
struct PlanCalendarDraft: Identifiable {
    let id = UUID()
    let plan: SharedPlan
    let title: String
}
