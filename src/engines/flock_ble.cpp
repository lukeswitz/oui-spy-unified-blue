/**
 * Flock-BLE Engine — detects Flock Safety and Raven surveillance devices via BLE.
 *
 * Ported from raw/flockyou.cpp BLE scanning logic.
 * Pushes detections to detectionQueue for BLE GATT notification.
 */
#include "flock_ble.h"
#include "protocol.h"
#include "ble_gatt.h"
#include <Arduino.h>
#include <NimBLEDevice.h>

// ============================================================================
// Detection Patterns
// ============================================================================

static const char* mac_prefixes[] = {
    // FS Ext Battery devices
    "58:8e:81", "cc:cc:cc", "ec:1b:bd", "90:35:ea", "04:0d:84",
    "f0:82:c0", "1c:34:f1", "38:5b:44", "94:34:69", "b4:e3:f9",
    // Flock WiFi devices
    "70:c9:4e", "3c:91:80", "d8:f3:bc", "80:30:49", "14:5a:fc",
    "74:4c:a1", "08:3a:88", "9c:2f:9d", "94:08:53", "e4:aa:ea"
};
static const int mac_prefix_count = sizeof(mac_prefixes) / sizeof(mac_prefixes[0]);

static const char* name_patterns[] = {
    "FS Ext Battery", "Penguin", "Flock", "Pigvision"
};
static const int name_pattern_count = sizeof(name_patterns) / sizeof(name_patterns[0]);

static const uint16_t mfg_ids[] = { 0x09C8 }; // XUNTONG
static const int mfg_id_count = sizeof(mfg_ids) / sizeof(mfg_ids[0]);

// Raven service UUIDs
#define RAVEN_GPS_SVC       "00003100-0000-1000-8000-00805f9b34fb"
#define RAVEN_POWER_SVC     "00003200-0000-1000-8000-00805f9b34fb"
#define RAVEN_OLD_LOC_SVC   "00001819-0000-1000-8000-00805f9b34fb"

static const char* raven_uuids[] = {
    "0000180a-0000-1000-8000-00805f9b34fb",  // Device Info
    RAVEN_GPS_SVC,
    RAVEN_POWER_SVC,
    "00003300-0000-1000-8000-00805f9b34fb",  // Network
    "00003400-0000-1000-8000-00805f9b34fb",  // Upload
    "00003500-0000-1000-8000-00805f9b34fb",  // Error
    "00001809-0000-1000-8000-00805f9b34fb",  // Old Health
    RAVEN_OLD_LOC_SVC
};
static const int raven_uuid_count = sizeof(raven_uuids) / sizeof(raven_uuids[0]);

// ============================================================================
// State
// ============================================================================

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;
static const unsigned long SCAN_INTERVAL_MS = 3000;
static const int SCAN_DURATION_S = 2;

// Simple dedup: track last N MACs to avoid spamming queue
#define DEDUP_SIZE 32
#define DEDUP_COOLDOWN_MS 5000
static struct {
    uint8_t mac[6];
    unsigned long lastSeen;
} dedup[DEDUP_SIZE];
static int dedupCount = 0;

// Detection count for stats
static uint32_t totalDetections = 0;

// ============================================================================
// Helpers
// ============================================================================

