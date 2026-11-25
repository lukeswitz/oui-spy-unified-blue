// Copyright (c) 2026 Luke Switzer
#ifndef ENGINE_FOXHUNTER_H
#define ENGINE_FOXHUNTER_H
#include "engine_registry.h"

extern const EngineCallbacks foxhunterCallbacks;

void foxhunterSetTarget(const uint8_t* mac, uint8_t channel = 0);

void foxhunterCheckBleDevice(const uint8_t* mac, int rssi);

void foxhunterCheckWifiDevice(const uint8_t* mac, int rssi, uint8_t channel);

void foxhunterCheckWifiDeviceISR(
    const uint8_t* addr1, const uint8_t* addr2, const uint8_t* addr3,
    int rssi, uint8_t channel);

bool foxhunterHasTarget(void);

#endif
