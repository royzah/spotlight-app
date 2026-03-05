import type { PluginListenerHandle } from '@capacitor/core';

export interface DownloadRegionOptions {
  /** Region identifier for later management */
  regionId: string;
  /** Bounding box [west, south, east, north] */
  bbox: [number, number, number, number];
  /** Minimum zoom level to cache */
  minZoom: number;
  /** Maximum zoom level to cache */
  maxZoom: number;
  /** Mapbox style URLs to cache tiles for */
  styleUrls?: string[];
  /** Include satellite tiles (default: true) */
  includeSatellite?: boolean;
  /** Include terrain DEM tiles (default: true) */
  includeTerrain?: boolean;
}

export interface DownloadProgressEvent {
  /** Region being downloaded */
  regionId: string;
  /** Number of tiles downloaded so far */
  completedTiles: number;
  /** Total tiles to download */
  totalTiles: number;
  /** Progress 0.0 – 1.0 */
  progress: number;
  /** Bytes downloaded so far */
  bytesDownloaded: number;
  /** Whether the download is complete */
  isComplete: boolean;
  /** Error message if download failed */
  error?: string;
}

export interface CacheStats {
  /** Total cached tiles */
  tileCount: number;
  /** Total size in bytes */
  totalBytes: number;
  /** Per-region breakdown */
  regions: {
    regionId: string;
    tileCount: number;
    totalBytes: number;
  }[];
}

export interface OfflineTilesPlugin {
  /**
   * Download tiles for a geographic region.
   * Emits 'downloadProgress' events during download.
   */
  downloadRegion(options: DownloadRegionOptions): Promise<void>;

  /**
   * Cancel an in-progress download.
   */
  cancelDownload(options: { regionId: string }): Promise<void>;

  /**
   * Delete cached tiles for a specific region.
   */
  deleteRegion(options: { regionId: string }): Promise<void>;

  /**
   * Clear the entire tile cache.
   */
  clearCache(): Promise<void>;

  /**
   * Get cache statistics (tile count, size, per-region breakdown).
   */
  getCacheStats(): Promise<CacheStats>;

  /**
   * Enable or disable the native request interceptor.
   * When enabled, tile requests are served from cache when available.
   */
  setInterceptorEnabled(options: { enabled: boolean }): Promise<void>;

  /**
   * Listen for download progress events.
   */
  addListener(
    eventName: 'downloadProgress',
    handler: (event: DownloadProgressEvent) => void,
  ): Promise<PluginListenerHandle>;
}
