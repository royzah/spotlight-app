import Foundation

/// Downloads map tiles for a bounding box across a range of zoom levels and
/// stores them via `TileCacheManager`.
///
/// Uses slippy-map math to convert lat/lon bbox to tile coordinates, then
/// fetches vector, satellite, and terrain tiles concurrently (max 4 at a time).
final class TileDownloadManager {

    // MARK: - Types

    /// Progress callback delivered on every tile completion.
    typealias ProgressCallback = (
        _ completedTiles: Int,
        _ totalTiles: Int,
        _ bytesDownloaded: Int64,
        _ isComplete: Bool,
        _ error: String?
    ) -> Void

    /// Region metadata persisted in UserDefaults.
    struct RegionMeta: Codable {
        let regionId: String
        let west: Double
        let south: Double
        let east: Double
        let north: Double
        let minZoom: Int
        let maxZoom: Int
        let tileCount: Int
        let createdAt: Date
    }

    // MARK: - Tile URL Templates

    private enum TileSource: CaseIterable {
        case vector
        case satellite
        case terrain

        func url(z: Int, x: Int, y: Int, token: String) -> String {
            switch self {
            case .vector:
                return "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/\(z)/\(x)/\(y).vector.pbf?access_token=\(token)"
            case .satellite:
                return "https://api.mapbox.com/v4/mapbox.satellite/\(z)/\(x)/\(y)@2x.webp?access_token=\(token)"
            case .terrain:
                return "https://api.mapbox.com/v4/mapbox.terrain-rgb/\(z)/\(x)/\(y).pngraw?access_token=\(token)"
            }
        }
    }

    // MARK: - Style Resource URLs

    /// Build URLs for style JSON, sprites, and glyph ranges (matching Android).
    private static func buildResourceURLs(styleName: String?, token: String) -> [String] {
        guard let styleName = styleName, !styleName.isEmpty else { return [] }

        var urls: [String] = []

        // Style JSON
        urls.append("https://api.mapbox.com/styles/v1/mapbox/\(styleName)?access_token=\(token)")
        // Sprite JSON + PNG
        urls.append("https://api.mapbox.com/styles/v1/mapbox/\(styleName)/sprite@2x.json?access_token=\(token)")
        urls.append("https://api.mapbox.com/styles/v1/mapbox/\(styleName)/sprite@2x.png?access_token=\(token)")

        // Common glyph ranges for Latin + Arabic text
        let fontStacks = [
            "DIN Pro Regular,Arial Unicode MS Regular",
            "DIN Pro Medium,Arial Unicode MS Regular",
            "DIN Pro Bold,Arial Unicode MS Bold"
        ]
        let glyphRanges = [
            "0-255", "256-511", "512-767", "768-1023",
            "8192-8447", "8448-8703", "65024-65279"
        ]
        for fontStack in fontStacks {
            for range in glyphRanges {
                urls.append("https://api.mapbox.com/fonts/v1/mapbox/\(fontStack)/\(range).pbf?access_token=\(token)")
            }
        }

        return urls
    }

    // MARK: - Properties

    private let cacheManager: TileCacheManager

    /// Tracks cancelled region IDs.
    private var cancelledRegions: Set<String> = []
    private let lock = NSLock()

    /// URLSession with limited concurrency.
    private let session: URLSession

    // MARK: - Init

    init(cacheManager: TileCacheManager) {
        self.cacheManager = cacheManager

        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 4
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300

        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 4
        queue.name = "ae.trustsky.spotlight.tiledownload"

        session = URLSession(configuration: config, delegate: nil, delegateQueue: queue)
    }

    // MARK: - Download

