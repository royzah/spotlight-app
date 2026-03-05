import Foundation
import WebKit

/// WKURLSchemeHandler for the `cachedtile://` custom scheme.
///
/// When the web app rewrites tile URLs from `https://` to `cachedtile://`,
/// WKWebView routes those requests here. The handler checks the file cache
/// first and falls back to a network fetch (which is then cached).
///
/// Registration: this handler MUST be set on the WKWebViewConfiguration
/// **before** the WKWebView is instantiated. See `CustomViewController.swift`.
final class TileSchemeHandler: NSObject, WKURLSchemeHandler {

    // MARK: - Properties

    private let cacheManager: TileCacheManager
    /// Active URLSessionDataTasks keyed by the scheme task's hash for cancellation.
    private var activeTasks: [Int: URLSessionDataTask] = [:]
    /// Hashes of scheme tasks that have not yet been stopped or finished.
    private var validTasks: Set<Int> = []
    private let lock = NSLock()

    // MARK: - Init

    init(cacheManager: TileCacheManager) {
        self.cacheManager = cacheManager
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        let taskHash = urlSchemeTask.hash

        lock.lock()
        validTasks.insert(taskHash)
        lock.unlock()

        guard let requestURL = urlSchemeTask.request.url else {
            finishWithError(urlSchemeTask, error: SchemeError.invalidURL)
            return
        }

        // Convert cachedtile:// back to https://
        let originalURLString = requestURL.absoluteString
            .replacingOccurrences(of: "cachedtile://", with: "https://")

        // --- Cache hit ---
        if let cachedData = cacheManager.get(url: originalURLString) {
            let mimeType = Self.mimeType(for: originalURLString)
            let response = Self.httpResponse(url: requestURL, mimeType: mimeType, dataLength: cachedData.count)
            deliverResponse(urlSchemeTask, response: response, data: cachedData)
            return
        }

        // --- Cache miss — fetch from network ---
        guard let fetchURL = URL(string: originalURLString) else {
            finishWithError(urlSchemeTask, error: SchemeError.invalidURL)
            return
        }

        let task = URLSession.shared.dataTask(with: fetchURL) { [weak self] data, response, error in
            guard let self = self else { return }

            // Remove from active network tasks
            self.lock.lock()
            self.activeTasks.removeValue(forKey: taskHash)
            lock.unlock()

            if let error = error {
                // Task was cancelled via stop — just bail out
                if (error as NSError).code == NSURLErrorCancelled { return }
                self.finishWithError(urlSchemeTask, error: error)
                return
            }

            guard let data = data, let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                self.finishWithError(urlSchemeTask, error: SchemeError.fetchFailed)
                return
            }

            // Cache the fetched tile
            self.cacheManager.put(url: originalURLString, data: data)

            // Deliver to WKWebView
            let mimeType = Self.mimeType(for: originalURLString)
            let wkResponse = Self.httpResponse(url: requestURL, mimeType: mimeType, dataLength: data.count)
            self.deliverResponse(urlSchemeTask, response: wkResponse, data: data)
        }

        lock.lock()
        activeTasks[taskHash] = task
        lock.unlock()

        task.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        let taskHash = urlSchemeTask.hash

        lock.lock()
        validTasks.remove(taskHash)
        let networkTask = activeTasks.removeValue(forKey: taskHash)
        lock.unlock()

        networkTask?.cancel()
    }

    // MARK: - Private Helpers

    /// Deliver a successful response to the scheme task, guarded against invalidation.
    private func deliverResponse(_ task: WKURLSchemeTask, response: URLResponse, data: Data) {
        lock.lock()
        let isValid = validTasks.remove(task.hash) != nil
        lock.unlock()

        guard isValid else { return }
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    /// Deliver an error to the scheme task, guarded against invalidation.
    private func finishWithError(_ task: WKURLSchemeTask, error: Error) {
        lock.lock()
        let isValid = validTasks.remove(task.hash) != nil
        lock.unlock()

        guard isValid else { return }
        task.didFailWithError(error)
    }

    // MARK: - Response Builder

    /// Build an HTTPURLResponse with CORS headers so WKWebView doesn't block
    /// cross-origin loads from the custom cachedtile:// scheme.
    private static func httpResponse(url: URL, mimeType: String, dataLength: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": mimeType,
                "Content-Length": "\(dataLength)",
                "Access-Control-Allow-Origin": "*",
            ]
        )!
    }

    // MARK: - MIME Type Detection

    /// Determine the MIME type from the URL path extension.
    static func mimeType(for urlString: String) -> String {
        let lowered = urlString.lowercased()

        // Strip query string for extension matching
        let pathPart: String
        if let queryIndex = lowered.firstIndex(of: "?") {
            pathPart = String(lowered[..<queryIndex])
        } else {
            pathPart = lowered
        }

        if pathPart.hasSuffix(".pbf") || pathPart.hasSuffix(".vector.pbf") {
            return "application/x-protobuf"
        } else if pathPart.hasSuffix(".png") || pathPart.hasSuffix(".pngraw") {
            return "image/png"
        } else if pathPart.hasSuffix(".webp") {
            return "image/webp"
        } else if pathPart.hasSuffix(".json") || pathPart.hasSuffix(".geojson") {
            return "application/json"
        } else if pathPart.hasSuffix(".jpg") || pathPart.hasSuffix(".jpeg") {
            return "image/jpeg"
        }

        return "application/octet-stream"
    }

    // MARK: - Errors

    private enum SchemeError: LocalizedError {
        case invalidURL
        case fetchFailed

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "TileSchemeHandler: invalid URL"
            case .fetchFailed: return "TileSchemeHandler: network fetch failed"
            }
        }
    }
}
