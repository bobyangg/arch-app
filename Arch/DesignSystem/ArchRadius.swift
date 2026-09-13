import SwiftUI

/// Corner radii carry hierarchy in Arch. One value everywhere would flatten the
/// difference between a photograph, a piece of writing and a control — so radius
/// is information, not decoration.
enum ArchRadius {
    /// 24 — photo cards. Generous; a photograph is the softest thing on screen.
    static let photo: CGFloat = 24
    /// 20 — prompt cards and other content surfaces.
    static let card: CGFloat = 20
    /// 12 — chips, buttons, input fields. Tighter, because they are handles.
    static let control: CGFloat = 12
    /// 28 — full-bleed sheets, applied to the top corners only.
    static let sheet: CGFloat = 28
    /// 8 — small inner details such as a keystone's corners.
    static let detail: CGFloat = 8
}

/// A rounded rectangle with only its top corners rounded — for sheets that sit
/// flush against the bottom of the screen.
struct TopRoundedRectangle: Shape {
    var radius: CGFloat = ArchRadius.sheet

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(radius, min(rect.width, rect.height) / 2)
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        path.addArc(
            tangent1End: CGPoint(x: rect.minX, y: rect.minY),
            tangent2End: CGPoint(x: rect.minX + r, y: rect.minY),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        path.addArc(
            tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
            tangent2End: CGPoint(x: rect.maxX, y: rect.minY + r),
            radius: r
        )
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

#Preview("Radius hierarchy") {
    let steps: [(String, CGFloat)] = [
        ("photo 24", ArchRadius.photo),
        ("card 20", ArchRadius.card),
        ("control 12", ArchRadius.control),
        ("detail 8", ArchRadius.detail)
    ]
    return VStack(spacing: ArchSpacing.m) {
        ForEach(steps, id: \.0) { name, value in
            RoundedRectangle(cornerRadius: value)
                .fill(ArchColor.stone)
                .frame(height: 64)
                .overlay(
                    Text(name)
                        .archText(.caption)
                        .foregroundStyle(ArchColor.mortar)
                )
        }
        TopRoundedRectangle()
            .fill(ArchColor.stone)
            .frame(height: 80)
            .overlay(alignment: .top) {
                Text("sheet 28, top only")
                    .archText(.caption)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.l)
            }
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
