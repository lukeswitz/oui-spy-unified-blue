#ifndef ENGINE_REGISTRY_H
#define ENGINE_REGISTRY_H

#include "protocol.h"

// Engine lifecycle callbacks
typedef struct {
    void (*init)(void);          // One-time initialization
    void (*start)(void);         // Enable and start scanning
    void (*stop)(void);          // Disable and clean up
    void (*loop)(void);          // Called every main loop iteration while active
    void (*config)(const uint8_t* payload, uint8_t len);  // Runtime config update (nullable)
    void (*applyPrefs)(void);    // Re-apply runtime prefs (alert cooldown/rediscover/etc). Nullable.
    const char* name;            // Human-readable name
} EngineCallbacks;

// Initialize the engine registry
void engineRegistryInit(void);

// Register an engine's callbacks
void engineRegister(EngineId id, const EngineCallbacks* callbacks);

// Enable/disable an engine (handles compatibility checks)
bool engineEnable(EngineId id);
bool engineDisable(EngineId id);

// Force-disable ALL engines (stop callbacks + reset state)
void engineDisableAll(void);

bool engineEnableLocal(EngineId id);
bool engineDisableLocal(EngineId id);
uint8_t engineGetLocalMask(void);
void engineDisableNonLocal(void);

// Get current state
EngineState engineGetState(EngineId id);
void engineSetState(EngineId id, EngineState state);

// Bitmask of active engines
uint8_t engineGetActiveMask(void);

// Bitmask of available (registered) engines
uint8_t engineGetAvailableMask(void);

// Call loop() on all active engines — called from main loop
void engineLoopAll(void);

// Process engine command from BLE queue
void engineProcessCommand(const EngineCommand* cmd);

void nodeCtlApply(uint8_t command, const uint8_t* payload, uint8_t len);

void engineApplyWifiBand(uint8_t mask);

void engineSetDenyMask(uint8_t mask);
void engineStateConfigApply(const uint8_t* data, uint8_t len);

void engineSetAutoPcap(bool enabled);
bool engineAutoPcapEnabled(void);
bool engineAutoPcapPending(void);
void engineSetAutoPcapDuration(uint16_t seconds);
uint16_t engineGetAutoPcapDuration(void);
void engineSetAutoPcapCooldown(uint16_t seconds);
uint16_t engineGetAutoPcapCooldown(void);
uint32_t engineGetAutoPcapCooldownRemainingMs(void);
uint32_t engineGetAutoPcapTriggerCount(void);
uint8_t  engineGetAutoPcapPausedMask(void);
uint32_t engineGetAutoPcapRemainingMs(void);
uint8_t  engineGetAutoPcapTriggerSrc(void);
const uint8_t* engineGetAutoPcapTriggerMac(void);

void engineRequestAutoPcap(EngineId src, uint8_t channel, const uint8_t* mac);

void engineLoadAlertPrefs(void);
uint32_t engineGetNotifyCooldownMs(void);
uint32_t engineGetRediscoverMs(void);

#endif // ENGINE_REGISTRY_H
