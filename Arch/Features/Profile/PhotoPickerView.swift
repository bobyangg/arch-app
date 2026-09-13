import SwiftUI

/// Choosing photos from the library.
///
/// **The mark on a chosen tile is a number, not a tick.** The order you tap is the
/// order they land in your profile, and slot one is the photo people see in their
/// five — so the number is telling you something you need, where a tick would only
/// be telling you what you just did.
///
/// Unchosen tiles carry no empty ring. A ring on every tile is a control on every
/// tile, and the line under the header explains the mechanic in one sentence
/// instead.
///
/// Nothing is added until you have positioned each one. Tapping "Add 2 photos"
/// walks you through the crops and only then hands them over, so backing out at any
/// point leaves your profile exactly as it was.
struct PhotoPickerView: View {
    /// How many photos the profile can still take.
    let slotsLeft: Int
    var library: [LibraryPhoto] = MockData.photoLibrary
    /// iOS has been given part of the library rather than all of it. A real state,
    /// and one that otherwise makes the grid look mysteriously short.
    var isLimited: Bool = false
    let onAdd: ([LibraryPhoto]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: [String] = []
    @State private var path: [Int] = []

    private let columns = Array(
        repeating: GridItem(.flexible(), spacing: ArchSpacing.xxs),
        count: 3
    )

    /// The chosen photos, in the order they were tapped.
    private var chosen: [LibraryPhoto] {
        picked.compactMap { id in library.first { $0.id == id } }
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                header
                instruction
                if isLimited { limitedNotice }
                grid
            }
            .background(ArchColor.night)
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { footer }
            .navigationDestination(for: Int.self) { step in
                PhotoCropView(
                    photo: chosen[step],
                    step: step + 1,
                    total: chosen.count,
                    onUse: { advance(from: step) }
                )
            }
        }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: ArchSpacing.s) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                    .frame(width: ArchSpacing.minimumTapTarget, height: ArchSpacing.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel("Close without adding anything")

            Text("Add photos")
                .archText(.titleM)
                .foregroundStyle(ArchColor.limestone)

            Spacer(minLength: 0)
        }
        .padding(.leading, ArchSpacing.xs)
        .padding(.trailing, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.xs)
        .overlay(alignment: .bottom) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    private var instruction: some View {
        Text(instructionText)
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.m)
            .padding(.bottom, ArchSpacing.s)
    }

    /// Said plainly rather than as a warning. Sharing part of your library with an
    /// app is a reasonable thing to have done, and this is not the place to argue
    /// with it — it just explains why there are eight photos here and four hundred
    /// on the phone.
    private var limitedNotice: some View {
        HStack(spacing: ArchSpacing.s) {
            Text("Arch can see some of your photos.")
                .archText(.footnote)
                .foregroundStyle(ArchColor.mortar)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: ArchSpacing.s)

            Button {} label: {
                Text("Manage")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.limestone)
            }
            .buttonStyle(PressScaleStyle(scale: 1))
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.bottom, ArchSpacing.s)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: ArchSpacing.xxs) {
                ForEach(library) { photo in
                    tile(photo)
                }
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.bottom, ArchSpacing.sectionGap)
        }
        .scrollIndicators(.hidden)
    }

    private func tile(_ photo: LibraryPhoto) -> some View {
        let order = picked.firstIndex(of: photo.id)
        let isFull = order == nil && picked.count >= slotsLeft

        return Button { toggle(photo) } label: {
            PhotoPlaceholder(toneIndex: photo.toneIndex)
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: ArchRadius.detail, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if let order {
                        orderMark(order + 1)
                    }
                }
                // Full means full. Letting you pick a seventh and then explaining
                // the rule afterwards is a worse way to say the same thing.
                .opacity(isFull ? 0.3 : 1)
        }
        .buttonStyle(PressScaleStyle(scale: 0.97))
        .disabled(isFull)
        .accessibilityLabel(accessibilityLabel(for: photo, order: order, isFull: isFull))
    }

    private func orderMark(_ number: Int) -> some View {
        Text("\(number)")
            .archText(.badge)
            .foregroundStyle(ArchColor.onLamp)
            .frame(width: 22, height: 22)
            .background(Circle().fill(ArchColor.lamp))
            .padding(ArchSpacing.xxs)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            ArchButton(title: buttonTitle, isEnabled: !picked.isEmpty) {
                path = [0]
            }
            .padding(.horizontal, ArchSpacing.screenMargin)
            .padding(.top, ArchSpacing.s)
            .padding(.bottom, ArchSpacing.s)
        }
        .background(ArchColor.stoneRaised)
        .overlay(alignment: .top) {
            Rectangle().fill(ArchColor.hairline).frame(height: ArchSpacing.hairline)
        }
    }

    // MARK: Behaviour

    private func toggle(_ photo: LibraryPhoto) {
        withAnimation(ArchMotion.quick) {
            if let index = picked.firstIndex(of: photo.id) {
                picked.remove(at: index)
            } else if picked.count < slotsLeft {
                picked.append(photo.id)
            }
        }
    }

    private func advance(from step: Int) {
        if step + 1 < chosen.count {
            path.append(step + 1)
        } else {
            onAdd(chosen)
            dismiss()
        }
    }

    // MARK: Words

    private var instructionText: String {
        let remaining = slotsLeft - picked.count
        if picked.isEmpty {
            return "Tap to choose. " + slotSentence(slotsLeft)
        }
        if remaining == 0 {
            return picked.count == 1
                ? "They are added in the order you tap them. That is your last slot."
                : "They are added in the order you tap them. That is every slot you have left."
        }
        return "They are added in the order you tap them. " + slotSentence(remaining)
    }

    private func slotSentence(_ count: Int) -> String {
        count == 1 ? "One slot left." : "\(ArchCopy.capitalisedWord(count)) slots left."
    }

    private var buttonTitle: String {
        switch picked.count {
        case 0:  return "Add photos"
        case 1:  return "Add one photo"
        default: return "Add \(ArchCopy.word(picked.count)) photos"
        }
    }

    private func accessibilityLabel(for photo: LibraryPhoto, order: Int?, isFull: Bool) -> String {
        guard let index = library.firstIndex(where: { $0.id == photo.id }) else { return "Photo" }
        let position = "Photo \(index + 1) of \(library.count)"
        if let order { return "\(position), chosen \(ArchCopy.ordinal(order + 1))" }
        return isFull ? "\(position), no slots left" : position
    }

}

// MARK: - Previews

#Preview("Two slots left") {
    PhotoPickerView(slotsLeft: 2) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("An empty profile, six slots") {
    PhotoPickerView(slotsLeft: 6) { _ in }
        .preferredColorScheme(.dark)
}

#Preview("Part of the library shared") {
    PhotoPickerView(
        slotsLeft: 3,
        library: Array(MockData.photoLibrary.prefix(8)),
        isLimited: true
    ) { _ in }
    .preferredColorScheme(.dark)
}
