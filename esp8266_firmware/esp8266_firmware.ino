/*
 ==============================================================================
  Tesla Coil Wi-Fi UDP & Web MIDI Interrupter for ESP8266 NodeMCU
  ------------------------------------------------------------------------------
  Riceve segnali MIDI via Wi-Fi UDP (o interfaccia Web integrata) da iPhone
  e genera impulsi quadri con On-Time e frequenza controllati tramite Timer1 hardware
  per pilotare l'ingresso interrupter di una bobina di Tesla (SSTC / DRSSTC).

  Caratteristiche:
  - Generazione rete Wi-Fi autonoma (Access Point: "TeslaCoil-NodeMCU")
  - Ricezione pacchetti MIDI via UDP (porta 5004 standard) con bassissima latenza
  - Interfaccia Web di controllo & Kill Switch raggiungibile su http://192.168.4.1
  - Generazione impulsi tramite Timer1 hardware a 160 MHz (zero jitter)
  - Pin di uscita: D1 (GPIO 5) - sicuro all'avvio, nessun conflitto di boot
  - Protezioni di sicurezza hardware:
      * On-Time rigidamente limitato (default 50 µs, max 180 µs)
      * Duty Cycle massimo di sicurezza (max 15%)
      * Watchdog di silenziamento automatico (500 ms) in caso di interruzione Wi-Fi
      * Monitor seriale con log in tempo reale delle note, frequenza e duty cycle
 ==============================================================================
*/

#include <Arduino.h>
#include <ESP8266WiFi.h>
#include <WiFiUdp.h>
#include <ESP8266WebServer.h>

extern "C" {
  #include "user_interface.h"
}

// ==============================================================================
// CONFIGURAZIONE PIN HARDWARE (NodeMCU ESP-12E / ESP-12F)
// ==============================================================================
// Su NodeMCU:
// D1 = GPIO 5 (Miglior pin per PWM/interrupter: nessun conflitto al boot!)
// D4 = GPIO 2 (LED blu onboard della scheda ESP-12, attivo LOW)
#define PIN_PWM_OUTPUT          5   // D1 (GPIO 5) -> Uscita segnale interrupter per bobina
#define PIN_STATUS_LED          2   // D4 (GPIO 2) -> LED blu onboard

// ==============================================================================
// CONFIGURAZIONE RETE WI-FI & UDP
// ==============================================================================
#define WIFI_AP_SSID            "TeslaCoil-NodeMCU"
#define WIFI_AP_PASS            "12345678"         // Minimo 8 caratteri WPA2
#define UDP_MIDI_PORT           5004               // Porta standard RTP-MIDI / UDP
#define WEB_SERVER_PORT         80

IPAddress apIP(192, 168, 4, 1);
IPAddress netMsk(255, 255, 255, 0);

WiFiUDP udp;
ESP8266WebServer webServer(WEB_SERVER_PORT);

// ==============================================================================
// LIMITI DI SICUREZZA BOBINA DI TESLA (DRSSTC / SSTC)
// ==============================================================================
#define ONTIME_ABSOLUTE_MAX_US  180   // Limite assoluto non superabile di On-Time (µs)
#define ONTIME_DEFAULT_US        50   // Valore iniziale di On-Time (µs)
#define ONTIME_MIN_US            10   // Minimo On-Time consentito (µs)

#define PERIOD_MIN_ABSOLUTE_US  800   // Minimo periodo = 800 µs (frequenza max 1250 Hz)
#define PERIOD_MIN_DEFAULT_US  1000   // Periodo minimo di default (1000 µs = 1000 Hz max)
#define PERIOD_MIN_MAX_US      2500   // Limite frequenza minima

#define MAX_DUTY_CYCLE_PERCENT 0.15f  // Duty cycle massimo consentito (15%)
#define SAFETY_WATCHDOG_MS      500   // Se non riceve dati per 500ms, spegne la bobina

