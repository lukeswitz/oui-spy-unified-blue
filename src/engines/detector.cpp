#include "detector.h"
#include "protocol.h"
#include "../ble_compat.h"
#include <WiFi.h>
#include <esp_wifi.h>
#include <Preferences.h>
#include <vector>

struct TargetFilter {
    char id[18];
    bool isFullMAC;
    char desc[32];
};

static std::vector<TargetFilter> filters;
static NimBLEScan* bleScan = nullptr;
static volatile bool scanning = false;
static unsigned long lastScanStart = 0;
static const unsigned long SCAN_INTERVAL_MS = 3000;
static const int SCAN_DURATION_S = 2;

// WiFi promiscuous — scan all 2.4GHz channels to maximize watchlist hit rate
static volatile bool wifiActive = false;
static const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
static const int channelCount = 14;
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 120;

#define DEDUP_SIZE 32
#define DEDUP_COOLDOWN_MS 3000
static struct { uint8_t mac[6]; unsigned long lastSeen; } dedup[DEDUP_SIZE];
static int dedupCount = 0;

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

static bool isDedupCooldown(const uint8_t* mac) {
    unsigned long now = millis();
    for (int i = 0; i < dedupCount; i++) {
        if (memcmp(dedup[i].mac, mac, 6) == 0) {
            if (now - dedup[i].lastSeen < DEDUP_COOLDOWN_MS) return true;
            dedup[i].lastSeen = now;
            return false;
        }
    }
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

static bool matchFilterBytes(const uint8_t* mac) {
    char macStr[18];
    snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    return matchFilter(macStr) != nullptr;
}

class DetectorCallback : public BLE_SCAN_CB_CLASS {
    BLE_SCAN_CB_ONRESULT(dev) {
        if (!scanning) return;
        std::string addrStr = dev->getAddress().toString();
        unsigned int m[6];
        sscanf(addrStr.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t mac[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                          (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};

        const TargetFilter* hit = matchFilter(addrStr.c_str());
        if (!hit) return;
        if (isDedupCooldown(mac)) return;

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_DETECTOR;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = 0;
        evt.ext.detector.is_full_mac = hit->isFullMAC ? 1 : 0;
        strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
        pushDetection(&evt);

        Serial.printf("[DETECTOR] BLE %s RSSI:%d [%s] %s\n",
                      addrStr.c_str(), dev->getRSSI(),
                      hit->isFullMAC ? "MAC" : "OUI", hit->desc);
    }
};

static DetectorCallback scanCb;

static void IRAM_ATTR wifiSnifferCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!scanning || !wifiActive) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    const uint8_t* addr2 = &p[10];
    if (!matchFilterBytes(addr2)) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, addr2, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    pushDetectionFromISR(&evt);
}

// Exported: check a MAC from wardrive's BLE callback
void detectorCheckBleDevice(const uint8_t* mac, int rssi) {
    if (!scanning) return;
    char macStr[18];
    snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x",
             mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
    const TargetFilter* hit = matchFilter(macStr);
    if (!hit) return;
    if (isDedupCooldown(mac)) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.channel = 0;
    evt.timestamp_ms = millis();
    evt.method = 0;
    evt.ext.detector.is_full_mac = hit->isFullMAC ? 1 : 0;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetection(&evt);

    Serial.printf("[DETECTOR] BLE %s RSSI:%d [%s] %s (via wardrive)\n",
                  macStr, rssi, hit->isFullMAC ? "MAC" : "OUI", hit->desc);
}

static void detectorInit(void) {
    loadFilters();
    dedupCount = 0;
    Serial.println("[DETECTOR] Initialized");
}

static void detectorStart(void) {
    scanning = true;

    // If wardrive owns the BLE scan, go passive for BLE
    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);

    if (!wardriveOwns) {
        bleScan = NimBLEDevice::getScan();
        bleScanSetCallbacks(bleScan, &scanCb);
        bleScan->setActiveScan(true);
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

    // WiFi promiscuous only when wardrive doesn't own WiFi
    if (!wardriveOwns) {
        WiFi.mode(WIFI_STA);
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wifiSnifferCb);
        esp_wifi_set_channel(channels[0], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        wifiActive = true;
    }

    Serial.printf("[DETECTOR] Started (%s)\n", wardriveOwns ? "passive — wardrive feeds" : "WiFi+BLE");
}

static void detectorStop(void) {
    scanning = false;

    if (wifiActive) {
        wifiActive = false;
        esp_wifi_set_promiscuous_rx_cb(NULL);
        esp_wifi_set_promiscuous(false);
        WiFi.disconnect(true);
        WiFi.mode(WIFI_OFF);
    }

    if (engineGetState(ENGINE_WARDRIVE) == ESTATE_DISABLED) {
        if (bleScan && bleScan->isScanning()) bleScan->stop();
        if (bleScan) bleScanClearCallbacks(bleScan);
    }
    bleScan = nullptr;

    Serial.println("[DETECTOR] Stopped");
}

static void detectorLoop(void) {
    if (!scanning) return;

    // Passive when wardrive active
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;

    if (wifiActive && millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % channelCount;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
    }

    if (bleScan && millis() - lastScanStart >= SCAN_INTERVAL_MS) {
        if (!bleScan->isScanning()) {
            bleScan->start(SCAN_DURATION_S, false);
            lastScanStart = millis();
        }
    }
}

const EngineCallbacks detectorCallbacks = {
    .init   = detectorInit,
    .start  = detectorStart,
    .stop   = detectorStop,
    .loop   = detectorLoop,
    .config = NULL,
    .name   = "Detector"
};
