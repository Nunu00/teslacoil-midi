import SwiftUI

public struct SettingsView: View {
    @ObservedObject var engine = MIDIPlaybackEngine.shared
    @ObservedObject var btService = BluetoothService.shared
    @Environment(\.dismiss) var dismiss
    
    var ontimeColor: Color {
        if engine.ontimeUs < 70 {
            return .green
        } else if engine.ontimeUs <= 120 {
            return .yellow
        } else {
            return .red
        }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        
                        // SEZIONE ON-TIME (Larghezza Impulso)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("ON-TIME IMPULSO INTERRUPTER")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(engine.ontimeUs) µs")
                                    .font(.title3)
                                    .bold()
                                    .foregroundColor(ontimeColor)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(engine.ontimeUs) },
                                set: { engine.ontimeUs = Int($0) }
                            ), in: 10...180, step: 5)
                            .tint(ontimeColor)
                            
                            HStack {
                                Text("10 µs (Minimo)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("50 µs (Sicuro)")
                                    .font(.caption2)
                                    .foregroundColor(.green)
                                Spacer()
                                Text("180 µs (Massimo)")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                            
                            // Spiegazione di Sicurezza
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(ontimeColor)
                                    .font(.subheadline)
                                Text("L'On-Time controlla per quanto tempo i transistor/IGBT della bobina restano accesi ad ogni ciclo. Valori superiori a 120 µs aumentano la scintilla ma rischiano di distruggere il ponte H se la bobina non è adeguatamente raffreddata!")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            .padding(10)
                            .background(ontimeColor.opacity(0.1))
                            .cornerRadius(8)
                        }
                        .padding()
                        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                        .cornerRadius(12)
                        
                        // SEZIONE FREQUENZA MASSIMA
                        VStack(alignment: .leading, spacing: 12) {
                            let maxFreq = 1_000_000 / engine.minPeriodUs
                            HStack {
                                Text("FREQUENZA MASSIMA (PERIODO MINIMO)")
                                    .font(.caption)
                                    .bold()
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("\(maxFreq) Hz (\(engine.minPeriodUs) µs)")
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.cyan)
                            }
                            
                            Slider(value: Binding(
                                get: { Double(engine.minPeriodUs) },
                                set: { engine.minPeriodUs = Int($0) }
                            ), in: 800...2500, step: 50)
                            .tint(.cyan)
                            
                            HStack {
                                Text("1250 Hz (800 µs)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text("1000 Hz (1000 µs)")
                                    .font(.caption2)
                                    .foregroundColor(.cyan)
                                Spacer()
                                Text("400 Hz (2500 µs)")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                            
                            Text("Le note con frequenza superiore a questo limite verranno automaticamente ignorate per evitare il surriscaldamento del circuito risonante.")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        .padding()
                        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                        .cornerRadius(12)
                        
                        // INFO BLUETOOTH E SIDESTORE
                        VStack(alignment: .leading, spacing: 10) {
                            Text("INFORMAZIONI DI SISTEMA")
                                .font(.caption)
                                .bold()
                                .foregroundColor(.gray)
                            
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Protocollo")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("Apple CoreMIDI BLE 2.4 GHz")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                                Divider().background(Color.gray.opacity(0.3))
                                HStack {
                                    Text("Dispositivo Target")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("TeslaCoil-MIDI (ESP32)")
                                        .font(.subheadline)
                                        .foregroundColor(.cyan)
                                }
                                Divider().background(Color.gray.opacity(0.3))
                                HStack {
                                    Text("Metodo Installazione")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                    Text("SideStore / AltStore IPA")
                                        .font(.subheadline)
                                        .foregroundColor(.white)
                                }
                            }
                        }
                        .padding()
                        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                        .cornerRadius(12)
                        
                        // PULSANTE RESET PARAMETRI
                        Button(action: {
                            engine.ontimeUs = 50
                            engine.minPeriodUs = 1000
                            engine.polyphonyMode = .topNote
                        }) {
                            HStack {
                                Image(systemName: "arrow.counterclockwise")
                                Text("Ripristina Valori Sicuri Predefiniti")
                            }
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(10)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Sicurezza & Parametri")
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
    }
}
