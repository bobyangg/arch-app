import SwiftUI

/// Writing the first message.
///
/// There is no match gate in Arch, so this is a bigger step than tapping a heart
/// elsewhere — you are writing to someone who has given you no signal at all. The
/// job of this sheet is to make that easy rather than brave, which is what the
/// quoted block is for: if you came in from a specific photo or answer, the message
/// already has something to be about.
struct MessageComposerSheet: View {
    let person: Person
    var quoted: ProfileItem?
    let onSend: (String) -> Void

    @State private var text = ""
    @State private var quotedItem: ProfileItem?
    @FocusState private var isWriting: Bool
    @Environment(\.dismiss) private var dismiss

    /// A real limit, so the counter is honest rather than decorative.
    private let characterLimit = 500
    /// Below this, the count is noise.
    private let counterAppearsAt = 400

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ArchSpacing.m) {
            recipient

            if let item = quotedItem {
                QuotedBlock(item: item) {
                    withAnimation(ArchMotion.quick) { quotedItem = nil }
                }
            }

            editor

            HStack {
                Spacer(minLength: 0)
                if text.count >= counterAppearsAt {
                    Text("\(text.count) of \(characterLimit)")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                }
            }
            .frame(height: 18)

            ArchButton(title: "Send", isEnabled: !trimmed.isEmpty) {
                onSend(trimmed)
            }
        }
        .padding(.horizontal, ArchSpacing.screenMargin)
        .padding(.top, ArchSpacing.l)
        .padding(.bottom, ArchSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(ArchColor.stone)
        .presentationDetents([.height(quotedItem == nil ? 420 : 520)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(ArchRadius.sheet)
        .presentationBackground(ArchColor.stone)
        .onAppear {
            quotedItem = quoted
            isWriting = true
        }
        .onChange(of: text) { _, new in
            if new.count > characterLimit {
                text = String(new.prefix(characterLimit))
            }
        }
    }

    private var recipient: some View {
        HStack(spacing: ArchSpacing.s) {
            PhotoPlaceholder(toneIndex: person.avatarToneIndex)
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous))

            VStack(alignment: .leading, spacing: 0) {
                Text(person.name)
                    .archText(.subhead)
                    .foregroundStyle(ArchColor.limestone)
                Text(person.location)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Writing to \(person.name)")
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text(quotedItem == nil ? "Start a conversation." : "Say something about it.")
                    .archText(.callout)
                    .foregroundStyle(ArchColor.mortar)
                    .padding(.top, ArchSpacing.s)
                    .padding(.leading, ArchSpacing.xxs + 1)
                    .allowsHitTesting(false)
            }
            TextEditor(text: $text)
                .archText(.callout)
                .foregroundStyle(ArchColor.limestone)
                .scrollContentBackground(.hidden)
                .focused($isWriting)
                .frame(minHeight: 132)
        }
        .padding(.horizontal, ArchSpacing.s)
        .padding(.vertical, ArchSpacing.xs)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.night)
        )
    }
}

/// The photo or answer the message is about, carried in from the profile.
struct QuotedBlock: View {
    let item: ProfileItem
    /// Nil in the message thread, where the quote is history and cannot be removed.
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: ArchSpacing.s) {
            content
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .archText(.footnote)
                        .foregroundStyle(ArchColor.mortar)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .accessibilityLabel("Remove what you are writing about")
            }
        }
        .padding(ArchSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ArchRadius.control, style: .continuous)
                .fill(ArchColor.stoneRaised)
        )
    }

    @ViewBuilder
    private var content: some View {
        switch item {
        case .photo(let photo):
            HStack(spacing: ArchSpacing.s) {
                PhotoPlaceholder(toneIndex: photo.toneIndex)
                    .frame(width: 40, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: ArchRadius.detail, style: .continuous))
                Text("About this photo")
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Spacer(minLength: 0)
            }
        case .prompt(let prompt):
            VStack(alignment: .leading, spacing: ArchSpacing.xxs) {
                Text(prompt.question)
                    .archText(.footnote)
                    .foregroundStyle(ArchColor.mortar)
                Text(prompt.answer)
                    .archText(.callout)
                    .foregroundStyle(ArchColor.limestone)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Previews

#Preview("Composer with an answer quoted") {
    MessageComposerSheet(
        person: MockData.nadia,
        quoted: .prompt(MockData.nadia.prompts[0]),
        onSend: { _ in }
    )
    .frame(height: 520)
    .preferredColorScheme(.dark)
}

#Preview("Composer with a photo quoted") {
    MessageComposerSheet(
        person: MockData.priya,
        quoted: .photo(MockData.priya.photos[1]),
        onSend: { _ in }
    )
    .frame(height: 520)
    .preferredColorScheme(.dark)
}

#Preview("Composer with nothing quoted") {
    MessageComposerSheet(person: MockData.lena, quoted: nil, onSend: { _ in })
        .frame(height: 420)
        .preferredColorScheme(.dark)
}
