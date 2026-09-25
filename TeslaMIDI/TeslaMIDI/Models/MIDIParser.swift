import Foundation

public enum MIDIParserError: LocalizedError {
    case invalidHeader
    case unsupportedFormat(Int)
    case corruptData(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidHeader:
            return "Il file non è un file MIDI valido (header MThd mancante)."
        case .unsupportedFormat(let format):
            return "Formato MIDI \(format) non supportato (supportati: 0 e 1)."
        case .corruptData(let detail):
            return "Dati MIDI corrotti o incompleti: \(detail)"
        }
    }
}

public class MIDIParser {
    
    private struct TempoChange {
        let tick: UInt64
        let microsecondsPerQuarterNote: UInt32
    }
    
    public static func parse(fileURL: URL) throws -> MIDISong {
        let data = try Data(contentsOf: fileURL)
        return try parse(data: data, fileURL: fileURL)
    }
    
    public static func parse(data: Data, fileURL: URL) throws -> MIDISong {
        var cursor = 0
        let totalBytes = data.count
        
        guard totalBytes >= 14 else {
            throw MIDIParserError.invalidHeader
        }
        
        // 1. Leggi Header MThd
        let headerTag = String(data: data.subdata(in: 0..<4), encoding: .ascii)
        guard headerTag == "MThd" else {
            throw MIDIParserError.invalidHeader
        }
        cursor += 4
        
        let headerLength = readUInt32(data: data, cursor: &cursor)
        guard headerLength >= 6 else {
            throw MIDIParserError.invalidHeader
        }
        
        let format = readUInt16(data: data, cursor: &cursor)
        let trackCount = readUInt16(data: data, cursor: &cursor)
        let divisionRaw = readUInt16(data: data, cursor: &cursor)
        
        // Se l'header è più lungo di 6 byte, salta i byte in eccesso
        if headerLength > 6 {
            cursor += Int(headerLength - 6)
        }
        
        guard format == 0 || format == 1 else {
            throw MIDIParserError.unsupportedFormat(Int(format))
        }
        
        // Division: se bit 15 è 0, sono Ticks per Quarter Note (BPM based)
        let ticksPerQuarterNote: Double
        if (divisionRaw & 0x8000) == 0 {
            ticksPerQuarterNote = Double(divisionRaw & 0x7FFF)
        } else {
            // SMPTE format fallback (default to 480 se non standard)
            ticksPerQuarterNote = 480.0
        }
        
        var rawEvents: [(tick: UInt64, type: MIDIEventType, channel: UInt8, data1: UInt8, data2: UInt8)] = []
        var tempoChanges: [TempoChange] = []
        var extractedTitle: String? = nil
        var detectedChannels = Set<UInt8>()
        
        // 2. Itera sui Track Chunks (MTrk)
        var tracksRead = 0
        while cursor + 8 <= totalBytes && tracksRead < Int(trackCount) {
            guard cursor + 4 <= totalBytes else { break }
            let chunkTag = String(data: data.subdata(in: cursor..<(cursor + 4)), encoding: .ascii)
            cursor += 4
            
            guard cursor + 4 <= totalBytes else { break }
            let chunkLength = Int(readUInt32(data: data, cursor: &cursor))
            let chunkEnd = min(cursor + chunkLength, totalBytes)
            
            if chunkTag == "MTrk" {
                tracksRead += 1
                var currentTick: UInt64 = 0
                var runningStatus: UInt8 = 0
                
                while cursor < chunkEnd {
                    // Leggi Delta Time in Variable-Length
                    let delta = readVarLen(data: data, cursor: &cursor, limit: chunkEnd)
                    currentTick += UInt64(delta)
                    
                    guard cursor < chunkEnd else { break }
                    var status = data[cursor]
                    
                    if status & 0x80 != 0 {
                        // Nuovo Status Byte
                        cursor += 1
                        runningStatus = status
                    } else {
                        // Running Status
                        status = runningStatus
                    }
                    
                    if status == 0xFF {
                        // Meta Event
                        guard cursor < chunkEnd else { break }
                        let metaType = data[cursor]
                        cursor += 1
                        let metaLength = Int(readVarLen(data: data, cursor: &cursor, limit: chunkEnd))
                        let metaDataEnd = min(cursor + metaLength, chunkEnd)
                        
                        if metaType == 0x51 && metaLength == 3 {
                            // Set Tempo: 3 bytes microsecondi per quarto
                            let b1 = UInt32(data[cursor])
                            let b2 = UInt32(data[cursor + 1])
                            let b3 = UInt32(data[cursor + 2])
                            let usPerQuarter = (b1 << 16) | (b2 << 8) | b3
                            tempoChanges.append(TempoChange(tick: currentTick, microsecondsPerQuarterNote: usPerQuarter))
                        } else if metaType == 0x03 && extractedTitle == nil && metaLength > 0 {
                            // Track Name
                            if let name = String(data: data.subdata(in: cursor..<metaDataEnd), encoding: .utf8) ??
                                          String(data: data.subdata(in: cursor..<metaDataEnd), encoding: .ascii) {
                                extractedTitle = name.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        } else if metaType == 0x2F {
                            // End of Track
                            cursor = metaDataEnd
                            break
                        }
                        cursor = metaDataEnd
                    } else if status == 0xF0 || status == 0xF7 {
                        // SysEx Event: salta i dati
                        let sysexLen = Int(readVarLen(data: data, cursor: &cursor, limit: chunkEnd))
                        cursor = min(cursor + sysexLen, chunkEnd)
                    } else {
                        // Messaggio di Canale MIDI
                        let msgType = status & 0xF0
                        let channel = status & 0x0F
                        detectedChannels.insert(channel)
                        
                        switch msgType {
                        case 0x90: // Note On
                            guard cursor + 1 < chunkEnd else { cursor = chunkEnd; break }
                            let pitch = data[cursor]
                            let vel = data[cursor + 1]
                            cursor += 2
                            let evtType: MIDIEventType = (vel == 0) ? .noteOff : .noteOn
                            rawEvents.append((tick: currentTick, type: evtType, channel: channel, data1: pitch, data2: vel))
                            
                        case 0x80: // Note Off
                            guard cursor + 1 < chunkEnd else { cursor = chunkEnd; break }
                            let pitch = data[cursor]
                            let vel = data[cursor + 1]
                            cursor += 2
                            rawEvents.append((tick: currentTick, type: .noteOff, channel: channel, data1: pitch, data2: vel))
                            
                        case 0xB0: // Control Change
                            guard cursor + 1 < chunkEnd else { cursor = chunkEnd; break }
                            let ccNum = data[cursor]
                            let ccVal = data[cursor + 1]
                            cursor += 2
                            rawEvents.append((tick: currentTick, type: .controlChange, channel: channel, data1: ccNum, data2: ccVal))
                            
                        case 0xC0: // Program Change (1 data byte)
                            guard cursor < chunkEnd else { cursor = chunkEnd; break }
                            let prg = data[cursor]
                            cursor += 1
                            rawEvents.append((tick: currentTick, type: .programChange, channel: channel, data1: prg, data2: 0))
                            
                        case 0xD0: // Channel Pressure (1 data byte)
                            guard cursor < chunkEnd else { cursor = chunkEnd; break }
                            let press = data[cursor]
                            cursor += 1
                            rawEvents.append((tick: currentTick, type: .meta, channel: channel, data1: press, data2: 0))
                            
                        case 0xE0: // Pitch Bend (2 data bytes)
                            guard cursor + 1 < chunkEnd else { cursor = chunkEnd; break }
                            let lsb = data[cursor]
                            let msb = data[cursor + 1]
                            cursor += 2
                            rawEvents.append((tick: currentTick, type: .pitchBend, channel: channel, data1: lsb, data2: msb))
                            
                        default:
                            cursor += 1
                        }
                    }
                }
            } else {
                // Salta chunk sconosciuti
                cursor = chunkEnd
            }
        }
        
        // 3. Calcola il timing assoluto in secondi per ogni evento
        // Ordina i cambi di tempo per tick
        tempoChanges.sort { $0.tick < $1.tick }
        if tempoChanges.isEmpty || tempoChanges.first?.tick != 0 {
            // Default 120 BPM = 500,000 microsecondi per quarto
            tempoChanges.insert(TempoChange(tick: 0, microsecondsPerQuarterNote: 500_000), at: 0)
        }
        
        // Funzione di conversione Tick -> Secondi
        func convertTickToSeconds(_ targetTick: UInt64) -> Double {
            var totalSeconds = 0.0
            var previousTick: UInt64 = 0
            var currentTempoUs: UInt32 = 500_000
            
            for tc in tempoChanges {
                if targetTick <= tc.tick {
                    break
                }
                let deltaTicks = tc.tick - previousTick
                let deltaQuarter = Double(deltaTicks) / ticksPerQuarterNote
                totalSeconds += deltaQuarter * (Double(currentTempoUs) / 1_000_000.0)
                previousTick = tc.tick
                currentTempoUs = tc.microsecondsPerQuarterNote
            }
            
            let remainingTicks = targetTick - previousTick
            let remainingQuarter = Double(remainingTicks) / ticksPerQuarterNote
            totalSeconds += remainingQuarter * (Double(currentTempoUs) / 1_000_000.0)
            
            return totalSeconds
        }
        
        // Converti tutti gli eventi
        var convertedEvents: [MIDIEvent] = []
        convertedEvents.reserveCapacity(rawEvents.count)
        
        var totalNotes = 0
        for ev in rawEvents {
            let seconds = convertTickToSeconds(ev.tick)
            let midiEvent = MIDIEvent(timeSeconds: seconds, tick: ev.tick, type: ev.type, channel: ev.channel, data1: ev.data1, data2: ev.data2)
            convertedEvents.append(midiEvent)
            if midiEvent.isNoteOn {
                totalNotes += 1
            }
        }
        
        // Ordina per timestamp in secondi
        convertedEvents.sort {
            if $0.timeSeconds != $1.timeSeconds {
                return $0.timeSeconds < $1.timeSeconds
            }
            // In caso di parità, NoteOff prima di NoteOn per evitare sovrapposizioni
            if $0.isNoteOff && !$1.isNoteOff {
                return true
            }
            return false
        }
        
        let duration = convertedEvents.last?.timeSeconds ?? 0.0
        let baseFileName = fileURL.deletingPathExtension().lastPathComponent
        
        let friendlyTitles: [String: String] = [
            "ACDC": "AC/DC - Thunderstruck",
            "Avast": "Avast Theme",
            "Axel": "Axel F (Beverly Hills Cop)",
            "Bamba": "La Bamba",
            "CoB": "Children of Bodom",
            "CoffinD": "Coffin Dance (Astronomia)",
            "EpicS": "Epic Sax Guy",
            "Ezio": "Assassin's Creed (Ezio's Family)",
            "furE": "Für Elise (Beethoven)",
            "Fur_Elise": "Für Elise (Beethoven)",
            "GhostB": "Ghostbusters Theme",
            "HarryP": "Harry Potter (Hedwig's Theme)",
            "Insomnia": "Faithless - Insomnia",
            "Inter": "Interstellar Theme",
            "LPolkka": "Ievan Polkka",
            "pig_T": "Pigstep (Minecraft)",
            "PoC": "Pirates of the Caribbean",
            "RoL": "Rick Roll (Never Gonna Give You Up)",
            "RoL_B": "Rick Roll (Bass Track)",
            "RoL_P": "Rick Roll (Piano Track)",
            "rushE": "Rush E",
            "SMB": "Super Mario Bros Theme",
            "Mario_Theme": "Super Mario Bros Theme",
            "SSS": "Sonic Theme",
            "Tarant": "Tarantella Napoletana",
            "Tetris": "Tetris (Korobeiniki)",
            "tlou": "The Last of Us Theme",
            "Bach_Toccata": "Bach - Toccata e Fuga in Re Minore"
        ]
        
        let finalTitle: String
        if let friendly = friendlyTitles[baseFileName] {
            finalTitle = friendly
        } else if let ext = extractedTitle, !ext.isEmpty, !isGenericTrackName(ext) {
            finalTitle = ext
        } else {
            finalTitle = baseFileName
        }
        
        let initialTempoBPM = 60_000_000.0 / Double(tempoChanges.first?.microsecondsPerQuarterNote ?? 500_000)
        
        return MIDISong(
            title: finalTitle,
            fileName: fileURL.lastPathComponent,
            fileURL: fileURL,
            duration: duration,
            events: convertedEvents,
            channels: detectedChannels,
            totalNotes: totalNotes,
            tempoBPM: initialTempoBPM
        )
    }
    
    private static func isGenericTrackName(_ name: String) -> Bool {
        let lower = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let genericWords = ["piano", "melody", "track", "unbenannt", "midi out", "acoustic", "electric"]
        if lower.count <= 2 { return true }
        for g in genericWords {
            if lower.contains(g) && lower.count <= 15 { return true }
        }
        return false
    }
    
    // MARK: - Binary Helpers
    
    private static func readUInt32(data: Data, cursor: inout Int) -> UInt32 {
        guard cursor + 4 <= data.count else { return 0 }
        let val = UInt32(data[cursor]) << 24 |
                  UInt32(data[cursor + 1]) << 16 |
                  UInt32(data[cursor + 2]) << 8 |
                  UInt32(data[cursor + 3])
        cursor += 4
        return val
    }
    
    private static func readUInt16(data: Data, cursor: inout Int) -> UInt16 {
        guard cursor + 2 <= data.count else { return 0 }
        let val = UInt16(data[cursor]) << 8 | UInt16(data[cursor + 1])
        cursor += 2
        return val
    }
    
    private static func readVarLen(data: Data, cursor: inout Int, limit: Int) -> UInt32 {
        var value: UInt32 = 0
        var shift = 0
        while cursor < limit && shift <= 28 {
            let byte = data[cursor]
            cursor += 1
            value = (value << 7) | UInt32(byte & 0x7F)
            if (byte & 0x80) == 0 {
                break
            }
            shift += 7
        }
        return value
    }
}
