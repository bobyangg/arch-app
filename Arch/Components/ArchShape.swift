import SwiftUI

// MARK: - Shared geometry

/// Point on a circle, in SwiftUI's y-down coordinate space.
/// 180 degrees is the left springing point, 270 the crown, 360 the right springing point.
private func pointOnCircle(_ centre: CGPoint, _ radius: CGFloat, _ angle: Angle) -> CGPoint {
    CGPoint(
        x: centre.x + radius * cos(angle.radians),
        y: centre.y + radius * sin(angle.radians)
    )
}

/// Rounds the corners of an arbitrary polygon. Used by the keystone.
private func roundedPolygon(_ points: [CGPoint], radius: CGFloat) -> Path {
    var path = Path()
    guard points.count >= 3 else { return path }
    let n = points.count
    let start = CGPoint(
        x: (points[0].x + points[1].x) / 2,
        y: (points[0].y + points[1].y) / 2
    )
    path.move(to: start)
    for i in 1...n {
        let corner = points[i % n]
        let next = points[(i + 1) % n]
        path.addArc(tangent1End: corner, tangent2End: next, radius: radius)
    }
    path.closeSubpath()
    return path
}

// MARK: - The mark

/// The Arch mark: a horizontal deck spanning a semicircular arch, reduced to two
/// strokes and nothing else. The deck overhangs the arch on both sides, the way a
/// bridge deck actually sits on its span.
///
/// One shape does five jobs — wordmark, launch animation, Daily 5 tab icon, app
/// icon, empty-state illustration — so the mark is never redrawn slightly
/// differently somewhere else in the app.
struct ArchMark: Shape {
    /// The stroke the caller will apply. The path insets itself by half of it so
    /// the drawn mark stays inside its frame.
    var lineWidth: CGFloat = ArchSpacing.glyphStroke

    /// How much of the path is drawn, 0...1. Animating this draws the mark in.
    var trim: CGFloat = 1

    /// Intrinsic proportion of the mark: height as a fraction of width.
    static let aspect: CGFloat = 0.90

    // Proportions, all fractions of the mark's width.
    private static let archRadius: CGFloat = 0.42
    private static let crownGap: CGFloat = 0.17
    private static let baseline: CGFloat = 0.90

    var animatableData: CGFloat {
        get { trim }
        set { trim = newValue }
    }

    func path(in rect: CGRect) -> Path {
        // Inscribe the mark's own proportion, centred, then inset for the stroke.
        let inset = lineWidth / 2
        let available = rect.insetBy(dx: inset, dy: inset)
        guard available.width > 0, available.height > 0 else { return Path() }

        let width = min(available.width, available.height / Self.aspect)
        let height = width * Self.aspect
        let origin = CGPoint(
            x: available.midX - width / 2,
            y: available.midY - height / 2
        )

        let radius = width * Self.archRadius
        let centre = CGPoint(
            x: origin.x + width / 2,
            y: origin.y + width * (Self.crownGap + Self.archRadius)
        )
        let footY = origin.y + width * Self.baseline

        var path = Path()

        // The deck.
        path.move(to: CGPoint(x: origin.x, y: origin.y))
        path.addLine(to: CGPoint(x: origin.x + width, y: origin.y))

        // The arch: left pier, span, right pier.
        path.move(to: CGPoint(x: centre.x - radius, y: footY))
        path.addLine(to: CGPoint(x: centre.x - radius, y: centre.y))
        path.addRelativeArc(
            center: centre,
            radius: radius,
            startAngle: .degrees(180),
            delta: .degrees(180)
        )
        path.addLine(to: CGPoint(x: centre.x + radius, y: footY))

        return trim >= 1 ? path : path.trimmedPath(from: 0, to: max(0, trim))
    }
}

// MARK: - The keystone

