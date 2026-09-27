# Guida Firmware ESP8266 NodeMCU per Bobina di Tesla (TeslaCoil Wi-Fi)

Questo firmware trasforma un **ESP8266 NodeMCU** (o Wemos D1 Mini / ESP-12) in un interrupter musicale wireless via **Wi-Fi UDP** compatibile con l'app iOS **TeslaMIDI**.

---

## 📌 Collegamenti Hardware (Pinout)

| Pin NodeMCU | GPIO ESP8266 | Funzione | Note |
|---|---|---|---|
| **D1** | **GPIO 5** | **Uscita Interrupter Bobina** | Collegare all'ingresso del gate driver / fibra ottica della bobina |
| **GND** | **GND** | **Massa di Riferimento** | Collegare alla massa del driver della bobina |
| **D4** | **GPIO 2** | LED di Stato Onboard | Si accende automaticamente quando la bobina suona |
| **VIN / 5V** | 5V / USB | Alimentazione | Alimentare tramite presa MicroUSB (5V) |

> [!IMPORTANT]
> **Perché usiamo il Pin D1 (GPIO 5)?**
> A differenza dei pin D3 (GPIO 0) e D4 (GPIO 2) che controllano il boot della scheda, il **Pin D1 (GPIO 5)** è completamente neutro, sicuro e non interferisce mai con l'avvio o la programmazione della NodeMCU.

---

## 🛠️ Come caricare il firmware con Arduino IDE

1. **Installa il supporto per ESP8266** in Arduino IDE (se non già presente):
   - Vai in *File -> Impostazioni* (o *Preferenze*).
   - In "URL aggiuntivi per il Gestore schede" inserisci:
     `https://arduino.esp8266.com/stable/package_esp8266com_index.json`
   - Vai in *Strumenti -> Scheda -> Gestore schede...*, cerca `esp8266` e installa.

2. **Configura le impostazioni scheda in Arduino IDE**:
   - **Scheda**: `NodeMCU 1.0 (ESP-12E Module)` (oppure `Generic ESP8266 Module`)
   - **CPU Frequency**: `160 MHz` *(impostare a 160 MHz per la massima reattività e precisione dei microsecondi)*
   - **Upload Speed**: `115200` o `921600`
   - **Porta**: Seleziona la porta COM della NodeMCU

3. Apri il file `esp8266_firmware.ino` e premi **Carica**.

---

## 📶 Connessione con l'iPhone

1. Accendi la NodeMCU: l'ESP8266 crea la rete Wi-Fi autonoma:
   - **SSID**: `TeslaCoil-NodeMCU`
   - **Password**: `12345678`
2. Sul tuo iPhone, vai in **Impostazioni -> Wi-Fi** e collegati a `TeslaCoil-NodeMCU`.
   *(Se iOS mostra l'avviso "Nessuna connessione a Internet", tocca "Mantieni connessione Wi-Fi")*.
3. Apri l'app **TeslaMIDI**:
   - Tocca il badge di connessione in alto.
   - Seleziona la scheda **📡 Wi-Fi (ESP8266)**.
   - Vedrai la spia verde **"Connesso (192.168.4.1)"** con il tempo di ping in tempo reale!
4. Fai partire qualsiasi canzone MIDI: la NodeMCU riceverà i pacchetti UDP a bassissima latenza e piloterà la bobina sul **Pin D1**!