// ==============================================================================
// TABELLA PERIODI NOTE MIDI (in microsecondi)
// Note da 0 a 127
// ==============================================================================
const unsigned int midiperiod[128] = {
    122312, 115447, 108968, 102852,  97079,  91631,  86488,  81634,  77052,  72727,
     68645,  64793,  61156,  57724,  54484,  51426,  48540,  45815,  43244,  40817,
     38526,  36364,  34323,  32396,  30578,  28862,  27242,  25713,  24270,  22908,
     21622,  20408,  19263,  18182,  17161,  16198,  15289,  14431,  13621,  12856,
     12135,  11454,  10811,  10204,   9631,   9091,   8581,   8099,   7645,   7215,
      6810,   6428,   6067,   5727,   5405,   5102,   4816,   4545,   4290,   4050,
      3822,   3608,   3405,   3214,   3034,   2863,   2703,   2551,   2408,   2273,
      2145,   2025,   1911,   1804,   1703,   1607,   1517,   1432,   1351,   1276,
      1204,   1136,   1073,   1012,    956,    902,    851,    804,    758,    716,
       676,    638,    602,    568,    536,    506,    478,    451,    426,    402,
       379,    358,    338,    319,    301,    284,    268,    253,    239,    225,
       213,    201,    190,    179,    169,    159,    150,    142,    134,    127,
       119,    113,    106,    100,     95,     89,     84,     80
};

const char* const NOTE_NAMES[12] = {
    "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"
};

// ==============================================================================
// VARIABILI GLOBALI
// ==============================================================================
volatile int current_ontime_us = ONTIME_DEFAULT_US;
volatile int current_period_min_us = PERIOD_MIN_DEFAULT_US;

volatile int8_t current_playing_pitch = -1;
volatile unsigned long last_packet_time = 0;
volatile bool timer_is_active = false;

// Note Stack per gestire polifonia in monofonia pulita
#define MAX_ACTIVE_NOTES 16
struct ActiveNote {
    uint8_t pitch;
    uint8_t velocity;
    uint8_t channel;
};
ActiveNote active_notes[MAX_ACTIVE_NOTES];
uint8_t active_note_count = 0;

// ==============================================================================
// GESTIONE TIMER1 HARDWARE (Interrupt ad altissima precisione)
// ==============================================================================

// Routine di interrupt hardware del Timer1 (eseguita nella IRAM a 160MHz)
void IRAM_ATTR onTimer1ISR() {
    if (current_playing_pitch >= 0 && current_ontime_us > 0) {
        // Genera impulso con On-Time preciso sul pin D1
        #ifdef GPOS
        GPOS = (1 << PIN_PWM_OUTPUT);
        delayMicroseconds(current_ontime_us);
        GPOC = (1 << PIN_PWM_OUTPUT);
        #else
        digitalWrite(PIN_PWM_OUTPUT, HIGH);
        delayMicroseconds(current_ontime_us);
        digitalWrite(PIN_PWM_OUTPUT, LOW);
        #endif
    }
}

void initTimer1Hardware() {
    pinMode(PIN_PWM_OUTPUT, OUTPUT);
    digitalWrite(PIN_PWM_OUTPUT, LOW);
    
    pinMode(PIN_STATUS_LED, OUTPUT);
    digitalWrite(PIN_STATUS_LED, HIGH); // LED spento (attivo LOW)
    
    timer1_isr_init();
    timer1_attachInterrupt(onTimer1ISR);
}

void silenceCoilImmediate() {
    timer1_disable();
    timer_is_active = false;
    current_playing_pitch = -1;
    
    #ifdef GPOC
    GPOC = (1 << PIN_PWM_OUTPUT);
    #else
    digitalWrite(PIN_PWM_OUTPUT, LOW);
    #endif
    
    digitalWrite(PIN_STATUS_LED, HIGH); // LED spento
}

