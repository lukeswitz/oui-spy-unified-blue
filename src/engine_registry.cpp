/**
 * Engine Registry implementation.
 */
#include "engine_registry.h"
#include "engines/pcap.h"
#include "mesh_espnow.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <esp_timer.h>

volatile uint32_t g_engRawSeen = 0;
static uint8_t g_engineDenyMask = 0;

static const EngineCallbacks* engines[ENGINE_COUNT] = {nullptr};
static EngineState states[ENGINE_COUNT] = {ESTATE_DISABLED};
static bool initialized[ENGINE_COUNT] = {false};

// WiFi engines are mutually exclusive
static bool isWifiEngine(EngineId id) {
    return id == ENGINE_FLOCK_WIFI || id == ENGINE_SKYSPY ||
           id == ENGINE_WARDRIVE   || id == ENGINE_PCAP;
}

static bool isBleScanEngine(EngineId id) {
    return id == ENGINE_FLOCK_BLE || id == ENGINE_UNIPWN ||
           id == ENGINE_FOXHUNTER || id == ENGINE_DETECTOR ||
           id == ENGINE_PCAP;
}

// Wardrive coexists with Flock-WiFi/Flock-BLE via passive mode (those engines
// detect on wardrive's sniffer callback instead of owning the radio).
static bool wifiCoexCompatible(EngineId a, EngineId b) {
    auto inGroup = [](EngineId e) {
        return e == ENGINE_WARDRIVE || e == ENGINE_FLOCK_WIFI ||
               e == ENGINE_SKYSPY || e == ENGINE_PCAP;
    };
    return inGroup(a) && inGroup(b);
}

static void autoPcapLoad(void);
static void autoPcapSave(void);

static volatile uint32_t g_notifyCooldownMs = 5000;
static volatile uint32_t g_rediscoverMs     = 10000;

void engineLoadAlertPrefs(void) {
    Preferences p;
    p.begin("ouispy-alert", true);
    uint16_t cool  = p.getUShort("cooldown",   5000);
    uint16_t redis = p.getUShort("rediscover", 10000);
    p.end();
    if (cool  < 100)   cool  = 100;
    if (redis < 1000)  redis = 1000;
    g_notifyCooldownMs = cool;
    g_rediscoverMs     = redis;
    Serial.printf("[ENGINE] Alert prefs loaded: notifyCool=%lums rediscover=%lums\n",
                  (unsigned long)g_notifyCooldownMs, (unsigned long)g_rediscoverMs);
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (engines[i] && engines[i]->applyPrefs) engines[i]->applyPrefs();
    }
}

uint32_t engineGetNotifyCooldownMs(void) { return g_notifyCooldownMs; }
uint32_t engineGetRediscoverMs(void)     { return g_rediscoverMs; }

void engineRegistryInit(void) {
    for (int i = 0; i < ENGINE_COUNT; i++) {
        engines[i] = nullptr;
        states[i] = ESTATE_DISABLED;
        initialized[i] = false;
    }
    autoPcapLoad();
    engineLoadAlertPrefs();
    Serial.println("[ENGINE] Registry initialized (all engines disabled)");
}

static bool autoPcapPending;
static bool autoPcapObservedActive;
static uint8_t autoPcapPausedMask;
static uint8_t autoPcapTriggerSrc = 0xFF;
static uint8_t autoPcapTriggerMac[6] = {0,0,0,0,0,0};
static bool autoPcapUserCancelled = false;
static esp_timer_handle_t autoPcapDeadlineTimer = nullptr;
static volatile bool autoPcapDeadlineFired = false;

static void autoPcapDeadlineCb(void* arg) {
    autoPcapDeadlineFired = true;
}

static void autoPcapArmDeadlineTimer(uint32_t ms) {
    autoPcapDeadlineFired = false;
    if (autoPcapDeadlineTimer == nullptr) {
        const esp_timer_create_args_t args = {
            .callback = &autoPcapDeadlineCb,
            .arg = nullptr,
            .dispatch_method = ESP_TIMER_TASK,
            .name = "ap_deadline",
            .skip_unhandled_events = false,
        };
        esp_timer_create(&args, &autoPcapDeadlineTimer);
    }
    esp_timer_stop(autoPcapDeadlineTimer);
    esp_timer_start_once(autoPcapDeadlineTimer, (uint64_t)ms * 1000ULL);
}

