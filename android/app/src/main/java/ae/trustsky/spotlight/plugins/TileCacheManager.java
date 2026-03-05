package ae.trustsky.spotlight.plugins;

import android.content.Context;
import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.util.concurrent.ConcurrentHashMap;

/**
 * File-based tile cache using the app's internal cache directory. Thread-safe via ConcurrentHashMap
 * for metadata and synchronized file I/O.
 */
public class TileCacheManager {

  private static final String TAG = "TileCacheManager";
  private static final String CACHE_DIR_NAME = "tiles";

  private final File cacheDir;
  private final ConcurrentHashMap<String, Long> fileSizeMap = new ConcurrentHashMap<>();

  public TileCacheManager(Context context) {
    cacheDir = new File(context.getCacheDir(), CACHE_DIR_NAME);
    if (!cacheDir.exists()) {
      cacheDir.mkdirs();
    }
    // Build initial size map from existing cached files
    rebuildSizeMap();
  }

  /**
   * Derive a cache key from a URL by stripping the access_token query param and replacing path
   * separators with underscores.
   */
  public String cacheKeyFromUrl(String url) {
    String stripped = url;

    // Strip access_token query parameter
    // Handle both ?access_token=... and &access_token=...
    stripped = stripped.replaceAll("[?&]access_token=[^&]*", "");
    // Clean up leftover ? if it was the only param
    if (stripped.endsWith("?")) {
      stripped = stripped.substring(0, stripped.length() - 1);
    }
    // If we removed the first param but others remain, fix the leading &
    stripped = stripped.replace("?&", "?");

    // Remove protocol
    stripped = stripped.replaceFirst("^https?://", "");

    // Replace path separators and other problematic characters with underscores
    stripped = stripped.replace("/", "_");
    stripped = stripped.replace("?", "_");
    stripped = stripped.replace("&", "_");
    stripped = stripped.replace("=", "_");
    stripped = stripped.replace("@", "_");

    return stripped;
  }

  /** Retrieve cached tile data by URL. Returns null if not cached. */
  public byte[] get(String url) {
    String key = cacheKeyFromUrl(url);
    File file = new File(cacheDir, key);

    if (!file.exists()) {
      return null;
    }

    try {
      return readFile(file);
    } catch (IOException e) {
      Log.w(TAG, "Failed to read cached tile: " + key, e);
      return null;
    }
  }

  /** Store tile data in the cache. */
  public void put(String url, byte[] data) {
    String key = cacheKeyFromUrl(url);
    File file = new File(cacheDir, key);

    try {
      writeFile(file, data);
      fileSizeMap.put(key, (long) data.length);
    } catch (IOException e) {
      Log.w(TAG, "Failed to cache tile: " + key, e);
    }
  }

  /**
   * Delete all cached tiles whose cache key starts with the given prefix. Useful for deleting a
   * specific region's tiles.
   */
  public int delete(String regionPrefix) {
    int deleted = 0;
    File[] files = cacheDir.listFiles();
    if (files == null) return 0;

    for (File file : files) {
      if (file.getName().startsWith(regionPrefix)) {
        if (file.delete()) {
          fileSizeMap.remove(file.getName());
          deleted++;
        }
      }
    }
    Log.d(TAG, "Deleted " + deleted + " tiles with prefix: " + regionPrefix);
    return deleted;
  }

  /** Clear the entire tile cache. */
  public int clear() {
    int deleted = 0;
    File[] files = cacheDir.listFiles();
    if (files == null) return 0;

    for (File file : files) {
      if (file.delete()) {
        deleted++;
      }
    }
    fileSizeMap.clear();
    Log.d(TAG, "Cleared tile cache, deleted " + deleted + " files");
    return deleted;
  }

  /** Get cache statistics: tile count and total size in bytes. */
  public CacheStats getStats() {
    File[] files = cacheDir.listFiles();
    if (files == null) {
      return new CacheStats(0, 0);
    }

    long totalBytes = 0;
    int count = 0;
    for (File file : files) {
      if (file.isFile()) {
        totalBytes += file.length();
        count++;
      }
    }
    return new CacheStats(count, totalBytes);
  }

  /** Get the cache directory path (for debugging). */
  public File getCacheDir() {
    return cacheDir;
  }

  /** Check if a URL is already cached. */
  public boolean has(String url) {
    String key = cacheKeyFromUrl(url);
    return new File(cacheDir, key).exists();
  }

  // --- Private helpers ---

  private void rebuildSizeMap() {
    File[] files = cacheDir.listFiles();
    if (files == null) return;
    for (File file : files) {
      if (file.isFile()) {
        fileSizeMap.put(file.getName(), file.length());
      }
    }
  }

  private synchronized byte[] readFile(File file) throws IOException {
    try (FileInputStream fis = new FileInputStream(file);
        ByteArrayOutputStream bos = new ByteArrayOutputStream((int) file.length())) {
      byte[] buffer = new byte[8192];
      int bytesRead;
      while ((bytesRead = fis.read(buffer)) != -1) {
        bos.write(buffer, 0, bytesRead);
      }
      return bos.toByteArray();
    }
  }

  private synchronized void writeFile(File file, byte[] data) throws IOException {
    // Write to a temp file first, then rename for atomicity
    File tempFile = new File(cacheDir, file.getName() + ".tmp");
    try (FileOutputStream fos = new FileOutputStream(tempFile)) {
      fos.write(data);
      fos.getFD().sync();
    }
    if (!tempFile.renameTo(file)) {
      // Fallback: direct write if rename fails
      tempFile.delete();
      try (FileOutputStream fos = new FileOutputStream(file)) {
        fos.write(data);
        fos.getFD().sync();
      }
    }
  }

  /** Simple stats container. */
  public static class CacheStats {
    public final int tileCount;
    public final long totalBytes;

    public CacheStats(int tileCount, long totalBytes) {
      this.tileCount = tileCount;
      this.totalBytes = totalBytes;
    }
  }
}
