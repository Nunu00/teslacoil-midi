import Foundation
import Combine
import QuartzCore

public class MIDIPlaybackEngine: ObservableObject {
    public static let shared = MIDIPlaybackEngine()
    
    // MARK: - Published State
    @Published public var currentSong: MIDISong? = nil
    @Published public var isPlaying: Bool = false
    @Published public var isPaused: Bool = false
    
    @Published public var currentTime: Double = 0.0
    @Published public var totalDuration: Double = 0.0
    @Published public var progress: Double = 0.0
    
    @Published public var currentPitch: UInt8? = nil
    @Published public var currentNoteName: String = "--"
    @Published public var currentFrequencyHz: Double = 0.0
    @Published public var currentPeriodUs: Double = 0.0
    @Published public var dutyCyclePercent: Double = 0.0
    @Published public var dutyCycleWarning: Bool = false
    
    @Published public var playbackSpeed: Double = 1.0
    @Published public var isLooping: Bool = false
    @Published public var polyphonyMode: PolyphonyMode = .topNote
    
    // Impostazioni Bobina (sincronizzate con ESP32)
    @Published public var ontimeUs: Int = 50 {
        didSet {
            BluetoothService.shared.sendOnTimeConfig(ontimeMicroseconds: ontimeUs)
            updateDutyCycle()
        }
    }
    
    @Published public var minPeriodUs: Int = 1000 {
        didSet {
            BluetoothService.shared.sendMaxFrequencyConfig(minPeriodMicroseconds: minPeriodUs)
        }
    }
    
    // Mute canali (true = silenziato, false = attivo)
    @Published public var channelMutes: [UInt8: Bool] = [:]
    
    // MARK: - Private Engine Properties
    private var playbackTimer: DispatchSourceTimer? = nil
    private let timerQueue = DispatchQueue(label: "com.teslamidi.sequencer", qos: .userInteractive)
    
    private var playbackStartWallTime: Double = 0.0
    private var playbackOffsetSeconds: Double = 0.0
    private var currentEventIndex: Int = 0
    private var playbackSessionId: Int = 0
    
    private struct ActiveNoteEntry: Equatable {
        let pitch: UInt8
        let channel: UInt8
        let velocity: UInt8
    }
    private var activeNotes: [ActiveNoteEntry] = []
    private var currentlySoundingPitch: UInt8? = nil
    
    private init() {}
    
    private func updateUIOnMain(_ updates: @escaping () -> Void) {
        if Thread.isMainThread {
            updates()
        } else {
            DispatchQueue.main.async(execute: updates)
        }
    }
    
    // MARK: - Song Loading
    
    public func load(song: MIDISong) {
        stop()
        self.currentSong = song
        self.totalDuration = song.duration
        self.currentTime = 0.0
        self.progress = 0.0
        self.currentEventIndex = 0
        self.playbackOffsetSeconds = 0.0
        
        // Inizializza i canali: attiva tutti di default, tranne il canale 9 (percussioni/batteria MIDI GM ch 10, 0-indexed 9)
        var mutes: [UInt8: Bool] = [:]
        for ch in song.channels {
            mutes[ch] = (ch == 9) // Muto per il canale di batteria di default per evitare rumore sulla bobina
        }
        self.channelMutes = mutes
    }
    
    public func play(song: MIDISong) {
        load(song: song)
        startPlaybackFromBeginning()
    }
    
    // MARK: - Playback Controls
    
    public func play() {
        guard let song = currentSong, !song.events.isEmpty else { return }
        
        if isPaused {
            resume()
            return
        }
        
        startPlaybackFromBeginning()
    }
    
    private func startPlaybackFromBeginning() {
        playbackSessionId += 1
        stopTimer()
        silenceCoilImmediate()
        
        currentEventIndex = 0
        currentTime = 0.0
        progress = 0.0
        playbackOffsetSeconds = 0.0
        playbackStartWallTime = CACurrentMediaTime()
        
        updateUIOnMain {
            self.isPlaying = true
            self.isPaused = false
        }
        
        startTimer()
    }
    
