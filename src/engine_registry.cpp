/**
 * Engine Registry implementation.
 */
#include "engine_registry.h"
#include "engines/pcap.h"
#include <Arduino.h>
#include <NimBLEDevice.h>

static const EngineCallbacks* engines[ENGINE_COUNT] = {nullptr};
static EngineState states[ENGINE_COUNT] = {ESTATE_DISABLED};
static bool initialized[ENGINE_COUNT] = {false};

// WiFi engines are mutually exclusive
static bool isWifiEngine(EngineId id) {
    return id == ENGINE_FLOCK_WIFI || id == ENGINE_SKYSPY || id == ENGINE_WARDRIVE;
}

// Wardrive coexists with Flock-WiFi/Flock-BLE via passive mode (those engines
// detect on wardrive's sniffer callback instead of owning the radio).
static bool wifiCoexCompatible(EngineId a, EngineId b) {
    return (a == ENGINE_WARDRIVE && b == ENGINE_FLOCK_WIFI) ||
           (a == ENGINE_FLOCK_WIFI && b == ENGINE_WARDRIVE);
}

void engineRegistryInit(void) {
    for (int i = 0; i < ENGINE_COUNT; i++) {
        engines[i] = nullptr;
        states[i] = ESTATE_DISABLED;
        initialized[i] = false;
    }
    Serial.println("[ENGINE] Registry initialized (all engines disabled)");
}

void engineDisableAll(void) {
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (states[i] != ESTATE_DISABLED && engines[i] != nullptr && engines[i]->stop) {
            Serial.printf("[ENGINE] Force-stopping %s\n", engines[i]->name);
            engines[i]->stop();
        }
        states[i] = ESTATE_DISABLED;
    }
    // Force-stop any lingering BLE scan to free the radio for GATT
    NimBLEScan* scan = NimBLEDevice::getScan();
    if (scan && scan->isScanning()) {
        scan->stop();
        Serial.println("[ENGINE] Force-stopped BLE scan");
    }
    Serial.println("[ENGINE] All engines disabled");
}

void engineRegister(EngineId id, const EngineCallbacks* callbacks) {
    if (id >= ENGINE_COUNT) return;
    engines[id] = callbacks;
    states[id] = ESTATE_DISABLED;
    Serial.printf("[ENGINE] Registered: %s (id=%d)\n", callbacks->name, id);
}

bool engineEnable(EngineId id) {
    if (id >= ENGINE_COUNT || engines[id] == nullptr) return false;

    // Already active?
    if (states[id] != ESTATE_DISABLED) return true;

    // WiFi exclusivity — force-stop conflicting WiFi engines, except
    // wardrive+flock_wifi which run together via passive mode.
    if (isWifiEngine(id)) {
        for (int i = 0; i < ENGINE_COUNT; i++) {
            if (i == id) continue;
            if (!isWifiEngine((EngineId)i)) continue;
            if (states[i] == ESTATE_DISABLED) continue;
            if (wifiCoexCompatible(id, (EngineId)i)) continue;
            Serial.printf("[ENGINE] Stopping %s for WiFi handoff to %s\n",
                          engines[i]->name, engines[id]->name);
            if (engines[i] != nullptr && engines[i]->stop) {
                engines[i]->stop();
            }
            states[i] = ESTATE_DISABLED;
        }
    }

    // One-time init
    if (!initialized[id] && engines[id]->init) {
        Serial.printf("[ENGINE] Initializing %s...\n", engines[id]->name);
        engines[id]->init();
        initialized[id] = true;
    }

    // Start
    if (engines[id]->start) {
        Serial.printf("[ENGINE] Starting %s\n", engines[id]->name);
        engines[id]->start();
    }
    states[id] = ESTATE_SCANNING;
    return true;
}

bool engineDisable(EngineId id) {
    if (id >= ENGINE_COUNT || engines[id] == nullptr) return false;
    if (states[id] == ESTATE_DISABLED) return true;

    if (engines[id]->stop) {
        Serial.printf("[ENGINE] Stopping %s\n", engines[id]->name);
        engines[id]->stop();
    }
    states[id] = ESTATE_DISABLED;
    return true;
}

EngineState engineGetState(EngineId id) {
    if (id >= ENGINE_COUNT) return ESTATE_DISABLED;
    return states[id];
}

void engineSetState(EngineId id, EngineState state) {
    if (id >= ENGINE_COUNT) return;
    states[id] = state;
}

