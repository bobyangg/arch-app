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
    /// What happened last time it was tapped, when what happened needs saying.
    ///
    /// **Silence was the whole problem.** The button asked for permission, was
    /// granted it, failed to turn the fix into a name, and then said nothing at
    /// all — so it read as a dead control, and tapping it again did the same
    /// nothing. A screen that cannot succeed quietly should not fail quietly.
    var locationNote: String? = nil
    /// Whether the list and the search are on offer at all.
    ///
    /// Onboarding says yes: a place has to come from somewhere, and the device
    /// is a convenience that may be refused. After that, choosing a place you
    /// are not in is part of Arch Premium, and everybody else gets the one
    /// button that puts them where they are. The picker draws both, so the two
    /// paths cannot drift apart.
    var canChoose: Bool = true
    /// Where "See Arch Premium" goes when `canChoose` is false. Nil hides it.
    var onOpenPremium: (() -> Void)? = nil

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
    private var typed: String { search.trimmingCharacters(in: .whitespaces) }
    private var isSearching: Bool { !typed.isEmpty }
    private var isWaiting: Bool { !isOffline && searcher.state == .searching }
    private var isUnreachable: Bool { !isOffline && searcher.state == .unreachable }

    /// **One character is not a failed search, and saying so was the bug.**
    /// `PlaceSearch` does not ask the geocoder below two characters, so the
    /// results were empty and the screen read "Nothing by that name" — which,
    /// after typing the C of Calgary, says the app does not have Canada in it.
    private var isTooShort: Bool { !isOffline && typed.count < 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if canChoose { field }

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    if permission != .denied && !isSearching {
                        useLocation
                    }
                    locationNoteRow

                    if !canChoose {
                        premiumNote
                    } else if isTooShort {
                        suggestions
                    } else if isWaiting && results.isEmpty {
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
            Text(canChoose ? "Where you live" : "Where you are")
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

    /// **The placeholder is the only thing that says what this can do.**
    /// The list underneath is the same thirty-two New York rows it has always
    /// been, so a picker that said "Search" looked exactly like the one that
    /// could only find those thirty-two. Somebody would open it, see the same
    /// screen, and conclude the app is still only in New York — which is what
    /// happened.
    private var field: some View {
        ArchField(text: $search, placeholder: "Any town in the US or Canada")
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

    /// The half of the picker that is not on offer, and why.
    ///
    /// Said plainly and once, on the same surface as everything else. The button
    /// is a text button rather than a `lamp` one: the screen was opened to set a
    /// location, and the thing it should push hardest is the button that does.
    private var premiumNote: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            if permission == .denied {
                Text("Arch places you from your phone's location, which is off for Arch. Turn it on in your iPhone settings, and this puts you where you are.")
                    .archText(.body)
                    .foregroundStyle(ArchColor.limestone)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Choosing somewhere you are not — a city you are moving to, or one you visit — is part of Arch Premium.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
            if let onOpenPremium {
                ArchTextButton(title: "See Arch Premium", action: onOpenPremium)
            }
        }
    }

    @ViewBuilder
    private var locationNoteRow: some View {
        if let locationNote {
            Text(locationNote)
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// What is offered before anybody types.
    ///
    /// **Not thirty-two New York neighbourhoods any more.** They were the whole
    /// gazetteer once, so listing them was listing the app; now they are one
    /// metro out of two countries, and opening this screen to a column of
    /// Brooklyn made Arch look like a Brooklyn app to everybody who is not in
    /// Brooklyn — which is almost everybody.
    ///
    /// What replaces them is nothing, on purpose. The two controls that matter
    /// are the search field and the location button, and an empty space below
    /// them points at both. The design build still lists them, because its
    /// mock people all live there and it has no geocoder to search with.
    @ViewBuilder
    private var suggestions: some View {
        if isOffline {
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
        } else {
            // Shown rather than hidden, because a place that came from the
            // geocoder is in no list and would otherwise be invisible here --
            // the screen would look as though nothing had been chosen.
            if let current {
                VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                    Text("Where you live")
                        .archText(.prompt)
                        .foregroundStyle(ArchColor.mortar)
                    row(current)
                }
            }
            Text("Type the town or neighbourhood where you live. Anywhere in the "
                 + "United States or Canada.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
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