static bool checkMACPrefix(const uint8_t* mac) {
    char pfx[9];
    snprintf(pfx, sizeof(pfx), "%02x:%02x:%02x", mac[0], mac[1], mac[2]);
    for (int i = 0; i < mac_prefix_count; i++) {
        if (strncasecmp(pfx, mac_prefixes[i], 8) == 0) return true;
    }
    return false;
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

static bool isDedupCooldown(const uint8_t* mac) {
    unsigned long now = millis();
    for (int i = 0; i < dedupCount; i++) {
        if (memcmp(dedup[i].mac, mac, 6) == 0) {
            if (now - dedup[i].lastSeen < DEDUP_COOLDOWN_MS) return true;
            dedup[i].lastSeen = now;
            return false;
        }
    }
    // Add new entry — circular ring buffer
    static int dedupHead = 0;
    int idx;
    if (dedupCount < DEDUP_SIZE) {
        idx = dedupCount++;
    } else {
        idx = dedupHead;
        dedupHead = (dedupHead + 1) % DEDUP_SIZE;
    }
    memcpy(dedup[idx].mac, mac, 6);
    dedup[idx].lastSeen = now;
    return false;
}

// ============================================================================
// BLE Scan Callback
// ============================================================================

class FlockBLECallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        std::string addrStr = dev->getAddress().toString();
        unsigned int m[6];
        sscanf(addrStr.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t mac[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                          (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};

        int rssi = dev->getRSSI();
        std::string name = dev->haveName() ? dev->getName() : "";

        bool detected = false;
        uint8_t method = 0;
        bool isRaven = false;
        const char* ravenFW = "";

        // 1. MAC prefix
        if (checkMACPrefix(mac)) {
            detected = true;
            method = METHOD_OUI_MATCH;
        }

        // 2. Device name
        if (!detected && !name.empty() && checkDeviceName(name.c_str())) {
            detected = true;
            method = METHOD_NAME_MATCH;
        }

        // 3. Manufacturer ID
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

        // 4. Raven UUID
        if (!detected && checkRavenUUID(dev)) {
            detected = true;
            method = METHOD_RAVEN_UUID;
            isRaven = true;
            ravenFW = estimateRavenFW(dev);
        }

        if (!detected) return;

        // Dedup cooldown — avoid spamming queue with same device every 2s scan
        if (isDedupCooldown(mac)) return;

        totalDetections++;

        // Build detection event for queue
        DetectionEvent evt;
        memset(&evt, 0, sizeof(evt));
        evt.engine_id = ENGINE_FLOCK_BLE;
        memcpy(evt.mac, mac, 6);
        evt.rssi = rssi;
        evt.channel = 0;  // BLE
        evt.timestamp_ms = millis();
        evt.method = method;
        evt.ext.flock.is_raven = isRaven ? 1 : 0;
        strncpy(evt.ext.flock.raven_fw, ravenFW, sizeof(evt.ext.flock.raven_fw) - 1);

        pushDetection(&evt);

        // Log
        const char* methodStr[] = {"oui", "name", "mfg_id", "raven_uuid"};
        Serial.printf("[FLOCK-BLE] %s %s RSSI:%d [%s]%s%s\n",
                      addrStr.c_str(), name.c_str(), rssi,
                      method < 4 ? methodStr[method] : "?",
                      isRaven ? " RAVEN:" : "",
                      isRaven ? ravenFW : "");
    }
};

static FlockBLECallback scanCb;

// ============================================================================
// Engine Lifecycle
// ============================================================================

static void flockBleInit(void) {
    // NimBLE already initialized by ble_gatt. Just need scan handle.
    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);  // true = duplicates
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    dedupCount = 0;
    totalDetections = 0;
    Serial.println("[FLOCK-BLE] Initialized");
}

static void flockBleStart(void) {
    scanning = true;
    lastScanStart = 0;  // Force immediate scan
    Serial.println("[FLOCK-BLE] Started");
}

static void flockBleStop(void) {
    if (bleScan && bleScan->isScanning()) {
        bleScan->stop();
    }
    scanning = false;
    Serial.println("[FLOCK-BLE] Stopped");
}

static void flockBleLoop(void) {
    if (!scanning || !bleScan) return;

    unsigned long now = millis();
    if (now - lastScanStart >= SCAN_INTERVAL_MS) {
        if (!bleScan->isScanning()) {
            bleScan->start(SCAN_DURATION_S, false);  // false = non-blocking
            lastScanStart = now;
        }
    }
}

// ============================================================================
// Export
// ============================================================================

const EngineCallbacks flockBleCallbacks = {
    .init  = flockBleInit,
    .start = flockBleStart,
    .stop  = flockBleStop,
    .loop  = flockBleLoop,
    .name  = "Flock-BLE"
};
