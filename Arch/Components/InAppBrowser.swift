import SafariServices
import SwiftUI

/// A web page over the app, in Safari's own sheet, for the few things that are
/// pages and not something Arch draws -- "Photos and reviews on Google" on a
/// Date planner stop. Closing it lands back where you were.
struct InAppBrowser: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(ArchColor.lamp)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// A page to show in `InAppBrowser`, for `.sheet(item:)`.
struct BrowserPage: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}
