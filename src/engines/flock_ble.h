/**
 * Flock-BLE Engine — BLE scanning for Flock Safety surveillance devices.
 *
 * Detection methods:
 *   - MAC prefix (OUI) matching
 *   - Device name pattern matching
 *   - Manufacturer company ID (0x09C8 XUNTONG)
 *   - Raven gunshot detector service UUID matching + firmware estimation
 */
#ifndef ENGINE_FLOCK_BLE_H
#define ENGINE_FLOCK_BLE_H

#include "engine_registry.h"

extern const EngineCallbacks flockBleCallbacks;

#endif
