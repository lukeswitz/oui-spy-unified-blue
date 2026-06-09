#include "ble_coex.h"
#include <Arduino.h>

#define BLE_COEX_MAX 8

static NimBLEAdvertisedDeviceCallbacks* g_cbs[BLE_COEX_MAX];
static volatile int g_count = 0;
static bool g_wantActive = false;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

class BleCoexDispatch : public NimBLEAdvertisedDeviceCallbacks {
  public:
    void onResult(NimBLEAdvertisedDevice* dev) override {
        int n = g_count;
        for (int i = 0; i < n; i++) {
            NimBLEAdvertisedDeviceCallbacks* c = g_cbs[i];
            if (c) c->onResult(dev);
        }
    }
};

static BleCoexDispatch g_dispatch;

NimBLEScan* bleCoexScan(void) {
    return NimBLEDevice::getScan();
}

void bleCoexRegister(NimBLEAdvertisedDeviceCallbacks* cb, bool activeScan) {
    if (!cb) return;
    portENTER_CRITICAL(&g_mux);
    bool found = false;
    for (int i = 0; i < g_count; i++) {
        if (g_cbs[i] == cb) { found = true; break; }
    }
    if (!found && g_count < BLE_COEX_MAX) {
        g_cbs[g_count++] = cb;
    }
    if (activeScan) g_wantActive = true;
    int count = g_count;
    portEXIT_CRITICAL(&g_mux);

    NimBLEScan* s = NimBLEDevice::getScan();
    s->setAdvertisedDeviceCallbacks(&g_dispatch, true);
    if (g_wantActive) s->setActiveScan(true);
    Serial.printf("[BLE-COEX] register (count=%d)\n", count);
}

void bleCoexUnregister(NimBLEAdvertisedDeviceCallbacks* cb) {
    if (!cb) return;
    portENTER_CRITICAL(&g_mux);
    for (int i = 0; i < g_count; i++) {
        if (g_cbs[i] == cb) {
            for (int j = i; j < g_count - 1; j++) g_cbs[j] = g_cbs[j + 1];
            g_count--;
            g_cbs[g_count] = nullptr;
            break;
        }
    }
    bool empty = (g_count == 0);
    portEXIT_CRITICAL(&g_mux);

    if (empty) {
        g_wantActive = false;
        NimBLEScan* s = NimBLEDevice::getScan();
        if (s->isScanning()) s->stop();
        s->setAdvertisedDeviceCallbacks(nullptr, false);
        Serial.println("[BLE-COEX] all unregistered, scan stopped");
    }
}

bool bleCoexActive(void) {
    return g_count > 0;
}
