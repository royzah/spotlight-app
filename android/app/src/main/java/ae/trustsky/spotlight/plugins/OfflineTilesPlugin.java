package ae.trustsky.spotlight.plugins;

import android.util.Log;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import com.getcapacitor.Bridge;
import com.getcapacitor.BridgeWebViewClient;
import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.util.ArrayList;
import java.util.List;
import org.json.JSONArray;
import org.json.JSONException;

/**
 * Capacitor 8 plugin that bridges the offline tile caching system to the web app. Provides methods
 * for downloading regions, managing cache, and toggling the WebView request interceptor for serving
 * cached tiles.
 */
@CapacitorPlugin(name = "OfflineTiles")
public class OfflineTilesPlugin extends Plugin {

  private static final String TAG = "OfflineTilesPlugin";

  private TileCacheManager cacheManager;
  private TileInterceptor interceptor;
  private TileDownloadManager downloadManager;

  @Override
  public void load() {
    cacheManager = new TileCacheManager(getContext());
    interceptor = new TileInterceptor(cacheManager);
    downloadManager = new TileDownloadManager(cacheManager);

    // Set up WebView interceptor by replacing the WebViewClient
    // with one that delegates tile requests to our interceptor.
    Bridge bridge = getBridge();
    bridge
        .getWebView()
        .post(
            () -> {
              bridge.setWebViewClient(
                  new BridgeWebViewClient(bridge) {
                    @Override
                    public WebResourceResponse shouldInterceptRequest(
                        WebView view, WebResourceRequest request) {
                      if (interceptor.isEnabled()) {
                        WebResourceResponse resp = interceptor.intercept(request);
                        if (resp != null) return resp;
                      }
                      return super.shouldInterceptRequest(view, request);
                    }

                    @Override
                    public void onReceivedError(
                        WebView view, WebResourceRequest request, WebResourceError error) {
                      if (request.isForMainFrame()) {
                        Log.w(TAG, "Main frame load failed: " + error.getDescription());
                        String retryUrl = request.getUrl().toString();
                        view.loadUrl(
                            "file:///android_asset/public/index.html#retry=" + retryUrl);
                        return;
                      }
                      super.onReceivedError(view, request, error);
                    }
                  });
            });

    Log.d(TAG, "OfflineTilesPlugin loaded, interceptor installed");
  }

