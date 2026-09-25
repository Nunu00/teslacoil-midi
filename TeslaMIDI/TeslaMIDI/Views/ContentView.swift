import SwiftUI

public struct ContentView: View {
    @ObservedObject var engine = MIDIPlaybackEngine.shared
    @ObservedObject var btService = BluetoothService.shared
    @ObservedObject var storage = SongStorageService.shared
    @ObservedObject var audioSynth = AudioToneSynthesizer.shared
    
    @State private var isShowingSongList = false
    @State private var isShowingBluetooth = false
    @State private var isShowingTracks = false
    @State private var isShowingSettings = false
    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0.0
    
    // Animazione arco elettrico
    @State private var arcPulse = false
    
    var dutyColor: Color {
        if engine.dutyCyclePercent < 7.0 {
            return .green
        } else if engine.dutyCyclePercent < 12.0 {
            return .yellow
        } else {
            return .red
        }
    }
    
    public var body: some View {
        ZStack {
            // Sfondo Cyberpunk Dark Slate
            Color(red: 0.06, green: 0.07, blue: 0.10).ignoresSafeArea()
            
            VStack(spacing: 12) {
                // 1. TOP BAR: STATO BLUETOOTH & PULSANTI RAPIDI
                topBarView
                    .padding(.horizontal)
                    .padding(.top, 4)
                
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 16) {
                        // 2. VISUALIZZATORE ARCO ELETTRICO & FREQUENZA
                        visualizerCard
                            .padding(.horizontal)
                        
                        // 3. SCHEDA BRANO ATTUALE & SCRUBBER
                        nowPlayingCard
                            .padding(.horizontal)
                        
                        // 4. REGOLAZIONE RAPIDA ON-TIME
                        quickOnTimeCard
                            .padding(.horizontal)
                        
                        // 5. PULSANTE DI ARRESTO EMERGENZA (KILL SWITCH)
                        emergencyStopButton
                            .padding(.horizontal)
                            .padding(.bottom, 8)
                    }
                    .padding(.bottom, 60)
                }
            }
            
