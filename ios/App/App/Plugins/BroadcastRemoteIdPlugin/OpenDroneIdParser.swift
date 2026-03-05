import Foundation

/// Parser for ASTM F3411 / ASD-STAN prEN 4709-002 OpenDroneID BLE messages.
///
/// Each message is 25 bytes. The header byte encodes `(type << 4 | protoVersion)`.
/// Service data from BLE advertisement UUID 0xFFFA may contain a single message
/// or a message pack (type 0xF) with multiple 25-byte messages.
struct OpenDroneIdParser {

    // MARK: - Message Types

    private static let msgBasicId    = 0
    private static let msgLocation   = 1
    private static let msgAuth       = 2
    private static let msgSelfId     = 3
    private static let msgSystem     = 4
    private static let msgOperatorId = 5
    private static let msgPack       = 0xF

    private static let msgSize = 25

    // MARK: - Result

    struct DroneInfo {
        var uasId: String = ""
        var idType: Int = 0
        var uaType: Int = 0
        var latitude: Double = 0
        var longitude: Double = 0
        var altGeo: Double = -1000
        var speed: Double = 0
        var heading: Double = 0
        var vertSpeed: Double = 0
        var status: Int = 0
        var operatorLat: Double = 0
        var operatorLon: Double = 0
        var operatorRegistrationId: String = ""
        var description: String = ""
        var timestamp: Int = 0
    }

    // MARK: - Public API

    /// Parse BLE service data for UUID 0xFFFA.
    /// The first byte is an application code (counter); actual messages start at offset 1.
    static func parseServiceData(_ data: Data) -> DroneInfo {
        var info = DroneInfo()
        guard data.count >= 2 else { return info }

        let offset = 1 // skip application code byte
        let remaining = data.count - offset
        guard remaining >= msgSize else { return info }

        let header = Int(data[offset])
        let msgType = (header >> 4) & 0x0F

        if msgType == msgPack {
            guard remaining >= 2 else { return info }
            let msgCount = Int(data[offset + 1])
            var packOffset = offset + 2
            for _ in 0..<msgCount {
                guard packOffset + msgSize <= data.count else { break }
                parseSingleMessage(data, offset: packOffset, info: &info)
                packOffset += msgSize
            }
        } else {
            parseSingleMessage(data, offset: offset, info: &info)
        }

        return info
    }

    // MARK: - Private

    private static func parseSingleMessage(_ data: Data, offset: Int, info: inout DroneInfo) {
        guard offset + msgSize <= data.count else { return }

        let header = Int(data[offset])
        let msgType = (header >> 4) & 0x0F
        let p = offset + 1 // payload start

        switch msgType {
        case msgBasicId:
            parseBasicId(data, p: p, info: &info)
        case msgLocation:
            parseLocation(data, p: p, info: &info)
        case msgSelfId:
            parseSelfId(data, p: p, info: &info)
        case msgSystem:
            parseSystem(data, p: p, info: &info)
        case msgOperatorId:
            parseOperatorId(data, p: p, info: &info)
        default:
            break // auth and unknown types ignored
        }
    }

    private static func parseBasicId(_ data: Data, p: Int, info: inout DroneInfo) {
        info.idType = (Int(data[p]) & 0xF0) >> 4
        info.uaType = Int(data[p]) & 0x0F
        info.uasId = extractString(data, offset: p + 1, maxLen: 20)
    }

    private static func parseLocation(_ data: Data, p: Int, info: inout DroneInfo) {
        let flags = Int(data[p])
        info.status = (flags >> 4) & 0x0F
        let speedMult = flags & 0x03
        let speedMultiplier: Double = speedMult == 0 ? 0.25 : (speedMult == 1 ? 0.75 : 1.0)

        let dirRaw = Int(data[p + 1])
        let ewBit = ((flags >> 2) & 0x01) == 1
        info.heading = Double((dirRaw + (ewBit ? 180 : 0)) % 360)

        let speedRaw = Int(data[p + 2])
        info.speed = Double(speedRaw) * speedMultiplier

        info.vertSpeed = Double(Int8(bitPattern: data[p + 3])) * 0.5

        info.latitude = Double(readInt32LE(data, offset: p + 4)) / 1e7
        info.longitude = Double(readInt32LE(data, offset: p + 8)) / 1e7

        let altGeoRaw = Int(readUInt16LE(data, offset: p + 14))
        info.altGeo = Double(altGeoRaw) * 0.5 - 1000

        info.timestamp = Int(readUInt16LE(data, offset: p + 22))
    }

    private static func parseSelfId(_ data: Data, p: Int, info: inout DroneInfo) {
        info.description = extractString(data, offset: p + 1, maxLen: 23)
    }

    private static func parseSystem(_ data: Data, p: Int, info: inout DroneInfo) {
        info.operatorLat = Double(readInt32LE(data, offset: p + 1)) / 1e7
        info.operatorLon = Double(readInt32LE(data, offset: p + 5)) / 1e7
    }

    private static func parseOperatorId(_ data: Data, p: Int, info: inout DroneInfo) {
        info.operatorRegistrationId = extractString(data, offset: p + 1, maxLen: 20)
    }

    // MARK: - Byte Helpers

    private static func readInt32LE(_ data: Data, offset: Int) -> Int32 {
        guard offset + 4 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: Int32.self)
        }
    }

    private static func readUInt16LE(_ data: Data, offset: Int) -> UInt16 {
        guard offset + 2 <= data.count else { return 0 }
        return data.withUnsafeBytes { ptr in
            ptr.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        }
    }

    private static func extractString(_ data: Data, offset: Int, maxLen: Int) -> String {
        let end = min(offset + maxLen, data.count)
        guard offset < end else { return "" }
        var bytes: [UInt8] = []
        for i in offset..<end {
            let b = data[i]
            if b == 0 { break }
            bytes.append(b)
        }
        return (String(bytes: bytes, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
}
