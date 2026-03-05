import { WebPlugin } from '@capacitor/core';
import type { BroadcastRemoteIdPlugin } from './BroadcastRemoteIdDefinitions';

/**
 * Web fallback — BLE scanning is not available in the browser.
 * All methods are no-ops.
 */
export class BroadcastRemoteIdWeb extends WebPlugin implements BroadcastRemoteIdPlugin {
  async startScan(): Promise<{ scanning: boolean }> {
    console.warn('BroadcastRemoteId: BLE scanning is not supported on web');
    return { scanning: false };
  }

  async stopScan(): Promise<{ scanning: boolean }> {
    return { scanning: false };
  }

  async isScanning(): Promise<{ scanning: boolean }> {
    return { scanning: false };
  }

  async checkPermissions(): Promise<{ bluetooth: string; location: string }> {
    return { bluetooth: 'denied', location: 'denied' };
  }

  async requestPermissions(): Promise<{ bluetooth: string; location: string }> {
    console.warn('BroadcastRemoteId: permissions not available on web');
    return { bluetooth: 'denied', location: 'denied' };
  }
}
