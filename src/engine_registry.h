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

#endif // ENGINE_REGISTRY_H
