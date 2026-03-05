import Foundation
import Capacitor

/// Capacitor 8 plugin exposing offline tile caching to the web layer.
///
/// The web app rewrites tile URLs from `https://` to `cachedtile://` when
/// running in Capacitor on iOS. The companion `TileSchemeHandler` (registered
/// on the WKWebView configuration in `CustomViewController`) intercepts those
/// requests and serves tiles from the file cache or fetches them from the
/// network.
///
/// This plugin provides the JavaScript API to pre-download regions, manage
/// the cache, and toggle the URL-rewrite interceptor.
@objc(OfflineTilesPlugin)
class OfflineTilesPlugin: CAPPlugin, CAPBridgedPlugin {

    // MARK: - CAPBridgedPlugin

    let identifier = "OfflineTilesPlugin"
    let jsName = "OfflineTiles"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "downloadRegion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "cancelDownload", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "deleteRegion", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "clearCache", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getCacheStats", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setInterceptorEnabled", returnType: CAPPluginReturnPromise),
    ]

    // MARK: - Properties

    private var cacheManager: TileCacheManager!
    private var downloadManager: TileDownloadManager!

    // MARK: - Lifecycle

    override func load() {
        cacheManager = TileCacheManager()
        downloadManager = TileDownloadManager(cacheManager: cacheManager)
    }

    // MARK: - downloadRegion

    /// Start downloading tiles for a geographic region.
    ///
    /// Options (from JS):
    /// - `regionId`: String (required)
    /// - `west`: Double (required)
    /// - `south`: Double (required)
    /// - `east`: Double (required)
    /// - `north`: Double (required)
    /// - `minZoom`: Int (required)
    /// - `maxZoom`: Int (required)
    /// - `mapboxToken`: String (required)
    /// - `sources`: [String]? (optional, e.g. ["vector","satellite","terrain"])
    ///
    /// Emits `downloadProgress` events with:
    ///   `{ regionId, completedTiles, totalTiles, bytesDownloaded, isComplete, error? }`
    @objc func downloadRegion(_ call: CAPPluginCall) {
        guard let regionId = call.getString("regionId"),
              let west = call.getDouble("west"),
              let south = call.getDouble("south"),
              let east = call.getDouble("east"),
              let north = call.getDouble("north"),
              let minZoom = call.getInt("minZoom"),
              let maxZoom = call.getInt("maxZoom"),
              let mapboxToken = call.getString("mapboxToken") else {
            call.reject("Missing required parameters: regionId, west, south, east, north, minZoom, maxZoom, mapboxToken")
            return
        }

        let sources = call.getArray("sources", String.self)
        let styleName = call.getString("styleName")

        let bbox = (west: west, south: south, east: east, north: north)

        // Acknowledge the call immediately — progress comes via events
        call.resolve(["started": true, "regionId": regionId])

        downloadManager.downloadRegion(
            regionId: regionId,
            bbox: bbox,
            minZoom: minZoom,
            maxZoom: maxZoom,
            mapboxToken: mapboxToken,
            sources: sources,
            styleName: styleName
        ) { [weak self] completed, total, bytes, isComplete, error in
            var data: [String: Any] = [
                "regionId": regionId,
                "completedTiles": completed,
                "totalTiles": total,
                "bytesDownloaded": bytes,
                "isComplete": isComplete,
            ]
            if let error = error {
                data["error"] = error
            }
            self?.notifyListeners("downloadProgress", data: data)
        }
    }

    // MARK: - cancelDownload

    @objc func cancelDownload(_ call: CAPPluginCall) {
        guard let regionId = call.getString("regionId") else {
            call.reject("Missing required parameter: regionId")
            return
        }
        downloadManager.cancelDownload(regionId: regionId)
        call.resolve(["cancelled": true, "regionId": regionId])
    }

    // MARK: - deleteRegion

    @objc func deleteRegion(_ call: CAPPluginCall) {
        guard let regionId = call.getString("regionId") else {
            call.reject("Missing required parameter: regionId")
            return
        }
        cacheManager.delete(regionPrefix: regionId)
        TileDownloadManager.removeRegionMeta(regionId: regionId)
        call.resolve(["deleted": true, "regionId": regionId])
    }

    // MARK: - clearCache

    @objc func clearCache(_ call: CAPPluginCall) {
        cacheManager.clear()
        // Also clear all region metadata
        UserDefaults.standard.removeObject(forKey: "ae.trustsky.spotlight.offlinetiles.regions")
        call.resolve(["cleared": true])
    }

    // MARK: - getCacheStats

    @objc func getCacheStats(_ call: CAPPluginCall) {
        let stats = cacheManager.getStats()
        let regions = TileDownloadManager.loadAllRegionMeta()

        var regionList: [[String: Any]] = []
        for (_, meta) in regions {
            regionList.append([
                "regionId": meta.regionId,
                "west": meta.west,
                "south": meta.south,
                "east": meta.east,
                "north": meta.north,
                "minZoom": meta.minZoom,
                "maxZoom": meta.maxZoom,
                "tileCount": meta.tileCount,
                "createdAt": ISO8601DateFormatter().string(from: meta.createdAt),
            ])
        }

        call.resolve([
            "tileCount": stats.tileCount,
            "totalBytes": stats.totalBytes,
            "totalMB": Double(stats.totalBytes) / (1024.0 * 1024.0),
            "regions": regionList,
        ])
    }

    // MARK: - setInterceptorEnabled

    /// Toggle whether the web layer should rewrite tile URLs to `cachedtile://`.
    /// The actual rewrite happens in JavaScript; this call simply persists the
    /// preference and returns the current state so the JS side can act on it.
    @objc func setInterceptorEnabled(_ call: CAPPluginCall) {
        guard let enabled = call.getBool("enabled") else {
            call.reject("Missing required parameter: enabled (Bool)")
            return
        }
        UserDefaults.standard.set(enabled, forKey: "ae.trustsky.spotlight.offlinetiles.interceptorEnabled")
        call.resolve(["enabled": enabled])
    }
}
