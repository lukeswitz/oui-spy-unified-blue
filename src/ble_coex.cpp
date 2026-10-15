#include "ble_coex.h"
#include "mesh_espnow.h"
#include <Arduino.h>

#define BLE_COEX_MAX 8

static NimBLEAdvertisedDeviceCallbacks* g_cbs[BLE_COEX_MAX];
static volatile int g_count = 0;
static bool g_wantActive = false;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;
volatile uint32_t g_bleRawSeen = 0;
#ifdef OUISPY_STATUS_LOG
static uint8_t g_uniq[64][6];
volatile uint32_t g_bleUniq = 0;
#endif

class BleCoexDispatch : public NimBLEAdvertisedDeviceCallbacks {
  public:
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_bleRawSeen++;
#ifdef OUISPY_STATUS_LOG
        const uint8_t* a = dev->getAddress().getBase()->val;
        bool seen = false;
        for (uint32_t i = 0; i < g_bleUniq && i < 64; i++)
            if (memcmp(g_uniq[i], a, 6) == 0) { seen = true; break; }
        if (!seen && g_bleUniq < 64) memcpy(g_uniq[g_bleUniq++], a, 6);
#endif
        NimBLEAdvertisedDeviceCallbacks* local[BLE_COEX_MAX];
        portENTER_CRITICAL(&g_mux);
        int n = g_count;
        for (int i = 0; i < n; i++) local[i] = g_cbs[i];
        portEXIT_CRITICAL(&g_mux);
        for (int i = 0; i < n; i++) {
            if (local[i]) local[i]->onResult(dev);
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

void bleCoexPauseForMesh(void) {
    NimBLEScan* s = NimBLEDevice::getScan();
    if (s->isScanning()) s->stop();
}

void bleCoexEnsureScanning(void) {
    if (g_count == 0) return;
#if CONFIG_IDF_TARGET_ESP32
    if (meshIsEnabled() && meshInMeshWindow()) return;
#endif
    NimBLEScan* s = NimBLEDevice::getScan();
    if (s->isScanning()) return;
    s->setActiveScan(g_wantActive);
    s->setInterval(100);
    s->setWindow(99);
#ifdef OUISPY_NIMBLE2_API
    s->start(0, false, false);
#else
    s->start(0, nullptr, false);
#endif
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
