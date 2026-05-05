/**
 * NimBLE GATT Server — sole control interface for the OUI-SPY device.
 * Phone connects here to control engines, receive detections, push GPS.
 */
#ifndef BLE_GATT_H
#define BLE_GATT_H

#include "protocol.h"

// Initialize NimBLE and start advertising
void bleGattInit(void);

// Send a detection event as a BLE notification
void bleGattNotifyDetection(const DetectionEvent* evt);

// Send foxhunter RSSI as a BLE notification
void bleGattNotifyFoxhunterRssi(int8_t rssi, uint16_t intervalMs);

// Send engine state update notification
void bleGattNotifyEngineState(void);

// Check if a phone is connected
bool bleGattIsConnected(void);

// Send mesh status notification
void bleGattNotifyMeshStatus(void);

#endif // BLE_GATT_H
