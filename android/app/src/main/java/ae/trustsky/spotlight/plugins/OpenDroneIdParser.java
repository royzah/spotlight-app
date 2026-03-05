package ae.trustsky.spotlight.plugins;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;

/**
 * Parser for ASTM F3411 / ASD-STAN prEN 4709-002 OpenDroneID BLE messages.
 *
 * Each message is 25 bytes. The header byte encodes (type << 4 | protoVersion).
 * Service data from BLE advertisement UUID 0xFFFA may contain a single message
 * (25 bytes) or a message pack (type 0xF) containing multiple 25-byte messages.
 */
public class OpenDroneIdParser {

    // Message types
    private static final int MSG_BASIC_ID     = 0;
    private static final int MSG_LOCATION     = 1;
    private static final int MSG_AUTH         = 2;
    private static final int MSG_SELF_ID      = 3;
    private static final int MSG_SYSTEM       = 4;
    private static final int MSG_OPERATOR_ID  = 5;
    private static final int MSG_PACK         = 0xF;

    private static final int MSG_SIZE = 25;

    private OpenDroneIdParser() {
        // Utility class — prevent instantiation
    }

    /** Accumulated result from parsing one or more messages. */
    public static class DroneInfo {
        private String uasId = "";
        private int idType = 0;
        private int uaType = 0;
        private double latitude = 0;
        private double longitude = 0;
        private double altGeo = -1000;
        private double speed = 0;
        private double heading = 0;
        private double vertSpeed = 0;
        private int status = 0;
        private double operatorLat = 0;
        private double operatorLon = 0;
        private String operatorRegistrationId = "";
        private String description = "";
        private long timestamp = 0;

        public String getUasId() { return uasId; }
        public int getIdType() { return idType; }
        public int getUaType() { return uaType; }
        public double getLatitude() { return latitude; }
        public double getLongitude() { return longitude; }
        public double getAltGeo() { return altGeo; }
        public double getSpeed() { return speed; }
        public double getHeading() { return heading; }
        public double getVertSpeed() { return vertSpeed; }
        public int getStatus() { return status; }
        public double getOperatorLat() { return operatorLat; }
        public double getOperatorLon() { return operatorLon; }
        public String getOperatorRegistrationId() { return operatorRegistrationId; }
        public String getDescription() { return description; }
        public long getTimestamp() { return timestamp; }
    }

    /**
     * Parse BLE service data for UUID 0xFFFA.
     * After Android strips the 16-bit UUID, the data layout is:
     *   Byte 0: Application Code (0x0D for OpenDroneID)
     *   Byte 1: 8-bit message counter
     *   Bytes 2+: 25-byte OpenDroneID message(s)
     */
    public static DroneInfo parseServiceData(byte[] data) {
        DroneInfo info = new DroneInfo();
        if (data == null || data.length < 3) return info;

        // Skip application code (0x0D) and message counter
        int offset = 2;
        int remaining = data.length - offset;

        if (remaining < MSG_SIZE) return info;

        int header = data[offset] & 0xFF;
        int msgType = (header >> 4) & 0x0F;

        if (msgType == MSG_PACK) {
            // Message pack: header byte, then 1 byte msgCount, then N * 25 messages
            if (remaining < 2) return info;
            int msgCount = data[offset + 1] & 0xFF;
            int packOffset = offset + 2;
            for (int i = 0; i < msgCount && packOffset + MSG_SIZE <= data.length; i++) {
                parseSingleMessage(data, packOffset, info);
                packOffset += MSG_SIZE;
            }
        } else {
            parseSingleMessage(data, offset, info);
        }

        return info;
    }

    private static void parseSingleMessage(byte[] data, int offset, DroneInfo info) {
        if (offset + MSG_SIZE > data.length) return;

        int header = data[offset] & 0xFF;
        int msgType = (header >> 4) & 0x0F;

        // Payload starts after the header byte
        int p = offset + 1;

        switch (msgType) {
            case MSG_BASIC_ID:
                parseBasicId(data, p, info);
                break;
            case MSG_LOCATION:
                parseLocation(data, p, info);
                break;
            case MSG_SELF_ID:
                parseSelfId(data, p, info);
                break;
            case MSG_SYSTEM:
                parseSystem(data, p, info);
                break;
            case MSG_OPERATOR_ID:
                parseOperatorId(data, p, info);
                break;
            case MSG_AUTH:
                // Authentication messages are optional; skip for now
                break;
            default:
                // Unknown message type; ignore
                break;
        }
    }

