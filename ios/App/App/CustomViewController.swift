import UIKit
import Capacitor
import WebKit

/// Custom subclass of CAPBridgeViewController that registers the
/// `cachedtile://` WKURLSchemeHandler BEFORE the WKWebView is created.
///
/// WKURLSchemeHandler must be set on the WKWebViewConfiguration prior to
/// WKWebView instantiation — there is no way to add a scheme handler after
/// the fact. Capacitor 8's CAPBridgeViewController exposes
/// `webViewConfiguration(for:)` specifically for this purpose.
///
/// The Main.storyboard must reference this class instead of the default
/// CAPBridgeViewController (customClass="CustomViewController",
/// customModule="App").
class CustomViewController: CAPBridgeViewController {

    /// Shared TileCacheManager used by both the scheme handler and the plugin.
    static let sharedCacheManager = TileCacheManager()

    /// Shared TileSchemeHandler instance — kept alive for the lifetime of the
    /// view controller (and therefore the WKWebView).
    private var schemeHandler: TileSchemeHandler?

    // MARK: - WKWebView Configuration

    /// Called by CAPBridgeViewController before creating the WKWebView.
    /// We register our custom URL scheme handler here.
    override func webViewConfiguration(for instanceConfiguration: InstanceConfiguration) -> WKWebViewConfiguration {
        let config = super.webViewConfiguration(for: instanceConfiguration)

        let handler = TileSchemeHandler(cacheManager: Self.sharedCacheManager)
        config.setURLSchemeHandler(handler, forURLScheme: "cachedtile")
        schemeHandler = handler

        return config
    }
}
