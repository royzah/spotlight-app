import { registerPlugin } from '@capacitor/core';
import type { OfflineTilesPlugin } from './definitions';

const OfflineTiles = registerPlugin<OfflineTilesPlugin>('OfflineTiles', {
  web: () => import('./web').then((m) => new m.OfflineTilesWeb()),
});

export * from './definitions';
export { OfflineTiles };
