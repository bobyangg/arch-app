import SwiftUI
import UIKit
#if canImport(SensitiveContentAnalysis)
import SensitiveContentAnalysis
#endif

/// Apple's own check for nudity, on the phone.
///
/// **Only for people who asked iOS to warn them.** The framework analyses
/// nothing unless the person holding the phone has turned on Sensitive Content
/// Warning (Settings, Privacy & Security) or is covered by Communication Safety --
/// for everybody else `analysisPolicy` is `.disabled` and this is a no-op. It
/// also needs the app's `sensitivecontentanalysis.client` entitlement; without
/// it, it is a no-op as well.
///
/// Two uses, the way Apple intends it:
///
/// - **Photographs you are shown** are checked before they are drawn, and one
///   iOS calls sensitive arrives blurred, with a choice to see it.
///   `CachedImage` does this, so it covers every profile photograph at once.
/// - **Photographs you add** are checked before they upload, and one iOS calls
///   sensitive is not added. `ProfileStore.upload` does this.
///
/// It is not a filter for everybody, and nothing here pretends otherwise: most
/// people have never turned the setting on. Reporting is what covers the rest.
enum SensitivePhotos {

    /// Whether this phone will analyse anything. Read once per launch: turning
    /// the setting on takes effect the next time Arch opens.
    static let isOn: Bool = {
        #if canImport(SensitiveContentAnalysis)
        return SCSensitivityAnalyzer().analysisPolicy != .disabled
        #else
        return false
        #endif
    }()

    /// Whether iOS calls this photograph sensitive. False whenever it cannot
    /// say -- the setting off, no entitlement, or the analysis failing -- because
    /// a photograph nobody could check is not one anybody flagged.
    static func isSensitive(_ image: UIImage) async -> Bool {
        #if canImport(SensitiveContentAnalysis)
        guard isOn, let cgImage = image.cgImage else { return false }
        let analyzer = SCSensitivityAnalyzer()
        guard let analysis = try? await analyzer.analyzeImage(cgImage) else { return false }
        return analysis.isSensitive
        #else
        return false
        #endif
    }

    static func isSensitive(jpeg: Data) async -> Bool {
        guard isOn, let image = UIImage(data: jpeg) else { return false }
        return await isSensitive(image)
    }
}

/// A photograph iOS called sensitive, blurred until the viewer chooses to see it.
///
/// Calm on purpose: it says what happened and offers the one choice, the way
/// Apple's own warnings do, rather than an alarm. Nobody is told it was covered.
struct SensitivePhotoCover: View {
    let image: UIImage
    let onShow: () -> Void

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .blur(radius: 48, opaque: true)
            // The scrim the tour uses, so the words read on any photograph.
            .overlay { Rectangle().fill(ArchColor.scrim) }
            .overlay {
                VStack(spacing: ArchSpacing.s) {
                    Image(systemName: "eye.slash")
                        .archText(.titleM)
                    Text("This may be sensitive")
                        .archText(.subhead)
                    Button("Show", action: onShow)
                        .archText(.subhead)
                        .padding(.horizontal, ArchSpacing.m)
                        .padding(.vertical, ArchSpacing.xs)
                        .background(Capsule().fill(.ultraThinMaterial))
                        .accessibilityHint("Shows a photo your iPhone flagged as possibly sensitive")
                }
                .foregroundStyle(.white)
                .padding(ArchSpacing.m)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Photo hidden because it may be sensitive")
    }
}
