package ae.trustsky.spotlight.plugins;

import android.util.Log;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;

/**
 * Intercepts WebView requests for Mapbox tile URLs. Checks the tile cache first; on miss, fetches
 * from the network, caches, and returns.
 *
 * <p>shouldInterceptRequest already runs on a background thread, so network I/O is performed
 * directly on the calling thread.
 */
public class TileInterceptor {

  private static final String TAG = "TileInterceptor";
  private static final int CONNECT_TIMEOUT_MS = 10_000;
  private static final int READ_TIMEOUT_MS = 15_000;

  private final TileCacheManager cacheManager;
  private volatile boolean enabled = false;

  // Hosts we intercept
  private static final Set<String> TILE_HOSTS = new HashSet<>();

  static {
    TILE_HOSTS.add("api.mapbox.com");
  }

  public TileInterceptor(TileCacheManager cacheManager) {
    this.cacheManager = cacheManager;
  }

  public boolean isEnabled() {
    return enabled;
  }

  public void setEnabled(boolean enabled) {
    this.enabled = enabled;
    Log.d(TAG, "Tile interceptor " + (enabled ? "enabled" : "disabled"));
  }

  /**
   * Attempt to intercept a WebResourceRequest for a tile URL. Returns a WebResourceResponse if the
   * request was handled, null otherwise.
   */
  public WebResourceResponse intercept(WebResourceRequest request) {
    if (!enabled) return null;

    String urlString = request.getUrl().toString();
    String host = request.getUrl().getHost();

    if (!isTileHost(host)) {
      return null;
    }

    // Only intercept GET requests
    if (!"GET".equalsIgnoreCase(request.getMethod())) {
      return null;
    }

    Log.d(TAG, "Intercepting tile request: " + urlString);

    // Check cache first
    byte[] cached = cacheManager.get(urlString);
    if (cached.length > 0) {
      Log.d(TAG, "Cache HIT: " + urlString);
      String mimeType = detectMimeType(urlString);
      return buildResponse(mimeType, cached);
    }

    // Cache miss — fetch from network
    Log.d(TAG, "Cache MISS, fetching: " + urlString);
    try {
      byte[] data = fetchFromNetwork(urlString, request.getRequestHeaders());
      if (data.length > 0) {
        cacheManager.put(urlString, data);
        String mimeType = detectMimeType(urlString);
        return buildResponse(mimeType, data);
      }
    } catch (IOException e) {
      Log.w(TAG, "Network fetch failed for: " + urlString, e);
    }

    // Let the WebView handle it normally
    return null;
  }

  /** Check if the host is a Mapbox tile host. */
  private boolean isTileHost(String host) {
    if (host == null) return false;
    if (TILE_HOSTS.contains(host)) return true;
    return host.endsWith(".tiles.mapbox.com");
  }

  /** Detect MIME type from the URL path. */
  static String detectMimeType(String url) {
    // Strip query params for extension detection
    String path = url;
    int queryIndex = path.indexOf('?');
    if (queryIndex > 0) {
      path = path.substring(0, queryIndex);
    }

    if (path.endsWith(".pbf") || path.endsWith(".vector.pbf")) {
      return "application/x-protobuf";
    } else if (path.endsWith(".png") || path.endsWith(".pngraw")) {
      return "image/png";
    } else if (path.endsWith(".webp")) {
      return "image/webp";
    } else if (path.endsWith(".jpg") || path.endsWith(".jpeg")) {
      return "image/jpeg";
    } else if (path.endsWith(".json")) {
      return "application/json";
    }

    // Default for unknown types
    return "application/octet-stream";
  }

  /** Build a WebResourceResponse from byte data. */
  private WebResourceResponse buildResponse(String mimeType, byte[] data) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Access-Control-Allow-Origin", "*");
    headers.put("Cache-Control", "max-age=604800"); // 7 days

    WebResourceResponse response =
        new WebResourceResponse(mimeType, "UTF-8", new ByteArrayInputStream(data));
    response.setStatusCodeAndReasonPhrase(200, "OK");
    response.setResponseHeaders(headers);
    return response;
  }

  /**
   * Fetch tile data from the network using HttpURLConnection. Called on the shouldInterceptRequest
   * background thread.
   */
  private byte[] fetchFromNetwork(String urlString, Map<String, String> requestHeaders)
      throws IOException {
    HttpURLConnection connection =
        (HttpURLConnection) URI.create(urlString).toURL().openConnection();
    try {
      connection.setConnectTimeout(CONNECT_TIMEOUT_MS);
      connection.setReadTimeout(READ_TIMEOUT_MS);
      connection.setRequestMethod("GET");

      // Forward relevant headers from the original request
      if (requestHeaders != null) {
        for (Map.Entry<String, String> entry : requestHeaders.entrySet()) {
          String key = entry.getKey();
          // Forward User-Agent and Accept headers, skip host-specific ones
          if ("User-Agent".equalsIgnoreCase(key)
              || "Accept".equalsIgnoreCase(key)
              || "Accept-Encoding".equalsIgnoreCase(key)
              || "Accept-Language".equalsIgnoreCase(key)) {
            connection.setRequestProperty(key, entry.getValue());
          }
        }
      }

      int responseCode = connection.getResponseCode();
      if (responseCode != 200) {
        Log.w(TAG, "Non-200 response (" + responseCode + ") for: " + urlString);
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
}
