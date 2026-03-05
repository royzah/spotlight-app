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
    private let lock = NSLock()

    // MARK: - Init

    init(cacheManager: TileCacheManager) {
        self.cacheManager = cacheManager
        super.init()
    }

    // MARK: - WKURLSchemeHandler

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let requestURL = urlSchemeTask.request.url else {
            urlSchemeTask.didFailWithError(SchemeError.invalidURL)
            return
        }

        // Convert cachedtile:// back to https://
        let originalURLString = requestURL.absoluteString
            .replacingOccurrences(of: "cachedtile://", with: "https://")

        // --- Cache hit ---
        if let cachedData = cacheManager.get(url: originalURLString) {
            let mimeType = Self.mimeType(for: originalURLString)
            let response = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: cachedData.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(cachedData)
            urlSchemeTask.didFinish()
            return
        }

        // --- Cache miss — fetch from network ---
        guard let fetchURL = URL(string: originalURLString) else {
            urlSchemeTask.didFailWithError(SchemeError.invalidURL)
            return
        }

        let task = URLSession.shared.dataTask(with: fetchURL) { [weak self] data, response, error in
            guard let self = self else { return }

            // Remove from active tasks
            self.lock.lock()
            self.activeTasks.removeValue(forKey: urlSchemeTask.hash)
            self.lock.unlock()

            if let error = error {
                // Task may have been cancelled — guard against calling didFailWithError
                // on an already-stopped scheme task.
                if (error as NSError).code == NSURLErrorCancelled { return }
                do {
                    urlSchemeTask.didFailWithError(error)
                } catch {
                    // urlSchemeTask may already be invalidated
                }
                return
            }

            guard let data = data, let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                do {
                    urlSchemeTask.didFailWithError(SchemeError.fetchFailed)
                } catch {
                    // urlSchemeTask may already be invalidated
                }
                return
            }

            // Cache the fetched tile
            self.cacheManager.put(url: originalURLString, data: data)

            // Deliver to WKWebView
            let mimeType = Self.mimeType(for: originalURLString)
            let wkResponse = URLResponse(
                url: requestURL,
                mimeType: mimeType,
                expectedContentLength: data.count,
                textEncodingName: nil
            )

            do {
                urlSchemeTask.didReceive(wkResponse)
                urlSchemeTask.didReceive(data)
                urlSchemeTask.didFinish()
            } catch {
                // urlSchemeTask may already be invalidated if stop was called
            }
        }

        lock.lock()
        activeTasks[urlSchemeTask.hash] = task
        lock.unlock()

        task.resume()
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {
        lock.lock()
        let task = activeTasks.removeValue(forKey: urlSchemeTask.hash)
        lock.unlock()
        task?.cancel()
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
