import MapKit
import SwiftUI

/// **Your distance, drawn.** A circle of that many miles round where you are,
/// on Apple's map, zoomed out to fit it -- so the circle grows as the number
/// does, and the neighbourhoods on the map say how far that really is.
///
/// Only ever yours: the other person's distance is never drawn. Centred on your
/// neighbourhood, never finer, and a still picture rather than a map to move
/// about -- the slider under it is the thing to touch.
struct ReachMap: View {
    let centre: Coordinate
    let miles: Int

    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        Map(position: $camera, interactionModes: []) {
            MapCircle(center: point, radius: metres)
                .foregroundStyle(ArchColor.lamp.opacity(0.14))
                .stroke(ArchColor.lamp, lineWidth: 1.5)
            Annotation("You", coordinate: point, anchor: .center) {
                Circle()
                    .fill(ArchColor.lamp)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(ArchColor.onLamp, lineWidth: 2))
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 180)
        .clipShape(RoundedRectangle(cornerRadius: ArchRadius.card, style: .continuous))
        .onAppear { camera = fitted }
        .onChange(of: miles) { _, _ in
            withAnimation(ArchMotion.standard) { camera = fitted }
        }
        .accessibilityHidden(true)
    }

    private var point: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: centre.latitude, longitude: centre.longitude)
    }

    private var metres: CLLocationDistance { Double(miles) * 1_609.344 }

    /// The circle with a little room round it.
    private var fitted: MapCameraPosition {
        .region(MKCoordinateRegion(center: point,
                                   latitudinalMeters: metres * 2.6,
                                   longitudinalMeters: metres * 2.6))
    }
}
