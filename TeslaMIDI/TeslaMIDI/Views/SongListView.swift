import SwiftUI
import UniformTypeIdentifiers

public struct SongListView: View {
    @ObservedObject var storage = SongStorageService.shared
    @ObservedObject var engine = MIDIPlaybackEngine.shared
    @ObservedObject var audioSynth = AudioToneSynthesizer.shared
    @Environment(\.dismiss) var dismiss
    
    @State private var isShowingFilePicker = false
    @State private var searchText = ""
    @State private var importErrorMessage: String? = nil
    
    var filteredSongs: [MIDISong] {
        if searchText.isEmpty {
            return storage.songs
        }
        return storage.songs.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }
    
    public var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.07, green: 0.08, blue: 0.12).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Pulsante Importa da File iOS
                    Button(action: {
                        isShowingFilePicker = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                            Text("Importa File MIDI da iPhone (File / iCloud)")
                                .font(.headline)
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.cyan)
                        .cornerRadius(12)
                    }
                    .padding()
                    
                    // Banner Anteprima Audio Altoparlante
                    HStack {
                        Image(systemName: audioSynth.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundColor(audioSynth.isSpeakerEnabled ? .green : .gray)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Anteprima Altoparlante iPhone")
                                .font(.subheadline)
                                .bold()
                                .foregroundColor(.white)
                            Text(audioSynth.isSpeakerEnabled ? "Attivo - puoi ascoltare i brani prima della bobina" : "Muto - tocca per abilitare l'audio del telefono")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Toggle("", isOn: $audioSynth.isSpeakerEnabled)
                            .labelsHidden()
                            .tint(.green)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                    
                    if let err = importErrorMessage {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal)
                    }
                    
                    // Lista Brani
                    if storage.isLoading {
                        Spacer()
                        ProgressView("Caricamento brani...")
                            .progressViewStyle(CircularProgressViewStyle(tint: .cyan))
                            .foregroundColor(.gray)
                        Spacer()
                    } else if storage.songs.isEmpty {
                        VStack(spacing: 12) {
                            Spacer()
                            Image(systemName: "music.note.list")
                                .font(.system(size: 48))
                                .foregroundColor(.gray.opacity(0.5))
                            Text("Nessun brano MIDI presente")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Tocca il pulsante sopra per importare file .mid o .midi dalla memoria del tuo iPhone o da iCloud.")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 32)
                            Spacer()
                        }
                    } else {
                        List {
                            ForEach(filteredSongs) { song in
                                let isCurrent = (engine.currentSong?.id == song.id)
                                
                                HStack {
                                    // Tocco sul brano per selezionarlo e chiudere
                                    Button(action: {
                                        engine.load(song: song)
                                        engine.play()
                                        dismiss()
                                    }) {
                                        HStack {
                                            Image(systemName: isCurrent && engine.isPlaying ? "waveform" : "music.note")
                                                .foregroundColor(isCurrent ? .cyan : .gray)
                                                .font(.title3)
                                                .frame(width: 32)
                                            
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(song.title)
                                                    .font(.headline)
                                                    .foregroundColor(isCurrent ? .cyan : .white)
                                                
                                                HStack(spacing: 8) {
                                                    Text(formatTime(song.duration))
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                    Text("•")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                    Text("\(song.totalNotes) note")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                    Text("•")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                    Text("\(song.channels.count) canali")
                                                        .font(.caption)
                                                        .foregroundColor(.gray)
                                                }
                                            }
                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    
                                    // Pulsante Ascolto rapido anteprima direttamente in lista
                                    Button(action: {
                                        if isCurrent && engine.isPlaying {
                                            engine.pause()
                                        } else {
                                            if !isCurrent {
                                                engine.load(song: song)
                                            }
                                            // Assicurati che l'altoparlante sia attivo quando l'utente preme ascolta
                                            audioSynth.isSpeakerEnabled = true
                                            engine.play()
                                        }
                                    }) {
                                        Image(systemName: isCurrent && engine.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .font(.title2)
                                            .foregroundColor(isCurrent && engine.isPlaying ? .cyan : .white.opacity(0.8))
                                            .padding(6)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .padding(.vertical, 6)
                                .listRowBackground(isCurrent ? Color.cyan.opacity(0.12) : Color(red: 0.12, green: 0.14, blue: 0.20))
                            }
                            .onDelete { indexSet in
                                for index in indexSet {
                                    let song = filteredSongs[index]
                                    storage.deleteSong(song)
                                    if engine.currentSong?.id == song.id {
                                        engine.stop()
                                    }
                                }
                            }
                        }
                        .listStyle(InsetGroupedListStyle())
                        .scrollContentBackground(.hidden)
                        .searchable(text: $searchText, prompt: "Cerca brani...")
                    }
                }
            }
            .navigationTitle("Libreria Brani MIDI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Chiudi") {
                        dismiss()
                    }
                    .foregroundColor(.cyan)
                }
            }
            .fileImporter(
                isPresented: $isShowingFilePicker,
                allowedContentTypes: [
                    UTType.midi,
                    UTType(filenameExtension: "mid") ?? .data,
                    UTType(filenameExtension: "midi") ?? .data
                ],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    do {
                        let imported = try storage.importSong(from: url)
                        engine.load(song: imported)
                        importErrorMessage = nil
                    } catch {
                        importErrorMessage = "Impossibile importare: \(error.localizedDescription)"
                    }
                case .failure(let error):
                    importErrorMessage = "Selezione annullata o non valida: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