            // 6. BOTTOM NAVIGATION BAR
            VStack {
                Spacer()
                bottomNavigationBar
            }
        }
        .sheet(isPresented: $isShowingSongList) {
            SongListView()
        }
        .sheet(isPresented: $isShowingBluetooth) {
            BluetoothModalView()
        }
        .sheet(isPresented: $isShowingTracks) {
            TrackSelectorView()
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .onAppear {
            if engine.currentSong == nil, let first = storage.songs.first {
                engine.load(song: first)
            }
        }
    }
    
    // MARK: - Subviews
    
    private var topBarView: some View {
        HStack {
            // Badge Bluetooth cliccabile
            Button(action: {
                isShowingBluetooth = true
            }) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(btService.status == .connected ? Color.green : Color.orange)
                        .frame(width: 10, height: 10)
                    
                    Image(systemName: "bolt.fill")
                        .foregroundColor(btService.status == .connected ? .cyan : .orange)
                        .font(.caption)
                    
                    Text(btService.status == .connected ? btService.connectedDeviceName : "Connetti Bobina")
                        .font(.caption)
                        .bold()
                        .foregroundColor(.white)
                    
                    if let rssi = btService.currentRSSI {
                        Text("\(rssi) dBm")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                .cornerRadius(20)
            }
            
            Spacer()
            
            // Pulsante Impostazioni
            Button(action: {
                isShowingSettings = true
            }) {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(.white.opacity(0.8))
                    .padding(10)
                    .background(Color(red: 0.12, green: 0.14, blue: 0.20))
                    .clipShape(Circle())
            }
        }
    }
    
    private var visualizerCard: some View {
        VStack(spacing: 12) {
            ZStack {
                // Cerchio plasma pulsante di sfondo
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.2), Color.purple.opacity(0.4), Color.cyan.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 4
                    )
                    .frame(width: 180, height: 180)
                    .scaleEffect(engine.currentPitch != nil ? 1.05 : 1.0)
                    .animation(engine.currentPitch != nil ? Animation.easeInOut(duration: 0.15).repeatForever(autoreverses: true) : .default, value: engine.currentPitch)
                
                Circle()
                    .fill(Color(red: 0.09, green: 0.10, blue: 0.15))
                    .frame(width: 160, height: 160)
                
                VStack(spacing: 4) {
                    Text(engine.currentNoteName)
                        .font(.system(size: 46, weight: .black, design: .monospaced))
                        .foregroundColor(engine.currentPitch != nil ? .cyan : .gray.opacity(0.4))
                        .shadow(color: engine.currentPitch != nil ? .cyan.opacity(0.6) : .clear, radius: 10)
                    
                    if engine.currentPitch != nil {
                        Text(String(format: "%.1f Hz", engine.currentFrequencyHz))
                            .font(.headline)
                            .bold()
                            .foregroundColor(.white)
                        
                        Text(String(format: "T = %.0f µs", engine.currentPeriodUs))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    } else {
                        Text("IN ATTESA")
                            .font(.caption)
                            .bold()
                            .foregroundColor(.gray.opacity(0.6))
                    }
                }
            }
            .padding(.top, 8)
            
            // Indicatori Parametri Spark
            HStack(spacing: 16) {
                VStack(spacing: 2) {
                    Text("ON-TIME")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("\(engine.ontimeUs) µs")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 30)
                    .background(Color.gray.opacity(0.3))
                
                VStack(spacing: 2) {
                    Text("DUTY CYCLE")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(String(format: "%.1f %%", engine.dutyCyclePercent))
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(dutyColor)
                }
                .frame(maxWidth: .infinity)
                
                Divider()
                    .frame(height: 30)
                    .background(Color.gray.opacity(0.3))
                
                VStack(spacing: 2) {
                    Text("POLIFONIA")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text(engine.polyphonyMode == .topNote ? "Top Note" : "Latest")
                        .font(.subheadline)
                        .bold()
                        .foregroundColor(.cyan)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 8)
            .background(Color(red: 0.08, green: 0.09, blue: 0.14))
            .cornerRadius(10)
            
            // Avviso Duty Cycle elevato se necessario
            if engine.dutyCycleWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                    Text("Duty Cycle elevato (>12%)! Riduci On-Time se i dissipatori scaldano.")
                        .font(.caption2)
                        .foregroundColor(.red)
                }
                .padding(6)
                .background(Color.red.opacity(0.12))
                .cornerRadius(6)
            }
        }
        .padding()
        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.cyan.opacity(0.2), lineWidth: 1)
        )
    }
    
    private var nowPlayingCard: some View {
        VStack(spacing: 12) {
            // Titolo Canzone & Selezione
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(engine.currentSong?.title ?? "Nessun brano selezionato")
                        .font(.headline)
                        .foregroundColor(.white)
                        .lineLimit(1)
                    
                    if let song = engine.currentSong {
                        Text("\(song.channels.count) canali • \(song.totalNotes) note")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
                Button(action: {
                    isShowingSongList = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                        Text("Libreria")
                    }
                    .font(.caption)
                    .foregroundColor(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.cyan.opacity(0.15))
                    .cornerRadius(8)
                }
            }
            
            // Toggle Altoparlante iPhone (Anteprima Audio)
            HStack {
                Button(action: {
                    audioSynth.isSpeakerEnabled.toggle()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: audioSynth.isSpeakerEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill")
                            .foregroundColor(audioSynth.isSpeakerEnabled ? .green : .gray)
                        Text(audioSynth.isSpeakerEnabled ? "Audio iPhone: ATTIVO" : "Audio iPhone: MUTO")
                            .font(.caption2)
                            .bold()
                            .foregroundColor(audioSynth.isSpeakerEnabled ? .white : .gray)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(audioSynth.isSpeakerEnabled ? Color.green.opacity(0.18) : Color.gray.opacity(0.15))
                    .cornerRadius(8)
                }
                
                Spacer()
                
                Text(audioSynth.previewMode == .teslaCoil ? "Simulatore Arco" : "Sintetizzatore")
                    .font(.caption2)
                    .foregroundColor(.cyan.opacity(0.8))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.1))
                    .cornerRadius(6)
            }
            
            // Barra Scrubber Timeline
            VStack(spacing: 4) {
                Slider(
                    value: Binding(
                        get: { isScrubbing ? scrubValue : engine.progress },
                        set: { scrubValue = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: { editing in
                        isScrubbing = editing
                        if !editing {
                            engine.seek(to: scrubValue * engine.totalDuration)
                        }
                    }
                )
                .tint(.cyan)
                
                HStack {
                    Text(formatTime(isScrubbing ? (scrubValue * engine.totalDuration) : engine.currentTime))
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Spacer()
                    Text(formatTime(engine.totalDuration))
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
            }
            
            // Controlli Playback Principali
            HStack(spacing: 24) {
                // Loop
                Button(action: {
                    engine.isLooping.toggle()
                }) {
                    Image(systemName: engine.isLooping ? "repeat.1" : "repeat")
                        .font(.title3)
                        .foregroundColor(engine.isLooping ? .cyan : .gray)
                }
                
                // Indietro (seek to 0)
                Button(action: {
                    engine.seek(to: 0.0)
                }) {
                    Image(systemName: "backward.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                // Play / Pause
                Button(action: {
                    if engine.isPlaying {
                        engine.pause()
                    } else {
                        engine.play()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.cyan)
                            .frame(width: 56, height: 56)
                            .shadow(color: .cyan.opacity(0.5), radius: 8)
                        
                        Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title2)
                            .foregroundColor(.black)
                    }
                }
                
                // Stop
                Button(action: {
                    engine.stop()
                }) {
                    Image(systemName: "stop.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                
                // Filtro Canali
                Button(action: {
                    isShowingTracks = true
                }) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title3)
                        .foregroundColor(.cyan)
                }
            }
            .padding(.top, 4)
            
            // Velocità di Riproduzione
            HStack(spacing: 8) {
                Text("Velocità:")
                    .font(.caption2)
                    .foregroundColor(.gray)
                
                ForEach([0.5, 0.75, 1.0, 1.25, 1.5], id: \.self) { spd in
                    Button(action: {
                        engine.playbackSpeed = spd
                    }) {
                        Text(String(format: "%.2gx", spd))
                            .font(.caption2)
                            .bold()
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(engine.playbackSpeed == spd ? Color.cyan : Color.gray.opacity(0.2))
                            .foregroundColor(engine.playbackSpeed == spd ? .black : .white)
                            .cornerRadius(6)
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding()
        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
        .cornerRadius(16)
    }
    
    private var quickOnTimeCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("REGOLAZIONE RAPIDA ON-TIME")
                    .font(.caption2)
                    .bold()
                    .foregroundColor(.gray)
                Spacer()
                Text("\(engine.ontimeUs) µs")
                    .font(.headline)
                    .bold()
                    .foregroundColor(dutyColor)
            }
            
            HStack(spacing: 12) {
                Button(action: {
                    if engine.ontimeUs > 15 {
                        engine.ontimeUs -= 5
                    }
                }) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
                
                Slider(value: Binding(
                    get: { Double(engine.ontimeUs) },
                    set: { engine.ontimeUs = Int($0) }
                ), in: 10...180, step: 5)
                .tint(dutyColor)
                
                Button(action: {
                    if engine.ontimeUs < 175 {
                        engine.ontimeUs += 5
                    }
                }) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundColor(.cyan)
                }
            }
        }
        .padding()
        .background(Color(red: 0.12, green: 0.14, blue: 0.20))
        .cornerRadius(14)
    }
    
    private var emergencyStopButton: some View {
        Button(action: {
            engine.emergencyStop()
        }) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.title2)
                Text("ARRESTO DI EMERGENZA (KILL)")
                    .font(.headline)
                    .bold()
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                LinearGradient(
                    colors: [Color.red, Color(red: 0.8, green: 0.1, blue: 0.1)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(14)
            .shadow(color: Color.red.opacity(0.6), radius: 10, x: 0, y: 4)
        }
    }
    
    private var bottomNavigationBar: some View {
        HStack {
            Button(action: {
                isShowingSongList = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                    Text("Brani")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                isShowingTracks = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "tuningfork")
                    Text("Canali")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                isShowingBluetooth = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                    Text("Bluetooth")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
            
            Button(action: {
                isShowingSettings = true
            }) {
                VStack(spacing: 4) {
                    Image(systemName: "shield.lefthalf.filled")
                    Text("Sicurezza")
                        .font(.caption2)
                }
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
        .background(
            Color(red: 0.09, green: 0.10, blue: 0.15)
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color.gray.opacity(0.2)),
            alignment: .top
        )
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
