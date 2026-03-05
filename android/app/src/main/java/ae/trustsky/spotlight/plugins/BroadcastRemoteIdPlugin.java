package ae.trustsky.spotlight.plugins;

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothManager;
import android.bluetooth.le.BluetoothLeScanner;
import android.bluetooth.le.ScanCallback;
import android.bluetooth.le.ScanFilter;
import android.bluetooth.le.ScanResult;
import android.bluetooth.le.ScanSettings;
import android.content.Context;
import android.os.ParcelUuid;
import android.util.Log;

import com.getcapacitor.JSObject;
import com.getcapacitor.Plugin;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
import com.getcapacitor.annotation.CapacitorPlugin;
import com.getcapacitor.annotation.Permission;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.TimeZone;

@CapacitorPlugin(
    name = "BroadcastRemoteId",
    permissions = {
        @Permission(
            alias = "bluetooth",
            strings = {
                Manifest.permission.BLUETOOTH_SCAN,
                Manifest.permission.BLUETOOTH_CONNECT
            }
        ),
        @Permission(
            alias = "location",
            strings = {
                Manifest.permission.ACCESS_FINE_LOCATION
            }
        )
    }
)
public class BroadcastRemoteIdPlugin extends Plugin {

    private static final String TAG = "BRIDPlugin";
    private static final String EVENT_DRONE_DETECTED = "droneDetected";
    private static final String EVENT_SCAN_ERROR = "scanError";

    private static final String KEY_SCANNING  = "scanning";
    private static final String KEY_BLUETOOTH = "bluetooth";
    private static final String KEY_LOCATION  = "location";

    /** OpenDroneID BLE service UUID (0xFFFA). */
    private static final ParcelUuid ODID_SERVICE_UUID =
        ParcelUuid.fromString("0000FFFA-0000-1000-8000-00805F9B34FB");

    /** OpenDroneID application code (0x0D) — first byte of service data. */
    private static final byte[] ODID_AD_CODE = new byte[]{(byte) 0x0D};

    private BluetoothLeScanner scanner;
    private boolean scanning = false;
    private final SimpleDateFormat isoFormat;

