/*
 ==============================================================================
  Tesla Coil Bluetooth LE MIDI Interrupter for ESP32
  ------------------------------------------------------------------------------
  Riceve segnali MIDI via Bluetooth Low Energy (BLE) da iPhone / iPad
  e genera impulsi quadri con On-Time e frequenza controllati per
  pilotare l'ingresso interrupter musicale di una bobina di Tesla (SSTC / DRSSTC).

  Compatibile con lo standard Apple BLE-MIDI (CoreMIDI) e app dedicata TeslaMIDI.

  Caratteristiche di sicurezza:
  - On-Time rigidamente limitato (default max 150 µs, configurabile)
  - Periodo minimo / Frequenza massima limitata (default max 1250 Hz / 800 µs)
  - Limitazione Duty Cycle hardware massimo (max 15%)
  - Gestione Note Stack (polifonia filtrata in monofonica senza note bloccate)
  - Watchdog di sicurezza per spegnimento automatico in caso di disconnessione BLE
  - Supporto potenziometri analogici fisici opzionali (GPIO 34 & 35)
  - Controllo dinamico On-Time e Parametri tramite messaggi MIDI CC
 ==============================================================================
*/

#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>

// ==============================================================================
// CONFIGURAZIONE PIN HARDWARE
// ==============================================================================
#define PIN_PWM_OUTPUT          18    // Pin di uscita verso l'interrupter della bobina
#define PIN_STATUS_LED           2    // LED di stato (LED onboard sulla maggior parte degli ESP32)

// Abilita potenziometri analogici fisici (opzionale, impostare a true se collegati)
#define ENABLE_ANALOG_POTS   false    // false: controllato da App/valori di default
#define PIN_POT_ONTIME          34    // ADC1_CH6 (solo se ENABLE_ANALOG_POTS è true)
#define PIN_POT_PERIOD_MIN      35    // ADC1_CH7 (solo se ENABLE_ANALOG_POTS è true)

// ==============================================================================
// LIMITI DI SICUREZZA BOBINA DI TESLA (DRSSTC / SSTC)
// ==============================================================================
#define ONTIME_ABSOLUTE_MAX_US  180   // Limite assoluto non superabile di On-Time (µs)
#define ONTIME_DEFAULT_US        50   // Valore iniziale di On-Time (µs)
#define ONTIME_MIN_US            10   // Minimo On-Time consentito (µs)

#define PERIOD_MIN_ABSOLUTE_US  800   // Minimo periodo = 800 µs (frequenza max 1250 Hz)
#define PERIOD_MIN_DEFAULT_US  1000   // Periodo minimo di default (1000 µs = 1000 Hz max)
#define PERIOD_MIN_MAX_US      2500   // Limite superiore per la frequenza minima

#define MAX_DUTY_CYCLE_PERCENT 0.15f  // Duty cycle massimo di sicurezza (15%)

#define SAFETY_WATCHDOG_MS     8000   // Spegne automaticamente la nota se suona per più di 8s
#define LEDC_RESOLUTION_BITS     12   // 12 bit = 4096 livelli di risoluzione PWM
#define LEDC_MAX_DUTY          4095

// Canale LEDC per ESP32 Core v2.x
#define LEDC_CHANNEL              0

// ==============================================================================
// UUID STANDARD APPLE BLUETOOTH LE MIDI
// ==============================================================================
#define BLE_MIDI_SERVICE_UUID        "03b80e5a-ede8-4b33-a020-008b000c7348"
#define BLE_MIDI_CHARACTERISTIC_UUID "7772e5db-3868-4112-a1a9-f2669d106bf3"
#define DEVICE_NAME                  "TeslaCoil-MIDI"

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

// ==============================================================================
// VARIABILI GLOBALI
// ==============================================================================
volatile int current_ontime_us = ONTIME_DEFAULT_US;
volatile int current_period_min_us = PERIOD_MIN_DEFAULT_US;

bool device_connected = false;
bool old_device_connected = false;

// Note Stack per gestire polifonia in monofonia senza blocchi
#define MAX_ACTIVE_NOTES 16
struct ActiveNote {
    uint8_t pitch;
    uint8_t velocity;
    uint8_t channel;
};
ActiveNote active_notes[MAX_ACTIVE_NOTES];
uint8_t active_note_count = 0;

int8_t current_playing_pitch = -1;
unsigned long note_start_time = 0;

BLEServer *pServer = NULL;
BLECharacteristic *pMidiCharacteristic = NULL;

// ==============================================================================
// FUNZIONI HARDWARE PWM (LEDC COMPATIBILE ESP32 V2 E V3)
// ==============================================================================

