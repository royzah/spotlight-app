package ae.trustsky.spotlight.plugins;

import android.util.Log;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicInteger;

/**
 * Manages bulk downloading of map tiles for offline use. Calculates tile coordinates from a
 * bounding box and zoom range, fetches tiles concurrently, and stores them in the TileCacheManager.
 */
public class TileDownloadManager {

  private static final String TAG = "TileDownloadManager";
  private static final int THREAD_COUNT = 4;
  private static final int CONNECT_TIMEOUT_MS = 15_000;
  private static final int READ_TIMEOUT_MS = 30_000;

  // Tile URL templates — token is appended as a query parameter
  private static final String VECTOR_TEMPLATE =
      "https://api.mapbox.com/v4/mapbox.mapbox-streets-v8/%d/%d/%d.vector.pbf?access_token=%s";
  private static final String SATELLITE_TEMPLATE =
      "https://api.mapbox.com/v4/mapbox.satellite/%d/%d/%d@2x.webp?access_token=%s";
  private static final String TERRAIN_TEMPLATE =
      "https://api.mapbox.com/v4/mapbox.terrain-rgb/%d/%d/%d.pngraw?access_token=%s";
  private static final String STYLE_TEMPLATE =
      "https://api.mapbox.com/styles/v1/mapbox/%s?access_token=%s";
  private static final String GLYPHS_TEMPLATE =
      "https://api.mapbox.com/fonts/v1/mapbox/%s/%s.pbf?access_token=%s";
  private static final String SPRITE_JSON_TEMPLATE =
      "https://api.mapbox.com/styles/v1/mapbox/%s/sprite@2x.json?access_token=%s";
  private static final String SPRITE_PNG_TEMPLATE =
      "https://api.mapbox.com/styles/v1/mapbox/%s/sprite@2x.png?access_token=%s";

  private final TileCacheManager cacheManager;
  private final ExecutorService executor;
  private final ConcurrentHashMap<String, AtomicBoolean> cancelFlags = new ConcurrentHashMap<>();

  public TileDownloadManager(TileCacheManager cacheManager) {
    this.cacheManager = cacheManager;
    this.executor = Executors.newFixedThreadPool(THREAD_COUNT);
  }

  /** Listener for download progress and completion events. */
  public interface DownloadListener {
    void onProgress(String regionId, int completed, int total, float percentage);

    void onComplete(String regionId, int totalTiles, boolean cancelled);

    void onError(String regionId, String error);
  }

  /** Tile layer types that can be downloaded. */
  public enum TileLayer {
    VECTOR,
    SATELLITE,
    TERRAIN
  }

  /** Groups download parameters into a single object. */
  public static class DownloadRequest {
    public final String regionId;
    public final double[] bbox;
    public final int minZoom;
    public final int maxZoom;
    public final List<TileLayer> layers;
    public final String styleName;
    public final String token;

    public DownloadRequest(
        String regionId,
        double[] bbox,
        int minZoom,
        int maxZoom,
        List<TileLayer> layers,
        String styleName,
        String token) {
      this.regionId = regionId;
      this.bbox = bbox;
      this.minZoom = minZoom;
      this.maxZoom = maxZoom;
      this.layers = layers;
      this.styleName = styleName;
      this.token = token;
    }
  }

  /**
   * Download tiles for a region defined by a bounding box and zoom range.
   *
   * @param request Download parameters
   * @param listener Progress callback listener
   */
  public void downloadRegion(DownloadRequest request, DownloadListener listener) {
    if (request.bbox == null || request.bbox.length != 4) {
      if (listener != null) {
        listener.onError(
            request.regionId, "Invalid bounding box: must be [west, south, east, north]");
      }
      return;
    }

    List<String> urls = buildAllUrls(request);
    int totalTiles = urls.size();

    Log.d(TAG, "Starting download for region " + request.regionId + ": " + totalTiles + " resources, zoom " + request.minZoom + "-" + request.maxZoom);

    submitDownloadTasks(request.regionId, urls, totalTiles, listener);
  }

