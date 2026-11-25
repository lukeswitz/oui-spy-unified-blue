// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_DETECTOR_H
#define ENGINE_DETECTOR_H

#include "engine_registry.h"

class NimBLEAdvertisedDevice;

extern const EngineCallbacks detectorCallbacks;

void detectorCheckBleDevice(const uint8_t* mac, int rssi);
void detectorCheckBleUuid(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi);
void detectorCheckBleSignatures(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi);
void detectorCheckWifiDeviceISR(const uint8_t* mac, int rssi, uint8_t channel);
void detectorCheckWifiSignaturesISR(const uint8_t* payload, int len, int rssi, uint8_t channel);
void detectorClearFilters(void);
void detectorAddFilter(const uint8_t* macBytes, uint8_t prefixLen, const char* desc);
void detectorAddUuidFilter(uint16_t uuid, const char* desc);
bool detectorAddRule(uint8_t type, const uint8_t* payload, uint8_t len);
int detectorFilterCount(void);
int detectorUuidFilterCount(void);
int detectorRuleCount(void);
const char* detectorLookupDesc(const uint8_t* mac);
size_t detectorSerialize(uint8_t* out, size_t maxLen);
size_t detectorSerializeWire(uint8_t* out, size_t maxLen);
void detectorExtPersist(void);
void detectorExtRestore(void);
bool detectorLocalEdits(void);
void detectorSetLocalEdits(bool on);
struct DetEditResult {
    uint8_t macs, uuids, rules, changed, skipped;
};
uint8_t detectorFilterEdit(uint8_t op, const uint8_t* data, size_t len, DetEditResult* r);
size_t detectorReportPage(uint8_t page, size_t pageMax, uint8_t* out, uint8_t* pages);
void detectorSetFilters(const uint8_t* data, size_t len);
bool detectorHoldsAll(const uint8_t* data, size_t len);
#define DETECTOR_LABELS_MAX (2 + 100 * 32)
size_t detectorSerializeLabels(uint8_t* out, size_t maxLen);
bool detectorSetLabels(const uint8_t* data, size_t len);
uint32_t detectorLabelsHash(void);
void detectorSetSigMask(uint16_t mask);
uint16_t detectorGetSigMask(void);
bool detectorUsesWifi(void);
void detectorHostSuspend(bool suspend);
#ifdef OUISPY_PORT_SELFTEST
int detectorPortSelfTest(void);
#endif

#endif