    /// Start downloading tiles for a region.
    ///
    /// - Parameters:
    ///   - regionId: Unique identifier for the download region.
    ///   - bbox: (west, south, east, north) in degrees.
    ///   - minZoom: Minimum zoom level (inclusive).
    ///   - maxZoom: Maximum zoom level (inclusive).
    ///   - mapboxToken: Mapbox access token.
    ///   - sources: Which tile sources to download. Defaults to all.
    ///   - progress: Callback invoked on every tile completion.
    func downloadRegion(
        regionId: String,
        bbox: (west: Double, south: Double, east: Double, north: Double),
        minZoom: Int,
        maxZoom: Int,
        mapboxToken: String,
        sources: [String]? = nil,
        styleName: String? = nil,
        progress: @escaping ProgressCallback
    ) {
        // Mark as active
        lock.lock()
        cancelledRegions.remove(regionId)
        lock.unlock()

        // Determine which sources to download
        let activeSources: [TileSource]
        if let sourceNames = sources {
            activeSources = sourceNames.compactMap { name -> TileSource? in
                switch name.lowercased() {
                case "vector": return .vector
                case "satellite": return .satellite
                case "terrain": return .terrain
                default: return nil
                }
            }
        } else {
            activeSources = TileSource.allCases
        }

        // Build the list of tile URLs
        var tileURLs: [(url: String, regionPrefix: String)] = []
        for z in minZoom...maxZoom {
            let tileRange = Self.tileRange(bbox: bbox, zoom: z)
            for x in tileRange.xMin...tileRange.xMax {
                for y in tileRange.yMin...tileRange.yMax {
                    for source in activeSources {
                        let url = source.url(z: z, x: x, y: y, token: mapboxToken)
                        tileURLs.append((url: url, regionPrefix: regionId))
                    }
                }
            }
        }

        // Add style, sprite, and glyph resource URLs
        for url in Self.buildResourceURLs(styleName: styleName, token: mapboxToken) {
            tileURLs.append((url: url, regionPrefix: regionId))
        }

        let totalTiles = tileURLs.count
        if totalTiles == 0 {
            progress(0, 0, 0, true, nil)
            return
        }

        // Save region metadata
        let meta = RegionMeta(
            regionId: regionId,
            west: bbox.west, south: bbox.south,
            east: bbox.east, north: bbox.north,
            minZoom: minZoom, maxZoom: maxZoom,
            tileCount: totalTiles,
            createdAt: Date()
        )
        Self.saveRegionMeta(meta)

        // Dispatch downloads
        var completed = 0
        var totalBytes: Int64 = 0
        var lastError: String?
        let statsLock = NSLock()

        let group = DispatchGroup()

        for tile in tileURLs {
            // Check cancellation
            lock.lock()
            let cancelled = cancelledRegions.contains(regionId)
            lock.unlock()
            if cancelled {
                progress(completed, totalTiles, totalBytes, true, "cancelled")
                return
            }

            // Skip tiles already cached
            if cacheManager.get(url: tile.url) != nil {
                statsLock.lock()
                completed += 1
                let c = completed
                let b = totalBytes
                let done = c == totalTiles
                statsLock.unlock()
                progress(c, totalTiles, b, done, nil)
                continue
            }

            group.enter()

            guard let fetchURL = URL(string: tile.url) else {
                group.leave()
                continue
            }

            session.dataTask(with: fetchURL) { [weak self] data, response, error in
                defer { group.leave() }
                guard let self = self else { return }

                // Check cancellation
                self.lock.lock()
                let cancelled = self.cancelledRegions.contains(regionId)
                self.lock.unlock()
                if cancelled { return }

                if let error = error {
                    statsLock.lock()
                    completed += 1
                    lastError = error.localizedDescription
                    let c = completed
                    let b = totalBytes
                    let done = c == totalTiles
                    let e = lastError
                    statsLock.unlock()
                    progress(c, totalTiles, b, done, e)
                    return
                }

                if let data = data,
                   let httpResponse = response as? HTTPURLResponse,
                   (200...299).contains(httpResponse.statusCode) {
                    self.cacheManager.put(url: tile.url, data: data)

                    statsLock.lock()
                    completed += 1
                    totalBytes += Int64(data.count)
                    let c = completed
                    let b = totalBytes
                    let done = c == totalTiles
                    statsLock.unlock()
                    progress(c, totalTiles, b, done, nil)
                } else {
                    statsLock.lock()
                    completed += 1
                    lastError = "HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)"
                    let c = completed
                    let b = totalBytes
                    let done = c == totalTiles
                    let e = lastError
                    statsLock.unlock()
                    progress(c, totalTiles, b, done, e)
                }
            }.resume()
        }

        // Fire a final completion event when every task finishes
        group.notify(queue: .main) {
            statsLock.lock()
            let c = completed
            let b = totalBytes
            let e = lastError
            statsLock.unlock()
            if c < totalTiles {
                progress(c, totalTiles, b, true, e)
            }
        }
    }

    // MARK: - Cancellation

    func cancelDownload(regionId: String) {
        lock.lock()
        cancelledRegions.insert(regionId)
        lock.unlock()
    }

    // MARK: - Slippy Map Math

    private struct TileRange {
        let xMin: Int
        let xMax: Int
        let yMin: Int
        let yMax: Int
    }

    /// Convert a bounding box at a given zoom to tile x/y ranges.
    private static func tileRange(
        bbox: (west: Double, south: Double, east: Double, north: Double),
        zoom: Int
    ) -> TileRange {
        let xMin = lonToTileX(lon: bbox.west, zoom: zoom)
        let xMax = lonToTileX(lon: bbox.east, zoom: zoom)
        let yMin = latToTileY(lat: bbox.north, zoom: zoom) // north → smaller y
        let yMax = latToTileY(lat: bbox.south, zoom: zoom)

        return TileRange(xMin: min(xMin, xMax),
                         xMax: max(xMin, xMax),
                         yMin: min(yMin, yMax),
                         yMax: max(yMin, yMax))
    }

    private static func lonToTileX(lon: Double, zoom: Int) -> Int {
        return Int(floor((lon + 180.0) / 360.0 * pow(2.0, Double(zoom))))
    }

    private static func latToTileY(lat: Double, zoom: Int) -> Int {
        let latRad = lat * .pi / 180.0

        return Int(floor(
            (1.0 - log(tan(latRad) + 1.0 / cos(latRad)) / .pi) / 2.0 * pow(2.0, Double(zoom))
        ))
    }

    // MARK: - Region Metadata Persistence

    private static let metaKey = "ae.trustsky.spotlight.offlinetiles.regions"

    static func saveRegionMeta(_ meta: RegionMeta) {
        var all = loadAllRegionMeta()
        all[meta.regionId] = meta
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: metaKey)
        }
    }

    static func loadAllRegionMeta() -> [String: RegionMeta] {
        guard let data = UserDefaults.standard.data(forKey: metaKey),
              let decoded = try? JSONDecoder().decode([String: RegionMeta].self, from: data) else {
            return [:]
        }

        return decoded
    }

    static func removeRegionMeta(regionId: String) {
        var all = loadAllRegionMeta()
        all.removeValue(forKey: regionId)
        if let data = try? JSONEncoder().encode(all) {
            UserDefaults.standard.set(data, forKey: metaKey)
        }
    }
}
