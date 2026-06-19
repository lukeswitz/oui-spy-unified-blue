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

// Offline scan flag — true means engines keep running when phone disconnects
bool bleGattOfflineScanEnabled(void);
void offlineScanEnabledSetFromPref(bool v);

// Manager: re-slice wardrive channel ranges when the live-node set changes
void bleGattMaybeResliceWardrive(void);

// Manager: re-send desired engines to any node whose reported mask lacks them
void bleGattReconcileEngines(void);

// Apply device-wide config (callable from BLE write or relayed mesh packet)
void hardwareConfigApply(const uint8_t* data, size_t len);
void alertConfigApply(const uint8_t* data, size_t len);
void autoPcapConfigApply(const uint8_t* data, size_t len);
void foxhunterConfigApply(const uint8_t* data, size_t len);

// Manager: periodically re-broadcast cached device-wide config to all nodes
void bleGattRebroadcastConfigs(void);
#if defined(OUISPY_STOP_SELFTEST) || defined(OUISPY_ENGSTRESS)
void mgrDebugSetCommanded(uint8_t mask);
#endif

// Send mesh status notification
void bleGattNotifyMeshStatus(void);

void bleGattNotifyPcapStats(void);
void bleGattStreamPcapBytes(const uint8_t* buf, size_t len);
void bleGattDispatchMeshNotify(uint8_t kind, const char source_node_id[5],
                               uint16_t seq, const uint8_t* payload, uint8_t len);
void bleGattStartFleetProgress(void);

#ifdef OUISPY_NETCOUNT
void bleGattNetcountDrive(void);
#endif

#endif // BLE_GATT_H
