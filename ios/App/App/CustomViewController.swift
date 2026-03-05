import Capacitor
import Network
import UIKit
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
        installNavigationErrorHandler()
    }

    /// Uses NWPathMonitor to check connectivity once at launch.
    /// If the device is offline, loads the local offline fallback page
    /// instead of letting the WKWebView show a blank error.
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

    /// Observe WKWebView navigation errors at runtime (like Android's
    /// onReceivedError). Shows the offline fallback if the main frame
    /// fails to load due to a network error.
    private func installNavigationErrorHandler() {
        navigationDelegate = WebViewNavigationDelegate(controller: self)
    }

    private var navigationDelegate: WebViewNavigationDelegate?

    fileprivate func loadOfflinePage() {
        guard let webView = webView else { return }
        let serverURL = bridge?.config.serverURL.absoluteString ?? ""
        if let offlineURL = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "public") {
            let urlWithRetry = URL(string: offlineURL.absoluteString + "#retry=\(serverURL)")!
            webView.loadFileURL(urlWithRetry, allowingReadAccessTo: offlineURL.deletingLastPathComponent())
        }
    }
}

// MARK: - Navigation Error Handler

/// Monitors WKWebView navigation failures and shows the offline page when
/// the main frame fails to load (matching Android's onReceivedError behavior).
private class WebViewNavigationDelegate: NSObject, WKNavigationDelegate {
    weak var controller: CustomViewController?
    /// Strong reference: Capacitor's delegate would be released when we replace
    /// webView.navigationDelegate, so we must retain it ourselves.
    private var originalDelegate: WKNavigationDelegate?

    init(controller: CustomViewController) {
        self.controller = controller
        super.init()

        // Chain with Capacitor's existing navigation delegate
        if let webView = controller.webView {
            originalDelegate = webView.navigationDelegate
            webView.navigationDelegate = self
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleError(error, webView: webView)
        originalDelegate?.webView?(webView, didFail: navigation, withError: error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleError(error, webView: webView)
        originalDelegate?.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
    }

    private func handleError(_ error: Error, webView _: WKWebView) {
        let nsError = error as NSError
        let networkErrors: Set<Int> = [
            NSURLErrorNotConnectedToInternet,
            NSURLErrorTimedOut,
            NSURLErrorCannotFindHost,
            NSURLErrorCannotConnectToHost,
            NSURLErrorNetworkConnectionLost,
            NSURLErrorDNSLookupFailed,
        ]
        if networkErrors.contains(nsError.code) {
            controller?.loadOfflinePage()
        }
    }

    // Forward all other delegate methods to the original

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didFinish: navigation)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didStartProvisionalNavigation: navigation)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        originalDelegate?.webView?(webView, didCommit: navigation)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let original = originalDelegate else {
            decisionHandler(.allow)
            return
        }
        original.webView?(webView, decidePolicyFor: navigationAction, decisionHandler: decisionHandler) ?? decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        guard let original = originalDelegate else {
            decisionHandler(.allow)
            return
        }
        original.webView?(webView, decidePolicyFor: navigationResponse, decisionHandler: decisionHandler) ?? decisionHandler(.allow)
    }
}