uint8_t engineGetActiveMask(void) {
    uint8_t mask = 0;
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (states[i] != ESTATE_DISABLED) {
            mask |= ENGINE_BITMASK(i);
        }
    }
    return mask;
}

uint8_t engineGetAvailableMask(void) {
    uint8_t mask = 0;
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (engines[i] != nullptr) {
            mask |= ENGINE_BITMASK(i);
        }
    }
    return mask;
}

static bool autoPcapEnabled = false;
static uint16_t autoPcapDurationSec = 10;
static unsigned long autoPcapDeadline = 0;
static EngineId autoPcapOrigin = ENGINE_COUNT;
static bool autoPcapPending = false;
static uint32_t autoPcapTriggers = 0;

void engineSetAutoPcap(bool en) { autoPcapEnabled = en; }
bool engineAutoPcapEnabled(void) { return autoPcapEnabled; }
void engineSetAutoPcapDuration(uint16_t s) { autoPcapDurationSec = (s == 0 ? 10 : s); }
uint16_t engineGetAutoPcapDuration(void) { return autoPcapDurationSec; }
uint32_t engineGetAutoPcapTriggerCount(void) { return autoPcapTriggers; }

void engineRequestAutoPcap(EngineId src, uint8_t channel) {
    if (!autoPcapEnabled) return;
    if (src == ENGINE_FOXHUNTER || src == ENGINE_PCAP || src == ENGINE_WARDRIVE) return;
    if (states[ENGINE_PCAP] != ESTATE_DISABLED) return;
    if (autoPcapPending) return;

    bool isBle;
    switch (src) {
        case ENGINE_FLOCK_BLE:
        case ENGINE_UNIPWN:
            isBle = true; break;
        case ENGINE_FLOCK_WIFI:
            isBle = false; break;
        default:
            isBle = (channel == 0);
    }

    uint8_t chan = isBle ? 1 : ((channel >= 1 && channel <= 14) ? channel : 6);
    uint8_t cfg[4] = {
        PCAP_CTRL_START,
        (uint8_t)(isBle ? PCAP_MODE_BLE : PCAP_MODE_WIFI),
        chan, chan
    };
    if (engines[ENGINE_PCAP] && engines[ENGINE_PCAP]->config) {
        engines[ENGINE_PCAP]->config(cfg, 4);
    }

    autoPcapOrigin = src;
    autoPcapTriggers++;

    engineDisable(src);
    engineEnable(ENGINE_PCAP);
    autoPcapDeadline = millis() + (unsigned long)autoPcapDurationSec * 1000UL;
    autoPcapPending = true;
    Serial.printf("[ENGINE] auto-pcap trigger src=%s ch=%u mode=%s duration=%us\n",
                  engines[src] ? engines[src]->name : "?",
                  chan, isBle ? "BLE" : "WIFI", autoPcapDurationSec);
}

static void autoPcapTick(void) {
    if (!autoPcapPending) return;
    if (states[ENGINE_PCAP] == ESTATE_DISABLED) {
        if (autoPcapOrigin < ENGINE_COUNT && engines[autoPcapOrigin]) {
            Serial.printf("[ENGINE] auto-pcap window done, restoring %s\n",
                          engines[autoPcapOrigin]->name);
            engineEnable(autoPcapOrigin);
        }
        autoPcapPending = false;
        autoPcapOrigin = (EngineId)ENGINE_COUNT;
        return;
    }
    if (millis() >= autoPcapDeadline) {
        Serial.println("[ENGINE] auto-pcap deadline, stopping PCAP");
        engineDisable(ENGINE_PCAP);
    }
}

void engineLoopAll(void) {
    autoPcapTick();
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (states[i] != ESTATE_DISABLED && engines[i] != nullptr && engines[i]->loop) {
            engines[i]->loop();
        }
    }
}

void engineProcessCommand(const EngineCommand* cmd) {
    if (cmd->engine_id >= ENGINE_COUNT) return;

    switch (cmd->command) {
        case 0x01: // Enable
            engineEnable((EngineId)cmd->engine_id);
            break;
        case 0x00: // Disable
            engineDisable((EngineId)cmd->engine_id);
            break;
        case 0x0F: // Disable ALL engines
            engineDisableAll();
            break;
        case 0x10: // Config update — forward to engine's config handler
            if (engines[cmd->engine_id] != nullptr && engines[cmd->engine_id]->config) {
                engines[cmd->engine_id]->config(cmd->payload, cmd->payload_len);
            }
            break;
    }
}
