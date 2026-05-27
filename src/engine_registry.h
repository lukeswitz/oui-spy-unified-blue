/**
 * Engine Registry — manages enable/disable, state, and compatibility.
 */
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

// ---- Auto-PCAP-on-detect ---------------------------------------------------
// When enabled, a detection from any engine other than Foxhunter triggers a
// timed PCAP capture on that detection's radio + channel. After the capture
// window expires, the origin engine is re-enabled.
void engineSetAutoPcap(bool enabled);
bool engineAutoPcapEnabled(void);
void engineSetAutoPcapDuration(uint16_t seconds);
uint16_t engineGetAutoPcapDuration(void);
uint32_t engineGetAutoPcapTriggerCount(void);

// Called by the detection notify task on every event. No-op if disabled.
void engineRequestAutoPcap(EngineId src, uint8_t channel);

#endif // ENGINE_REGISTRY_H