static void autoPcapCancelDeadlineTimer(void) {
    if (autoPcapDeadlineTimer != nullptr) {
        esp_timer_stop(autoPcapDeadlineTimer);
    }
}

void engineDisableAll(void) {
    autoPcapCancelDeadlineTimer();
    autoPcapPending = false;
    autoPcapObservedActive = false;
    autoPcapPausedMask = 0;
    autoPcapTriggerSrc = 0xFF;
    autoPcapUserCancelled = false;
    memset(autoPcapTriggerMac, 0, 6);
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

    if (id != ENGINE_PCAP &&
        (states[ENGINE_PCAP] == ESTATE_SCANNING || autoPcapPending)) {
        uint8_t pm = pcapActiveMode();
        bool blocked = (pm == PCAP_MODE_BLE)
                           ? isBleScanEngine(id)
                           : (isWifiEngine(id) || isBleScanEngine(id));
        if (blocked) {
            Serial.printf("[ENGINE] enable %s refused — PCAP owns radio\n",
                          engines[id]->name);
            return false;
        }
    }

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
static uint16_t autoPcapCooldownSec = 0;
static unsigned long autoPcapCooldownUntilMs = 0;

static void autoPcapSave(void) {
    Preferences p;
    p.begin("ouispy-ap", false);
    p.putBool("en", autoPcapEnabled);
    p.putUShort("dur", autoPcapDurationSec);
    p.putUShort("cool", autoPcapCooldownSec);
    p.end();
}

static void autoPcapLoad(void) {
    Preferences p;
    p.begin("ouispy-ap", true);
    autoPcapEnabled = p.getBool("en", false);
    autoPcapDurationSec = p.getUShort("dur", 10);
    if (autoPcapDurationSec == 0) autoPcapDurationSec = 10;
    autoPcapCooldownSec = p.getUShort("cool", 0);
    p.end();
    Serial.printf("[AUTO-PCAP] loaded en=%d dur=%us cool=%us\n",
                  (int)autoPcapEnabled, autoPcapDurationSec, autoPcapCooldownSec);
}
static unsigned long autoPcapDeadline = 0;
static uint32_t autoPcapTriggers = 0;

void engineSetAutoPcap(bool en) {
    if (autoPcapEnabled == en) return;
    autoPcapEnabled = en;
    autoPcapSave();
}
bool engineAutoPcapEnabled(void) { return autoPcapEnabled; }
void engineSetAutoPcapDuration(uint16_t s) {
    uint16_t v = (s == 0 ? 10 : s);
    if (autoPcapDurationSec == v) return;
    autoPcapDurationSec = v;
    autoPcapSave();
}
uint16_t engineGetAutoPcapDuration(void) { return autoPcapDurationSec; }

void engineSetAutoPcapCooldown(uint16_t s) {
    if (autoPcapCooldownSec == s) return;
    autoPcapCooldownSec = s;
    if (s == 0) autoPcapCooldownUntilMs = 0;
    autoPcapSave();
}
uint16_t engineGetAutoPcapCooldown(void) { return autoPcapCooldownSec; }
uint32_t engineGetAutoPcapCooldownRemainingMs(void) {
    if (autoPcapCooldownUntilMs == 0) return 0;
    long rem = (long)(autoPcapCooldownUntilMs - millis());
    return rem > 0 ? (uint32_t)rem : 0;
}

uint32_t engineGetAutoPcapTriggerCount(void) { return autoPcapTriggers; }
uint8_t engineGetAutoPcapPausedMask(void) { return autoPcapPending ? autoPcapPausedMask : 0; }

uint32_t engineGetAutoPcapRemainingMs(void) {
    if (!autoPcapPending) return 0;
    long rem = (long)(autoPcapDeadline - millis());
    return rem > 0 ? (uint32_t)rem : 0;
}

uint8_t engineGetAutoPcapTriggerSrc(void) {
    return autoPcapPending ? autoPcapTriggerSrc : 0xFF;
}

const uint8_t* engineGetAutoPcapTriggerMac(void) {
    return autoPcapTriggerMac;
}

#define AUTO_PCAP_MAC_RING_SIZE 32
static struct {
    uint8_t mac[6];
    unsigned long ts;
} autoPcapMacRing[AUTO_PCAP_MAC_RING_SIZE];
static int autoPcapMacHead = 0;
static int autoPcapMacCount = 0;

static bool autoPcapMacRecent(const uint8_t* mac, unsigned long cooldownMs) {
    if (mac == nullptr) return false;
    unsigned long now = millis();
    for (int i = 0; i < autoPcapMacCount; i++) {
        if (memcmp(autoPcapMacRing[i].mac, mac, 6) == 0) {
            unsigned long age = now - autoPcapMacRing[i].ts;
            if (age < cooldownMs) return true;
            autoPcapMacRing[i].ts = now;
            return false;
        }
    }
    int idx;
    if (autoPcapMacCount < AUTO_PCAP_MAC_RING_SIZE) {
        idx = autoPcapMacCount++;
    } else {
        idx = autoPcapMacHead;
        autoPcapMacHead = (autoPcapMacHead + 1) % AUTO_PCAP_MAC_RING_SIZE;
    }
    memcpy(autoPcapMacRing[idx].mac, mac, 6);
    autoPcapMacRing[idx].ts = now;
    return false;
}

void engineRequestAutoPcap(EngineId src, uint8_t channel, const uint8_t* mac) {
    if (!autoPcapEnabled) return;
    switch (src) {
        case ENGINE_DETECTOR:
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
        case ENGINE_SKYSPY:
        case ENGINE_UNIPWN:
            break;
        default:
            return;
    }
    if (autoPcapPending) return;
    if (states[ENGINE_PCAP] != ESTATE_DISABLED) return;

    if (autoPcapCooldownUntilMs != 0) {
        long rem = (long)(autoPcapCooldownUntilMs - millis());
        if (rem > 0) {
            Serial.printf("[ENGINE] auto-pcap suppress: cooldown active rem=%ldms\n", rem);
            return;
        }
        autoPcapCooldownUntilMs = 0;
    }

    if (mac != nullptr && autoPcapMacRecent(mac, g_rediscoverMs)) {
        Serial.printf("[ENGINE] auto-pcap suppress mac=%02X:%02X:%02X:%02X:%02X:%02X (within rediscover=%lums)\n",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                      (unsigned long)g_rediscoverMs);
        return;
    }

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

    autoPcapPausedMask = 0;
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if (i == ENGINE_PCAP) continue;
        if (states[i] == ESTATE_DISABLED) continue;
        bool conflict = isBle ? isBleScanEngine((EngineId)i)
                              : (isWifiEngine((EngineId)i) || isBleScanEngine((EngineId)i));
        if (!conflict) continue;
        autoPcapPausedMask |= ENGINE_BITMASK(i);
        engineDisable((EngineId)i);
    }

    autoPcapTriggers++;
    autoPcapTriggerSrc = (uint8_t)src;
    if (mac != nullptr) memcpy(autoPcapTriggerMac, mac, 6);
    else memset(autoPcapTriggerMac, 0, 6);
    autoPcapPending = true;
    autoPcapObservedActive = false;
    autoPcapUserCancelled = false;
    autoPcapDeadline = millis() + (unsigned long)autoPcapDurationSec * 1000UL;
    autoPcapArmDeadlineTimer((uint32_t)autoPcapDurationSec * 1000U);
    uint8_t maskSnap = autoPcapPausedMask;
    meshBroadcastAutoPcapEvent((uint8_t)src, autoPcapTriggerMac, chan,
                               autoPcapDurationSec, maskSnap,
                               (uint8_t)(isBle ? PCAP_MODE_BLE : PCAP_MODE_WIFI));
    Serial.printf("[ENGINE] auto-pcap trigger src=%s ch=%u mode=%s duration=%us paused=0x%02X\n",
                  engines[src] ? engines[src]->name : "?",
                  chan, isBle ? "BLE" : "WIFI", autoPcapDurationSec, maskSnap);
    if (!isBle && meshIsEnabled()) {
        meshFlushPendingTxAllChannels();
    }
    engineEnable(ENGINE_PCAP);
}

