import Capacitor
import CoreBluetooth
import Foundation

/// Capacitor plugin that scans for ASTM F3411 Broadcast Remote ID signals via BLE.
@objc(BroadcastRemoteIdPlugin)
class BroadcastRemoteIdPlugin: CAPPlugin, CAPBridgedPlugin, CBCentralManagerDelegate {

    let identifier = "BroadcastRemoteIdPlugin"
    let jsName = "BroadcastRemoteId"
    let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "startScan", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stopScan", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isScanning", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "checkPermissions", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "requestPermissions", returnType: CAPPluginReturnPromise),
    ]

    /// OpenDroneID BLE service UUID (0xFFFA).
    private static let odidServiceUUID = CBUUID(string: "FFFA")

    private var centralManager: CBCentralManager?
    private var scanning = false
    private var pendingStartCall: CAPPluginCall?

    private let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // MARK: - Plugin Methods

    @objc func startScan(_ call: CAPPluginCall) {
        if scanning {
            call.resolve(["scanning": true])
            return
        }

        pendingStartCall = call

        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        } else if centralManager?.state == .poweredOn {
            beginScanning()
            call.resolve(["scanning": true])
            pendingStartCall = nil
        } else {
            call.reject("Bluetooth is not powered on")
            pendingStartCall = nil
        }
    }

    @objc func stopScan(_ call: CAPPluginCall) {
        stopScanning()
        call.resolve(["scanning": false])
    }

    @objc func isScanning(_ call: CAPPluginCall) {
        call.resolve(["scanning": scanning])
    }

    @objc func checkPermissions(_ call: CAPPluginCall) {
        let btStatus: String
        if #available(iOS 13.1, *) {
            switch CBCentralManager.authorization {
            case .allowedAlways: btStatus = "granted"
            case .denied: btStatus = "denied"
            case .restricted: btStatus = "denied"
            case .notDetermined: btStatus = "prompt"
            @unknown default: btStatus = "prompt"
            }
        } else {
            btStatus = "granted"
        }
        call.resolve(["bluetooth": btStatus, "location": "granted"])
    }

    @objc func requestPermissions(_ call: CAPPluginCall) {
        // On iOS, Bluetooth permission is requested when CBCentralManager is initialised.
        // Creating the manager triggers the system prompt if not yet granted.
        if centralManager == nil {
            centralManager = CBCentralManager(delegate: self, queue: nil)
        }
        // Return current state after a short delay to let the prompt appear
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkPermissions(call)
        }
    }

    // MARK: - CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            if let call = pendingStartCall {
                beginScanning()
                call.resolve(["scanning": true])
                pendingStartCall = nil
            }
        case .poweredOff:
            scanning = false
            if let call = pendingStartCall {
                call.reject("Bluetooth is powered off")
                pendingStartCall = nil
            }
        case .unauthorized:
            scanning = false
            if let call = pendingStartCall {
                call.reject("Bluetooth permission denied")
                pendingStartCall = nil
            }
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        // Extract service data for OpenDroneID UUID (0xFFFA)
        guard let serviceDataDict = advertisementData[CBAdvertisementDataServiceDataKey] as? [CBUUID: Data],
              let serviceData = serviceDataDict[Self.odidServiceUUID],
              serviceData.count >= 2 else {
            return
        }

        let info = OpenDroneIdParser.parseServiceData(serviceData)
        let deviceId = peripheral.identifier.uuidString
        let rssi = RSSI.intValue

        var obj: [String: Any] = [
            "deviceId": deviceId,
            "rssi": rssi,
            "timestamp": isoFormatter.string(from: Date()),
        ]

        if !info.uasId.isEmpty { obj["uasId"] = info.uasId }
        if info.idType != 0 { obj["idType"] = info.idType }
        if info.uaType != 0 { obj["uaType"] = info.uaType }
        if info.latitude != 0 { obj["latitude"] = info.latitude }
        if info.longitude != 0 { obj["longitude"] = info.longitude }
        if info.altGeo > -1000 { obj["altGeo"] = info.altGeo }
        if info.speed > 0 { obj["speed"] = info.speed }
        obj["heading"] = info.heading
        obj["vertSpeed"] = info.vertSpeed
        obj["status"] = info.status
        if info.operatorLat != 0 { obj["operatorLat"] = info.operatorLat }
        if info.operatorLon != 0 { obj["operatorLon"] = info.operatorLon }
        if !info.operatorRegistrationId.isEmpty {
            obj["operatorRegistrationId"] = info.operatorRegistrationId
        }
        if !info.description.isEmpty { obj["description"] = info.description }

        notifyListeners("droneDetected", data: obj)
    }

    // MARK: - Private

    private func beginScanning() {
        centralManager?.scanForPeripherals(
            withServices: [Self.odidServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
        scanning = true
        CAPLog.print("BRID: BLE scan started for OpenDroneID")
    }

    private func stopScanning() {
        centralManager?.stopScan()
        scanning = false
        CAPLog.print("BRID: BLE scan stopped")
    }

    deinit {
        stopScanning()
    }
}
