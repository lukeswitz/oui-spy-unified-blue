#include "flock_ble.h"
#include "protocol.h"
#include "flock_oui.h"
#include "dedup_ring.h"
#include "../mesh_espnow.h"
#include <Arduino.h>
#include <NimBLEDevice.h>

static const char* name_patterns[] = {
    "FS Ext Battery", "Penguin", "Flock", "Pigvision"
};
static const int name_pattern_count = sizeof(name_patterns) / sizeof(name_patterns[0]);

static const uint16_t mfg_ids[] = { 0x09C8 };
static const int mfg_id_count = sizeof(mfg_ids) / sizeof(mfg_ids[0]);

#define RAVEN_GPS_SVC       "00003100-0000-1000-8000-00805f9b34fb"
#define RAVEN_POWER_SVC     "00003200-0000-1000-8000-00805f9b34fb"
#define RAVEN_OLD_LOC_SVC   "00001819-0000-1000-8000-00805f9b34fb"

static const char* raven_uuids[] = {
    "0000180a-0000-1000-8000-00805f9b34fb",
    RAVEN_GPS_SVC,
    RAVEN_POWER_SVC,
    "00003300-0000-1000-8000-00805f9b34fb",
    "00003400-0000-1000-8000-00805f9b34fb",
    "00003500-0000-1000-8000-00805f9b34fb",
    "00001809-0000-1000-8000-00805f9b34fb",
    RAVEN_OLD_LOC_SVC
};
static const int raven_uuid_count = sizeof(raven_uuids) / sizeof(raven_uuids[0]);

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;
static const unsigned long SCAN_INTERVAL_MS = 3000;
static const int SCAN_DURATION_S = 2;

static DedupRing<32, 5000> dedup;
static uint32_t totalDetections = 0;

static bool checkMACPrefix(const uint8_t* mac) {
    return flockMatchOui(mac);
}

static bool checkDeviceName(const char* name) {
    if (!name || !name[0]) return false;
    for (int i = 0; i < name_pattern_count; i++) {
        if (strcasestr(name, name_patterns[i])) return true;
    }
    return false;
}

static bool checkMfgID(uint16_t id) {
    for (int i = 0; i < mfg_id_count; i++) {
        if (mfg_ids[i] == id) return true;
    }
    return false;
}

static bool checkRavenUUID(NimBLEAdvertisedDevice* dev) {
    if (!dev->haveServiceUUID()) return false;
    int count = dev->getServiceUUIDCount();
    for (int i = 0; i < count; i++) {
        std::string str = dev->getServiceUUID(i).toString();
        for (int j = 0; j < raven_uuid_count; j++) {
            if (strcasecmp(str.c_str(), raven_uuids[j]) == 0) return true;
        }
    }
    return false;
}

static const char* estimateRavenFW(NimBLEAdvertisedDevice* dev) {
    if (!dev->haveServiceUUID()) return "?";
    bool has_new_gps = false, has_old_loc = false, has_power = false;
    int count = dev->getServiceUUIDCount();
    for (int i = 0; i < count; i++) {
        std::string u = dev->getServiceUUID(i).toString();
        if (strcasecmp(u.c_str(), RAVEN_GPS_SVC) == 0)     has_new_gps = true;
        if (strcasecmp(u.c_str(), RAVEN_OLD_LOC_SVC) == 0)  has_old_loc = true;
        if (strcasecmp(u.c_str(), RAVEN_POWER_SVC) == 0)    has_power = true;
    }
    if (has_old_loc && !has_new_gps) return "1.1.x";
    if (has_new_gps && !has_power)   return "1.2.x";
    if (has_new_gps && has_power)    return "1.3.x";
    return "?";
}

class FlockBLECallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        uint8_t mac[6];
        memcpy(mac, dev->getAddress().getNative(), 6);

        int rssi = dev->getRSSI();
        std::string name = dev->haveName() ? dev->getName() : "";

        bool detected = false;
        uint8_t method = 0;
        bool isRaven = false;
        const char* ravenFW = "";

        if (checkMACPrefix(mac)) {
            detected = true;
            method = METHOD_OUI_MATCH;
        }

        if (!detected && !name.empty() && checkDeviceName(name.c_str())) {
            detected = true;
            method = METHOD_NAME_MATCH;
        }

        if (!detected) {
            for (int i = 0; i < (int)dev->getManufacturerDataCount(); i++) {
                std::string data = dev->getManufacturerData(i);
                if (data.size() >= 2) {
                    uint16_t code = ((uint16_t)(uint8_t)data[1] << 8) |
                                     (uint16_t)(uint8_t)data[0];
                    if (checkMfgID(code)) {
                        detected = true;
                        method = METHOD_MFG_ID;
                        break;
                    }
                }
            }
        }

        if (!detected && checkRavenUUID(dev)) {
            detected = true;
            method = METHOD_RAVEN_UUID;
            isRaven = true;
            ravenFW = estimateRavenFW(dev);
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
        strncpy(evt.ext.flock.raven_fw, ravenFW, sizeof(evt.ext.flock.raven_fw) - 1);
        pushDetection(&evt);

        std::string addrStr = dev->getAddress().toString();
        const char* methodStr[] = {"oui", "name", "mfg_id", "raven_uuid"};
        Serial.printf("[FLOCK-BLE] %s %s RSSI:%d [%s]%s%s\n",
                      addrStr.c_str(), name.c_str(), rssi,
                      method < 4 ? methodStr[method] : "?",
                      isRaven ? " RAVEN:" : "",
                      isRaven ? ravenFW : "");
    }
};

static FlockBLECallback scanCb;

static void flockBleInit(void) {
    dedup.reset();
    totalDetections = 0;
    flockOuiInitBuckets();
    Serial.println("[FLOCK-BLE] Initialized");
}

static void flockBleStart(void) {
    scanning = true;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) {
        Serial.println("[FLOCK-BLE] Started (passive — wardrive handles BLE scan)");
        return;
    }
    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    lastScanStart = 0;
    Serial.println("[FLOCK-BLE] Started");
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
    if (now - lastScanStart >= SCAN_INTERVAL_MS) {
        if (!bleScan->isScanning()) {
            bleScan->start(SCAN_DURATION_S, false);
            lastScanStart = now;
        }
    }
}

const EngineCallbacks flockBleCallbacks = {
    .init   = flockBleInit,
    .start  = flockBleStart,
    .stop   = flockBleStop,
    .loop   = flockBleLoop,
    .config = NULL,
    .name   = "Flock-BLE"
};
