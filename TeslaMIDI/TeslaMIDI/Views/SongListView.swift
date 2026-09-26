import SwiftUI
import UIKit
import UniformTypeIdentifiers

public struct SongListView: View {
    @ObservedObject var storage = SongStorageService.shared
    @ObservedObject var engine = MIDIPlaybackEngine.shared
    @ObservedObject var audioSynth = AudioToneSynthesizer.shared
    @Environment(\.dismiss) var dismiss
    
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
                        importErrorMessage = nil
                        DocumentPickerManager.shared.presentPicker { urls in
                            guard let url = urls.first else { return }
                            do {
                                let song = try storage.importSong(from: url)
                                engine.play(song: song)
                                dismiss()
                            } catch {
                                print("[SongListView] Errore importazione: \(error)")
                                importErrorMessage = "Errore: \(error.localizedDescription)"
                            }
                        }
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
                                        engine.play(song: song)
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
                                            audioSynth.isSpeakerEnabled = true
                                            if isCurrent {
                                                engine.play()
                                            } else {
                                                engine.play(song: song)
                                            }
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
            .alert(isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            )) {
                Alert(
                    title: Text("Importazione File MIDI"),
                    message: Text(importErrorMessage ?? "Errore sconosciuto."),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Native Document Picker Manager
public class DocumentPickerManager: NSObject, UIDocumentPickerDelegate {
    public static let shared = DocumentPickerManager()
    
    private var onPickHandler: (([URL]) -> Void)?
    private var onCancelHandler: (() -> Void)?
    
    private override init() {
        super.init()
    }
    
    public func presentPicker(
        onPick: @escaping ([URL]) -> Void,
        onCancel: (() -> Void)? = nil
    ) {
        self.onPickHandler = onPick
        self.onCancelHandler = onCancel
        
        var types: [UTType] = []
        if let mid = UTType(filenameExtension: "mid") { types.append(mid) }
        if let midi = UTType(filenameExtension: "midi") { types.append(midi) }
        if let pubMidi = UTType("public.midi") { types.append(pubMidi) }
        if let pubMidiAudio = UTType("public.midi-audio") { types.append(pubMidiAudio) }
        types.append(.audio)
        types.append(.data)
        types.append(.item)
        
        // Remove duplicates preserving order
        let uniqueTypes = Array(NSOrderedSet(array: types)) as! [UTType]
        
        // asCopy: true ensures iOS downloads iCloud files and places a local copy in sandbox tmp/
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: uniqueTypes, asCopy: true)
        picker.delegate = self
        picker.allowsMultipleSelection = false // Single tap selects and immediately returns
        picker.modalPresentationStyle = .formSheet
        
        guard let topVC = getTopViewController() else {
            print("[DocumentPicker] Top view controller not found")
            return
        }
        
        topVC.present(picker, animated: true)
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onPickHandler?(urls)
            self?.cleanup()
        }
    }
    
    public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentAt url: URL) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onPickHandler?([url])
            self?.cleanup()
        }
    }
    
    public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        controller.dismiss(animated: true) { [weak self] in
            self?.onCancelHandler?()
            self?.cleanup()
        }
    }
    
    private func cleanup() {
        onPickHandler = nil
        onCancelHandler = nil
    }
    
    private func getTopViewController(base: UIViewController? = nil) -> UIViewController? {
        let baseVC: UIViewController? = base ?? {
            let keyWindow = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
            return keyWindow?.rootViewController
        }()
        
        if let nav = baseVC as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
        }
        if let tab = baseVC as? UITabBarController {
            if let selected = tab.selectedViewController {
                return getTopViewController(base: selected)
            }
        }
        if let presented = baseVC?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return baseVC
    }
}
