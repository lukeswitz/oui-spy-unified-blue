#ifndef ENGINE_FOXHUNTER_H
#define ENGINE_FOXHUNTER_H
#include "engine_registry.h"

extern const EngineCallbacks foxhunterCallbacks;

/// Set foxhunter target MAC (called from GATT write).
void foxhunterSetTarget(const uint8_t* mac);

/// Check a BLE device against foxhunter's target. Called by wardrive when
/// foxhunter is active but wardrive owns the BLE scan.
void foxhunterCheckBleDevice(const uint8_t* mac, int rssi);

#endif