/// A single voussoir seen face-on: wider at the extrados than at the intrados.
/// This is the like affordance and the Premium tab glyph — never a heart, never a crown.
struct KeystoneShape: InsettableShape {
    /// Fraction of the width taken off each bottom corner.
    var taper: CGFloat = 0.16
    /// Corner rounding, as a fraction of width, so the stone looks the same at
    /// 20pt in the tab bar as it does at 34pt on a card.
    var cornerFraction: CGFloat = 0.08
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> KeystoneShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in bounds: CGRect) -> Path {
        let rect = bounds.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let inset = rect.width * taper
        let corners = [
            CGPoint(x: rect.minX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX - inset, y: rect.maxY),
            CGPoint(x: rect.minX + inset, y: rect.maxY)
        ]
        return roundedPolygon(corners, radius: rect.width * cornerFraction)
    }
}

// MARK: - The band

/// Layout for the Daily Arch: five voussoirs springing from a common centre, with
/// the centre stone drawn proud of the band on both faces so it reads as the
/// keystone with no colour change at all.
struct ArchBand {
    var count: Int = 5
    /// The mortar joint left open either side of each stone.
    var joint: Angle = .degrees(1.3)
    /// Radial thickness of the band.
    var thickness: CGFloat = 24
    /// How far the keystone stands proud of the extrados.
    var outerProud: CGFloat = 5
    /// How far it drops below the intrados.
    var innerProud: CGFloat = 4

    var keystoneIndex: Int { count / 2 }
    private var step: Double { 180.0 / Double(count) }

    func isKeystone(_ index: Int) -> Bool { index == keystoneIndex }

    /// Height needed to draw the band at a given width without clipping the keystone.
    func height(forWidth width: CGFloat) -> CGFloat {
        width / 2 + outerProud
    }

    private func extrados(in size: CGSize) -> CGFloat {
        max(1, min(size.width / 2, size.height) - outerProud)
    }

    func segment(_ index: Int, in size: CGSize) -> ArchSegment {
        let base = extrados(in: size)
        let proud = isKeystone(index)
        return ArchSegment(
            startAngle: .degrees(180 + Double(index) * step + joint.degrees),
            endAngle: .degrees(180 + Double(index + 1) * step - joint.degrees),
            outerRadius: base + (proud ? outerProud : 0),
            innerRadius: max(1, base - thickness - (proud ? innerProud : 0))
        )
    }
}

/// One stone of the Daily Arch — an annulus sector springing from the midpoint of
/// the frame's bottom edge.
struct ArchSegment: Shape {
    var startAngle: Angle
    var endAngle: Angle
    var outerRadius: CGFloat
    var innerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let centre = CGPoint(x: rect.midX, y: rect.maxY)
        let sweep = endAngle.degrees - startAngle.degrees

        var path = Path()
        path.addRelativeArc(
            center: centre,
            radius: outerRadius,
            startAngle: startAngle,
            delta: .degrees(sweep)
        )
        path.addLine(to: pointOnCircle(centre, innerRadius, endAngle))
        path.addRelativeArc(
            center: centre,
            radius: innerRadius,
            startAngle: endAngle,
            delta: .degrees(-sweep)
        )
        path.closeSubpath()
        return path
    }
}

// MARK: - Tab glyphs

/// A span with a single pier dropping from it. Reads as a message bubble, drawn in
/// the same stroke language as the rest of the set.
struct MessageGlyph: Shape {
    var lineWidth: CGFloat = ArchSpacing.glyphStroke

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard r.width > 0, r.height > 0 else { return Path() }

        let bubbleBottom = r.minY + r.height * 0.76
        let corner = r.width * 0.22
        let tailStart = CGPoint(x: r.minX + r.width * 0.44, y: bubbleBottom)
        let tailTip = CGPoint(x: r.minX + r.width * 0.18, y: r.maxY)
        let tailEnd = CGPoint(x: r.minX + r.width * 0.28, y: bubbleBottom)

