/**
 * Detector Engine — BLE watchlist scan.
 * Matches BLE advertisements against NVS-stored OUI prefixes or full MACs.
 * Ported from raw/detector.cpp BLE scan callback.
 */
#include "detector.h"
#include "protocol.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <vector>

// ============================================================================
// Filter storage
// ============================================================================

struct TargetFilter {
    char id[18];       // OUI "xx:xx:xx" or full MAC "xx:xx:xx:xx:xx:xx"
    bool isFullMAC;
    char desc[32];
};

static std::vector<TargetFilter> filters;
static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;
static const unsigned long SCAN_INTERVAL_MS = 3000;
static const int SCAN_DURATION_S = 2;

#define DEDUP_SIZE 32
#define DEDUP_COOLDOWN_MS 3000
static struct { uint8_t mac[6]; unsigned long lastSeen; } dedup[DEDUP_SIZE];
static int dedupCount = 0;

// ============================================================================
// NVS filter loading
// ============================================================================

static void loadFilters() {
    Preferences p;
    p.begin("ouispy", true);
    int count = p.getInt("filterCount", 0);
    filters.clear();
    for (int i = 0; i < count && i < 50; i++) {
        TargetFilter f;
        char key[16];
        snprintf(key, sizeof(key), "id_%d", i);
        String id = p.getString(key, "");
        if (id.length() == 0) continue;
        strncpy(f.id, id.c_str(), sizeof(f.id) - 1);
        snprintf(key, sizeof(key), "mac_%d", i);
        f.isFullMAC = p.getBool(key, false);
        snprintf(key, sizeof(key), "desc_%d", i);
        String desc = p.getString(key, "");
        strncpy(f.desc, desc.c_str(), sizeof(f.desc) - 1);
        filters.push_back(f);
    }
    p.end();
    Serial.printf("[DETECTOR] Loaded %d filters\n", (int)filters.size());
}

// ============================================================================
// Matching
// ============================================================================

static bool isDedupCooldown(const uint8_t* mac) {
    unsigned long now = millis();
    for (int i = 0; i < dedupCount; i++) {
        if (memcmp(dedup[i].mac, mac, 6) == 0) {
            if (now - dedup[i].lastSeen < DEDUP_COOLDOWN_MS) return true;
            dedup[i].lastSeen = now;
            return false;
        }
    }
    int idx = dedupCount < DEDUP_SIZE ? dedupCount++ : 0;
    memcpy(dedup[idx].mac, mac, 6);
    dedup[idx].lastSeen = now;
    return false;
}

static const TargetFilter* matchFilter(const char* macStr) {
    for (const auto& f : filters) {
        if (f.isFullMAC) {
            if (strcasecmp(macStr, f.id) == 0) return &f;
        } else {
            if (strncasecmp(macStr, f.id, strlen(f.id)) == 0) return &f;
        }
    }
    return nullptr;
}

// ============================================================================
// BLE Scan Callback
// ============================================================================

class DetectorCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        std::string addrStr = dev->getAddress().toString();
        unsigned int m[6];
        sscanf(addrStr.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t mac[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                          (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};

        const TargetFilter* hit = matchFilter(addrStr.c_str());
        if (!hit) return;
        if (isDedupCooldown(mac)) return;

        DetectionEvent evt;
        memset(&evt, 0, sizeof(evt));
        evt.engine_id = ENGINE_DETECTOR;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = 0; // watchlist
        evt.ext.detector.is_full_mac = hit->isFullMAC ? 1 : 0;
        strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);

        pushDetection(&evt);

        Serial.printf("[DETECTOR] %s RSSI:%d [%s] %s\n",
                      addrStr.c_str(), dev->getRSSI(),
                      hit->isFullMAC ? "MAC" : "OUI", hit->desc);
    }
};

static DetectorCallback scanCb;

// ============================================================================
// Lifecycle
// ============================================================================

static void detectorInit(void) {
    loadFilters();
    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    dedupCount = 0;
    Serial.println("[DETECTOR] Initialized");
}

static void detectorStart(void) {
    scanning = true;
    lastScanStart = 0;
    Serial.println("[DETECTOR] Started");
}

static void detectorStop(void) {
    if (bleScan && bleScan->isScanning()) bleScan->stop();
    scanning = false;
    Serial.println("[DETECTOR] Stopped");
}

static void detectorLoop(void) {
    if (!scanning || !bleScan) return;
    if (millis() - lastScanStart >= SCAN_INTERVAL_MS) {
        if (!bleScan->isScanning()) {
            bleScan->start(SCAN_DURATION_S, false);
            lastScanStart = millis();
        }
    }
}

const EngineCallbacks detectorCallbacks = {
    .init  = detectorInit,
    .start = detectorStart,
    .stop  = detectorStop,
    .loop  = detectorLoop,
    .name  = "Detector"
};
