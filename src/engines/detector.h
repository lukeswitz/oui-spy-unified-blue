/**
 * Detector Engine — BLE watchlist alerting.
 * Scans for OUI prefixes or full MAC addresses from user-configured filter list.
 */
#ifndef ENGINE_DETECTOR_H
#define ENGINE_DETECTOR_H

#include "engine_registry.h"

extern const EngineCallbacks detectorCallbacks;

/// Check a BLE device against detector's watchlist. Called by wardrive when
/// detector is active but wardrive owns the BLE scan.
void detectorCheckBleDevice(const uint8_t* mac, int rssi);

#endif