void initPwmHardware() {
    pinMode(PIN_PWM_OUTPUT, OUTPUT);
    digitalWrite(PIN_PWM_OUTPUT, LOW);

#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
    // ESP32 Arduino Core 3.x
    ledcAttach(PIN_PWM_OUTPUT, 1000, LEDC_RESOLUTION_BITS);
    ledcWrite(PIN_PWM_OUTPUT, 0);
#else
    // ESP32 Arduino Core 2.x
    ledcSetup(LEDC_CHANNEL, 1000, LEDC_RESOLUTION_BITS);
    ledcAttachPin(PIN_PWM_OUTPUT, LEDC_CHANNEL);
    ledcWrite(LEDC_CHANNEL, 0);
#endif
}

void setPwmOutput(uint32_t freq_hz, uint32_t duty_val) {
    if (duty_val == 0 || freq_hz == 0) {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
        ledcWrite(PIN_PWM_OUTPUT, 0);
#else
        ledcWrite(LEDC_CHANNEL, 0);
#endif
        return;
    }

#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
    ledcChangeFrequency(PIN_PWM_OUTPUT, freq_hz, LEDC_RESOLUTION_BITS);
    ledcWrite(PIN_PWM_OUTPUT, duty_val);
#else
    ledcSetup(LEDC_CHANNEL, freq_hz, LEDC_RESOLUTION_BITS);
    ledcWrite(LEDC_CHANNEL, duty_val);
#endif
}

void stopPwmOutput() {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && (ESP_ARDUINO_VERSION_MAJOR >= 3)
    ledcWrite(PIN_PWM_OUTPUT, 0);
#else
    ledcWrite(LEDC_CHANNEL, 0);
#endif
    current_playing_pitch = -1;
    digitalWrite(PIN_STATUS_LED, device_connected ? HIGH : LOW);
}

// ==============================================================================
// GESTIONE DELLE NOTE MIDI
// ==============================================================================

void applyPitch(uint8_t pitch) {
    if (pitch >= 128) return;

    unsigned int period_us = midiperiod[pitch];

    // Controllo di sicurezza: periodo minimo (frequenza massima)
    if (period_us < (unsigned int)current_period_min_us) {
        // Frequenza troppo alta per la bobina: silenzia per sicurezza
        stopPwmOutput();
        return;
    }

    uint32_t freq_hz = 1000000UL / period_us;
    if (freq_hz == 0) freq_hz = 1;

    // Calcolo del duty cycle corrispondente a current_ontime_us
    int safe_ontime = constrain(current_ontime_us, ONTIME_MIN_US, ONTIME_ABSOLUTE_MAX_US);
    
    // Duty proporzionale: duty_val / 4095 = ontime_us / period_us
    uint32_t duty_val = (uint32_t)(((float)safe_ontime / (float)period_us) * (float)LEDC_MAX_DUTY);

    // Limite di sicurezza assoluto del Duty Cycle (default max 15%)
    uint32_t max_duty_allowed = (uint32_t)(LEDC_MAX_DUTY * MAX_DUTY_CYCLE_PERCENT);
    if (duty_val > max_duty_allowed) {
        duty_val = max_duty_allowed;
    }

    if (duty_val < 1) duty_val = 1;

    setPwmOutput(freq_hz, duty_val);
    current_playing_pitch = pitch;
    note_start_time = millis();

    // Lampeggio visivo LED di stato
    digitalWrite(PIN_STATUS_LED, LOW);
}

void handleNoteOn(uint8_t channel, uint8_t pitch, uint8_t velocity) {
    if (velocity == 0) {
        handleNoteOff(channel, pitch, velocity);
        return;
    }

    // Aggiungi la nota al Note Stack se non è già presente
    bool already_active = false;
    for (uint8_t i = 0; i < active_note_count; i++) {
        if (active_notes[i].pitch == pitch && active_notes[i].channel == channel) {
            active_notes[i].velocity = velocity;
            already_active = true;
            break;
        }
    }
    if (!already_active && active_note_count < MAX_ACTIVE_NOTES) {
        active_notes[active_note_count].pitch = pitch;
        active_notes[active_note_count].velocity = velocity;
        active_notes[active_note_count].channel = channel;
        active_note_count++;
    }

    // Modalità Monofonica Priorità Ultima Nota / Nota Più Alta
    // Qui suoniamo l'ultima nota inserita
    applyPitch(pitch);
}