    public func pause() {
        guard isPlaying else { return }
        playbackSessionId += 1
        stopTimer()
        silenceCoilImmediate()
        
        playbackOffsetSeconds = currentTime
        
        updateUIOnMain {
            self.isPlaying = false
            self.isPaused = true
            self.currentPitch = nil
            self.currentNoteName = "PAUSA"
            self.currentFrequencyHz = 0.0
            self.currentPeriodUs = 0.0
            self.dutyCyclePercent = 0.0
            self.dutyCycleWarning = false
        }
    }
    
    public func resume() {
        guard isPaused, currentSong != nil else { return }
        
        playbackSessionId += 1
        silenceCoilImmediate()
        playbackStartWallTime = CACurrentMediaTime()
        
        updateUIOnMain {
            self.isPlaying = true
            self.isPaused = false
        }
        
        startTimer()
    }
    
    public func stop() {
        playbackSessionId += 1
        stopTimer()
        silenceCoilImmediate()
        
        currentTime = 0.0
        progress = 0.0
        currentEventIndex = 0
        playbackOffsetSeconds = 0.0
        
        updateUIOnMain {
            self.isPlaying = false
            self.isPaused = false
            self.resetVisuals()
        }
    }
    
    public func emergencyStop() {
        playbackSessionId += 1
        stopTimer()
        silenceCoilImmediate()
        
        currentTime = 0.0
        progress = 0.0
        currentEventIndex = 0
        playbackOffsetSeconds = 0.0
        
        updateUIOnMain {
            self.isPlaying = false
            self.isPaused = false
            self.resetVisuals()
        }
        
        // Invia comando rapido di stop ripetuto per assicurare la ricezione
        for _ in 0..<3 {
            BluetoothService.shared.sendAllNotesOff()
        }
    }
    
    public func seek(to targetSeconds: Double) {
        let clamped = max(0.0, min(totalDuration, targetSeconds))
        let wasPlaying = isPlaying
        
        playbackSessionId += 1
        silenceCoilImmediate()
        
        guard let song = currentSong else { return }
        
        // Trova il nuovo indice evento corrispondente al tempo richiesto
        var newIndex = 0
        for (i, ev) in song.events.enumerated() {
            if ev.timeSeconds >= clamped {
                newIndex = i
                break
            }
        }
        
        currentEventIndex = newIndex
        playbackOffsetSeconds = clamped
        playbackStartWallTime = CACurrentMediaTime()
        currentTime = clamped
        progress = totalDuration > 0 ? (clamped / totalDuration) : 0
        
        if wasPlaying {
            startTimer()
        }
    }
    
    // MARK: - Timer Loop
    
