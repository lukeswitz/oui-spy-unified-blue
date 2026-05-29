#include "flock_ble.h"
#include "protocol.h"
#include "flock_match.h"
#include "dedup_ring.h"
#include "wardrive.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include <Arduino.h>
#include <NimBLEDevice.h>

// Standalone Flock-BLE scanner. When Wardrive is active, this engine yields:
// Wardrive's BLE callback runs the same predicates from flock_match.h and
// emits FLOCK_BLE events directly.

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;
static unsigned long scanIntervalMs = 3000;
static unsigned long scanDurationMs = 2000;
static uint16_t bleScanInterval = 100;
static uint16_t bleScanWindow   = 99;

static DedupRing<64, 5000> dedup;
static uint32_t totalDetections = 0;

class FlockBLECallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        // Address-type filter: drop RPA (resolvable) — phones/watches.
        if (!flockShouldConsiderAddr(dev)) return;

        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);

        int rssi = dev->getRSSI();
        std::string name = dev->haveName() ? dev->getName() : "";

        bool detected = false;
        uint8_t method = 0;
        bool isRaven = false;
        const char* ravenFW = "";
        char tnSerial[20] = {0};

        if (flockMatchOui(mac)) {
            detected = true;
            method = METHOD_OUI_MATCH;
        }

        if (!detected && !name.empty() && flockMatchNameStr(name.c_str())) {
            detected = true;
            method = METHOD_NAME_MATCH;
        }

        if (!detected && dev->haveManufacturerData()) {
            std::string data = dev->getManufacturerData();
            if (flockMatchMfgPayload((const uint8_t*)data.data(), data.size(),
                                     tnSerial, sizeof(tnSerial))) {
                detected = true;
                method = METHOD_MFG_ID;
            }
        }

        if (!detected) {
            if (flockMatchRavenUuid(dev, &ravenFW)) {
                detected = true;
                method = METHOD_RAVEN_UUID;
                isRaven = true;
            }
        }

        if (!detected) return;
        if (dedup.check(mac)) return;

        totalDetections++;

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_FLOCK_BLE;
        memcpy(evt.mac, mac, 6);
        evt.rssi = rssi;
        evt.timestamp_ms = millis();
        evt.method = method;
        evt.ext.flock.is_raven = isRaven ? 1 : 0;
        if (isRaven) {
            strncpy(evt.ext.flock.raven_fw, ravenFW,
                    sizeof(evt.ext.flock.raven_fw) - 1);
        } else if (tnSerial[0]) {
            // Surface TN-serial via raven_fw slot (16 chars).
            strncpy(evt.ext.flock.raven_fw, tnSerial,
                    sizeof(evt.ext.flock.raven_fw) - 1);
        }
        pushDetection(&evt);

        std::string addrStr = dev->getAddress().toString();
        const char* methodStr[] = {"oui", "name", "mfg_id", "raven_uuid"};
        Serial.printf("[FLOCK-BLE] %s %s RSSI:%d [%s]%s%s%s%s\n",
                      addrStr.c_str(), name.c_str(), rssi,
                      method < 4 ? methodStr[method] : "?",
                      isRaven ? " RAVEN:" : "",
                      isRaven ? ravenFW : "",
                      tnSerial[0] ? " " : "",
                      tnSerial[0] ? tnSerial : "");
    }
};

static FlockBLECallback scanCb;

static void flockBleInit(void) {
    dedup.reset();
    totalDetections = 0;
    flockMatchInit();
    Serial.println("[FLOCK-BLE] Initialized");
}

static void flockBleStart(void) {
    scanning = true;
    dedup.setCooldownMs(engineGetRediscoverMs());
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) {
        Serial.println("[FLOCK-BLE] Started (passive — wardrive handles BLE scan)");
        return;
    }

    scanDurationMs = wardriveGetBleScanDurationMs();
    scanIntervalMs = wardriveGetBleScanIntervalMs();
    bleScanInterval = 100;
    bleScanWindow   = 99;
    bool wifiCoex = (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED);

    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
    bleScan->setActiveScan(true);
    bleScan->setInterval(bleScanInterval);
    bleScan->setWindow(bleScanWindow);
    lastScanStart = 0;
    Serial.printf("[FLOCK-BLE] Started (%u/%u dur=%lu int=%lu coex=%d)\n",
                  bleScanInterval, bleScanWindow,
                  scanDurationMs, scanIntervalMs, wifiCoex ? 1 : 0);
}

static void flockBleStop(void) {
    scanning = false;
    if (engineGetState(ENGINE_WARDRIVE) == ESTATE_DISABLED) {
        if (bleScan && bleScan->isScanning()) bleScan->stop();
        if (bleScan) bleScan->setAdvertisedDeviceCallbacks(nullptr, false);
    }
    bleScan = nullptr;
    Serial.println("[FLOCK-BLE] Stopped");
}

static void flockBleLoop(void) {
    if (!scanning) return;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;
    if (!bleScan) return;
    unsigned long now = millis();
    if (now - lastScanStart >= scanIntervalMs && !bleScan->isScanning()) {
        scanDurationMs = wardriveGetBleScanDurationMs();
        scanIntervalMs = wardriveGetBleScanIntervalMs();
        bleScan->start(0, false);
        lastScanStart = now;
    } else if (bleScan->isScanning() && (now - lastScanStart >= scanDurationMs)) {
        bleScan->stop();
    }
}

static void flockBleApplyPrefs(void) {
    dedup.setCooldownMs(engineGetRediscoverMs());
}

const EngineCallbacks flockBleCallbacks = {
    .init       = flockBleInit,
    .start      = flockBleStart,
    .stop       = flockBleStop,
    .loop       = flockBleLoop,
    .config     = NULL,
    .applyPrefs = flockBleApplyPrefs,
    .name       = "Flock-BLE"
};
