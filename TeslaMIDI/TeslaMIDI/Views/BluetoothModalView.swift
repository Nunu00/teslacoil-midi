import SwiftUI
import CoreBluetooth

public struct BluetoothModalView: View {
    @ObservedObject var btService = BluetoothService.shared
    @Environment(\.dismiss) var dismiss
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()
                
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
                            Text("L'app non può rilevare l'ESP32 perché il permesso Bluetooth non è stato autorizzato. Apri Impostazioni iPhone > TeslaMIDI e attiva l'interruttore Bluetooth.")
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
                            Text("Attiva il Bluetooth dell'iPhone dal Centro di Controllo o dalle Impostazioni per connettere la bobina di Tesla.")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding()
                        .background(Color.orange.opacity(0.25))
                        .cornerRadius(12)
                        .padding(.horizontal)
                    }
                    
                    // Stato Connessione Corrente
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
                    
                    // Lista Dispositivi Rilevati
                    VStack(alignment: .leading, spacing: 8) {
                        Text("DISPOSITIVI NELLE VICINANZE")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.horizontal)
                        
                        if btService.discoveredDevices.isEmpty {
                            VStack(spacing: 12) {
                                Spacer()
                                Image(systemName: "antenna.radiowaves.left.and.right")
                                    .font(.system(size: 40))
                                    .foregroundColor(.gray.opacity(0.5))
                                Text(btService.status == .scanning ? "Ricerca della bobina di Tesla in corso..." : "Nessun dispositivo rilevato.")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                Text("💡 Nota iOS: i dispositivi BLE-MIDI come TeslaCoil non compaiono in Impostazioni > Bluetooth dell'iPhone, ma vengono scansionati e connessi direttamente qui nell'app.")
                                    .font(.caption)
                                    .foregroundColor(.cyan.opacity(0.9))
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 24)
                                    .padding(.top, 4)
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
                    
                    // Pulsante Scansione
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
                                Text(btService.status == .scanning ? "Ferma Scansione" : "Aggiorna Scansione")
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
            .navigationTitle("Bluetooth Tesla Coil")
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
            if btService.status != .connected && btService.status != .scanning {
                btService.startScanning()
            }
        }
    }
}
