import Foundation
import CoreBluetooth
import Combine
import Network

public enum ConnectionMode: String, CaseIterable, Identifiable {
    case bluetooth = "⚡ Bluetooth (ESP32)"
    case wifi = "📡 Wi-Fi UDP (NodeMCU)"
    public var id: String { rawValue }
}

public struct DiscoveredDevice: Identifiable, Equatable {
    public let id: UUID
    public let peripheral: CBPeripheral
    public let name: String
    public let rssi: Int
    public let lastSeen: Date
    
    public static func == (lhs: DiscoveredDevice, rhs: DiscoveredDevice) -> Bool {
        return lhs.peripheral.identifier == rhs.peripheral.identifier
    }
}

public enum BLEConnectionStatus: String {
    case disconnected = "Disconnesso"
    case scanning = "Scansione in corso..."
    case connecting = "Connessione..."
    case connected = "Connesso"
}

public class BluetoothService: NSObject, ObservableObject {
    public static let shared = BluetoothService()
    
    // Standard Apple BLE-MIDI UUIDs (MIDI Manufacturers Association)
    public static let midiServiceUUID       = CBUUID(string: "03B80E5A-EDE8-4B33-A751-6CE34EC4C700")
    public static let legacyMidiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A020-008B000C7348")
    public static let midiCharUUID          = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")
    
    // Modalità di connessione (Bluetooth o Wi-Fi UDP)
    @Published public var connectionMode: ConnectionMode = .wifi {
        didSet {
            UserDefaults.standard.set(connectionMode.rawValue, forKey: "TeslaMIDI_ConnectionMode")
            if connectionMode == .wifi {
                startWifiConnection()
            } else {
                stopWifiConnection()
            }
        }
    }
    
    // Parametri Wi-Fi UDP (ESP8266 NodeMCU)
    @Published public var wifiHost: String = "192.168.4.1" {
        didSet {
            UserDefaults.standard.set(wifiHost, forKey: "TeslaMIDI_WifiHost")
        }
    }
    @Published public var wifiPort: UInt16 = 5004 {
        didSet {
            UserDefaults.standard.set(Int(wifiPort), forKey: "TeslaMIDI_WifiPort")
        }
    }
    @Published public var isWifiConnected: Bool = false
    @Published public var wifiPingMs: Int? = nil
    @Published public var isTest200kActive: Bool = false
    
    public var isConnected: Bool {
        if connectionMode == .wifi {
            return isWifiConnected
        } else {
            return status == .connected
        }
    }
    
    @Published public var status: BLEConnectionStatus = .disconnected
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var connectedDevice: CBPeripheral? = nil
    @Published public var connectedDeviceName: String = "Nessun dispositivo"
    @Published public var currentRSSI: Int? = nil
    @Published public var isBluetoothPoweredOn: Bool = false
    @Published public var bluetoothState: CBManagerState = .unknown
    
    private var centralManager: CBCentralManager!
    private var midiCharacteristic: CBCharacteristic? = nil
    private var rssiTimer: Timer? = nil
    
    private var udpConnection: NWConnection?
    private var udpPingTimer: Timer?
    private var pingStartTime: Date?
    
    override private init() {
        if let savedMode = UserDefaults.standard.string(forKey: "TeslaMIDI_ConnectionMode"),
           let mode = ConnectionMode(rawValue: savedMode) {
            self.connectionMode = mode
        }
        if let savedHost = UserDefaults.standard.string(forKey: "TeslaMIDI_WifiHost"), !savedHost.isEmpty {
            self.wifiHost = savedHost
        }
        let savedPort = UserDefaults.standard.integer(forKey: "TeslaMIDI_WifiPort")
        if savedPort > 0 && savedPort <= 65535 {
            self.wifiPort = UInt16(savedPort)
        }
        
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
        
        if connectionMode == .wifi {
            startWifiConnection()
        }
    }
    
    // MARK: - Scanning & Connection
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        status = .scanning
        
        // Scansione attiva su tutti i dispositivi BLE per non perdere né advertisement né scan response
        centralManager.scanForPeripherals(
            withServices: nil,
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        if status == .scanning {
            status = (connectedDevice != nil) ? .connected : .disconnected
        }
    }
    
