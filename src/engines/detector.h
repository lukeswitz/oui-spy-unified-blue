/**
 * Detector Engine — BLE watchlist alerting.
 * Scans for OUI prefixes or full MAC addresses from user-configured filter list.
 */
#ifndef ENGINE_DETECTOR_H
#define ENGINE_DETECTOR_H

#include "engine_registry.h"

extern const EngineCallbacks detectorCallbacks;

void detectorCheckBleDevice(const uint8_t* mac, int rssi);
void detectorCheckWifiDeviceISR(const uint8_t* mac, int rssi, uint8_t channel);
void detectorClearFilters(void);
void detectorAddFilter(const uint8_t* macBytes, uint8_t prefixLen, const char* desc);
int detectorFilterCount(void);

#endif
