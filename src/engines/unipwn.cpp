#include "unipwn.h"
#include "protocol.h"
#include "dedup_ring.h"
#include "../ble_coex.h"
#include "../engine_registry.h"
#include <Arduino.h>
#include <NimBLEDevice.h>

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;

static DedupRing<8, 10000> dedup;

static const char* robotPrefixes[] = {"Go2_", "G1_", "H1_", "B2_", "X1_"};
static const int prefixCount = 5;

static bool isUnitreeDevice(const char* name) {
    if (!name || !name[0]) return false;
    for (int i = 0; i < prefixCount; i++) {
        if (strncmp(name, robotPrefixes[i], strlen(robotPrefixes[i])) == 0)
            return true;
    }
    return false;
}

static const char* getRobotType(const char* name) {
    if (strncmp(name, "Go2_", 4) == 0) return "Go2";
    if (strncmp(name, "G1_", 3) == 0) return "G1";
    if (strncmp(name, "H1_", 3) == 0) return "H1";
    if (strncmp(name, "B2_", 3) == 0) return "B2";
    if (strncmp(name, "X1_", 3) == 0) return "X1";
    return "?";
}

class UnipwnCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        std::string name = dev->haveName() ? dev->getName() : "";
        if (!isUnitreeDevice(name.c_str())) return;

        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);
        if (dedup.check(mac)) return;

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_UNIPWN;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.timestamp_ms = millis();
        strncpy(evt.ext.unipwn.robot_type, getRobotType(name.c_str()),
                sizeof(evt.ext.unipwn.robot_type) - 1);
        pushDetection(&evt);

        Serial.printf("[UNIPWN] Robot found: %s RSSI:%d\n", name.c_str(), dev->getRSSI());
    }
};

static UnipwnCallback scanCb;

static void unipwnInit(void) {
    bleScan = NimBLEDevice::getScan();
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    dedup.reset();
    Serial.println("[UNIPWN] Initialized");
}

static void unipwnStart(void) {
    scanning = true;
    dedup.setCooldownMs(engineGetRediscoverMs());
    lastScanStart = 0;
    bleCoexRegister(&scanCb, true);
    Serial.println("[UNIPWN] Started — scanning for Unitree robots");
}

static void unipwnStop(void) {
    bleCoexUnregister(&scanCb);
    if (bleScan && bleScan->isScanning()) bleScan->stop();
    scanning = false;
    Serial.println("[UNIPWN] Stopped");
}

static void unipwnLoop(void) {
    if (!scanning || !bleScan) return;
    // Yield the shared scan to wardrive's duty cycle when it owns the radio;
    // our scanCb still gets adverts via ble_coex dispatch.
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;
    if (millis() - lastScanStart >= 2000) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }
}

static void unipwnApplyPrefs(void) {
    dedup.setCooldownMs(engineGetRediscoverMs());
}

const EngineCallbacks unipwnCallbacks = {
    .init       = unipwnInit,
    .start      = unipwnStart,
    .stop       = unipwnStop,
    .loop       = unipwnLoop,
    .config     = NULL,
    .applyPrefs = unipwnApplyPrefs,
    .name       = "UniPwn"
};
