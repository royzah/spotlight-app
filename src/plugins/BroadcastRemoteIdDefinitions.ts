import type { PluginListenerHandle } from '@capacitor/core';

/** Event emitted when a BRID drone is detected or updated via BLE. */
export interface BridDroneEvent {
  deviceId: string;
  rssi: number;
  uasId?: string;
  idType?: number;
  uaType?: number;
  latitude?: number;
  longitude?: number;
  altGeo?: number;
  speed?: number;
  heading?: number;
  vertSpeed?: number;
  status?: number;
  operatorLat?: number;
  operatorLon?: number;
  operatorRegistrationId?: string;
  description?: string;
  timestamp: string;
}

export interface BroadcastRemoteIdPlugin {
  startScan(): Promise<{ scanning: boolean }>;
  stopScan(): Promise<{ scanning: boolean }>;
  isScanning(): Promise<{ scanning: boolean }>;
  checkPermissions(): Promise<{ bluetooth: string; location: string }>;
  requestPermissions(): Promise<{ bluetooth: string; location: string }>;
  addListener(
    eventName: 'droneDetected',
    handler: (event: BridDroneEvent) => void,
  ): Promise<PluginListenerHandle>;
  addListener(
    eventName: 'scanError',
    handler: (event: { code: number; message: string }) => void,
  ): Promise<PluginListenerHandle>;
}