    public func connect(to peripheral: CBPeripheral) {
        stopScanning()
        status = .connecting
        connectedDevice = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: [
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true
        ])
    }
    
    public func disconnect() {
        sendAllNotesOff()
        stopRSSITimer()
        if let peripheral = connectedDevice {
            centralManager.cancelPeripheralConnection(peripheral)
        }
        connectedDevice = nil
        midiCharacteristic = nil
        status = .disconnected
        connectedDeviceName = "Nessun dispositivo"
        currentRSSI = nil
    }
    
    // MARK: - MIDI Transmission Methods
    
    public func sendNoteOn(channel: UInt8, pitch: UInt8, velocity: UInt8) {
        guard pitch <= 127 else { return }
        let statusByte: UInt8 = 0x90 | (channel & 0x0F)
        let packet: [UInt8] = [0x80, 0x80, statusByte, pitch, velocity & 0x7F]
        sendMidiPacket(Data(packet))
    }
    
    public func sendNoteOff(channel: UInt8, pitch: UInt8, velocity: UInt8 = 0) {
        guard pitch <= 127 else { return }
        let statusByte: UInt8 = 0x80 | (channel & 0x0F)
        let packet: [UInt8] = [0x80, 0x80, statusByte, pitch, velocity & 0x7F]
        sendMidiPacket(Data(packet))
    }
    
    public func sendControlChange(channel: UInt8, ccNumber: UInt8, value: UInt8) {
        let statusByte: UInt8 = 0xB0 | (channel & 0x0F)
        let packet: [UInt8] = [0x80, 0x80, statusByte, ccNumber & 0x7F, value & 0x7F]
        sendMidiPacket(Data(packet))
    }
    
    public func sendAllNotesOff(channel: UInt8 = 0) {
        if isTest200kActive {
            setTest200kActive(false)
        }
        // Invia CC 120 (All Sound Off) e CC 123 (All Notes Off)
        sendControlChange(channel: channel, ccNumber: 120, value: 0)
        sendControlChange(channel: channel, ccNumber: 123, value: 0)
    }
    
    public func sendOnTimeConfig(ontimeMicroseconds: Int) {
        // Mappa da [10, 180] a [0, 127] su CC 14
        let clamped = max(10, min(180, ontimeMicroseconds))
        let ccVal = UInt8(round(Double(clamped - 10) / 170.0 * 127.0))
        sendControlChange(channel: 0, ccNumber: 14, value: ccVal)
    }
    
    public func sendMaxFrequencyConfig(minPeriodMicroseconds: Int) {
        // Mappa da [800, 2500] a [0, 127] su CC 15
        let clamped = max(800, min(2500, minPeriodMicroseconds))
        let ccVal = UInt8(round(Double(clamped - 800) / 1700.0 * 127.0))
        sendControlChange(channel: 0, ccNumber: 15, value: ccVal)
    }
    
    private func sendMidiPacket(_ data: Data) {
        if connectionMode == .wifi {
            sendUdpPacket(data)
        } else {
            guard let peripheral = connectedDevice,
                  let characteristic = midiCharacteristic else { return }
            
            let writeType: CBCharacteristicWriteType =
                characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
            
            peripheral.writeValue(data, for: characteristic, type: writeType)
        }
    }
    
    // MARK: - Wi-Fi UDP Networking (ESP8266 NodeMCU)
    
    public func startWifiConnection() {
        stopWifiConnection()
        
        let host = NWEndpoint.Host(wifiHost)
        guard let port = NWEndpoint.Port(rawValue: wifiPort) else { return }
        
        let params = NWParameters.udp
        params.allowLocalEndpointReuse = true
        
        let conn = NWConnection(host: host, port: port, using: params)
        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                switch state {
                case .ready:
                    print("[WiFiUDP] Socket UDP pronto verso \(self?.wifiHost ?? ""):\(self?.wifiPort ?? 0)")
                    self?.listenUdpResponses()
                case .failed(let err):
                    print("[WiFiUDP] Errore connessione UDP: \(err)")
                    self?.isWifiConnected = false
                default:
                    break
                }
            }
        }
        
        conn.start(queue: .global(qos: .userInteractive))
        self.udpConnection = conn
        
        startUdpPingTimer()
    }
    
    public func stopWifiConnection() {
        stopUdpPingTimer()
        udpConnection?.cancel()
        udpConnection = nil
        isWifiConnected = false
        wifiPingMs = nil
    }
    
    public func sendUdpPacket(_ data: Data) {
        guard let conn = udpConnection else {
            startWifiConnection()
            return
        }
        conn.send(content: data, completion: .contentProcessed({ error in
            if let error = error {
                print("[WiFiUDP] Errore invio pacchetto: \(error)")
            }
        }))
    }
    
    private func listenUdpResponses() {
        udpConnection?.receiveMessage { [weak self] content, context, isComplete, error in
            guard let self = self else { return }
            if let data = content, data.count >= 2 {
                if data[0] == 0xFF && data[1] == 0x02 {
                    // Pong ricevuto da ESP8266!
                    DispatchQueue.main.async {
                        if let start = self.pingStartTime {
                            let ms = Int(Date().timeIntervalSince(start) * 1000.0)
                            self.wifiPingMs = max(1, ms)
                        }
                        self.isWifiConnected = true
                        if data.count >= 6 {
                            self.isTest200kActive = (data[5] == 1)
                        }
                    }
                }
            }
            if error == nil {
                self.listenUdpResponses()
            }
        }
    }
    
    private func startUdpPingTimer() {
        stopUdpPingTimer()
        sendUdpPing()
        udpPingTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.sendUdpPing()
        }
    }
    
    private func stopUdpPingTimer() {
        udpPingTimer?.invalidate()
        udpPingTimer = nil
    }
    
    public func sendUdpPing() {
        guard connectionMode == .wifi else { return }
        pingStartTime = Date()
        let pingPacket = Data([0xFF, 0x01])
        sendUdpPacket(pingPacket)
    }
    
    public func sendTestNote() {
        sendNoteOn(channel: 0, pitch: 69, velocity: 100) // Note A4 (440 Hz)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.sendNoteOff(channel: 0, pitch: 69)
        }
    }
    
    // MARK: - Segnale Test Hardware 200 kHz (Pin D2 / GPIO 4)
    
    public func setTest200kActive(_ active: Bool) {
        isTest200kActive = active
        if connectionMode == .wifi {
            let cmd: [UInt8] = [0xFF, 0x10, active ? 0x01 : 0x00]
            sendUdpPacket(Data(cmd))
        }
        // Invia anche MIDI CC 16 per interoperabilità
        sendControlChange(channel: 0, ccNumber: 16, value: active ? 127 : 0)
    }
    
    public func toggleTest200k() {
        setTest200kActive(!isTest200kActive)
    }
    
    // MARK: - RSSI Polling
    
    private func startRSSITimer() {
        stopRSSITimer()
        rssiTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.connectedDevice?.readRSSI()
        }
    }
    
    private func stopRSSITimer() {
        rssiTimer?.invalidate()
        rssiTimer = nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BluetoothService: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        bluetoothState = central.state
        isBluetoothPoweredOn = (central.state == .poweredOn)
        if central.state == .poweredOn {
            startScanning()
        } else {
            status = .disconnected
            connectedDevice = nil
            midiCharacteristic = nil
        }
    }
    
    public func centralManager(_ central: CBCentralManager,
                               didDiscover peripheral: CBPeripheral,
                               advertisementData: [String : Any],
                               rssi RSSI: NSNumber) {
        let name = peripheral.name ??
                   (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ??
                   ""
        
        let advertisedUUIDs = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        let isMidiService = advertisedUUIDs.contains(BluetoothService.midiServiceUUID) ||
                            advertisedUUIDs.contains(BluetoothService.legacyMidiServiceUUID)
        let isTeslaName = name.localizedCaseInsensitiveContains("tesla") ||
                          name.localizedCaseInsensitiveContains("esp32") ||
                          name.localizedCaseInsensitiveContains("midi")
        
        // Accetta se espone il servizio MIDI o ha un nome correlato
        guard isMidiService || isTeslaName else {
            return
        }
        
        let displayName = !name.isEmpty ? name : "TeslaCoil-MIDI"
        
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: displayName,
            rssi: RSSI.intValue,
            lastSeen: Date()
        )
        
        if let idx = discoveredDevices.firstIndex(where: { $0.id == device.id }) {
            discoveredDevices[idx] = device
        } else {
            discoveredDevices.append(device)
        }
        
        // Ordinamento per intensità segnale (RSSI decrescente)
        discoveredDevices.sort { $0.rssi > $1.rssi }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        status = .connected
        connectedDevice = peripheral
        connectedDeviceName = peripheral.name ?? "TeslaCoil-MIDI"
        peripheral.discoverServices(nil)
        startRSSITimer()
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        status = .disconnected
        connectedDevice = nil
        midiCharacteristic = nil
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        status = .disconnected
        connectedDevice = nil
        midiCharacteristic = nil
        connectedDeviceName = "Nessun dispositivo"
        currentRSSI = nil
        stopRSSITimer()
    }
}

// MARK: - CBPeripheralDelegate

extension BluetoothService: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == BluetoothService.midiCharUUID ||
               char.properties.contains(.write) ||
               char.properties.contains(.writeWithoutResponse) {
                self.midiCharacteristic = char
                if char.properties.contains(.notify) {
                    peripheral.setNotifyValue(true, for: char)
                }
                print("[BLE] Caratteristica MIDI agganciata e pronta! UUID: \(char.uuid)")
                break
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        DispatchQueue.main.async {
            self.currentRSSI = RSSI.intValue
        }
    }
}
