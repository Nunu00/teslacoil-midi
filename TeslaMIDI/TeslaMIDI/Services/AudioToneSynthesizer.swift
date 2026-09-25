import Foundation
import AVFoundation
import Combine

public enum AudioPreviewMode: String, CaseIterable, Identifiable {
    case teslaCoil = "Simulatore Arco (Onda Quadra)"
    case cleanSynth = "Sintetizzatore Morbido"
    
    public var id: String { rawValue }
}

public class AudioToneSynthesizer: ObservableObject {
    public static let shared = AudioToneSynthesizer()
    
    @Published public var isSpeakerEnabled: Bool = true {
        didSet {
            if !isSpeakerEnabled {
                stopTone()
            }
        }
    }
    
    @Published public var previewMode: AudioPreviewMode = .teslaCoil
    @Published public var volume: Float = 0.7
    
    private var audioEngine: AVAudioEngine?
    private var sourceNode: AVAudioSourceNode?
    
    // Variabili per il render block audio real-time
    private var currentFrequency: Double = 0.0
    private var targetFrequency: Double = 0.0
    private var isToneActive: Bool = false
    private var phase: Double = 0.0
    private var sampleRate: Double = 44100.0
    private var envelope: Float = 0.0
    
    private let audioQueue = DispatchQueue(label: "com.teslamidi.audio_synth", qos: .userInteractive)
    
    private init() {
        setupAudioSession()
        setupAudioEngine()
    }
    
    // MARK: - Setup Audio
    
    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[AudioSynth] Errore configurazione AVAudioSession: \(error)")
        }
    }
    
    private func setupAudioEngine() {
        let engine = AVAudioEngine()
        let mainMixer = engine.mainMixerNode
        sampleRate = mainMixer.outputFormat(forBus: 0).sampleRate
        if sampleRate <= 0 { sampleRate = 44100.0 }
        
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            
            let twoPi = 2.0 * Double.pi
            let mode = self.previewMode
            let userVol = self.volume
            let isEnabled = self.isSpeakerEnabled
            
            for frame in 0..<Int(frameCount) {
                // Inviluppo morbido per evitare clic all'attacco e rilascio
                if self.isToneActive && isEnabled {
                    if self.envelope < 1.0 {
                        self.envelope += 0.003 // ~7ms di attacco
                        if self.envelope > 1.0 { self.envelope = 1.0 }
                    }
                } else {
                    if self.envelope > 0.0 {
                        self.envelope -= 0.003 // ~7ms di rilascio
                        if self.envelope < 0.0 { self.envelope = 0.0 }
                    }
                }
                
                // Interpolazione dolce della frequenza per glissando
                self.currentFrequency += (self.targetFrequency - self.currentFrequency) * 0.05
                
                var sample: Float = 0.0
                if self.envelope > 0.001 && self.currentFrequency > 10.0 {
                    let phaseStep = (self.currentFrequency / self.sampleRate) * twoPi
                    self.phase += phaseStep
                    if self.phase >= twoPi {
                        self.phase -= twoPi
                    }
                    
                    let rawSine = sin(self.phase)
                    
                    switch mode {
                    case .teslaCoil:
                        // Genera un'onda quadra ricca e calda che simula il ronzio tipico dell'arco di una bobina di Tesla
                        // Usiamo una funzione tanh morbida per evitare armoniche oltre Nyquist
                        let squareVal = tanh(rawSine * 6.0)
                        sample = Float(squareVal) * 0.35 * self.envelope * userVol
                        
                    case .cleanSynth:
                        // Tono sinusoidale puro e morbido con una punta di seconda armonica
                        let secondHarmonic = sin(self.phase * 2.0) * 0.25
                        sample = Float(rawSine + secondHarmonic) * 0.4 * self.envelope * userVol
                    }
                }
                
                // Scrive nei buffer audio stereo
                for buffer in ablPointer {
                    let buf = buffer.mData?.assumingMemoryBound(to: Float.self)
                    buf?[frame] = sample
                }
            }
            return noErr
        }
        
        self.sourceNode = node
        engine.attach(node)
        engine.connect(node, to: mainMixer, format: format)
        
        do {
            try engine.start()
            self.audioEngine = engine
            print("[AudioSynth] Motore audio avviato con successo a \(sampleRate) Hz.")
        } catch {
            print("[AudioSynth] Errore avvio AVAudioEngine: \(error)")
        }
    }
    
    // MARK: - Controllo Tono
    
    public func playTone(frequency: Double) {
        guard isSpeakerEnabled, frequency > 0 else { return }
        
        audioQueue.async {
            // Se l'engine era andato in pausa, riavvialo
            if let engine = self.audioEngine, !engine.isRunning {
                try? engine.start()
            }
            self.targetFrequency = frequency
            if !self.isToneActive {
                self.currentFrequency = frequency
            }
            self.isToneActive = true
        }
    }
    
    public func stopTone() {
        audioQueue.async {
            self.isToneActive = false
        }
    }
}