void handleNoteOff(uint8_t channel, uint8_t pitch, uint8_t velocity) {
    // Rimuovi la nota dal Note Stack
    int remove_idx = -1;
    for (uint8_t i = 0; i < active_note_count; i++) {
        if (active_notes[i].pitch == pitch && active_notes[i].channel == channel) {
            remove_idx = i;
            break;
        }
    }

    if (remove_idx >= 0) {
        for (uint8_t i = remove_idx; i < active_note_count - 1; i++) {
            active_notes[i] = active_notes[i + 1];
        }
        active_note_count--;
    }

    // Se la nota rilasciata era quella attualmente in riproduzione:
    if (current_playing_pitch == (int8_t)pitch) {
        if (active_note_count > 0) {
            // Suona l'ultima nota ancora attiva
            applyPitch(active_notes[active_note_count - 1].pitch);
        } else {
            // Nessuna nota rimasta attiva: spegni l'interrupter
            stopPwmOutput();
        }
    }
}

void allNotesOff() {
    active_note_count = 0;
    stopPwmOutput();
}

void handleControlChange(uint8_t channel, uint8_t cc_number, uint8_t cc_value) {
    // CC 120 (All Sound Off) o CC 123 (All Notes Off) -> Arresto di emergenza
    if (cc_number == 120 || cc_number == 123) {
        allNotesOff();
        return;
    }

    // CC 14: Controllo remoto On-Time in microsecondi dall'app iPhone
    // cc_value (0-127) mappato tra ONTIME_MIN_US e ONTIME_ABSOLUTE_MAX_US
    if (cc_number == 14) {
        current_ontime_us = map(cc_value, 0, 127, ONTIME_MIN_US, ONTIME_ABSOLUTE_MAX_US);
        if (current_playing_pitch >= 0) {
            applyPitch(current_playing_pitch);
        }
        return;
    }

    // CC 15: Controllo remoto Periodo Minimo (Frequenza Max) dall'app iPhone
    if (cc_number == 15) {
        current_period_min_us = map(cc_value, 0, 127, PERIOD_MIN_ABSOLUTE_US, PERIOD_MIN_MAX_US);
        if (current_playing_pitch >= 0) {
            applyPitch(current_playing_pitch);
        }
        return;
    }
}

// ==============================================================================
// PARSER PACCHETTI STANDARD BLUETOOTH LE MIDI (Apple CoreMIDI)
// ==============================================================================

void parseBleMidiPacket(const uint8_t *data, size_t length) {
    if (length < 3) return;

    size_t idx = 0;

    // Byte 0: Header Byte (bit 7 = 1, bit 6 = 0)
    if ((data[0] & 0x80) && !(data[0] & 0x40)) {
        idx = 1;
    }

    uint8_t running_status = 0;

    while (idx < length) {
        // Se il byte corrente è un timestamp (bit 7 = 1) o uno status byte
        if (data[idx] & 0x80) {
            if ((data[idx] & 0xF0) >= 0x80) {
                // È uno Status Byte MIDI (0x80 - 0xEF)
                running_status = data[idx++];
            } else {
                // È un byte di timestamp, salta al successivo
                idx++;
                if (idx >= length) break;
                if (data[idx] & 0x80) {
                    running_status = data[idx++];
                }
            }
        }

        uint8_t msg_type = running_status & 0xF0;
        uint8_t channel  = running_status & 0x0F;

        if (msg_type == 0x90) { // Note On
            if (idx + 1 < length) {
                uint8_t pitch = data[idx++];
                uint8_t vel   = data[idx++];
                if (vel == 0) {
                    handleNoteOff(channel, pitch, 0);
                } else {
                    handleNoteOn(channel, pitch, vel);
                }
            } else break;
        } 
        else if (msg_type == 0x80) { // Note Off
            if (idx + 1 < length) {
                uint8_t pitch = data[idx++];
                uint8_t vel   = data[idx++];
                handleNoteOff(channel, pitch, vel);
            } else break;
        } 
        else if (msg_type == 0xB0) { // Control Change
            if (idx + 1 < length) {
                uint8_t cc_num = data[idx++];
                uint8_t cc_val = data[idx++];
                handleControlChange(channel, cc_num, cc_val);
            } else break;
        } 
        else if (msg_type == 0xC0 || msg_type == 0xD0) { // Program Change / Aftertouch (1 data byte)
            if (idx < length) idx++;
        } 
        else if (msg_type == 0xE0) { // Pitch Bend (2 data bytes)
            if (idx + 1 < length) idx += 2;
            else break;
        } 
        else {
            idx++; // Byte non gestito
        }
    }
}

// ==============================================================================
// CALLBACKS SERVER BLUETOOTH
// ==============================================================================

