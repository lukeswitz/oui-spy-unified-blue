#pragma once
#include <NimBLEDevice.h>

void bleCoexRegister(NimBLEAdvertisedDeviceCallbacks* cb, bool activeScan);
void bleCoexUnregister(NimBLEAdvertisedDeviceCallbacks* cb);
NimBLEScan* bleCoexScan(void);
bool bleCoexActive(void);
void bleCoexEnsureScanning(void);
void bleCoexPauseForMesh(void);
void bleCoexSetPassiveOnly(bool passive);
bool bleCoexActiveScanAllowed(void);