  /**
   * Download tiles for a region (convenience overload with individual parameters).
   */
  public void downloadRegion(
      String regionId,
      double[] bbox,
      int minZoom,
      int maxZoom,
      List<TileLayer> layers,
      String styleName,
      String token,
      DownloadListener listener) {
    downloadRegion(
        new DownloadRequest(regionId, bbox, minZoom, maxZoom, layers, styleName, token), listener);
  }

  /** Cancel an in-progress download. */
  public void cancel(String regionId) {
    AtomicBoolean flag = cancelFlags.get(regionId);
    if (flag != null) {
      flag.set(true);
      cancelFlags.remove(regionId);
      Log.d(TAG, "Cancelled download for region: " + regionId);
    }
  }

  /** Shut down the executor service. */
  public void shutdown() {
    executor.shutdownNow();
  }

  /** Estimate the number of tiles for a region (for UI previews). */
  public static int estimateTileCount(double[] bbox, int minZoom, int maxZoom, int layerCount) {
    if (bbox == null || bbox.length != 4) return 0;

    double west = bbox[0];
    double south = bbox[1];
    double east = bbox[2];
    double north = bbox[3];
    int total = 0;

    for (int z = minZoom; z <= maxZoom; z++) {
      int minX = lonToTileX(west, z);
      int maxX = lonToTileX(east, z);
      int minY = latToTileY(north, z);
      int maxY = latToTileY(south, z);

      int tilesAtZoom = (maxX - minX + 1) * (maxY - minY + 1);
      total += tilesAtZoom;
    }

    return total * layerCount;
  }

  // --- Private helpers ---

  /** Build the complete list of URLs to download (tiles + style resources). */
  private List<String> buildAllUrls(DownloadRequest request) {
    double west = request.bbox[0];
    double south = request.bbox[1];
    double east = request.bbox[2];
    double north = request.bbox[3];

    List<TileCoord> tileCoords = calculateTileCoords(west, south, east, north, request.minZoom, request.maxZoom);
    List<String> urls = buildTileUrls(tileCoords, request.layers, request.token);
    urls.addAll(buildResourceUrls(request.styleName, request.token));
    return urls;
  }

  /** Calculate all tile coordinates for the given bounds and zoom range. */
  private static List<TileCoord> calculateTileCoords(
      double west, double south, double east, double north, int minZoom, int maxZoom) {
    List<TileCoord> coords = new ArrayList<>();
    for (int z = minZoom; z <= maxZoom; z++) {
      int minX = lonToTileX(west, z);
      int maxX = lonToTileX(east, z);
      int minY = latToTileY(north, z);
      int maxY = latToTileY(south, z);

      for (int x = minX; x <= maxX; x++) {
        for (int y = minY; y <= maxY; y++) {
          coords.add(new TileCoord(z, x, y));
        }
      }
    }
    return coords;
  }

  /** Build tile URLs for all coordinates and layers. */
  private static List<String> buildTileUrls(
      List<TileCoord> tileCoords, List<TileLayer> layers, String token) {
    List<String> urls = new ArrayList<>();
    for (TileCoord coord : tileCoords) {
      for (TileLayer layer : layers) {
        urls.add(tileUrlForLayer(layer, coord, token));
      }
    }
    return urls;
  }

  /** Get the URL template for a specific tile layer. */
  private static String tileUrlForLayer(TileLayer layer, TileCoord coord, String token) {
    switch (layer) {
      case VECTOR:
        return String.format(VECTOR_TEMPLATE, coord.z, coord.x, coord.y, token);
      case SATELLITE:
        return String.format(SATELLITE_TEMPLATE, coord.z, coord.x, coord.y, token);
      case TERRAIN:
        return String.format(TERRAIN_TEMPLATE, coord.z, coord.x, coord.y, token);
      default:
        return String.format(VECTOR_TEMPLATE, coord.z, coord.x, coord.y, token);
    }
  }

