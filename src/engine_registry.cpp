/**
 * Engine Registry implementation.
 */
#include "engine_registry.h"
#include <Arduino.h>

static const EngineCallbacks* engines[ENGINE_COUNT] = {nullptr};
static EngineState states[ENGINE_COUNT] = {ESTATE_DISABLED};
static bool initialized[ENGINE_COUNT] = {false};

// WiFi engines are mutually exclusive
static bool isWifiEngine(EngineId id) {
    return id == ENGINE_FLOCK_WIFI || id == ENGINE_SKYSPY;
}

void engineRegistryInit(void) {
    for (int i = 0; i < ENGINE_COUNT; i++) {
        engines[i] = nullptr;
        states[i] = ESTATE_DISABLED;
        initialized[i] = false;
    }
    Serial.println("[ENGINE] Registry initialized");
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

    // WiFi exclusivity check
    if (isWifiEngine(id)) {
        for (int i = 0; i < ENGINE_COUNT; i++) {
            if (i != id && isWifiEngine((EngineId)i) && states[i] != ESTATE_DISABLED) {
                Serial.printf("[ENGINE] Cannot enable %s — WiFi conflict with %s\n",
                              engines[id]->name, engines[i]->name);
                return false;
            }
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

void engineLoopAll(void) {
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
        case 0x10: // Config update — engine-specific handling
            // Engines read config from SPIFFS/NVS on demand
            break;
    }
}
