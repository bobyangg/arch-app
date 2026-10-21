import MapKit
import SwiftUI

/// "Custom spot": a place you name, added to an item of the date.
///
/// **On the map** -- Apple's own map, in the app -- any place Apple shows can
/// be tapped: a café, a park, a restaurant, a beach. What you search for is
/// pinned on it too. Tapping either shows the place at the bottom with "Add to
/// the date". **The list** is the same search as rows, for when you know the
/// name. In a design build the search is the bundled places; the map's own
/// places are Apple's either way.
struct CustomSpotSheet: View {
    let isLive: Bool
    let near: Coordinate?
    /// The design build's places, searched by name instead of Apple Maps.
    let library: [Venue]
    let onPick: (Venue) -> Void
    let onCancel: () -> Void

    private enum Mode: String, CaseIterable, Identifiable {
        case map = "Map", list = "List"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .map
    @State private var query = ""
    @State private var results: [Venue] = []
    @State private var unreachable = false
    @State private var searching = false
    @State private var camera: MapCameraPosition = .automatic
    /// The place on Apple's map you tapped, while it is being looked at.
    @State private var feature: MapFeature?
    /// The place shown at the bottom of the map, ready to add.
    @State private var chosen: Venue?
    @State private var lookingUp = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Add your own spot")
                    .archText(.titleM)
                    .foregroundStyle(ArchColor.limestone)
                Spacer(minLength: 0)
                ArchTextButton(title: "Cancel", action: onCancel)
                    .fixedSize()
            }
            .padding(.top, ArchSpacing.xl)

            ArchField(text: $query, placeholder: "Search for a place", surface: ArchColor.night)
                .accessibilityIdentifier("planner.custom.search")
                .padding(.top, ArchSpacing.m)

            modeSwitch
                .padding(.top, ArchSpacing.s)

            switch mode {
            case .map:  map
            case .list: list
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
        .onAppear {
            if let near {
                camera = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: near.latitude, longitude: near.longitude),
                    latitudinalMeters: 3_000, longitudinalMeters: 3_000))
            }
        }
        // A beat after the last keystroke, so a word is one search, not five.
        .task(id: query) {
            let words = query.trimmingCharacters(in: .whitespaces)
            guard words.count >= 2 else { results = []; return }
            let found: [Venue]?
            if isLive {
                searching = true
                try? await Task.sleep(nanoseconds: 350_000_000)
                guard !Task.isCancelled else { return }
                found = await VenueSearch.find(words, near: near)
                guard !Task.isCancelled else { return }
            } else {
                found = library.filter { $0.name.localizedCaseInsensitiveContains(words) }
            }
            unreachable = found == nil
            results = found ?? []
            searching = false
            // Frame what was found, so the pins are on screen.
            if !results.isEmpty { withAnimation(ArchMotion.standard) { camera = .automatic } }
        }
    }

    // MARK: Map or list

    /// Two buttons in a capsule, like the time of day on the planner.
    private var modeSwitch: some View {
        HStack(spacing: 0) {
            ForEach(Mode.allCases) { option in
                let isOn = option == mode
                Button { mode = option } label: {
                    Text(option.rawValue)
                        .archText(.footnote)
                        .foregroundStyle(isOn ? ArchColor.limestone : ArchColor.mortar)
                        .padding(.horizontal, ArchSpacing.m)
                        .frame(height: 30)
                        .background(Capsule().fill(isOn ? ArchColor.stoneRaised : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(PressScaleStyle(scale: 0.97))
                .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("planner.custom.mode.\(option.rawValue.lowercased())")
            }
        }
        .padding(3)
        .background(Capsule().fill(ArchColor.stone))
    }

    // MARK: The map

    private var map: some View {
        ZStack(alignment: .bottom) {
            Map(position: $camera, selection: $feature) {
                ForEach(results) { venue in
                    Annotation(venue.name, coordinate: venue.coordinate.location, anchor: .bottom) {
                        Button { choose(venue) } label: {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: chosen?.id == venue.id ? 34 : 26))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(ArchColor.onLamp, ArchColor.lamp)
                        }
                        .buttonStyle(PressScaleStyle())
                        .accessibilityLabel(venue.name)
                        .accessibilityIdentifier("planner.custom.pin")
                    }
                }
            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous))
            .accessibilityIdentifier("planner.custom.map")
            .onChange(of: feature) { _, tapped in
                guard let tapped else { return }
                Task { await lookAt(tapped) }
            }

            placeCard
                .padding(ArchSpacing.s)
        }
        .frame(maxHeight: .infinity)
        .padding(.top, ArchSpacing.m)
    }

    /// The bottom of the map: the place you tapped, or how to tap one.
    @ViewBuilder private var placeCard: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.s) {
            if let chosen {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chosen.name)
                        .archText(.subhead)
                        .foregroundStyle(ArchColor.limestone)
                    Text(describe(chosen))
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
                ArchButton(title: "Add to the date") { onPick(chosen) }
                    .accessibilityIdentifier("planner.custom.add")
            } else {
                Text(lookingUp ? "Looking\u{2026}"
                     : unreachable ? "Arch could not reach Apple Maps just now."
                     : "Tap a place on the map, or search for one.")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
        }
        .padding(ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous)
                .fill(ArchColor.stone)
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
        )
    }

    private func choose(_ venue: Venue) {
        feature = nil
        withAnimation(ArchMotion.standard) { chosen = venue }
    }

    /// A place on Apple's map: its name, what Apple says it is, and the
    /// neighbourhood it is in. A city or a country is not a place to go.
    private func lookAt(_ tapped: MapFeature) async {
        guard tapped.kind != .territory,
              let name = tapped.title?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return }
        lookingUp = true
        withAnimation(ArchMotion.standard) { chosen = nil }
        let at = Coordinate(latitude: tapped.coordinate.latitude, longitude: tapped.coordinate.longitude)
        let neighbourhood = await VenueSearch.neighbourhood(at: at)
        lookingUp = false
        // Another place tapped meanwhile: that one is shown, not this.
        guard feature == tapped else { return }
        let venue = Venue(
            id: String(format: "mk:%@|%.4f|%.4f", name, at.latitude, at.longitude),
            name: name,
            kind: VenueSearch.kind(of: tapped.pointOfInterestCategory),
            neighbourhood: neighbourhood ?? "",
            coordinate: at,
            themes: DateTheme.themes(in: name),
            times: [.afternoon, .evening]
        )
        withAnimation(ArchMotion.standard) { chosen = venue }
    }

    // MARK: The list

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ArchSpacing.xs) {
                if unreachable {
                    note("Arch could not reach Apple Maps just now.")
                } else if query.trimmingCharacters(in: .whitespaces).count < 2 {
                    note("A caf\u{00E9}, a park, a restaurant: whatever you have in mind.")
                } else if results.isEmpty {
                    note(searching ? "Looking\u{2026}" : "Nothing by that name nearby.")
                } else {
                    ForEach(results) { venue in
                        Button { onPick(venue) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(venue.name)
                                    .archText(.subhead)
                                    .foregroundStyle(ArchColor.limestone)
                                Text(describe(venue))
                                    .archText(.footnote)
                                    .foregroundStyle(ArchColor.mortar)
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
                        .accessibilityLabel("Add \(venue.name)")
                        .accessibilityIdentifier("planner.custom.result")
                    }
                }
            }
            .padding(.top, ArchSpacing.m)
        }
        .scrollIndicators(.hidden)
    }

    private func describe(_ venue: Venue) -> String {
        [venue.kind.label, venue.neighbourhood].filter { !$0.isEmpty }.joined(separator: " \u{00B7} ")
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private extension Coordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
