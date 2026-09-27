import SwiftUI
import CoreBluetooth

public struct BluetoothModalView: View {
    @ObservedObject var btService = BluetoothService.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var portString: String = "5004"
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Segmented Control: Selezione Modalità Connessione
                    Picker("Tipo Connessione", selection: $btService.connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    if btService.connectionMode == .wifi {
                        wifiView
                    } else {
                        bluetoothView
                    }
                }
            }
            .navigationTitle("Connessione Bobina")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
        .onAppear {
            portString = String(btService.wifiPort)
            if btService.connectionMode == .bluetooth {
                if btService.status != .connected && btService.status != .scanning {
                    btService.startScanning()
                }
            } else {
                btService.sendUdpPing()
            }
        }
    }
    
    // MARK: - Wi-Fi View (ESP8266 NodeMCU)
    
    private var wifiView: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Scheda Stato Wi-Fi
                VStack(spacing: 12) {
                    HStack {
                        Circle()
                            .fill(btService.isWifiConnected ? Color.green : Color.orange)
                            .frame(width: 14, height: 14)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(btService.isWifiConnected ? "Connesso all'ESP8266" : "In attesa di risposta...")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text(btService.isWifiConnected ? "Pronto per la riproduzione su Pin D1 (GPIO 5)" : "Verifica di essere connesso al Wi-Fi 'TeslaCoil-NodeMCU'")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        
                        Spacer()
                        
                        if let ping = btService.wifiPingMs {
                            HStack(spacing: 4) {
                                Image(systemName: "bolt.fill")
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                                Text("\(ping) ms")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.cyan)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                    
                    Divider().background(Color.gray.opacity(0.3))
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TARGET IP & PORTA")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            Text("\(btService.wifiHost):\(btService.wifiPort)")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.white)
                        }
                        Spacer()
                        Button(action: {
                            btService.sendUdpPing()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.clockwise")
                                Text("Invia Ping")
                            }
                            .font(.caption)
                            .foregroundColor(.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.cyan.opacity(0.15))
                            .cornerRadius(8)
                        }
                    }
                }
                .padding()
                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(btService.isWifiConnected ? Color.green.opacity(0.3) : Color.orange.opacity(0.3), lineWidth: 1)
                )
                .padding(.horizontal)
                
                // Guida Rapida di Connessione
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.cyan)
                        Text("GUIDA CONNESSIONE NODEMCU")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.cyan)
                    }
                    
                    Text("1. Accendi la scheda ESP8266 NodeMCU collegata all'alimentazione.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    Text("2. Apri **Impostazioni iPhone -> Wi-Fi** e connettiti alla rete:")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                    HStack {
                        Text("SSID: **TeslaCoil-NodeMCU**")
                            .font(.caption)
                            .foregroundColor(.yellow)
                        Spacer()
                        Text("PW: **12345678**")
                            .font(.caption)
                            .foregroundColor(.yellow)
                    }
                    .padding(8)
                    .background(Color.black.opacity(0.3))
                    .cornerRadius(6)
                    Text("3. Se iOS chiede 'Nessuna connessione Internet', tocca **Mantieni Wi-Fi**.")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text("4. Collega il gate driver della bobina al **Pin D1 (GPIO 5)** e GND.")
                        .font(.caption)
                        .foregroundColor(.cyan)
                }
                .padding()
                .background(Color(red: 0.10, green: 0.12, blue: 0.18))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Configurazione Parametri IP (se si vuole cambiare IP o porta)
                VStack(alignment: .leading, spacing: 10) {
                    Text("IMPOSTAZIONI SOCKET UDP")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Indirizzo IP")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            TextField("192.168.4.1", text: $btService.wifiHost)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color(red: 0.16, green: 0.18, blue: 0.24))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Porta UDP")
                                .font(.caption2)
                                .foregroundColor(.gray)
                            TextField("5004", text: $portString)
                                .textFieldStyle(PlainTextFieldStyle())
                                .padding(8)
                                .background(Color(red: 0.16, green: 0.18, blue: 0.24))
                                .cornerRadius(8)
                                .foregroundColor(.white)
                                .font(.system(.body, design: .monospaced))
                                .keyboardType(.numberPad)
                                .onChange(of: portString) { newVal in
                                    if let p = UInt16(newVal) {
                                        btService.wifiPort = p
                                    }
                                }
                        }
                    }
                    
                    Button(action: {
                        btService.startWifiConnection()
                    }) {
                        HStack {
                            Image(systemName: "network")
                            Text("Riconnetti Socket UDP")
                        }
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.cyan.opacity(0.8))
                        .cornerRadius(8)
                    }
                }
                .padding()
                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                .cornerRadius(12)
                .padding(.horizontal)
                
                // Pulsanti di Test Rapido
                VStack(spacing: 10) {
                    Button(action: {
                        btService.sendTestNote()
                    }) {
                        HStack {
                            Image(systemName: "speaker.wave.3.fill")
                            Text("Invia Tono di Test (440 Hz / La4 - 300ms)")
                        }
                        .font(.headline)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .cornerRadius(12)
                    }
                    
                    Button(action: {
                        btService.sendAllNotesOff()
                    }) {
                        HStack {
                            Image(systemName: "hand.raised.fill")
                            Text("Spegni Bobina (All Notes Off)")
                        }
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.8))
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 20)
            }
        }
    }
    
    // MARK: - Bluetooth View (ESP32)
    
    private var bluetoothView: some View {
        VStack(spacing: 16) {
            // Avvisi di stato Bluetooth di sistema
            if btService.bluetoothState == .unauthorized {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text("Permesso Bluetooth Mancante")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Text("Apri Impostazioni iPhone > TeslaMIDI e attiva l'interruttore Bluetooth.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding()
                .background(Color.red.opacity(0.25))
                .cornerRadius(12)
                .padding(.horizontal)
            } else if btService.bluetoothState == .poweredOff {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "bolt.slash.fill")
                            .foregroundColor(.orange)
                        Text("Bluetooth iPhone Spento")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    Text("Attiva il Bluetooth dell'iPhone dal Centro di Controllo per connettere l'ESP32.")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.9))
                }
                .padding()
                .background(Color.orange.opacity(0.25))
                .cornerRadius(12)
                .padding(.horizontal)
            }
            
            // Stato Connessione Corrente BLE
            VStack(spacing: 8) {
                HStack {
                    Circle()
                        .fill(btService.status == .connected ? Color.green : (btService.status == .scanning ? Color.orange : Color.red))
                        .frame(width: 12, height: 12)
                    Text(btService.status.rawValue)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    
                    if btService.status == .scanning {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                    }
                }
                .padding()
                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                .cornerRadius(12)
                
                if btService.status == .connected {
                    HStack {
                        Image(systemName: "bolt.horizontal.fill")
                            .foregroundColor(.cyan)
                        Text(btService.connectedDeviceName)
                            .foregroundColor(.white)
                            .bold()
                        Spacer()
                        if let rssi = btService.currentRSSI {
                            Text("\(rssi) dBm")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Button(action: {
                            btService.disconnect()
                        }) {
                            Text("Disconnetti")
                                .font(.subheadline)
                                .foregroundColor(.red)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.15))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                    .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                    .cornerRadius(12)
                }
            }
            .padding(.horizontal)
            
            // Lista Dispositivi BLE
            VStack(alignment: .leading, spacing: 8) {
                Text("DISPOSITIVI BLE NELLE VICINANZE")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal)
                
                if btService.discoveredDevices.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 40))
                            .foregroundColor(.gray.opacity(0.5))
                        Text(btService.status == .scanning ? "Ricerca dell'ESP32 in corso..." : "Nessun dispositivo BLE rilevato.")
                            .font(.subheadline)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(btService.discoveredDevices) { device in
                            Button(action: {
                                btService.connect(to: device.peripheral)
                            }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(device.name)
                                            .font(.body)
                                            .foregroundColor(.white)
                                        Text("RSSI: \(device.rssi) dBm")
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                    Spacer()
                                    
                                    if btService.connectedDevice?.identifier == device.id {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    } else {
                                        Text("Connetti")
                                            .font(.subheadline)
                                            .foregroundColor(.cyan)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(Color.cyan.opacity(0.15))
                                            .cornerRadius(8)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowBackground(Color(red: 0.12, green: 0.14, blue: 0.20))
                        }
                    }
                    .listStyle(InsetGroupedListStyle())
                    .scrollContentBackground(.hidden)
                }
            }
            
            // Pulsante Scansione BLE
            HStack(spacing: 16) {
                Button(action: {
                    if btService.status == .scanning {
                        btService.stopScanning()
                    } else {
                        btService.startScanning()
                    }
                }) {
                    HStack {
                        Image(systemName: btService.status == .scanning ? "stop.fill" : "arrow.clockwise")
                        Text(btService.status == .scanning ? "Ferma Scansione" : "Aggiorna Scansione BLE")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.cyan.opacity(0.8))
                    .cornerRadius(12)
                }
            }
            .padding()
        }
    }
}
