#include "detector.h"
#include "protocol.h"
#include "dedup_ring.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <Preferences.h>

struct TargetFilter {
    uint8_t macBytes[6];
    uint8_t prefixLen;
    char desc[32];
};

static TargetFilter filters[50];
static int filterCount = 0;
static NimBLEScan* bleScan = nullptr;
static volatile bool scanning = false;
static unsigned long lastScanStart = 0;
static const unsigned long SCAN_INTERVAL_MS = 3000;
static const int SCAN_DURATION_S = 2;

static volatile bool wifiActive = false;
static const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
static const int channelCount = 14;
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 120;

static DedupRing<32, 3000> dedup;

static void parseHexMac(const char* str, uint8_t* out, uint8_t* outLen) {
    uint8_t buf[6] = {};
    int n = 0;
    const char* p = str;
    while (*p && n < 6) {
        char hi = *p++;
        if (hi == ':' || hi == '-' || hi == '.') continue;
        char lo = *p ? *p++ : '0';
        uint8_t val = 0;
        if (hi >= '0' && hi <= '9') val = (hi - '0') << 4;
        else if (hi >= 'a' && hi <= 'f') val = (hi - 'a' + 10) << 4;
        else if (hi >= 'A' && hi <= 'F') val = (hi - 'A' + 10) << 4;
        if (lo >= '0' && lo <= '9') val |= (lo - '0');
        else if (lo >= 'a' && lo <= 'f') val |= (lo - 'a' + 10);
        else if (lo >= 'A' && lo <= 'F') val |= (lo - 'A' + 10);
        buf[n++] = val;
    }
    memcpy(out, buf, 6);
    *outLen = (uint8_t)n;
}

static void loadFilters() {
    Preferences p;
    p.begin("ouispy", true);
    int count = p.getInt("filterCount", 0);
    filterCount = 0;
    for (int i = 0; i < count && i < 50; i++) {
        char key[16];
        snprintf(key, sizeof(key), "id_%d", i);
        String id = p.getString(key, "");
        if (id.length() == 0) continue;

        snprintf(key, sizeof(key), "mac_%d", i);
        bool isFullMAC = p.getBool(key, false);

        TargetFilter f = {};
        parseHexMac(id.c_str(), f.macBytes, &f.prefixLen);
        if (!isFullMAC && f.prefixLen > 3) f.prefixLen = 3;

        snprintf(key, sizeof(key), "desc_%d", i);
        String desc = p.getString(key, "");
        strncpy(f.desc, desc.c_str(), sizeof(f.desc) - 1);

        filters[filterCount++] = f;
    }
    p.end();
    Serial.printf("[DETECTOR] Loaded %d filters\n", filterCount);
}

static const TargetFilter* matchFilterBytes(const uint8_t* mac) {
    for (int i = 0; i < filterCount; i++) {
        if (memcmp(mac, filters[i].macBytes, filters[i].prefixLen) == 0) {
            return &filters[i];
        }
    }
    return nullptr;
}

class DetectorCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        if (!scanning) return;
        uint8_t mac[6];
        memcpy(mac, dev->getAddress().getNative(), 6);

        const TargetFilter* hit = matchFilterBytes(mac);
        if (!hit) return;
        if (dedup.check(mac)) return;

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_DETECTOR;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.timestamp_ms = millis();
        evt.ext.detector.is_full_mac = (hit->prefixLen == 6) ? 1 : 0;
        strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
        pushDetection(&evt);

        Serial.printf("[DETECTOR] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [%s] %s\n",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                      dev->getRSSI(),
                      hit->prefixLen == 6 ? "MAC" : "OUI", hit->desc);
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
    const TargetFilter* hit = matchFilterBytes(addr2);
    if (!hit) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, addr2, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    pushDetectionFromISR(&evt);
}

void detectorCheckBleDevice(const uint8_t* mac, int rssi) {
    if (!scanning) return;
    const TargetFilter* hit = matchFilterBytes(mac);
    if (!hit) return;
    if (dedup.check(mac)) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.timestamp_ms = millis();
    evt.ext.detector.is_full_mac = (hit->prefixLen == 6) ? 1 : 0;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetection(&evt);

    Serial.printf("[DETECTOR] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [%s] %s (via wardrive)\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                  rssi, hit->prefixLen == 6 ? "MAC" : "OUI", hit->desc);
}

static void detectorInit(void) {
    loadFilters();
    dedup.reset();
    Serial.println("[DETECTOR] Initialized");
}

static void detectorStart(void) {
    scanning = true;
    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);

    if (!wardriveOwns) {
        bleScan = NimBLEDevice::getScan();
        bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
        bleScan->setActiveScan(true);
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

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
        if (bleScan) bleScan->setAdvertisedDeviceCallbacks(nullptr, false);
    }
    bleScan = nullptr;

    Serial.println("[DETECTOR] Stopped");
}

static void detectorLoop(void) {
    if (!scanning) return;
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
