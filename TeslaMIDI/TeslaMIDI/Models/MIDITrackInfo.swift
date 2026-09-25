import Foundation

// MARK: - Note Pitch to Name and Frequency Helpers

public struct MIDINoteHelper {
    private static let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    
    public static func noteName(for pitch: UInt8) -> String {
        guard pitch <= 127 else { return "--" }
        let octave = Int(pitch) / 12 - 1
        let noteIndex = Int(pitch) % 12
        return "\(noteNames[noteIndex])\(octave)"
    }
    
    public static func frequency(for pitch: UInt8) -> Double {
        guard pitch <= 127 else { return 0.0 }
        // f = 440 * 2^((pitch - 69) / 12)
        return 440.0 * pow(2.0, Double(Int(pitch) - 69) / 12.0)
    }
    
    public static func periodMicroseconds(for pitch: UInt8) -> Double {
        let freq = frequency(for: pitch)
        guard freq > 0 else { return 0 }
        return 1_000_000.0 / freq
    }
}

// MARK: - MIDI Event Types

public enum MIDIEventType: Equatable {
    case noteOn
    case noteOff
    case controlChange
    case programChange
    case pitchBend
    case meta
}

public struct MIDIEvent: Identifiable, Equatable {
    public let id = UUID()
    public let timeSeconds: Double
    public let tick: UInt64
    public let type: MIDIEventType
    public let channel: UInt8
    public let data1: UInt8  // pitch or cc#
    public let data2: UInt8  // velocity or cc value
    
    public var isNoteOn: Bool {
        return type == .noteOn && data2 > 0
    }
    
    public var isNoteOff: Bool {
        return type == .noteOff || (type == .noteOn && data2 == 0)
    }
}

// MARK: - Polyphony Filter Mode for Tesla Coil

public enum PolyphonyMode: String, CaseIterable, Identifiable {
    case topNote = "Nota Più Alta (Melodia)"
    case latestNote = "Ultima Nota (Classico)"
    case bottomNote = "Nota Più Bassa (Basso)"
    case allNotes = "Tutte (Pass-through)"
    
    public var id: String { rawValue }
    
    public var description: String {
        switch self {
        case .topNote:
            return "Consigliato per bobine di Tesla: seleziona sempre la nota di frequenza più alta, ideale per fare risaltare la melodia principale."
        case .latestNote:
            return "Riproduce l'ultima nota premuta. Ottimo per assoli e brani lineari."
        case .bottomNote:
            return "Focalizza la linea di basso e frequenze più gravi."
        case .allNotes:
            return "Invia tutte le note all'ESP32 lasciando che sia il microcontrollore a filtrarle con il suo note stack."
        }
    }
}

// MARK: - MIDI Song Model

public struct MIDISong: Identifiable, Equatable {
    public let id: UUID
    public var title: String
    public var fileName: String
    public var fileURL: URL
    public var duration: Double
    public var events: [MIDIEvent]
    public var channels: Set<UInt8>
    public var totalNotes: Int
    public var tempoBPM: Double
    
    public init(id: UUID = UUID(), title: String, fileName: String, fileURL: URL, duration: Double, events: [MIDIEvent], channels: Set<UInt8>, totalNotes: Int, tempoBPM: Double = 120.0) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileURL = fileURL
        self.duration = duration
        self.events = events
        self.channels = channels
        self.totalNotes = totalNotes
        self.tempoBPM = tempoBPM
    }
    
    public static func == (lhs: MIDISong, rhs: MIDISong) -> Bool {
        return lhs.id == rhs.id
    }
}
