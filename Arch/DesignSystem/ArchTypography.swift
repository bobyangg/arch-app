import CoreText
import SwiftUI
import UIKit

/// The Arch type scale.
///
/// Two families, hard-split roles. **Fraunces** is used *only* for the wordmark,
/// screen titles, profile names and prompt questions — it is the brand's voice and
/// it is not a UI font. **Instrument Sans** carries every piece of chrome.
/// Sentence case throughout — no all-caps labels, no tracked-out eyebrow text.
///
/// Sizes are metered against a Dynamic Type text style, so the whole scale moves
/// with the reader's text size instead of being frozen at a literal point size.
enum ArchType: CaseIterable {

    // Serif — Fraunces
    /// 40 / medium — the wordmark.
    case display
    /// 30 / semibold — screen titles, profile names.
    case titleL
    /// 24 / semibold — modal and empty-state headlines.
    case titleM
    /// 19 / regular — prompt questions. Always `mortar`.
    case prompt

    // Sans — Instrument Sans
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
    /// heavy enough to read on terracotta.
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

    /// The cut this step is set in — family and weight both, so there is one place
    /// to look and nothing to keep in sync.
    ///
    /// Fraunces is an optical-size family, so the split is not only by weight:
    /// titles take the 72pt cut, whose hairlines are drawn for large sizes, and a
    /// prompt question at 19pt takes the 14pt cut, which is drawn to survive being
    /// small. Using one cut for both is the usual way a variable serif ends up
    /// looking thin in a headline and muddy in a paragraph.
    var face: ArchFace {
        switch self {
        case .display:            return .frauncesDisplayMedium
        case .titleL, .titleM:    return .frauncesDisplaySemiBold
        case .prompt:             return .frauncesText
        case .subhead, .badge:    return .instrumentSemiBold
        case .caption:            return .instrumentMedium
        case .bodyL, .body,
             .callout, .footnote: return .instrumentRegular
        }
    }

    /// Fraunces is wider and warmer than the system serif it replaced, so the
    /// wordmark no longer needs opening up. Everything else was always untracked.
    var tracking: CGFloat { 0 }

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

/// The six cuts the app ships, by PostScript name.
///
/// Both families come from Google Fonts as variable-only, and Fraunces' own
/// defaults are opsz 9 / wght 900 / WONK 1 — a wonky black at caption size. These
/// are static instances pinned at build time rather than axes resolved at runtime,
/// so what the app asks for is exactly what it draws.
enum ArchFace: String, CaseIterable {
    case frauncesDisplayMedium   = "FrauncesDisplay-Medium"
    case frauncesDisplaySemiBold = "FrauncesDisplay-SemiBold"
    case frauncesText            = "FrauncesText-Regular"
    case instrumentRegular       = "InstrumentSans-Regular"
    case instrumentMedium        = "InstrumentSans-Medium"
    case instrumentSemiBold      = "InstrumentSans-SemiBold"

    var fileName: String { rawValue }
    var postScriptName: String { rawValue }

    var isSerif: Bool {
        switch self {
        case .frauncesDisplayMedium, .frauncesDisplaySemiBold, .frauncesText: return true
        case .instrumentRegular, .instrumentMedium, .instrumentSemiBold: return false
        }
    }

    /// What the system stands in with when the file is not in the bundle.
    var fallbackWeight: UIFont.Weight {
        switch self {
        case .frauncesDisplayMedium, .instrumentMedium: return .medium
        case .frauncesDisplaySemiBold, .instrumentSemiBold: return .semibold
        case .frauncesText, .instrumentRegular: return .regular
        }
    }
}

enum ArchTypography {

    static func font(_ type: ArchType) -> Font {
        Font(UIFontMetrics(forTextStyle: type.metrics).scaledFont(for: uiFont(type)))
    }

    /// The unscaled cut, for the few places that need a `UIFont` rather than a
    /// `Font` — `UITextView`, attributed strings, a `UIKit` control's title.
    static func uiFont(_ type: ArchType) -> UIFont {
        face(type.face, size: type.size)
    }

    /// One brand face at a literal size, for the lock-up — where the word is
    /// metered against the mark beside it rather than against the type scale.
    /// Everything that is running text goes through `archText` instead.
    static func font(_ face: ArchFace, size: CGFloat) -> Font {
        Font(self.face(face, size: size))
    }

    static func face(_ face: ArchFace, size: CGFloat) -> UIFont {
        ArchFonts.register()
        if let custom = UIFont(name: face.postScriptName, size: size) {
            return custom
        }
        var descriptor = UIFont.systemFont(ofSize: size, weight: face.fallbackWeight).fontDescriptor
        if face.isSerif, let serif = descriptor.withDesign(.serif) {
            descriptor = serif
        }
        return UIFont(descriptor: descriptor, size: size)
    }

    static func lineSpacing(_ type: ArchType) -> CGFloat {
        let gap = max(0, type.lineHeight - type.size)
        return UIFontMetrics(forTextStyle: type.metrics).scaledValue(for: gap)
    }
}

/// Registers the bundled faces with Core Text, once.
///
/// Deliberately not done through `UIAppFonts` in the Info.plist: registering from
/// code keeps the whole type system inside the design system, where a missing file
/// is a fallback rather than a plist key nobody remembers to add.
enum ArchFonts {
    private static let once: Void = {
        for face in ArchFace.allCases {
            guard let url = ArchFonts.url(for: face) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()

    static func register() { _ = once }

    /// Xcode flattens a group into the bundle root and keeps a folder reference as
    /// a directory, and which one a project uses is not this file's business.
    private static func url(for face: ArchFace) -> URL? {
        Bundle.main.url(forResource: face.fileName, withExtension: "ttf")
            ?? Bundle.main.url(forResource: face.fileName, withExtension: "ttf", subdirectory: "Fonts")
    }

    /// True once the brand faces are actually drawing. The appearance setting shows
    /// its specimen from this, so a build without the font files says so instead of
    /// quietly showing the fallback as though it were the brand.
    static var areBrandFacesAvailable: Bool {
        register()
        return UIFont(name: ArchFace.frauncesDisplayMedium.postScriptName, size: 12) != nil
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
            specimen(.display, "arch")
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
    "\(type)   \(type.face.postScriptName) \(Int(type.size))/\(Int(type.lineHeight))"
}
