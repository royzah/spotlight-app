/**
 * Tile URL patterns for offline caching.
 * Used by native plugins to identify which requests to intercept.
 */
export const TILE_URL_PATTERNS = [
  // Vector tiles (dark basemap)
  '*.tiles.mapbox.com/v4/mapbox.mapbox-streets-v8/*',
  // Satellite raster
  'api.mapbox.com/v4/mapbox.satellite/*',
  // Terrain DEM
  'api.mapbox.com/v4/mapbox.terrain-rgb/*',
  // Style JSON
  'api.mapbox.com/styles/v1/mapbox/*',
  // Glyphs / fonts
  'api.mapbox.com/fonts/v1/mapbox/*',
  // Sprites
  'api.mapbox.com/styles/v1/mapbox/*/sprite*',
] as const;

/**
 * Hostnames that serve map tiles.
 */
export const TILE_HOSTS = [
  'api.mapbox.com',
  'a.tiles.mapbox.com',
  'b.tiles.mapbox.com',
  'c.tiles.mapbox.com',
  'd.tiles.mapbox.com',
] as const;

/**
 * UAE bounding box [west, south, east, north] for default offline region.
 */
export const UAE_BBOX: [number, number, number, number] = [51, 22, 57, 26];

/**
 * Default zoom range for offline tile downloads.
 */
export const DEFAULT_ZOOM_RANGE = { min: 5, max: 12 } as const;

/**
 * Check if a URL is a map tile URL that should be cached.
 */
export function isTileUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return TILE_HOSTS.some(
      (host) => parsed.hostname === host || parsed.hostname.endsWith(`.${host}`),
    );
  } catch {
    return false;
  }
}
