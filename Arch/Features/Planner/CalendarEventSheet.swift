import CoreLocation
import EventKit
import EventKitUI
import SwiftUI

/// "Add to calendar": Apple's own new-event screen, filled in with a settled
/// plan -- a date you both said yes to, or a self plan you confirmed.
///
/// **Apple's screen rather than writing the event ourselves, and not for the
/// look.** From iOS 17 it runs outside the app, so Arch never asks for, and
/// never has, access to anybody's calendar: it hands over a filled-in event and
/// you tap Add, or change anything first, or cancel. Nothing is written until
/// you do.
///
/// The event is the plan as settled: "Date with Sahij", from the first stop to
/// the end of the last, at the first place -- with its position, so Calendar
/// can offer directions and a time to leave -- and every stop in the notes.
struct CalendarEventSheet: UIViewControllerRepresentable {
    let plan: SharedPlan
    /// The event's name: "Date with Sahij", "Self plan".
    let title: String
    let onDone: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDone: onDone) }

    func makeUIViewController(context: Context) -> EKEventEditViewController {
        let store = EKEventStore()
        let controller = EKEventEditViewController()
        controller.eventStore = store
        controller.event = Self.event(for: plan, titled: title, in: store)
        controller.editViewDelegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}

    final class Coordinator: NSObject, EKEventEditViewDelegate {
        let onDone: () -> Void
        init(onDone: @escaping () -> Void) { self.onDone = onDone }

        /// Added or cancelled, the sheet goes; Calendar has already done the
        /// saving, if there was any.
        func eventEditViewController(_ controller: EKEventEditViewController,
                                     didCompleteWith action: EKEventEditViewAction) {
            onDone()
        }
    }

    /// A settled plan as a calendar event.
    static func event(for plan: SharedPlan, titled title: String, in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        let stops = plan.stops ?? []
        // A plan from before days were chosen has none; today is the honest
        // guess, and the screen lets it be changed before it is added.
        let day = plan.planDay ?? PlanDay.today
        let starts = stops.first?.start ?? plan.timeOfDay?.start ?? 18 * 60
        let lastEnds = stops.last.map { $0.start + ($0.minutes ?? 60) }
        let ends = max(lastEnds ?? starts + 120, starts + 30)

        event.title = title
        event.startDate = day.at(minutes: starts)
        event.endDate = day.at(minutes: ends)
        if let first = stops.first {
            let place = EKStructuredLocation(
                title: first.neighbourhood.isEmpty ? first.name : "\(first.name), \(first.neighbourhood)"
            )
            if let latitude = first.latitude, let longitude = first.longitude {
                place.geoLocation = CLLocation(latitude: latitude, longitude: longitude)
            }
            event.structuredLocation = place
        }
        event.notes = (stops.map {
            "\(DatePlanner.clockTime($0.start)) \u{00B7} \($0.name)"
                + ($0.neighbourhood.isEmpty ? "" : ", \($0.neighbourhood)")
        } + ["", "Planned in Arch."]).joined(separator: "\n")
        return event
    }
}

private extension PlanDay {
    /// This day at so many minutes after midnight, in this phone's calendar --
    /// past 24 hours runs into the next day, which is where a bar's last hour is.
    func at(minutes: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        let midnight = Calendar.current.date(from: components) ?? date
        return Calendar.current.date(byAdding: .minute, value: minutes, to: midnight) ?? midnight
    }
}