    private static void parseBasicId(byte[] data, int p, DroneInfo info) {
        // Byte 0: idType (4 bits) | uaType (4 bits)
        info.idType = (data[p] & 0xF0) >> 4;
        info.uaType = data[p] & 0x0F;
        // Bytes 1..20: UAS ID (null-terminated ASCII)
        info.uasId = extractString(data, p + 1, 20);
    }

    private static void parseLocation(byte[] data, int p, DroneInfo info) {
        ByteBuffer bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);

        // Byte 0: status (4 bits) | heightType (1 bit) | EW direction (1 bit) | speedMult (2 bits)
        int flags = data[p] & 0xFF;
        info.status = (flags >> 4) & 0x0F;
        int speedMult = flags & 0x03;
        double speedMultiplier = resolveSpeedMultiplier(speedMult);

        // Byte 1: direction — EW bit selects 0-179 or 180-359 range
        int dirRaw = data[p + 1] & 0xFF;
        boolean ewBit = ((flags >> 2) & 0x01) == 1;
        info.heading = (dirRaw + (ewBit ? 180 : 0)) % 360;

        // Byte 2: speed (encoded, depends on multiplier)
        int speedRaw = data[p + 2] & 0xFF;
        info.speed = speedRaw * speedMultiplier;

        // Byte 3: vertical speed (int8, resolution 0.5 m/s)
        info.vertSpeed = data[p + 3] * 0.5;

        // Bytes 4-7: latitude (int32 LE, degrees * 1e7)
        info.latitude = bb.getInt(p + 4) / 1e7;

        // Bytes 8-11: longitude (int32 LE, degrees * 1e7)
        info.longitude = bb.getInt(p + 8) / 1e7;

        // Bytes 14-15: geodetic altitude (uint16 LE, * 0.5 - 1000)
        int altGeoRaw = bb.getShort(p + 14) & 0xFFFF;
        info.altGeo = altGeoRaw * 0.5 - 1000;

        // Bytes 22-23: timestamp (uint16 LE, tenths of seconds since the hour)
        int tsRaw = bb.getShort(p + 22) & 0xFFFF;
        info.timestamp = tsRaw;
    }

    private static double resolveSpeedMultiplier(int speedMult) {
        if (speedMult == 0) return 0.25;
        if (speedMult == 1) return 0.75;
        return 1.0;
    }

    private static void parseSelfId(byte[] data, int p, DroneInfo info) {
        // Byte 0: description type
        // Bytes 1..23: description text (null-terminated)
        info.description = extractString(data, p + 1, 23);
    }

    private static void parseSystem(byte[] data, int p, DroneInfo info) {
        ByteBuffer bb = ByteBuffer.wrap(data).order(ByteOrder.LITTLE_ENDIAN);

        // Bytes 1-4: operator latitude (int32 LE / 1e7)
        info.operatorLat = bb.getInt(p + 1) / 1e7;
        // Bytes 5-8: operator longitude (int32 LE / 1e7)
        info.operatorLon = bb.getInt(p + 5) / 1e7;
    }

    private static void parseOperatorId(byte[] data, int p, DroneInfo info) {
        // Bytes 1..20: operator registration ID (null-terminated ASCII)
        info.operatorRegistrationId = extractString(data, p + 1, 20);
    }

    /**
     * Find the OpenDroneID payload in raw BLE advertisement bytes.
     * Scans for AD type 0x16 with UUID 0xFFFA and app code 0x0D.
     * Returns the index of the app code byte, or -1 if not found.
     */
    public static int findOdidPayload(byte[] raw) {
        if (raw == null) return -1;
        int i = 0;
        while (i < raw.length) {
            int adLen = raw[i] & 0xFF;
            if (adLen == 0 || i + adLen >= raw.length) break;
            // AD type at i+1, data starts at i+2
            int adType = raw[i + 1] & 0xFF;
            if (adType == 0x16 && adLen >= 5) {
                // Check for UUID 0xFFFA (little-endian: FA FF)
                int uuidLo = raw[i + 2] & 0xFF;
                int uuidHi = raw[i + 3] & 0xFF;
                if (uuidLo == 0xFA && uuidHi == 0xFF) {
                    // App code at i+4, counter at i+5, message at i+6
                    return i + 4;
                }
            }
            i += adLen + 1;
        }
        return -1;
    }

    /** Extract a null-terminated ASCII string from a byte array. */
    private static String extractString(byte[] data, int offset, int maxLen) {
        int end = Math.min(offset + maxLen, data.length);
        StringBuilder sb = new StringBuilder();
        for (int i = offset; i < end; i++) {
            char c = (char) (data[i] & 0xFF);
            if (c == 0) break;
            sb.append(c);
        }
        return sb.toString().trim();
    }
}
