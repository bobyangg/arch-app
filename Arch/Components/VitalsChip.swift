import SwiftUI

/// One fact about a person. Small, quiet, and on `stone` so the run of them reads
/// as a single band under the name rather than as four separate controls.
struct VitalsChip: View {
    let text: String

    var body: some View {
        Text(text)
            .archText(.caption)
            .foregroundStyle(ArchColor.mortar)
            .padding(.horizontal, ArchSpacing.s)
            .padding(.vertical, ArchSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                    .fill(ArchColor.stone)
            )
    }
}

/// The vitals row. Wraps onto as many lines as it needs, because "Structural
/// engineer" is longer than "29" and neither should be truncated.
struct VitalsRow: View {
    let vitals: [String]

    var body: some View {
        FlowLayout(spacing: ArchSpacing.xs, lineSpacing: ArchSpacing.xs) {
            ForEach(vitals, id: \.self) { vital in
                VitalsChip(text: vital)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// A left-aligned wrapping layout. Written here rather than pulled in, since Arch
/// takes no third-party dependencies.
struct FlowLayout: Layout {
    var spacing: CGFloat = ArchSpacing.xs
    var lineSpacing: CGFloat = ArchSpacing.xs

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        arrange(subviews: subviews, maxWidth: proposal.width ?? .infinity).size
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout Void
    ) {
        let result = arrange(subviews: subviews, maxWidth: bounds.width)
        for (index, subview) in subviews.enumerated() {
            let offset = result.offsets[index]
            subview.place(
                at: CGPoint(x: bounds.minX + offset.x, y: bounds.minY + offset.y),
                proposal: .unspecified
            )
        }
    }

    private func arrange(subviews: Subviews, maxWidth: CGFloat) -> (size: CGSize, offsets: [CGPoint]) {
        var offsets: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }
            offsets.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }

        return (CGSize(width: min(widest, maxWidth), height: y + rowHeight), offsets)
    }
}

#Preview("Vitals") {
    VStack(alignment: .leading, spacing: ArchSpacing.xxl) {
        ForEach(MockData.people) { person in
            VStack(alignment: .leading, spacing: ArchSpacing.s) {
                Text(person.name)
                    .archText(.titleL)
                    .foregroundStyle(ArchColor.limestone)
                VitalsRow(vitals: person.vitals)
            }
        }
    }
    .padding(ArchSpacing.screenMargin)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}