        var path = Path()
        path.move(to: CGPoint(x: r.minX, y: r.minY + corner))
        path.addArc(
            tangent1End: CGPoint(x: r.minX, y: r.minY),
            tangent2End: CGPoint(x: r.minX + corner, y: r.minY),
            radius: corner
        )
        path.addLine(to: CGPoint(x: r.maxX - corner, y: r.minY))
        path.addArc(
            tangent1End: CGPoint(x: r.maxX, y: r.minY),
            tangent2End: CGPoint(x: r.maxX, y: r.minY + corner),
            radius: corner
        )
        path.addLine(to: CGPoint(x: r.maxX, y: bubbleBottom - corner))
        path.addArc(
            tangent1End: CGPoint(x: r.maxX, y: bubbleBottom),
            tangent2End: CGPoint(x: r.maxX - corner, y: bubbleBottom),
            radius: corner
        )
        path.addLine(to: tailStart)
        path.addLine(to: tailTip)
        path.addLine(to: tailEnd)
        path.addLine(to: CGPoint(x: r.minX + corner, y: bubbleBottom))
        path.addArc(
            tangent1End: CGPoint(x: r.minX, y: bubbleBottom),
            tangent2End: CGPoint(x: r.minX, y: bubbleBottom - corner),
            radius: corner
        )
        path.closeSubpath()
        return path
    }
}

/// Head and shoulders, same stroke weight as its siblings.
struct PersonGlyph: Shape {
    var lineWidth: CGFloat = ArchSpacing.glyphStroke

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
        guard r.width > 0, r.height > 0 else { return Path() }

        let headRadius = r.width * 0.17
        let headCentre = CGPoint(x: r.midX, y: r.minY + headRadius)
        let shoulderRadius = r.width * 0.46
        let shoulderCentre = CGPoint(x: r.midX, y: r.minY + r.height * 0.52 + shoulderRadius)

        var path = Path()
        path.addEllipse(in: CGRect(
            x: headCentre.x - headRadius,
            y: headCentre.y - headRadius,
            width: headRadius * 2,
            height: headRadius * 2
        ))
        path.move(to: pointOnCircle(shoulderCentre, shoulderRadius, .degrees(190)))
        path.addRelativeArc(
            center: shoulderCentre,
            radius: shoulderRadius,
            startAngle: .degrees(190),
            delta: .degrees(160)
        )
        return path
    }
}

// MARK: - Previews

#Preview("Arch mark") {
    VStack(spacing: ArchSpacing.xxl) {
        ArchMark(lineWidth: 6)
            .stroke(
                ArchColor.lamp,
                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
            )
            .frame(width: 160, height: 144)

        HStack(spacing: ArchSpacing.xl) {
            ForEach([29, 40, 60, 76], id: \.self) { size in
                let side = CGFloat(size)
                let stroke = max(1, side * 0.075)
                VStack(spacing: ArchSpacing.xs) {
                    ArchMark(lineWidth: stroke)
                        .stroke(
                            ArchColor.lamp,
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round, lineJoin: .round)
                        )
                        .padding(side * 0.16)
                        .frame(width: side, height: side)
                        .background(ArchColor.stone)
                        .clipShape(RoundedRectangle(cornerRadius: side * 0.22))
                    Text("\(size)pt")
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                }
            }
        }
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

#Preview("Glyphs") {
    HStack(spacing: ArchSpacing.xxl) {
        KeystoneShape()
            .stroke(ArchColor.mortar, style: StrokeStyle(lineWidth: ArchSpacing.glyphStroke, lineJoin: .round))
        ArchMark()
            .stroke(ArchColor.lamp, style: StrokeStyle(lineWidth: ArchSpacing.glyphStroke, lineCap: .round, lineJoin: .round))
        MessageGlyph()
            .stroke(ArchColor.mortar, style: StrokeStyle(lineWidth: ArchSpacing.glyphStroke, lineCap: .round, lineJoin: .round))
        PersonGlyph()
            .stroke(ArchColor.mortar, style: StrokeStyle(lineWidth: ArchSpacing.glyphStroke, lineCap: .round, lineJoin: .round))
    }
    .frame(height: 26)
    .padding(ArchSpacing.xxxl)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
