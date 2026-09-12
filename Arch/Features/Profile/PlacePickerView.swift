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

    private var results: [Place] { PlaceLibrary.search(search) }
    private var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            field

            ScrollView {
                VStack(alignment: .leading, spacing: ArchSpacing.xl) {
                    if permission != .denied && !isSearching {
                        useLocation
                    }

                    if results.isEmpty {
                        nothingFound
                    } else if isSearching {
                        VStack(spacing: ArchSpacing.xs) {
                            ForEach(results) { row($0) }
                        }
                    } else {
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
                }
                .padding(.top, ArchSpacing.m)
                .padding(.bottom, ArchSpacing.sectionGap)
            }
            .scrollIndicators(.hidden)
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

    private var nothingFound: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.xs) {
            Text("Nothing by that name")
                .archText(.body)
                .foregroundStyle(ArchColor.limestone)
            Text("Try the borough or the town instead — Arch is only in New York so far.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)
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
