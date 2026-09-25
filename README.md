# ⚡ Tesla Coil Bluetooth MIDI Interrupter (ESP32 + iOS SideStore)

Sistema completo per suonare una **Bobina di Tesla (SSTC / DRSSTC)** senza fili tramite **Bluetooth Low Energy (BLE)** controllata direttamente da **iPhone**, leggendo qualsiasi file `.mid` / `.midi` presente nella memoria del telefono o su iCloud.

---

## 🧐 Perché l'Arduino si bloccava e come questa soluzione risolve il problema

Nelle bobine di Tesla, le scintille e la commutazione ad alta frequenza generano intensi campi elettromagnetici (**EMI**) e spike di potenziale sul piano di massa:
1. **Connessione a cavo con Arduino**: un filo di controllo lungo funge da antenna, cattura l'EMI e manda in tilt il microcontrollore, blocca il bus SPI della MicroSD e fa andare in crash l'interrupter.
2. **Connessione wireless BLE con ESP32**:
   - I dati viaggiano via radio a 2.4 GHz con pacchetti protetti da CRC e ritrasmissione hardware.
   - L'operatore e l'iPhone rimangono a **distanza di sicurezza (5-10 metri)** dalla bobina.
   - L'ESP32 è configurato con **potenza di trasmissione radio BLE al massimo (+9 dBm)** per superare l'eventuale rumore RF dell'arco.
   - Non ci sono schede MicroSD esterne soggette a disturbi di bus: i file MIDI risiedono comodamente nell'iPhone.

---

## 📁 Struttura del Progetto

```
teslacoil/
│
├── .github/
│   └── workflows/
│       └── build-ipa.yml             # Workflow GitHub Actions per compilare l'IPA
│
├── esp32_firmware/
│   ├── esp32_firmware.ino            # Firmware ESP32 (PWM LEDC hardware + BLE MIDI)
│   └── README.md                     # Guida dettagliata hardware e schemi
│
├── TeslaMIDI/                        # App iOS nativa in Swift / SwiftUI
│   ├── TeslaMIDI.xcodeproj           # Progetto Xcode configurato
│   └── TeslaMIDI/
│       ├── Info.plist                # Permessi Bluetooth e associazione file MIDI
│       ├── TeslaMIDIApp.swift        # Entrypoint dell'applicazione
│       ├── Models/
│       │   ├── MIDITrackInfo.swift   # Calcolo frequenze/periodi e filtri polifonia
│       │   └── MIDIParser.swift      # Parser ad alte prestazioni Standard MIDI File (0 e 1)
│       ├── Services/
│       │   ├── BluetoothService.swift    # Gestione CoreBluetooth Apple BLE-MIDI
│       │   ├── MIDIPlaybackEngine.swift  # Clock temporale ad alta precisione e scrubber
│       │   └── SongStorageService.swift  # Importazione e persistenza file MIDI locali
│       └── Views/
│           ├── ContentView.swift         # Dashboard con visualizzatore arco e KILL SWITCH
│           ├── SongListView.swift        # Browser brani e picker File iOS
│           ├── TrackSelectorView.swift   # Filtro canali e modalità monofonica
│           ├── BluetoothModalView.swift  # Scanner e accoppiamento BLE
│           └── SettingsView.swift        # Calibrazione On-Time e soglie di sicurezza
│
├── sample_midis/                     # File MIDI dimostrativi di test inclusi
│   ├── Bach_Toccata.mid              # Toccata e Fuga di Bach (il classico per Tesla Coil!)
│   ├── Mario_Theme.mid               # Super Mario Bros Theme
│   └── Fur_Elise.mid                 # Per Elisa di Beethoven
│
├── codice.txt                        # Codice Arduino AVR originale (mantenuto per riferimento)
└── README.md                         # Questa documentazione
```

---

## 🛠️ PARTE 1: Collegamento Hardware & Flash dell'ESP32

### 1. Schema di collegamento
```
        +-----------------------------+
        |         ESP32 Board         |
        |                             |
        |  GPIO 18 (PWM Interrupter)  |-----> [+] Ingresso Optoisolatore (6N137)
        |  GND                        |-----> [-] GND Ingresso Optoisolatore
        |  GPIO 2  (LED di Stato)     |       (o Trasmettitore Fibra Ottica)
        +-----------------------------+
```

> [!IMPORTANT]
> **Isolamento Ottico Raccomandato**: Non collegare mai il pin dell'ESP32 direttamente al circuito primario ad alta tensione della bobina. Utilizza un optoisolatore veloce (es. **6N137** o **HCPL-2601**) o un link a **fibra ottica plastica (TOSLINK o Broadcom Versatile Link)**. Questo garantisce che nessun ritorno di corrente o arco accidentale possa raggiungere l'ESP32.

