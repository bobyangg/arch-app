import SwiftUI
import UIKit

/// The Arch type scale.
///
/// Two families, hard-split roles. New York (the system serif) is used *only* for
/// the wordmark, screen titles, profile names and prompt questions. SF Pro Text
/// carries every piece of UI chrome. Sentence case throughout — no all-caps labels,
/// no tracked-out eyebrow text.
///
/// Sizes are metered against a Dynamic Type text style, so the whole scale moves
/// with the reader's text size instead of being frozen at a literal point size.
enum ArchType: CaseIterable {

    // Serif — New York
    /// 40 / medium — the wordmark.
    case display
    /// 30 / semibold — screen titles, profile names.
    case titleL
    /// 24 / semibold — modal and empty-state headlines.
    case titleM
    /// 19 / regular — prompt questions. Always `mortar`.
    case prompt

    // Sans — SF Pro Text
    /// 20 / regular — prompt answers. Always `limestone`.
    case bodyL
    /// 17 / regular — settings rows, paragraphs, premium benefits.
    case body
    /// 16 / regular — message bubbles and the thread input.
    case callout
    /// 15 / semibold — button labels, section headers, list names.
    case subhead
    /// 13 / regular — timestamps, message previews, secondary rows.
    case footnote
    /// 12 / medium — vitals chips, tab labels.
    case caption
    /// 11 / semibold — the unread count. Small enough to sit on a 16pt dot,
    /// heavy enough to read on lamplight.
    case badge

    var size: CGFloat {
        switch self {
        case .display:  return 40
        case .titleL:   return 30
        case .titleM:   return 24
        case .prompt:   return 19
        case .bodyL:    return 20
        case .body:     return 17
        case .callout:  return 16
        case .subhead:  return 15
        case .footnote: return 13
        case .caption:  return 12
        case .badge:    return 11
        }
    }

    var lineHeight: CGFloat {
        switch self {
        case .display:  return 46
        case .titleL:   return 36
        case .titleM:   return 30
        case .prompt:   return 26
        case .bodyL:    return 28
        case .body:     return 24
        case .callout:  return 22
        case .subhead:  return 20
        case .footnote: return 18
        case .caption:  return 16
        case .badge:    return 14
        }
    }

    var weight: UIFont.Weight {
        switch self {
        case .display:                     return .medium
        case .titleL, .titleM:             return .semibold
        case .prompt, .bodyL, .body,
             .callout, .footnote:          return .regular
        case .subhead:                     return .semibold
        case .caption:                     return .medium
        case .badge:                       return .semibold
        }
    }

    var isSerif: Bool {
        switch self {
        case .display, .titleL, .titleM, .prompt: return true
        default: return false
        }
    }

    /// A small optical correction on the wordmark only. Everything else is untracked.
    var tracking: CGFloat {
        self == .display ? 0.5 : 0
    }

    /// The Dynamic Type style this size is metered against.
    var metrics: UIFont.TextStyle {
        switch self {
        case .display:            return .largeTitle
        case .titleL:             return .title1
        case .titleM:             return .title2
        case .prompt, .bodyL:     return .body
        case .body, .callout:     return .body
        case .subhead:            return .subheadline
        case .footnote:           return .footnote
        case .caption:            return .caption1
        case .badge:              return .caption2
        }
    }

    var font: Font { ArchTypography.font(self) }

    /// SwiftUI has no line-height API, so the scale's line heights are expressed
    /// as the gap between lines. Scaled alongside the font.
    var lineSpacing: CGFloat { ArchTypography.lineSpacing(self) }
}

enum ArchTypography {

    static func font(_ type: ArchType) -> Font {
        var descriptor = UIFont.systemFont(ofSize: type.size, weight: type.weight).fontDescriptor
        if type.isSerif, let serif = descriptor.withDesign(.serif) {
            descriptor = serif
        }
        let base = UIFont(descriptor: descriptor, size: type.size)
        return Font(UIFontMetrics(forTextStyle: type.metrics).scaledFont(for: base))
    }

    static func lineSpacing(_ type: ArchType) -> CGFloat {
        let gap = max(0, type.lineHeight - type.size)
        return UIFontMetrics(forTextStyle: type.metrics).scaledValue(for: gap)
    }
}

extension View {
    /// Applies one step of the Arch type scale: family, size, weight, line height, tracking.
    func archText(_ type: ArchType) -> some View {
        self
            .font(type.font)
            .lineSpacing(type.lineSpacing)
            .tracking(type.tracking)
    }
}

#Preview("Type scale") {
    ScrollView {
        VStack(alignment: .leading, spacing: 22) {
            specimen(.display, "Arch")
            specimen(.titleL, "Today's five")
            specimen(.titleM, "You both set the same stone")
            specimen(.prompt, "The last thing I read twice")
            specimen(.bodyL, "A field guide to bridges I found in my grandad's garage.")
            specimen(.body, "Discovery preferences")
            specimen(.callout, "That bakery on Union closes at two, annoyingly.")
            specimen(.subhead, "Send a message")
            specimen(.footnote, "Yesterday")
            specimen(.caption, "Structural engineer")
        }
        .padding(20)
    }
    .frame(maxWidth: .infinity)
    .background(ArchColor.night)
    .preferredColorScheme(.dark)
}

@ViewBuilder
private func specimen(_ type: ArchType, _ text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(label(for: type))
            .archText(.footnote)
            .foregroundStyle(ArchColor.mortar)
        Text(text)
            .archText(type)
            .foregroundStyle(ArchColor.limestone)
    }
}

private func label(for type: ArchType) -> String {
    let family = type.isSerif ? "New York" : "SF Pro Text"
    return "\(type)   \(family) \(Int(type.size))/\(Int(type.lineHeight))"
}
