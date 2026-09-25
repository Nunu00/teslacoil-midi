import Foundation
import Combine

public class SongStorageService: ObservableObject {
    public static let shared = SongStorageService()
    
    @Published public var songs: [MIDISong] = []
    @Published public var isLoading: Bool = false
    @Published public var errorMessage: String? = nil
    
    private var libraryDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let lib = docs.appendingPathComponent("MidiLibrary", isDirectory: true)
        if !FileManager.default.fileExists(atPath: lib.path) {
            try? FileManager.default.createDirectory(at: lib, withIntermediateDirectories: true)
        }
        return lib
    }
    
    private init() {
        reloadLibrary()
    }
    
    public func reloadLibrary() {
        isLoading = true
        errorMessage = nil
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Se la cartella è vuota, crea i brani demo integrati
            self.ensureDefaultSongsExist()
            
            var loadedSongs: [MIDISong] = []
            do {
                let fileURLs = try FileManager.default.contentsOfDirectory(
                    at: self.libraryDirectory,
                    includingPropertiesForKeys: [.contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )
                
                let midiFiles = fileURLs.filter {
                    let ext = $0.pathExtension.lowercased()
                    return ext == "mid" || ext == "midi"
                }
                
                for url in midiFiles {
                    do {
                        let song = try MIDIParser.parse(fileURL: url)
                        loadedSongs.append(song)
                    } catch {
                        print("[SongStorage] Errore nel parsing di \(url.lastPathComponent): \(error)")
                    }
                }
                
                // Ordina per titolo
                loadedSongs.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Errore lettura libreria: \(error.localizedDescription)"
                }
            }
            
            DispatchQueue.main.async {
                self.songs = loadedSongs
                self.isLoading = false
            }
        }
    }
    
    public func importSong(from sourceURL: URL) throws -> MIDISong {
        let isSecured = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if isSecured {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let destinationURL = libraryDirectory.appendingPathComponent(sourceURL.lastPathComponent)
        
        // Se esiste già un file con lo stesso nome, rimuovilo prima
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: destinationURL)
        
        let song = try MIDIParser.parse(data: data, fileURL: destinationURL)
        
        DispatchQueue.main.async {
            self.songs.removeAll { $0.fileName == song.fileName }
            self.songs.append(song)
            self.songs.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }
        
        return song
    }
    
    public func deleteSong(_ song: MIDISong) {
        try? FileManager.default.removeItem(at: song.fileURL)
        songs.removeAll { $0.id == song.id }
    }
    
    // MARK: - Brani Dimostrativi Integrati
    
    private func ensureDefaultSongsExist() {
        let bachDest = libraryDirectory.appendingPathComponent("Bach_Toccata.mid")
        let marioDest = libraryDirectory.appendingPathComponent("Mario_Theme.mid")
        let eliseDest = libraryDirectory.appendingPathComponent("Fur_Elise.mid")
        
        if !FileManager.default.fileExists(atPath: bachDest.path) {
            writeDefaultSong(url: bachDest, notes: bachNotes, bpm: 100)
        }
        if !FileManager.default.fileExists(atPath: marioDest.path) {
            writeDefaultSong(url: marioDest, notes: marioNotes, bpm: 180)
        }
        if !FileManager.default.fileExists(atPath: eliseDest.path) {
            writeDefaultSong(url: eliseDest, notes: eliseNotes, bpm: 130)
        }
    }
    
    private func writeDefaultSong(url: URL, notes: [(pitch: UInt8, dur: UInt32, rest: UInt32)], bpm: Double) {
        let tempoUs = UInt32(60_000_000.0 / bpm)
        var trackData = Data()
        
        // Delta 0, Tempo FF 51 03
        trackData.append(contentsOf: varLenBytes(0))
        trackData.append(contentsOf: [0xFF, 0x51, 0x03, UInt8((tempoUs >> 16) & 0xFF), UInt8((tempoUs >> 8) & 0xFF), UInt8(tempoUs & 0xFF)])
        
        var pendingDelta: UInt32 = 0
        for n in notes {
            // Note On
            trackData.append(contentsOf: varLenBytes(pendingDelta))
            trackData.append(contentsOf: [0x90, n.pitch, 100])
            
            // Note Off
            trackData.append(contentsOf: varLenBytes(n.dur))
            trackData.append(contentsOf: [0x80, n.pitch, 0])
            
            pendingDelta = n.rest
        }
        
        // End of Track
        trackData.append(contentsOf: varLenBytes(pendingDelta))
        trackData.append(contentsOf: [0xFF, 0x2F, 0x00])
        
        // Header MThd
        var fileData = Data()
        fileData.append("MThd".data(using: .ascii)!)
        fileData.append(contentsOf: [0x00, 0x00, 0x00, 0x06]) // length 6
        fileData.append(contentsOf: [0x00, 0x00]) // format 0
        fileData.append(contentsOf: [0x00, 0x01]) // 1 track
        fileData.append(contentsOf: [0x01, 0xE0]) // 480 division
        
        // MTrk
        fileData.append("MTrk".data(using: .ascii)!)
        let trackLen = UInt32(trackData.count)
        fileData.append(contentsOf: [
            UInt8((trackLen >> 24) & 0xFF),
            UInt8((trackLen >> 16) & 0xFF),
            UInt8((trackLen >> 8) & 0xFF),
            UInt8(trackLen & 0xFF)
        ])
        fileData.append(trackData)
        
        try? fileData.write(to: url)
    }
    
    private func varLenBytes(_ value: UInt32) -> [UInt8] {
        var v = value
        var buf: [UInt8] = []
        buf.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            buf.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return buf.reversed()
    }
    
    // Note dimostrative
    private var bachNotes: [(pitch: UInt8, dur: UInt32, rest: UInt32)] {
        return [
            (69, 120, 30), (67, 120, 30), (69, 480, 240),
            (67, 120, 30), (65, 120, 30), (64, 120, 30), (62, 480, 240),
            (61, 480, 120), (62, 960, 480),
            (57, 120, 30), (55, 120, 30), (57, 480, 240),
            (55, 120, 30), (53, 120, 30), (52, 120, 30), (50, 480, 240),
            (49, 480, 120), (50, 960, 480)
        ]
    }
    
    private var marioNotes: [(pitch: UInt8, dur: UInt32, rest: UInt32)] {
        return [
            (76, 120, 60), (76, 120, 180), (76, 120, 180), (72, 120, 60),
            (76, 240, 120), (79, 360, 240), (67, 360, 240),
            (72, 240, 180), (67, 240, 180), (64, 240, 180),
            (69, 180, 60), (71, 180, 60), (70, 180, 60), (69, 240, 120)
        ]
    }
    
    private var eliseNotes: [(pitch: UInt8, dur: UInt32, rest: UInt32)] {
        return [
            (76, 120, 30), (75, 120, 30), (76, 120, 30), (75, 120, 30),
            (76, 120, 30), (71, 120, 30), (74, 120, 30), (72, 120, 30),
            (69, 360, 120), (60, 120, 30), (64, 120, 30), (69, 120, 30),
            (71, 360, 120), (64, 120, 30), (68, 120, 30), (71, 120, 30),
            (72, 360, 120)
        ]
    }
}
