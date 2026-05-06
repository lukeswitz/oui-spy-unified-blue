#ifndef ENGINE_FOXHUNTER_H
#define ENGINE_FOXHUNTER_H
#include "engine_registry.h"

extern const EngineCallbacks foxhunterCallbacks;

/// Set foxhunter target MAC + optional channel hint (called from GATT write).
/// channel=0 means hop ch1/6/11, channel=1-14 means lock to that channel.
void foxhunterSetTarget(const uint8_t* mac, uint8_t channel = 0);

/// Check a BLE device against foxhunter's target. Called by wardrive when
/// foxhunter is active but wardrive owns the BLE scan.
void foxhunterCheckBleDevice(const uint8_t* mac, int rssi);

/// Check a WiFi device against foxhunter's target. Called by wardrive when
/// foxhunter is active but wardrive owns the WiFi scan.
void foxhunterCheckWifiDevice(const uint8_t* mac, int rssi, uint8_t channel);

/// ISR-safe: check 3 802.11 address fields against foxhunter target.
/// Called from wardrive promiscuous callback (IRAM context).
void IRAM_ATTR foxhunterCheckWifiDeviceISR(
    const uint8_t* addr1, const uint8_t* addr2, const uint8_t* addr3,
    int rssi, uint8_t channel);

#endif