void playToneHardware(unsigned int period_us, int ontime_us) {
    if (period_us < (unsigned int)current_period_min_us) {
        period_us = current_period_min_us;
    }
    
    // Hard Interlock di sicurezza sul Duty Cycle (max 15%)
    int effective_ontime = ontime_us;
    int max_allowed_ontime = (int)(period_us * MAX_DUTY_CYCLE_PERCENT);
    if (effective_ontime > max_allowed_ontime) {
        effective_ontime = max_allowed_ontime;
    }
    if (effective_ontime > ONTIME_ABSOLUTE_MAX_US) {
        effective_ontime = ONTIME_ABSOLUTE_MAX_US;
    }
    if (effective_ontime < ONTIME_MIN_US) {
        effective_ontime = ONTIME_MIN_US;
    }
    
    current_ontime_us = effective_ontime;
    
    // A TIM_DIV16 su clock 80MHz, ogni tick è 0.2 µs (5 tick per microsecondo)
    // Registro Timer1 a 23 bit: ticks = period_us * 5
    uint32_t ticks = (uint32_t)period_us * 5;
    
    timer1_write(ticks);
    if (!timer_is_active) {
        timer1_enable(TIM_DIV16, TIM_EDGE, TIM_LOOP);
        timer_is_active = true;
    }
    
    digitalWrite(PIN_STATUS_LED, LOW); // LED acceso (attivo LOW)
}

// ==============================================================================
// GESTIONE NOTE STACK
// ==============================================================================

void pushNote(uint8_t pitch, uint8_t velocity, uint8_t channel) {
    for (uint8_t i = 0; i < active_note_count; i++) {
        if (active_notes[i].pitch == pitch && active_notes[i].channel == channel) {
            active_notes[i].velocity = velocity;
            return;
        }
    }
    if (active_note_count < MAX_ACTIVE_NOTES) {
        active_notes[active_note_count].pitch = pitch;
        active_notes[active_note_count].velocity = velocity;
        active_notes[active_note_count].channel = channel;
        active_note_count++;
    }
}

void popNote(uint8_t pitch, uint8_t channel) {
    int found_index = -1;
    for (uint8_t i = 0; i < active_note_count; i++) {
        if (active_notes[i].pitch == pitch && active_notes[i].channel == channel) {
            found_index = i;
            break;
        }
    }
    if (found_index >= 0) {
        for (uint8_t i = found_index; i < active_note_count - 1; i++) {
            active_notes[i] = active_notes[i + 1];
        }
        active_note_count--;
    }
}

void clearAllNotes() {
    active_note_count = 0;
    silenceCoilImmediate();
    Serial.println(F("[SAFETY] Tutte le note azzerate. Bobina silenziata."));
}

void updateCoilOutput() {
    if (active_note_count == 0) {
        silenceCoilImmediate();
        return;
    }
    
    // Modalità Top-Note: suona la nota più alta presente nello stack
    uint8_t highest_pitch = 0;
    for (uint8_t i = 0; i < active_note_count; i++) {
        if (active_notes[i].pitch > highest_pitch) {
            highest_pitch = active_notes[i].pitch;
        }
    }
    
    if (highest_pitch != current_playing_pitch) {
        current_playing_pitch = highest_pitch;
        unsigned int period_us = midiperiod[highest_pitch];
        
        playToneHardware(period_us, current_ontime_us);
        
        // Log monitor seriale
        float freq = 1000000.0f / (float)period_us;
        float duty = ((float)current_ontime_us / (float)period_us) * 100.0f;
        int noteIndex = highest_pitch % 12;
        int octave = (highest_pitch / 12) - 1;
        
        Serial.printf("[NOTE] %s%d (MIDI %d) | %.1f Hz | On-Time: %d us | Duty: %.1f%%\n",
                      NOTE_NAMES[noteIndex], octave, highest_pitch, freq, current_ontime_us, duty);
    }
}

// ==============================================================================
// GESTIONE MESSAGGI MIDI
// ==============================================================================

