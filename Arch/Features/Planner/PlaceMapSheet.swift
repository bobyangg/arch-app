import MapKit
import SwiftUI

/// "Maps" on a stop: the place on a map in the app, rather than a trip out
/// to Apple Maps. Apple Maps is still one tap away, for directions.
struct PlaceMapSheet: View {
    let venue: Venue
    let onClose: () -> Void

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(venue.name)
                        .archText(.titleM)
                        .foregroundStyle(ArchColor.limestone)
                        .fixedSize(horizontal: false, vertical: true)
                    Text([venue.kind.label, venue.neighbourhood].filter { !$0.isEmpty }
                            .joined(separator: " \u{00B7} "))
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
                Spacer(minLength: ArchSpacing.s)
                ArchTextButton(title: "Done", action: onClose)
                    .fixedSize()
            }
            .padding(.top, ArchSpacing.xl)

            Map(initialPosition: .region(MKCoordinateRegion(
                center: point, latitudinalMeters: 900, longitudinalMeters: 900))) {
                Marker(venue.name, coordinate: point)
                    .tint(ArchColor.lamp)
            }
            .mapStyle(.standard(pointsOfInterest: .all))
            .clipShape(RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous))
            .frame(maxHeight: .infinity)
            .padding(.top, ArchSpacing.m)
            .accessibilityIdentifier("planner.placeMap")

            // The place itself, by Apple's identifier where there is one.
            ArchButton(title: "Open in Apple Maps", kind: .quiet) {
                Task { await VenueSearch.openInMaps(venue) { openURL($0) } }
            }
            .padding(.top, ArchSpacing.m)
            .accessibilityHint("For directions")
            .accessibilityIdentifier("planner.placeMap.open")
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .archSheetBackground()
    }

    private var point: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: venue.coordinate.latitude, longitude: venue.coordinate.longitude)
    }
}
