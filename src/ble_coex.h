#pragma once
#include <NimBLEDevice.h>

void bleCoexRegister(NimBLEAdvertisedDeviceCallbacks* cb, bool activeScan);
void bleCoexUnregister(NimBLEAdvertisedDeviceCallbacks* cb);
NimBLEScan* bleCoexScan(void);
bool bleCoexActive(void);
