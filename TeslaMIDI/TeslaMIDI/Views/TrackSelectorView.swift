import SwiftUI

public struct TrackSelectorView: View {
    @ObservedObject var engine = MIDIPlaybackEngine.shared
    @Environment(\.dismiss) var dismiss
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Modalità Polifonica per Bobina
                        VStack(alignment: .leading, spacing: 10) {
                            Text("FILTRO POLIFONIA BOBINA DI TESLA")
                                .font(.caption)
                                .foregroundColor(.gray)
                                .padding(.horizontal)
                            
                            VStack(spacing: 0) {
                                ForEach(PolyphonyMode.allCases) { mode in
                                    Button(action: {
                                        engine.polyphonyMode = mode
                                    }) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(mode.rawValue)
                                                    .font(.body)
                                                    .foregroundColor(.white)
                                                Text(mode.description)
                                                    .font(.caption2)
                                                    .foregroundColor(.gray)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                            Spacer()
                                            if engine.polyphonyMode == mode {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.cyan)
                                                    .font(.title3)
                                            }
                                        }
                                        .padding()
                                    }
                                    if mode != PolyphonyMode.allCases.last {
                                        Divider().background(Color.gray.opacity(0.3))
                                    }
                                }
                            }
                            .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        
                        // Canali MIDI Rilevati
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("CANALI MIDI NEL BRANO")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                                Spacer()
                                Button(action: {
                                    // Mute all except channel 0
                                    for ch in engine.channelMutes.keys {
                                        engine.channelMutes[ch] = (ch != 0)
                                    }
                                }) {
                                    Text("Solo Canale 1")
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                }
                                Text("•")
                                    .foregroundColor(.gray)
                                Button(action: {
                                    // Attiva tutti tranne batteria
                                    for ch in engine.channelMutes.keys {
                                        engine.channelMutes[ch] = (ch == 9)
                                    }
                                }) {
                                    Text("Reset Predefinito")
                                        .font(.caption)
                                        .foregroundColor(.cyan)
                                }
                            }
                            .padding(.horizontal)
                            
                            if let song = engine.currentSong, !song.channels.isEmpty {
                                VStack(spacing: 0) {
                                    let sortedChannels = Array(song.channels).sorted()
                                    ForEach(sortedChannels, id: \.self) { ch in
                                        let isMuted = engine.channelMutes[ch] ?? false
                                        let isDrum = (ch == 9) // Canale 10 MIDI standard
                                        
                                        HStack {
                                            VStack(alignment: .leading, spacing: 2) {
                                                HStack(spacing: 6) {
                                                    Text("Canale \(ch + 1)")
                                                        .font(.body)
                                                        .foregroundColor(.white)
                                                    if isDrum {
                                                        Text("BATTERIA / DRUMS")
                                                            .font(.caption2)
                                                            .bold()
                                                            .padding(.horizontal, 6)
                                                            .padding(.vertical, 2)
                                                            .background(Color.orange.opacity(0.2))
                                                            .foregroundColor(.orange)
                                                            .cornerRadius(4)
                                                    }
                                                }
                                                Text(isDrum ? "Consigliato muto: percussioni generano rumore termico" : (isMuted ? "Silenziato" : "Attivo in riproduzione"))
                                                    .font(.caption2)
                                                    .foregroundColor(isMuted ? .gray : .cyan)
                                            }
                                            Spacer()
                                            
                                            Toggle("", isOn: Binding(
                                                get: { !(engine.channelMutes[ch] ?? false) },
                                                set: { engine.channelMutes[ch] = !$0 }
                                            ))
                                            .labelsHidden()
                                            .tint(.cyan)
                                        }
                                        .padding()
                                        
                                        if ch != sortedChannels.last {
                                            Divider().background(Color.gray.opacity(0.3))
                                        }
                                    }
                                }
                                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            } else {
                                HStack {
                                    Spacer()
                                    Text("Nessun brano caricato o nessun canale rilevato.")
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    Spacer()
                                }
                                .padding()
                                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                                .cornerRadius(12)
                                .padding(.horizontal)
                            }
                        }
                    }
                    .padding(.vertical)
                }
            }
            .navigationTitle("Canali & Polifonia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fatto") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
        }
    }
}
