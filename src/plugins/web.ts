import { WebPlugin } from '@capacitor/core';
import type { CacheStats, DownloadRegionOptions, OfflineTilesPlugin } from './definitions';

/**
 * Web fallback — tile caching is not supported in the browser.
 * All methods are no-ops or return empty results.
 */
export class OfflineTilesWeb extends WebPlugin implements OfflineTilesPlugin {
  async downloadRegion(_options: DownloadRegionOptions): Promise<void> {
    console.warn('OfflineTiles: downloadRegion is not supported on web');
  }

  async cancelDownload(_options: { regionId: string }): Promise<void> {
    console.warn('OfflineTiles: cancelDownload is not supported on web');
  }

  async deleteRegion(_options: { regionId: string }): Promise<void> {
    console.warn('OfflineTiles: deleteRegion is not supported on web');
  }

  async clearCache(): Promise<void> {
    console.warn('OfflineTiles: clearCache is not supported on web');
  }

  async getCacheStats(): Promise<CacheStats> {
    return { tileCount: 0, totalBytes: 0, regions: [] };
  }

  async setInterceptorEnabled(_options: { enabled: boolean }): Promise<void> {
    console.warn('OfflineTiles: setInterceptorEnabled is not supported on web');
  }
}
