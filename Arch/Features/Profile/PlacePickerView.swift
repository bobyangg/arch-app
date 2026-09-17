import SwiftUI

/// Where iOS stands on giving Arch a location.
///
/// A design build has no CoreLocation, so this stands in for it. The states are the
/// real ones, which is what the screens have to be built against.
enum LocationPermission: Hashable {
    case notAsked
    case granted
    case denied
}

/// Choosing where you live.
///
/// **The picker is the mechanism; the device is a convenience.** Asking first and
/// falling back to a list would be two paths, and the fallback is always the one
/// that gets less care — so the list is the path, and a location, when there is
/// one, fills it in.
///
/// It has to be a list rather than a map for a reason that is not effort. Arch
/// never shows a distance on anybody's profile, so precision here buys nothing
/// visible; a dropped pin would store roughly where somebody sleeps, which is a
/// more sensitive fact than anything on their profile. What this stores instead —
/// the name of a neighbourhood — is *already* the chip everybody can read.
struct PlacePickerView: View {
    var permission: LocationPermission = .notAsked
    let current: Place?
    let onChoose: (Place) -> Void
    /// Asks the system. The result comes back as a coordinate, already coarsened,
    /// or nil if it was refused.
    var onUseLocation: () -> Void = {}
    let onCancel: () -> Void

    @State private var search = ""
    /// Asks the device's geocoder, which knows every town in the United States
    /// and Canada. Held by the view rather than made per keystroke so that one
    /// lookup can cancel the one before it.
    @State private var searcher = PlaceSearch()

    /// **The design build searches the bundled list instead, and that is not a
    /// shortcut.** The UI tests run in a simulator against `MockData`, where
    /// every profile is in New York and there may be no network at all; a picker
    /// that needed Apple's servers to show a row would make them flaky for a
    /// reason that has nothing to do with what they test.
    private var isOffline: Bool { !ArchConfig.isConfigured }

    private var results: [Place] {
        isOffline ? PlaceLibrary.search(search) : searcher.results
    }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }
    private var isWaiting: Bool { !isOffline && searcher.state == .searching }
    private var isUnreachable: Bool { !isOffline && searcher.state == .unreachable }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            field

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    if permission != .denied && !isSearching {
                        useLocation
                    }

                    if isWaiting && results.isEmpty {
                        note("Looking…", nil)
                    } else if isUnreachable {
                        note("Arch could not reach the map just now.",
                             "It needs a connection to find a town by name. "
                             + "The list below works without one.")
                        suggestions
                    } else if results.isEmpty {
                        nothingFound
                    } else if isSearching {
                        VStack(spacing: ArchSpacing.xs) {
                            ForEach(results) { row($0) }
                        }
                    } else {
                        suggestions
                    }
                }
                .padding(.top, ArchSpacing.m)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
        }
        .onChange(of: search) { _, text in
            guard !isOffline else { return }
            searcher.search(text)
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Text("Where you live")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)
            Spacer(minLength: 0)
            Button(action: onCancel) {
                Text("Cancel")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            .buttonStyle(PressScaleStyle(scale: 1))
        }
        .padding(.top, ArchSpacing.l)
    }

    private var field: some View {
        ArchField(text: $search, placeholder: "Search")
            .padding(.top, ArchSpacing.m)
    }

    /// Offered, never insisted on. Denying it costs nothing — the list underneath
    /// is the same list either way.
    private var useLocation: some View {
        Button(action: onUseLocation) {
            HStack(spacing: ArchSpacing.s) {
                Image(systemName: "location")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.mortar)
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text("Use my location")
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                    Text("Fills this in, and places you to about a kilometre. Arch keeps nothing finer than that.")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
            }
            .padding(ArchSpacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.stoneRaised)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
    }

    /// What is offered before anybody types: the bundled list, grouped.
    ///
    /// It is a set of suggestions rather than the extent of the app. Anywhere in
    /// either country can be typed into the field above.
    @ViewBuilder
    private var suggestions: some View {
        ForEach(PlaceLibrary.groups, id: \.city) { group in
            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                Text(group.city)
                    .archText(.prompt)
                    .foregroundStyle(ArchColor.mortar)
                VStack(spacing: ArchSpacing.xs) {
                    ForEach(group.places) { row($0) }
                }
            }
        }
    }

    private var nothingFound: some View {
        note("Nothing by that name",
             isSearching
                ? "Arch is in the United States and Canada. Try the town, or the "
                  + "nearest one."
                : nil)
    }

    private func note(_ title: String, _ detail: String?) -> some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text(title)
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)
            if let detail {
                Text(detail)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(_ place: Place) -> some View {
        let isCurrent = place.id == current?.id
        return Button { onChoose(place) } label: {
            HStack(spacing: ArchSpacing.s) {
                VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                    Text(place.name)
                        .archText(.body)
                        .foregroundStyle(ArchColor.limestone)
                        .multilineTextAlignment(.leading)
                    // Only while searching, when a bare name has lost its column.
                    if isSearching {
                        Text(place.city)
                            .archText(.footnote)
                            .foregroundStyle(ArchColor.mortar)
                    }
                }
                Spacer(minLength: 0)
                if isCurrent {
                    Image(systemName: "checkmark")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.limestone)
                }
            }
            .padding(.horizontal, ArchSpacing.m)
            .padding(.vertical, ArchSpacing.s + 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(isCurrent ? ArchColor.stoneRaised : ArchColor.stone)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityLabel(place.label)
        .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
    }
}

/// The row that opens it, built to read like an `ArchField` for the same reason
/// `HeightRow` is — it sits in a column of them.
struct PlaceRow: View {
    let place: Place?
    var surface: Color = ArchColor.night
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: ArchSpacing.s) {
                Text("Where you live")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                    .frame(width: 108, alignment: .leading)
                Text(place?.label ?? "Choose")
                    .archText(.callout)
                    .foregroundStyle(place == nil ? ArchColor.mortar : ArchColor.limestone)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
            }
            .padding(ArchSpacing.s)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(surface)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressScaleStyle(scale: 0.99))
        .accessibilityLabel(place.map { "Where you live, \($0.label)" } ?? "Where you live, not chosen")
    }
}

// MARK: - Previews

#Preview("Nothing chosen") {
    PlacePickerView(current: nil, onChoose: { _ in }, onCancel: {})
        .padding(.horizontal, ArchSpacing.screenMargin)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(ArchColor.stone)
        .preferredColorScheme(.dark)
}

#Preview("Already somewhere") {
    PlacePickerView(
        permission: .granted,
        current: PlaceLibrary.place(matching: "bk-fort-greene"),
        onChoose: { _ in },
        onCancel: {}
    )
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.stone)
    .preferredColorScheme(.dark)
}

/// Refused in iOS settings, so the offer is gone rather than sitting there failing.
#Preview("Location refused") {
    PlacePickerView(
        permission: .denied,
        current: nil,
        onChoose: { _ in },
        onCancel: {}
    )
    .padding(.horizontal, ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.stone)
    .preferredColorScheme(.dark)
}
