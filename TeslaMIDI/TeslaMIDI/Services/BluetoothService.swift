import Foundation
import CoreBluetooth
import Combine

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
    
    // Standard Apple BLE-MIDI UUIDs
    public static let midiServiceUUID = CBUUID(string: "03B80E5A-EDE8-4B33-A020-008B000C7348")
    public static let midiCharUUID    = CBUUID(string: "7772E5DB-3868-4112-A1A9-F2669D106BF3")
    
    @Published public var status: BLEConnectionStatus = .disconnected
    @Published public var discoveredDevices: [DiscoveredDevice] = []
    @Published public var connectedDevice: CBPeripheral? = nil
    @Published public var connectedDeviceName: String = "Nessun dispositivo"
    @Published public var currentRSSI: Int? = nil
    @Published public var isBluetoothPoweredOn: Bool = false
    
    private var centralManager: CBCentralManager!
    private var midiCharacteristic: CBCharacteristic? = nil
    private var rssiTimer: Timer? = nil
    
    override private init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: DispatchQueue.main)
    }
    
    // MARK: - Scanning & Connection
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else { return }
        discoveredDevices.removeAll()
        status = .scanning
        
        // Cerca sia per UUID di servizio MIDI che periferiche con nome
        centralManager.scanForPeripherals(
            withServices: [BluetoothService.midiServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        
        // Avvia anche scansione generica temporanea se il servizio non è nell'advertisement primario
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self, self.status == .scanning else { return }
            self.centralManager.scanForPeripherals(withServices: nil, options: nil)
        }
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
        guard let peripheral = connectedDevice,
              let characteristic = midiCharacteristic,
              status == .connected else { return }
        
        let writeType: CBCharacteristicWriteType =
            characteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        
        peripheral.writeValue(data, for: characteristic, type: writeType)
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
                   "Dispositivo Sconosciuto"
        
        // Filtra dispositivi inerenti a Tesla, ESP32 o BLE-MIDI
        let isMidiService = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID])?.contains(BluetoothService.midiServiceUUID) ?? false
        let isTeslaName = name.localizedCaseInsensitiveContains("tesla") ||
                          name.localizedCaseInsensitiveContains("esp32") ||
                          name.localizedCaseInsensitiveContains("midi")
        
        guard isMidiService || isTeslaName || advertisementData[CBAdvertisementDataServiceUUIDsKey] != nil else {
            return
        }
        
        let device = DiscoveredDevice(
            id: peripheral.identifier,
            peripheral: peripheral,
            name: name,
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
        peripheral.discoverServices([BluetoothService.midiServiceUUID])
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
            if service.uuid == BluetoothService.midiServiceUUID {
                peripheral.discoverCharacteristics([BluetoothService.midiCharUUID], for: service)
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == BluetoothService.midiCharUUID {
                self.midiCharacteristic = char
                peripheral.setNotifyValue(true, for: char)
                print("[BLE] Caratteristica MIDI trovata e pronta per la trasmissione!")
            }
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didReadRSSI RSSI: NSNumber, error: Error?) {
        DispatchQueue.main.async {
            self.currentRSSI = RSSI.intValue
        }
    }
}