### 2. Caricamento del Firmware su ESP32
1. Collega l'ESP32 al PC tramite cavo USB.
2. Apri **Arduino IDE**.
3. Assicurati di avere il pacchetto schede ESP32 installato (`Strumenti` -> `Scheda` -> `Gestore Schede` -> `esp32`).
4. Apri il file `esp32_firmware/esp32_firmware.ino`.
5. Seleziona la tua scheda in `Strumenti` -> `Scheda` (es. `ESP32 Dev Module`) e la porta COM.
6. Clicca **Carica**.
7. All'avvio, l'ESP32 inizializzerà il PWM e avvierà il Bluetooth pubblicando il nome **`TeslaCoil-MIDI`**. Il LED onboard (GPIO 2) lampeggerà lentamente in attesa di connessione dall'iPhone.

---

## 📱 PARTE 2: Compilazione dell'App iOS con GitHub Actions

L'app è predisposta per essere compilata gratuitamente su GitHub usando un runner macOS con Xcode:

### 1. Crea il repository su GitHub e carica il codice
Da PowerShell in questa cartella (`c:\Antigravity\teslacoil`):
```powershell
git init
git add .
git commit -m "Initial commit - Tesla Coil BLE MIDI and iOS App"
git branch -M main
git remote add origin https://github.com/TUO_USERNAME/teslacoil-midi.git
git push -u origin main
```

### 2. Scarica il file `.ipa`
1. Vai sulla pagina del tuo repository su GitHub nel browser.
2. Clicca sulla scheda **"Actions"** in alto.
3. Vedrai il workflow **`Build TeslaMIDI IPA for SideStore`** in esecuzione (richiede circa 1 minuto).
4. Al termine (icona verde di successo ✅), clicca sul build completato.
5. Scorri in basso nella sezione **Artifacts** e clicca su **`TeslaMIDI-SideStore`** per scaricare lo zip contenente `TeslaMIDI.ipa`.

---

## 📲 PARTE 3: Installazione su iPhone tramite SideStore

1. Trasferisci il file `TeslaMIDI.ipa` sul tuo iPhone (puoi scaricarlo direttamente da Safari sul tuo iPhone da GitHub, oppure inviartelo tramite AirDrop / iCloud Drive).
2. Apri **SideStore** sul tuo iPhone.
3. Vai nella sezione **"My Apps"** e tocca l'icona **`+`** in alto a sinistra.
4. Seleziona il file `TeslaMIDI.ipa`.
5. SideStore firmerà automaticamente l'applicazione con il tuo Apple ID gratuito e la installerà sulla schermata home del tuo iPhone.

---

## 🎵 PARTE 4: Guida all'Uso dell'App

### 1. Connessione Bluetooth
- Accendi l'ESP32.
- Apri **TeslaMIDI** sull'iPhone.
- Tocca il banner **"Connetti Bobina"** in alto (o la scheda *Bluetooth* in basso).
- Tocca **"Connetti"** accanto a **`TeslaCoil-MIDI`**. Il badge diventerà verde.

### 2. Importazione dei tuoi file MIDI
- Tocca il pulsante **"Libreria"** -> **"Importa File MIDI da iPhone"**.
- L'app apre l'interfaccia File di iOS: puoi selezionare qualsiasi file `.mid` o `.midi` salvato nella memoria dell'iPhone, scaricato da internet o presente su iCloud Drive.
- L'app analizza all'istante le tracce, calcola la durata, il tempo BPM e le note.

### 3. Filtro Polifonia & Canali (Fondamentale per Bobine di Tesla!)
- Una bobina di Tesla genera una sola scintilla alla volta. Se un file MIDI suona 10 note contemporaneamente (accordi, percussioni), il suono risulterebbe caotico e i finali scalderebbero.
- L'app include un **filtro polifonico avanzato**:
  - **Nota Più Alta (Top Note)** *(Consigliato)*: Estrae automaticamente solo la melodia principale.
  - **Filtro Canali**: Tocca *Canali* per silenziare tracce specifiche. Il Canale 10 (batteria/drums) viene silenziato automaticamente di default per evitare disturbi.

### 4. Regolazione Sicura dell'On-Time
- Nella schermata principale puoi regolare l'**On-Time** da 10 a 180 µs:
  - **10 - 60 µs**: Verde (Molto sicuro, ideale per iniziare o per test a freddo).
  - **65 - 110 µs**: Giallo (Arco lungo e suono potente).
  - **115 - 180 µs**: Rosso (Massima potenza, monitorare la temperatura del ponte H!).
- L'app calcola in tempo reale il **Duty Cycle %** e mostra un allarme se supera il 12%.

### 5. Tasto Arresto di Emergenza (Kill Switch)
- In caso di anomalie dell'arco o surriscaldamento, tocca il grande pulsante rosso **`ARRESTO DI EMERGENZA (KILL)`**.
- L'app ferma all'istante il clock e invia ripetutamente comandi CC 120 e CC 123 (All Notes Off), spegnendo immediatamente l'uscita PWM dell'ESP32.