  /**
   * Download tiles for a region.
   *
   * <p>Args (from JS): regionId: string bbox: [west, south, east, north] minZoom: number maxZoom:
   * number layers: string[] — e.g. ["vector", "satellite", "terrain"] styleName: string — e.g.
   * "dark-v11" accessToken: string
   */
  @PluginMethod
  public void downloadRegion(PluginCall call) {
    String regionId = call.getString("regionId");
    if (regionId == null || regionId.isEmpty()) {
      call.reject("regionId is required");
      return;
    }

    JSONArray bboxArray = call.getArray("bbox");
    if (bboxArray == null || bboxArray.length() != 4) {
      call.reject("bbox must be an array of [west, south, east, north]");
      return;
    }

    int minZoom = call.getInt("minZoom", 0);
    int maxZoom = call.getInt("maxZoom", 14);
    String styleName = call.getString("styleName", "dark-v11");
    String accessToken = call.getString("accessToken");

    if (accessToken == null || accessToken.isEmpty()) {
      call.reject("accessToken is required");
      return;
    }

    double[] bbox;
    try {
      bbox =
          new double[] {
            bboxArray.getDouble(0),
            bboxArray.getDouble(1),
            bboxArray.getDouble(2),
            bboxArray.getDouble(3)
          };
    } catch (JSONException e) {
      call.reject("Invalid bbox values: " + e.getMessage());
      return;
    }

    // Parse layer types
    List<TileDownloadManager.TileLayer> layers = new ArrayList<>();
    JSONArray layerArray = call.getArray("layers");
    if (layerArray != null) {
      for (int i = 0; i < layerArray.length(); i++) {
        try {
          String layerName = layerArray.getString(i).toUpperCase();
          layers.add(TileDownloadManager.TileLayer.valueOf(layerName));
        } catch (Exception e) {
          Log.w(TAG, "Unknown layer type at index " + i + ", skipping");
        }
      }
    }
    if (layers.isEmpty()) {
      layers.add(TileDownloadManager.TileLayer.VECTOR);
    }

    // Resolve the call immediately — progress comes via events
    JSObject result = new JSObject();
    int estimate = TileDownloadManager.estimateTileCount(bbox, minZoom, maxZoom, layers.size());
    result.put("regionId", regionId);
    result.put("estimatedTiles", estimate);
    result.put("status", "started");
    call.resolve(result);

    // Start the download with progress events
    downloadManager.downloadRegion(
        regionId,
        bbox,
        minZoom,
        maxZoom,
        layers,
        styleName,
        accessToken,
        new TileDownloadManager.DownloadListener() {
          @Override
          public void onProgress(String regionId, int completed, int total, float percentage) {
            JSObject event = new JSObject();
            event.put("regionId", regionId);
            event.put("completed", completed);
            event.put("total", total);
            event.put("percentage", Math.round(percentage * 10) / 10.0);
            notifyListeners("downloadProgress", event);
          }

          @Override
          public void onComplete(String regionId, int totalTiles, boolean cancelled) {
            JSObject event = new JSObject();
            event.put("regionId", regionId);
            event.put("totalTiles", totalTiles);
            event.put("cancelled", cancelled);
            event.put("status", cancelled ? "cancelled" : "complete");
            notifyListeners("downloadProgress", event);
          }

          @Override
          public void onError(String regionId, String error) {
            JSObject event = new JSObject();
            event.put("regionId", regionId);
            event.put("error", error);
            event.put("status", "error");
            notifyListeners("downloadProgress", event);
          }
        });
  }

  /** Cancel an in-progress download. Args: regionId: string */
  @PluginMethod
  public void cancelDownload(PluginCall call) {
    String regionId = call.getString("regionId");
    if (regionId == null || regionId.isEmpty()) {
      call.reject("regionId is required");
      return;
    }

    downloadManager.cancel(regionId);

    JSObject result = new JSObject();
    result.put("regionId", regionId);
    result.put("status", "cancelled");
    call.resolve(result);
  }

  /** Delete cached tiles for a region. Args: regionPrefix: string — cache key prefix to match */
  @PluginMethod
  public void deleteRegion(PluginCall call) {
    String regionPrefix = call.getString("regionPrefix");
    if (regionPrefix == null || regionPrefix.isEmpty()) {
      call.reject("regionPrefix is required");
      return;
    }

    int deleted = cacheManager.delete(regionPrefix);

    JSObject result = new JSObject();
    result.put("regionPrefix", regionPrefix);
    result.put("deletedCount", deleted);
    call.resolve(result);
  }

  /** Clear the entire tile cache. */
  @PluginMethod
  public void clearCache(PluginCall call) {
    int deleted = cacheManager.clear();

    JSObject result = new JSObject();
    result.put("deletedCount", deleted);
    call.resolve(result);
  }

  /** Get cache statistics. Returns: { tileCount, totalBytes, totalMB } */
  @PluginMethod
  public void getCacheStats(PluginCall call) {
    TileCacheManager.CacheStats stats = cacheManager.getStats();

    JSObject result = new JSObject();
    result.put("tileCount", stats.tileCount);
    result.put("totalBytes", stats.totalBytes);
    result.put("totalMB", Math.round(stats.totalBytes / 1024.0 / 1024.0 * 100) / 100.0);
    call.resolve(result);
  }

  /** Enable or disable the tile cache interceptor. Args: enabled: boolean */
  @PluginMethod
  public void setInterceptorEnabled(PluginCall call) {
    Boolean enabled = call.getBoolean("enabled");
    if (enabled == null) {
      call.reject("enabled (boolean) is required");
      return;
    }

    interceptor.setEnabled(enabled);

    JSObject result = new JSObject();
    result.put("enabled", enabled);
    call.resolve(result);
  }
}
