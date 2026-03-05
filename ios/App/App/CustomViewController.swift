import UIKit
import Capacitor
import WebKit
import Network

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

    // MARK: - Status Bar

    /// Light status bar text (white) to match the dark app theme.
    override var preferredStatusBarStyle: UIStatusBarStyle {
        return .lightContent
    }

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

    // MARK: - Offline Fallback

    override func viewDidLoad() {
        super.viewDidLoad()
        checkConnectivityOnLaunch()
    }

    /// Uses NWPathMonitor to check connectivity once at launch.
    /// If the device is offline, loads the local offline fallback page
    /// instead of letting the WKWebView show a blank error.
    /// Does NOT replace Capacitor's WKNavigationDelegate.
    private func checkConnectivityOnLaunch() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            monitor.cancel()
            if path.status != .satisfied {
                DispatchQueue.main.async {
                    self?.loadOfflinePage()
                }
            }
        }
        monitor.start(queue: DispatchQueue.global(qos: .userInitiated))
    }

    private func loadOfflinePage() {
        guard let webView = webView else { return }
        let serverURL = bridge?.config.serverURL?.absoluteString ?? ""
        if let offlineURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "public") {
            let urlWithRetry = URL(string: offlineURL.absoluteString + "#retry=\(serverURL)")!
            webView.loadFileURL(urlWithRetry, allowingReadAccessTo: offlineURL.deletingLastPathComponent())
        }
    }
}
