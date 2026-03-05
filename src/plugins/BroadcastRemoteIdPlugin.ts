import { registerPlugin } from '@capacitor/core';
import type { BroadcastRemoteIdPlugin } from './BroadcastRemoteIdDefinitions';

const BroadcastRemoteId = registerPlugin<BroadcastRemoteIdPlugin>('BroadcastRemoteId', {
  web: () => import('./BroadcastRemoteIdWeb').then((m) => new m.BroadcastRemoteIdWeb()),
});

export * from './BroadcastRemoteIdDefinitions';
export { BroadcastRemoteId };