  /** Build style, sprite, and glyph resource URLs. */
  private static List<String> buildResourceUrls(String styleName, String token) {
    List<String> urls = new ArrayList<>();
    if (styleName == null || styleName.isEmpty()) {
      return urls;
    }

    urls.add(String.format(STYLE_TEMPLATE, styleName, token));
    urls.add(String.format(SPRITE_JSON_TEMPLATE, styleName, token));
    urls.add(String.format(SPRITE_PNG_TEMPLATE, styleName, token));

    // Common glyph ranges for typical Latin + Arabic text
    String[] fontStacks = {
      "DIN Pro Regular,Arial Unicode MS Regular",
      "DIN Pro Medium,Arial Unicode MS Regular",
      "DIN Pro Bold,Arial Unicode MS Bold"
    };
    String[] glyphRanges = {
      "0-255", "256-511", "512-767", "768-1023",
      "8192-8447", "8448-8703", "65024-65279"
    };
    for (String fontStack : fontStacks) {
      for (String range : glyphRanges) {
        urls.add(String.format(GLYPHS_TEMPLATE, fontStack, range, token));
      }
    }
    return urls;
  }

  /** Submit all download tasks to the executor and track progress. */
  private void submitDownloadTasks(
      String regionId, List<String> urls, int totalTiles, DownloadListener listener) {
    AtomicBoolean cancelFlag = new AtomicBoolean(false);
    cancelFlags.put(regionId, cancelFlag);

    AtomicInteger completed = new AtomicInteger(0);

    for (String url : urls) {
      executor.submit(
          () -> {
            if (cancelFlag.get()) return;

            try {
              if (!cacheManager.has(url)) {
                byte[] data = fetchTile(url);
                if (data.length > 0 && !cancelFlag.get()) {
                  cacheManager.put(url, data);
                }
              }
            } catch (IOException e) {
              Log.w(TAG, "Failed to download: " + url, e);
            }

            int done = completed.incrementAndGet();
            if (listener != null && !cancelFlag.get()) {
              float pct = (float) done / totalTiles * 100f;
              listener.onProgress(regionId, done, totalTiles, pct);

              if (done >= totalTiles) {
                cancelFlags.remove(regionId);
                listener.onComplete(regionId, totalTiles, false);
              }
            }
          });
    }
  }

  // --- Slippy map tile coordinate math ---

  /**
   * Convert longitude to tile X coordinate at a given zoom level. x = floor((lon + 180) / 360 *
   * 2^z)
   */
  static int lonToTileX(double lon, int zoom) {
    int n = 1 << zoom; // 2^z
    int x = (int) Math.floor((lon + 180.0) / 360.0 * n);
    return Math.max(0, Math.min(n - 1, x));
  }

  /**
   * Convert latitude to tile Y coordinate at a given zoom level. y = floor((1 - ln(tan(lat_rad) +
   * sec(lat_rad)) / pi) / 2 * 2^z)
   */
  static int latToTileY(double lat, int zoom) {
    int n = 1 << zoom; // 2^z
    double latRad = Math.toRadians(lat);
    int y =
        (int)
            Math.floor(
                (1.0 - Math.log(Math.tan(latRad) + 1.0 / Math.cos(latRad)) / Math.PI) / 2.0 * n);
    return Math.max(0, Math.min(n - 1, y));
  }

  /** Fetch a tile from the network. Returns empty array on non-200 response. */
  private byte[] fetchTile(String urlString) throws IOException {
    HttpURLConnection connection =
        (HttpURLConnection) URI.create(urlString).toURL().openConnection();
    try {
      connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
      connection.setReadTimeout(READ_TIMEOUT_MS);
      connection.setRequestMethod("GET");
      connection.setRequestProperty("User-Agent", "TrustSky-Spotlight-Android/1.0");

      int responseCode = connection.getResponseCode();
      if (responseCode != 200) {
        Log.w(TAG, "HTTP " + responseCode + " for: " + urlString);
        return new byte[0];
      }

      try (InputStream inputStream = connection.getInputStream();
          ByteArrayOutputStream baos = new ByteArrayOutputStream()) {
        byte[] buffer = new byte[8192];
        int bytesRead;
        while ((bytesRead = inputStream.read(buffer)) != -1) {
          baos.write(buffer, 0, bytesRead);
        }
        return baos.toByteArray();
      }
    } finally {
      connection.disconnect();
    }
  }

  /** Internal tile coordinate holder. */
  private static class TileCoord {
    final int z;
    final int x;
    final int y;

    TileCoord(int z, int x, int y) {
      this.z = z;
      this.x = x;
      this.y = y;
    }
  }
}