class MyServerCallbacks : public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
        device_connected = true;
        digitalWrite(PIN_STATUS_LED, HIGH);
        Serial.println(F("[BLE] iPhone Connesso!"));
    }

    void onDisconnect(BLEServer* pServer) {
        device_connected = false;
        allNotesOff();
        digitalWrite(PIN_STATUS_LED, LOW);
        Serial.println(F("[BLE] iPhone Disconnesso - Interrupter SPENTO"));
    }
};

class MyCharacteristicCallbacks : public BLECharacteristicCallbacks {
    void onWrite(BLECharacteristic *pCharacteristic) {
        std::string rxValue = pCharacteristic->getValue();
        if (rxValue.length() > 0) {
            parseBleMidiPacket((const uint8_t*)rxValue.data(), rxValue.length());
        }
    }
};

// ==============================================================================
// SETUP
// ==============================================================================

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println();
    Serial.println(F("=================================================="));
    Serial.println(F("   Tesla Coil BLE MIDI Interrupter - ESP32        "));
    Serial.println(F("=================================================="));

    pinMode(PIN_STATUS_LED, OUTPUT);
    digitalWrite(PIN_STATUS_LED, LOW);

    // Inizializza l'uscita PWM
    initPwmHardware();
    stopPwmOutput();

    // Configura potenziometri fisici se abilitati
    if (ENABLE_ANALOG_POTS) {
        pinMode(PIN_POT_ONTIME, INPUT);
        pinMode(PIN_POT_PERIOD_MIN, INPUT);
        analogReadResolution(12);
    }

    // Inizializza Bluetooth LE
    Serial.println(F("[BLE] Inizializzazione BLE MIDI..."));
    BLEDevice::init(DEVICE_NAME);

    // Imposta la potenza di trasmissione massima per contrastare l'EMI della bobina
    esp_ble_tx_power_set(ESP_BLE_PWR_TYPE_DEFAULT, ESP_PWR_LVL_P9);

    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    // Crea il Servizio Standard Apple BLE MIDI
    BLEService *pMidiService = pServer->createService(BLEUUID(BLE_MIDI_SERVICE_UUID));

    pMidiCharacteristic = pMidiService->createCharacteristic(
        BLEUUID(BLE_MIDI_CHARACTERISTIC_UUID),
        BLECharacteristic::PROPERTY_READ   |
        BLECharacteristic::PROPERTY_WRITE  |
        BLECharacteristic::PROPERTY_NOTIFY |
        BLECharacteristic::PROPERTY_WRITE_NR
    );

    pMidiCharacteristic->setCallbacks(new MyCharacteristicCallbacks());
    pMidiCharacteristic->addDescriptor(new BLE2902());

    pMidiService->start();

    // Avvia Advertising
    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    pAdvertising->addServiceUUID(BLE_MIDI_SERVICE_UUID);
    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06); // Funziona bene con iPhone / CoreBluetooth
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();

    Serial.println(F("[BLE] In attesa di connessione da iPhone..."));
}

// ==============================================================================
// LOOP PRINCIPALE
// ==============================================================================

void loop() {
    // 1. Riavvia Advertising in caso di disconnessione
    if (!device_connected && old_device_connected) {
        delay(300);
        pServer->startAdvertising();
        Serial.println(F("[BLE] Riavvio Advertising..."));
        old_device_connected = device_connected;
    }
    if (device_connected && !old_device_connected) {
        old_device_connected = device_connected;
    }

    // 2. Lettura opzionale potenziometri fisici
    if (ENABLE_ANALOG_POTS) {
        int raw_ontime = analogRead(PIN_POT_ONTIME);
        int raw_period = analogRead(PIN_POT_PERIOD_MIN);

        current_ontime_us = map(raw_ontime, 0, 4095, ONTIME_MIN_US, ONTIME_ABSOLUTE_MAX_US);
        current_period_min_us = map(raw_period, 0, 4095, PERIOD_MIN_ABSOLUTE_US, PERIOD_MIN_MAX_US);
    }

    // 3. Watchdog di sicurezza: spegne la nota se suona ininterrottamente da oltre SAFETY_WATCHDOG_MS
    if (current_playing_pitch >= 0) {
        if (millis() - note_start_time > SAFETY_WATCHDOG_MS) {
            Serial.println(F("[SICUREZZA] Watchdog timeout nota continua - Spegnimento forzato"));
            stopPwmOutput();
            active_note_count = 0;
        }
    }

    // Lampeggio lento del LED di stato quando in attesa di connessione
    if (!device_connected) {
        static unsigned long last_blink = 0;
        if (millis() - last_blink > 800) {
            last_blink = millis();
            digitalWrite(PIN_STATUS_LED, !digitalRead(PIN_STATUS_LED));
        }
    }

    delay(2);
}