    private func startTimer() {
        stopTimer()
        let session = self.playbackSessionId
        
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: timerQueue)
        // Timer a 5 millisecondi per massima precisione temporale MIDI
        timer.schedule(deadline: .now(), repeating: .milliseconds(5), leeway: .milliseconds(1))
        
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            guard self.playbackSessionId == session else {
                timer.cancel()
                return
            }
            self.timerTick(session: session)
        }
        
        self.playbackTimer = timer
        timer.resume()
    }
    
    private func stopTimer() {
        playbackTimer?.cancel()
        playbackTimer = nil
    }
    
    private func timerTick(session: Int) {
        guard isPlaying, playbackSessionId == session, let song = currentSong else { return }
        
        let now = CACurrentMediaTime()
        let elapsed = (now - playbackStartWallTime) * playbackSpeed + playbackOffsetSeconds
        
        // Fine della canzone
        if elapsed >= song.duration {
            silenceCoilImmediate()
            if isLooping {
                DispatchQueue.main.async {
                    self.seek(to: 0.0)
                }
            } else {
                DispatchQueue.main.async {
                    self.stop()
                }
            }
            return
        }
        
        // Elabora eventi MIDI fino al tempo corrente
        while currentEventIndex < song.events.count {
            guard playbackSessionId == session else { return }
            let ev = song.events[currentEventIndex]
            if ev.timeSeconds > elapsed {
                break
            }
            
            // Verifica se il canale è mutato
            let isMuted = channelMutes[ev.channel] ?? false
            if !isMuted {
                processMidiEvent(ev, session: session)
            }
            
            currentEventIndex += 1
        }
        
        guard playbackSessionId == session else { return }
        
        // Aggiorna stato UI su Main Thread con throttling
        let progressVal = song.duration > 0 ? (elapsed / song.duration) : 0.0
        DispatchQueue.main.async {
            self.currentTime = elapsed
            self.progress = progressVal
        }
    }
    
    private func processMidiEvent(_ ev: MIDIEvent, session: Int) {
        guard playbackSessionId == session else { return }
        if ev.isNoteOn {
            let entry = ActiveNoteEntry(pitch: ev.data1, channel: ev.channel, velocity: ev.data2)
            // Aggiungi se non già presente
            if !activeNotes.contains(entry) {
                activeNotes.append(entry)
            }
            evaluateActiveNoteOutput(session: session)
        } else if ev.isNoteOff {
            activeNotes.removeAll { $0.pitch == ev.data1 && $0.channel == ev.channel }
            evaluateActiveNoteOutput(session: session)
        }
    }
    
    private func evaluateActiveNoteOutput(session: Int) {
        guard playbackSessionId == session else { return }
        guard !activeNotes.isEmpty else {
            // Nessuna nota attiva: spegni
            if let current = currentlySoundingPitch {
                BluetoothService.shared.sendNoteOff(channel: 0, pitch: current)
                currentlySoundingPitch = nil
                AudioToneSynthesizer.shared.stopTone()
                DispatchQueue.main.async {
                    self.resetVisuals()
                }
            }
            return
        }
        
        let selectedPitch: UInt8
        switch polyphonyMode {
        case .topNote:
            selectedPitch = activeNotes.map { $0.pitch }.max() ?? activeNotes.last!.pitch
        case .bottomNote:
            selectedPitch = activeNotes.map { $0.pitch }.min() ?? activeNotes.last!.pitch
        case .latestNote:
            selectedPitch = activeNotes.last!.pitch
        case .allNotes:
            // Invia l'ultima nota all'ESP32
            selectedPitch = activeNotes.last!.pitch
        }
        
        // Se la nota da suonare è cambiata rispetto alla nota attualmente attiva sulla bobina
        if selectedPitch != currentlySoundingPitch {
            guard playbackSessionId == session else { return }
            if let oldPitch = currentlySoundingPitch {
                BluetoothService.shared.sendNoteOff(channel: 0, pitch: oldPitch)
            }
            BluetoothService.shared.sendNoteOn(channel: 0, pitch: selectedPitch, velocity: 100)
            currentlySoundingPitch = selectedPitch
            
            let noteName = MIDINoteHelper.noteName(for: selectedPitch)
            let freq = MIDINoteHelper.frequency(for: selectedPitch)
            let period = MIDINoteHelper.periodMicroseconds(for: selectedPitch)
            let duty = period > 0 ? (Double(ontimeUs) / period) * 100.0 : 0.0
            
            // Riproduci il tono attraverso l'altoparlante dell'iPhone per l'anteprima
            AudioToneSynthesizer.shared.playTone(frequency: freq)
            
            DispatchQueue.main.async {
                self.currentPitch = selectedPitch
                self.currentNoteName = noteName
                self.currentFrequencyHz = freq
                self.currentPeriodUs = period
                self.dutyCyclePercent = duty
                self.dutyCycleWarning = (duty > 12.0)
            }
        }
    }
    
    public func silenceCoilImmediate() {
        AudioToneSynthesizer.shared.stopTone()
        if let current = currentlySoundingPitch {
            BluetoothService.shared.sendNoteOff(channel: 0, pitch: current)
            currentlySoundingPitch = nil
        }
        activeNotes.removeAll()
        BluetoothService.shared.sendAllNotesOff()
    }
    
    private func resetVisuals() {
        self.currentPitch = nil
        self.currentNoteName = "--"
        self.currentFrequencyHz = 0.0
        self.currentPeriodUs = 0.0
        self.dutyCyclePercent = 0.0
        self.dutyCycleWarning = false
    }
    
    private func updateDutyCycle() {
        if let pitch = currentPitch {
            let period = MIDINoteHelper.periodMicroseconds(for: pitch)
            let duty = period > 0 ? (Double(ontimeUs) / period) * 100.0 : 0.0
            self.dutyCyclePercent = duty
            self.dutyCycleWarning = (duty > 12.0)
        }
    }
}