    public BroadcastRemoteIdPlugin() {
        isoFormat = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US);
        isoFormat.setTimeZone(TimeZone.getTimeZone("UTC"));
    }

    private final ScanCallback scanCallback = new ScanCallback() {
        @Override
        public void onScanResult(int callbackType, ScanResult result) {
            processScanResult(result);
        }

        @Override
        public void onBatchScanResults(List<ScanResult> results) {
            for (ScanResult result : results) {
                processScanResult(result);
            }
        }

        @Override
        public void onScanFailed(int errorCode) {
            Log.e(TAG, "BLE scan failed with error code: " + errorCode);
            scanning = false;
            JSObject err = new JSObject();
            err.put("code", errorCode);
            err.put("message", "BLE scan failed: " + errorCode);
            notifyListeners(EVENT_SCAN_ERROR, err);
        }

        private void processScanResult(ScanResult result) {
            if (result.getScanRecord() == null) return;

            // Try getServiceData first (returns bytes after UUID: appCode + counter + message)
            byte[] serviceData = result.getScanRecord().getServiceData(ODID_SERVICE_UUID);

            if (serviceData == null || serviceData.length < 27) {
                // Fallback: some Android versions return null from getServiceData.
                // Parse raw advertisement bytes like the reference receiver-android app.
                serviceData = result.getScanRecord().getBytes();
                if (serviceData == null) return;
                // In raw bytes, find the OpenDroneID payload starting at the AD code 0x0D
                // Layout: ... [len] [0x16] [FA] [FF] [0x0D] [counter] [25-byte msg] ...
                // getBytes() includes all AD structures; scan for our service data
                int idx = OpenDroneIdParser.findOdidPayload(serviceData);
                if (idx < 0) return;
                // Extract from appCode onward
                int payloadLen = serviceData.length - idx;
                byte[] extracted = new byte[payloadLen];
                System.arraycopy(serviceData, idx, extracted, 0, payloadLen);
                serviceData = extracted;
            }

            OpenDroneIdParser.DroneInfo info = OpenDroneIdParser.parseServiceData(serviceData);

            String deviceId = result.getDevice().getAddress();
            int rssi = result.getRssi();

            JSObject obj = new JSObject();
            obj.put("deviceId", deviceId);
            obj.put("rssi", rssi);
            obj.put("timestamp", isoFormat.format(new Date()));

            if (!info.getUasId().isEmpty()) obj.put("uasId", info.getUasId());
            if (info.getIdType() != 0) obj.put("idType", info.getIdType());
            if (info.getUaType() != 0) obj.put("uaType", info.getUaType());
            if (info.getLatitude() != 0) obj.put("latitude", info.getLatitude());
            if (info.getLongitude() != 0) obj.put("longitude", info.getLongitude());
            if (info.getAltGeo() > -1000) obj.put("altGeo", info.getAltGeo());
            if (info.getSpeed() > 0) obj.put("speed", info.getSpeed());
            obj.put("heading", info.getHeading());
            obj.put("vertSpeed", info.getVertSpeed());
            obj.put("status", info.getStatus());
            if (info.getOperatorLat() != 0) obj.put("operatorLat", info.getOperatorLat());
            if (info.getOperatorLon() != 0) obj.put("operatorLon", info.getOperatorLon());
            if (!info.getOperatorRegistrationId().isEmpty())
                obj.put("operatorRegistrationId", info.getOperatorRegistrationId());
            if (!info.getDescription().isEmpty()) obj.put("description", info.getDescription());

            notifyListeners(EVENT_DRONE_DETECTED, obj);
        }
    };

    @PluginMethod
    public void startScan(PluginCall call) {
        if (scanning) {
            call.resolve(scanningResult(true));
            return;
        }

        BluetoothManager btManager = (BluetoothManager)
            getContext().getSystemService(Context.BLUETOOTH_SERVICE);
        if (btManager == null) {
            call.reject("Bluetooth not available");
            return;
        }

        BluetoothAdapter adapter = btManager.getAdapter();
        if (adapter == null || !adapter.isEnabled()) {
            call.reject("Bluetooth is disabled");
            return;
        }

        try {
            scanner = adapter.getBluetoothLeScanner();
        } catch (SecurityException e) {
            call.reject("Bluetooth permission denied");
            return;
        }

        if (scanner == null) {
            call.reject("BLE scanner not available");
            return;
        }

        // Filter for OpenDroneID service UUID 0xFFFA with app code 0x0D
        ScanFilter filter = new ScanFilter.Builder()
            .setServiceData(ODID_SERVICE_UUID, ODID_AD_CODE)
            .build();

        List<ScanFilter> filters = new ArrayList<>();
        filters.add(filter);

        ScanSettings settings = new ScanSettings.Builder()
            .setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY)
            .setReportDelay(0)
            .build();

        try {
            scanner.startScan(filters, settings, scanCallback);
            scanning = true;
            Log.i(TAG, "BLE scan started for OpenDroneID");
            call.resolve(scanningResult(true));
        } catch (SecurityException e) {
            call.reject("Bluetooth scan permission denied");
        }
    }

    @PluginMethod
    public void stopScan(PluginCall call) {
        stopScanning();
        call.resolve(scanningResult(false));
    }

    @PluginMethod
    public void isScanning(PluginCall call) {
        call.resolve(scanningResult(scanning));
    }

    @PluginMethod
    public void checkPermissions(PluginCall call) {
        call.resolve(permissionResult());
    }

    @PluginMethod
    public void requestPermissions(PluginCall call) {
        requestAllPermissions(call, "handlePermissionResult");
    }

    @com.getcapacitor.annotation.PermissionCallback
    private void handlePermissionResult(PluginCall call) {
        call.resolve(permissionResult());
    }

    @Override
    protected void handleOnDestroy() {
        stopScanning();
    }

    private void stopScanning() {
        if (scanning && scanner != null) {
            try {
                scanner.stopScan(scanCallback);
            } catch (SecurityException e) {
                Log.w(TAG, "Could not stop scan: " + e.getMessage());
            }
        }
        scanning = false;
        Log.i(TAG, "BLE scan stopped");
    }

    /** Build a JSObject with the "scanning" key. */
    private static JSObject scanningResult(boolean value) {
        JSObject ret = new JSObject();
        ret.put(KEY_SCANNING, value);
        return ret;
    }

    /** Build a JSObject with current bluetooth and location permission states. */
    private JSObject permissionResult() {
        JSObject ret = new JSObject();
        ret.put(KEY_BLUETOOTH, getPermissionState(KEY_BLUETOOTH));
        ret.put(KEY_LOCATION, getPermissionState(KEY_LOCATION));
        return ret;
    }
}
