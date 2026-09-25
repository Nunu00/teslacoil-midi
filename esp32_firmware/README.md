# Guida Hardware & Firmware ESP32 Tesla Coil Interrupter

Questo firmware converte l'ESP32 in un ricevitore MIDI Bluetooth Low Energy (BLE) conforme allo standard Apple CoreMIDI, generando onde quadre con frequenza e larghezza d'impulso (*On-Time*) rigorosamente controllate per pilotare l'interrupter di una bobina di Tesla (SSTC, DRSSTC, VTTC).

---

## ⚡ Perché l'Arduino si bloccava e perché l'ESP32 + BLE risolve il problema

1. **Interferenze Elettromagnetiche (EMI) e RF**:
   Le bobine di Tesla generano campi elettromagnetici intensi e spike di tensione sul piano di massa. Con l'Arduino precedente:
   - I cavi lunghi si comportavano come antenne captando il rumore RF e bloccando la CPU / bus I2C / SPI / SD card.
   - La presenza fisica vicino alla bobina aumentava il rischio di disturbi.

2. **Vantaggio dell'ESP32 via Bluetooth con iPhone**:
   - **Isolamento a distanza**: Puoi stare a 5-10 metri dalla bobina con l'iPhone in mano.
   - **Nessun cavo di controllo audio/dati lungo**: I dati viaggiano via radio BLE a 2.4 GHz protetti da checksum e ritrasmissione automatica del protocollo BLE.
   - **Potenza RF ESP32 massimizzata**: Il firmware imposta `esp_ble_tx_power_set(..., ESP_PWR_LVL_P9)` (+9 dBm) per bucare l'eventuale rumore RF circostante.

---

## 🔌 Schema di Collegamento Hardware

```
                +---------------------+
                |        ESP32        |
                |                     |
                |  GPIO 18 (PWM Out)  |----+
                |  GND                |--+ |
                +---------------------+  | |
                                         | |
                                         v v
                     +-------------------------------+
                     | DISACCOPPIATORE OTTICO        |
                     | (Es. 6N137 / HCPL-2601 / TLP) |
                     |   o Trasmettitore Fibra Ottica|
                     |   (Es. HFBR-1414T / Broadcom) |
                     +-------------------------------+
                                         |
                                         v
                         Interrupter Input Bobina
```

### ⚠️ Regola d'Oro per la Bobina di Tesla: L'Isolamento Ottico!
Si raccomanda vivamente di interporre tra il pin GPIO 18 dell'ESP32 e il gate driver della bobina:
- Un **optoisolatore veloce** (es. **6N137** o **HCPL-2601** con resistenza di pull-up da 1kΩ e condensatore 100nF sull'alimentazione).
- Oppure un **link a fibra ottica plastica (TOSLINK o Broadcom Versatile Link HFBR-1414 / HFBR-2412)**: questo garantisce un isolamento galvanico totale a prova di arco elettrico!

### Pinout Utilizzato
- **GPIO 18**: Uscita segnale PWM / Interrupter (Impulso attivo alto).
- **GPIO 2**: LED di stato (Lampeggia lentamente in attesa di iPhone, acceso fisso quando connesso, lampeggia durante le note).
- **GND**: Massa comune (o ingresso optoisolatore).
- *(Opzionale)* **GPIO 34**: Potenziometro On-Time (se `ENABLE_ANALOG_POTS` è impostato a `true`).
- *(Opzionale)* **GPIO 35**: Potenziometro Periodo Minimo (se `ENABLE_ANALOG_POTS` è impostato a `true`).

---

## 🛡️ Protezioni e Limiti di Sicurezza Integrati nel Firmware

1. **Hard Limit On-Time**:
   L'On-time è rigidamente limitato a `180 µs` (default `50 µs`). È matematicamente impossibile che il software invii impulsi più larghi, proteggendo gli IGBT o MOSFET dal cross-conduction o overcurrent.
2. **Hard Limit Frequenza**:
   Frequenza massima limitata a `1250 Hz` (periodo minimo 800 µs), evitando che note MIDI troppo acute surriscaldino il primario.
3. **Limite Duty Cycle (15%)**:
   Anche se si seleziona una frequenza alta e un on-time elevato, il firmware calcola il rapporto ciclico e lo tronca al 15% massimo.
4. **Note Stack Monofonico**:
   I file MIDI contengono spesso accordi e tracce polifoniche. Il firmware mantiene uno stack delle note attive, suonando sempre la nota più recente o più alta ed evitando che il rilascio di un tasto tagli improvvisamente le altre note.
5. **Watchdog di Sicurezza (8 secondi)**:
   Se una nota rimane attiva ininterrottamente per più di 8 secondi (es. pacchetto NoteOff perso), il firmware toglie automaticamente l'uscita PWM.
6. **Disconnessione Istantanea**:
   Non appena la connessione Bluetooth cade, l'uscita PWM viene forzata immediatamente a `LOW`.

---

## 🚀 Come Caricare il Firmware su ESP32

1. Apri **Arduino IDE** (o VSCode con PlatformIO).
2. Installa il supporto schede **ESP32 by Espressif Systems** (se non già presente):
   - `File` -> `Preferenze` -> `URL aggiuntive per il Gestore schede`:
     `https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json`
   - `Strumenti` -> `Scheda` -> `Gestore Schede` -> cerca `esp32` e clicca `Installa`.
3. Seleziona la tua scheda in `Strumenti` -> `Scheda` (es. `ESP32 Dev Module`).
4. Apri il file `esp32_firmware.ino`.
5. Collega l'ESP32 via cavo USB e seleziona la porta COM corretta.
6. Clicca **Carica**.
7. All'avvio, l'ESP32 avvierà il Bluetooth con il nome **`TeslaCoil-MIDI`**.
