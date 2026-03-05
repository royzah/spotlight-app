import Foundation

/// Thread-safe file-based tile cache stored in Library/Caches/tiles/.
/// Uses a concurrent DispatchQueue with barrier writes for safe concurrent reads.
final class TileCacheManager {

    // MARK: - Properties

    private let cacheDirectory: URL
    private let queue = DispatchQueue(label: "ae.trustsky.spotlight.tilecache",
                                      attributes: .concurrent)

    // MARK: - Init

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("tiles", isDirectory: true)

        // Ensure the directory exists
        try? FileManager.default.createDirectory(at: cacheDirectory,
                                                  withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Retrieve cached tile data for a given URL string.
    func get(url: String) -> Data? {
        let key = cacheKey(for: url)
        let filePath = cacheDirectory.appendingPathComponent(key)

        var result: Data?
        queue.sync {
            result = FileManager.default.contents(atPath: filePath.path)
        }

        return result
    }

    /// Write tile data into the cache for a given URL string.
    func put(url: String, data: Data) {
        let key = cacheKey(for: url)
        let filePath = cacheDirectory.appendingPathComponent(key)

        queue.async(flags: .barrier) {
            try? data.write(to: filePath, options: .atomic)
        }
    }

    /// Delete all cached tiles whose cache-key starts with a given region prefix.
    func delete(regionPrefix: String) {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(atPath: self.cacheDirectory.path) else { return }
            for file in files where file.hasPrefix(regionPrefix) {
                try? fm.removeItem(at: self.cacheDirectory.appendingPathComponent(file))
            }
        }
    }

    /// Remove every tile from the cache directory.
    func clear() {
        queue.async(flags: .barrier) { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: self.cacheDirectory)
            try? fm.createDirectory(at: self.cacheDirectory,
                                    withIntermediateDirectories: true)
        }
    }

    /// Returns tile count and total size in bytes (synchronous).
    func getStats() -> (tileCount: Int, totalBytes: Int64) {
        var count = 0
        var bytes: Int64 = 0

        queue.sync {
            let fm = FileManager.default
            guard let files = try? fm.contentsOfDirectory(atPath: self.cacheDirectory.path) else { return }
            for file in files {
                let filePath = self.cacheDirectory.appendingPathComponent(file).path
                if let attrs = try? fm.attributesOfItem(atPath: filePath),
                   let size = attrs[.size] as? Int64 {
                    count += 1
                    bytes += size
                }
            }
        }

        return (count, bytes)
    }

    // MARK: - Cache Key

    /// Build a file-system-safe cache key from a tile URL.
    ///
    /// 1. Strip query parameters starting with `access_token` (and any that follow).
    /// 2. Remove the scheme (`https://`, `cachedtile://`, etc.).
    /// 3. Replace `/` with `_`.
    func cacheKey(for url: String) -> String {
        var cleaned = url

        // Strip access_token and everything after it in the query string
        if let range = cleaned.range(of: "access_token") {
            // Walk back to the preceding '?' or '&'
            let prefixEnd = cleaned[..<range.lowerBound]
            if let separatorIndex = prefixEnd.lastIndex(where: { $0 == "?" || $0 == "&" }) {
                cleaned = String(cleaned[..<separatorIndex])
            }
        }

        // Remove scheme
        if let schemeEnd = cleaned.range(of: "://") {
            cleaned = String(cleaned[schemeEnd.upperBound...])
        }

        // Replace path separators
        cleaned = cleaned.replacingOccurrences(of: "/", with: "_")

        return cleaned
    }
}