void handleMidiMessage(uint8_t status, uint8_t data1, uint8_t data2) {
    uint8_t msgType = status & 0xF0;
    uint8_t channel = status & 0x0F;
    
    if (msgType == 0x90) { // Note On
        uint8_t pitch = data1;
        uint8_t velocity = data2;
        if (pitch > 127) return;
        
        if (velocity == 0) {
            popNote(pitch, channel);
            updateCoilOutput();
        } else {
            pushNote(pitch, velocity, channel);
            updateCoilOutput();
        }
    } else if (msgType == 0x80) { // Note Off
        uint8_t pitch = data1;
        if (pitch > 127) return;
        popNote(pitch, channel);
        updateCoilOutput();
    } else if (msgType == 0xB0) { // Control Change
        uint8_t ccNumber = data1;
        uint8_t ccValue = data2;
        
        if (ccNumber == 14) { // Config On-Time dinamico da App (10..180 us)
            int new_ontime = (int)map(ccValue, 0, 127, ONTIME_MIN_US, ONTIME_ABSOLUTE_MAX_US);
            current_ontime_us = new_ontime;
            Serial.printf("[CONFIG] On-Time aggiornato da App: %d us\n", current_ontime_us);
            if (current_playing_pitch >= 0) {
                playToneHardware(midiperiod[current_playing_pitch], current_ontime_us);
            }
        } else if (ccNumber == 15) { // Config Periodo Minimo (800..2500 us)
            current_period_min_us = (int)map(ccValue, 0, 127, PERIOD_MIN_ABSOLUTE_US, PERIOD_MIN_MAX_US);
            Serial.printf("[CONFIG] Periodo Minimo aggiornato: %d us\n", current_period_min_us);
        } else if (ccNumber == 120 || ccNumber == 123) { // All Sound Off / All Notes Off
            clearAllNotes();
        }
    }
}

// ==============================================================================
// GESTIONE SERVER WEB & PAGINA EMERGENZA (PORTA 80)
// ==============================================================================