static void autoPcapTick(void) {
    if (!autoPcapPending) return;

    bool pcapDown = (states[ENGINE_PCAP] == ESTATE_DISABLED);
    if (!pcapDown) autoPcapObservedActive = true;
    bool deadlineHit = autoPcapDeadlineFired || (long)(millis() - autoPcapDeadline) >= 0;

    if (!pcapDown && deadlineHit) {
        Serial.println("[ENGINE] auto-pcap deadline, stopping PCAP");
        engineDisable(ENGINE_PCAP);
        pcapDown = true;
    }

    if (pcapDown && (autoPcapObservedActive || autoPcapUserCancelled)) {
        autoPcapCancelDeadlineTimer();
        uint8_t mask = autoPcapUserCancelled ? 0 : autoPcapPausedMask;
        bool cancelled = autoPcapUserCancelled;
        autoPcapPending = false;
        autoPcapObservedActive = false;
        autoPcapUserCancelled = false;
        autoPcapPausedMask = 0;
        autoPcapTriggerSrc = 0xFF;
        memset(autoPcapTriggerMac, 0, 6);
        if (!cancelled && autoPcapCooldownSec > 0) {
            autoPcapCooldownUntilMs = millis() + (unsigned long)autoPcapCooldownSec * 1000UL;
            Serial.printf("[ENGINE] auto-pcap cooldown armed %us\n", autoPcapCooldownSec);
        }
        for (int i = 0; i < ENGINE_COUNT; i++) {
            if ((mask & ENGINE_BITMASK(i)) == 0) continue;
            if (engines[i] == nullptr) continue;
            if (states[i] != ESTATE_DISABLED) continue;
            Serial.printf("[ENGINE] auto-pcap restore %s\n", engines[i]->name);
            engineEnable((EngineId)i);
        }
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

void engineSetDenyMask(uint8_t mask) {
    if (mask == g_engineDenyMask) return;
    g_engineDenyMask = mask;
    for (int i = 0; i < ENGINE_COUNT; i++) {
        if ((mask & ENGINE_BITMASK(i)) && states[i] != ESTATE_DISABLED) {
            Serial.printf("[ENGINE] fan-out deny -> stopping engine %d\n", i);
            engineDisable((EngineId)i);
        }
    }
}

void engineProcessCommand(const EngineCommand* cmd) {
    if (cmd->engine_id >= ENGINE_COUNT) return;

    switch (cmd->command) {
        case 0x01: // Enable
            if (g_engineDenyMask & ENGINE_BITMASK(cmd->engine_id)) {
                Serial.printf("[ENGINE] enable engine %d denied (fan-out)\n", cmd->engine_id);
                break;
            }
            if (autoPcapPausedMask & ENGINE_BITMASK(cmd->engine_id)) {
                autoPcapPausedMask &= ~ENGINE_BITMASK(cmd->engine_id);
            }
            engineEnable((EngineId)cmd->engine_id);
            break;
        case 0x00: // Disable
            if (autoPcapPausedMask & ENGINE_BITMASK(cmd->engine_id)) {
                autoPcapPausedMask &= ~ENGINE_BITMASK(cmd->engine_id);
                Serial.printf("[ENGINE] user-disabled paused engine %d; dropped from restore mask\n",
                              cmd->engine_id);
            }
            if (cmd->engine_id == ENGINE_PCAP && autoPcapPending) {
                autoPcapUserCancelled = true;
                autoPcapPausedMask = 0;
                Serial.println("[ENGINE] user cancelled auto-pcap; restore skipped");
            }
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