const char INDEX_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>TeslaCoil ESP8266 Interrupter</title>
<style>
  body { background: #0f111a; color: #fff; font-family: -apple-system, BlinkMacSystemFont, sans-serif; text-align: center; padding: 20px; }
  h1 { color: #00e5ff; margin-bottom: 5px; }
  .card { background: #1a1e2e; border: 1px solid #00e5ff33; border-radius: 14px; padding: 20px; max-width: 400px; margin: 20px auto; }
  .btn-kill { background: #ff2a2a; color: #fff; font-weight: bold; font-size: 20px; padding: 16px; border: none; border-radius: 12px; width: 100%; cursor: pointer; box-shadow: 0 4px 15px #ff2a2a66; }
  .btn-kill:hover { background: #cc1111; }
  .badge { display: inline-block; padding: 6px 12px; background: #00e5ff22; color: #00e5ff; border-radius: 20px; font-size: 13px; font-weight: bold; margin-bottom: 15px; }
  .info { font-size: 14px; color: #8892b0; margin-top: 15px; line-height: 1.6; }
</style>
</head>
<body>
  <h1>⚡ TeslaCoil NodeMCU</h1>
  <div class="badge">Wi-Fi AP: TeslaCoil-NodeMCU</div>
  
  <div class="card">
    <button class="btn-kill" onclick="fetch('/kill')">🛑 ARRESTO EMERGENZA</button>
    <div class="info">
      Uscita segnale: <b>Pin D1 (GPIO 5)</b><br>
      Porta UDP MIDI: <b>5004</b><br>
      IP Bobina: <b>192.168.4.1</b><br>
      Stato Watchdog: <b>500 ms ATTIVO</b>
    </div>
  </div>
</body>
</html>
)rawliteral";

void handleRoot() {
    webServer.send(200, "text/html", INDEX_HTML);
}

void handleKill() {
    clearAllNotes();
    webServer.send(200, "text/plain", "COIL SILENCED - ALL NOTES OFF");
}

// ==============================================================================
// SETUP & LOOP
// ==============================================================================

void setup() {
    // 1. Aumenta frequenza CPU a 160 MHz per massima precisione microsecondi
    system_update_cpu_freq(160);
    
    Serial.begin(115200);
    delay(200);
    
    Serial.println();
    Serial.println(F("=================================================="));
    Serial.println(F("⚡ Tesla Coil Wi-Fi UDP Interrupter (ESP8266 NodeMCU)"));
    Serial.println(F("=================================================="));
    
    // 2. Inizializza Timer1 hardware & pin di uscita
    initTimer1Hardware();
    Serial.println(F("[HW] Timer1 inizializzato a 160 MHz su Pin D1 (GPIO 5)"));
    
    // 3. Configura Wi-Fi in modalità Access Point
    WiFi.mode(WIFI_AP);
    WiFi.softAPConfig(apIP, apIP, netMsk);
    WiFi.softAP(WIFI_AP_SSID, WIFI_AP_PASS, 1, 0, 4); // Max 4 client connessi
    
    Serial.print(F("[WIFI] Access Point avviato! SSID: "));
    Serial.println(WIFI_AP_SSID);
    Serial.print(F("[WIFI] Password: "));
    Serial.println(WIFI_AP_PASS);
    Serial.print(F("[WIFI] Indirizzo IP: "));
    Serial.println(WiFi.softAPIP());
    
    // 4. Avvia listener UDP sulla porta 5004
    udp.begin(UDP_MIDI_PORT);
    Serial.printf("[UDP] Server MIDI UDP in ascolto su porta %d\n", UDP_MIDI_PORT);
    
    // 5. Avvia Web Server sulla porta 80
    webServer.on("/", handleRoot);
    webServer.on("/kill", handleKill);
    webServer.begin();
    Serial.println(F("[HTTP] Web Server di emergenza avviato su http://192.168.4.1"));
    
    Serial.println(F("[READY] Pronto a ricevere comandi MIDI dall'app iPhone TeslaMIDI!"));
    Serial.println(F("=================================================="));
    
    last_packet_time = millis();
}

void loop() {
    // Gestione richieste Web Server (pagina emergenza /kill)
    webServer.handleClient();
    
    // Lettura pacchetti UDP MIDI in arrivo
    int packetSize = udp.parsePacket();
    if (packetSize > 0) {
        uint8_t packetBuffer[64];
        int len = udp.read(packetBuffer, sizeof(packetBuffer));
        
        if (len >= 2) {
            last_packet_time = millis();
            
            // 1. Pacchetto Ping dall'app [0xFF, 0x01] -> rispondi con Pong [0xFF, 0x02, ontime, duty, ...]
            if (packetBuffer[0] == 0xFF && packetBuffer[1] == 0x01) {
                uint8_t pong[6] = {
                    0xFF,
                    0x02,
                    (uint8_t)current_ontime_us,
                    (uint8_t)(current_playing_pitch >= 0 ? 1 : 0),
                    (uint8_t)(active_note_count),
                    0
                };
                udp.beginPacket(udp.remoteIP(), udp.remotePort());
                udp.write(pong, sizeof(pong));
                udp.endPacket();
                return;
            }
            
            // 2. Pacchetto MIDI: può essere formato a 5 byte Apple [0x80, 0x80, status, d1, d2]
            // o formato MIDI standard a 3 byte [status, d1, d2]
            if (len >= 3) {
                int offset = 0;
                // Salta eventuale header Apple BLE-MIDI (byte 0 con bit 7 e timestamp byte 1)
                if (len >= 5 && (packetBuffer[0] & 0x80) && (packetBuffer[1] & 0x80)) {
                    offset = 2;
                }
                
                uint8_t status = packetBuffer[offset];
                uint8_t d1 = (offset + 1 < len) ? packetBuffer[offset + 1] : 0;
                uint8_t d2 = (offset + 2 < len) ? packetBuffer[offset + 2] : 0;
                
                handleMidiMessage(status, d1, d2);
            }
        }
    }
    
    // Watchdog di sicurezza: se nessuna nota/pacchetto per oltre SAFETY_WATCHDOG_MS mentre la bobina suona
    if (current_playing_pitch >= 0 && (millis() - last_packet_time > SAFETY_WATCHDOG_MS)) {
        clearAllNotes();
        Serial.println(F("[WATCHDOG] Timeout pacchetti Wi-Fi! Bobina silenziata per sicurezza."));
    }
}
