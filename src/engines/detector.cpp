#include "detector.h"
#include "protocol.h"
#include "../mesh_espnow.h"
#include "dedup_ring.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <WiFi.h>
#include <esp_wifi.h>

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
static uint8_t detectorRadioMask = 0x03;
static const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
static const int channelCount = 14;
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 120;

static DedupRing<32, 3000> dedup;

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
        g_engRawSeen++;
        if (!scanning) return;
        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);

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
    g_engRawSeen++;
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

void IRAM_ATTR detectorCheckWifiDeviceISR(const uint8_t* mac, int rssi, uint8_t channel) {
    if (!scanning) return;
    const TargetFilter* hit = matchFilterBytes(mac);
    if (!hit) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.channel = channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    evt.ext.detector.is_full_mac = (hit->prefixLen == 6) ? 1 : 0;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetectionFromISR(&evt);
}

void detectorClearFilters(void) {
    filterCount = 0;
    Serial.println("[DETECTOR] Filters cleared");
}

void detectorAddFilter(const uint8_t* macBytes, uint8_t prefixLen, const char* desc) {
    if (filterCount >= 50) return;
    if (prefixLen == 0 || prefixLen > 6) return;
    TargetFilter f = {};
    memcpy(f.macBytes, macBytes, 6);
    f.prefixLen = prefixLen;
    if (desc) strncpy(f.desc, desc, sizeof(f.desc) - 1);
    filters[filterCount++] = f;
    Serial.printf("[DETECTOR] +filter %02x:%02x:%02x len=%u desc=%s (total=%d)\n",
                  macBytes[0], macBytes[1], macBytes[2], prefixLen,
                  f.desc, filterCount);
}

int detectorFilterCount(void) { return filterCount; }

size_t detectorSerialize(uint8_t* out, size_t maxLen) {
    if (out == nullptr || maxLen < 1) return 0;
    size_t off = 1;
    uint8_t cnt = 0;
    for (int i = 0; i < filterCount; i++) {
        if (off + 7 > maxLen) break;
        out[off++] = filters[i].prefixLen;
        memcpy(out + off, filters[i].macBytes, 6);
        off += 6;
        cnt++;
    }
    out[0] = cnt;
    return off;
}

void detectorSetFilters(const uint8_t* data, size_t len) {
    if (data == nullptr || len < 1) return;
    detectorClearFilters();
    uint8_t cnt = data[0];
    size_t off = 1;
    for (uint8_t i = 0; i < cnt; i++) {
        if (off + 7 > len) break;
        uint8_t prefixLen = data[off];
        detectorAddFilter(data + off + 1, prefixLen, "");
        off += 7;
    }
    Serial.printf("[CFG] Detector watchlist: %u filters\n", detectorFilterCount());
}

static void detectorInit(void) {
    dedup.reset();
    Serial.printf("[DETECTOR] Initialized (preserved filters=%d)\n", filterCount);
}

static void detectorStart(void) {
    scanning = true;
    dedup.setCooldownMs(engineGetRediscoverMs());
    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);
    bool wantBle  = (detectorRadioMask & 0x02) != 0;
    bool wantWifi = (detectorRadioMask & 0x01) != 0;

    if (!wardriveOwns && wantBle) {
        bleScan = NimBLEDevice::getScan();
        bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
        bleScan->setActiveScan(true);
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

    if (!wardriveOwns && wantWifi) {
        if (!meshIsEnabled()) {
            WiFi.mode(WIFI_STA);
        }
        wifi_promiscuous_filter_t filter = {
            .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT |
                           WIFI_PROMIS_FILTER_MASK_DATA
        };
        esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
        esp_wifi_set_promiscuous_filter(&filter);
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wifiSnifferCb);
        esp_wifi_set_channel(channels[0], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        wifiActive = true;
    }

    const char* mode = wardriveOwns ? "passive — wardrive feeds"
                     : (wantWifi && wantBle) ? "WiFi+BLE"
                     : wantWifi ? "WiFi only"
                     : wantBle  ? "BLE only" : "no radio";
    Serial.printf("[DETECTOR] Started (%s) filters=%d\n", mode, filterCount);
}

static void detectorConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    uint8_t mask = payload[0] & 0x03;
    if (mask == 0) mask = 0x03;
    detectorRadioMask = mask;
    Serial.printf("[DETECTOR] Config radio mask=0x%02x\n", detectorRadioMask);
}

static void detectorStop(void) {
    scanning = false;

    if (wifiActive) {
        wifiActive = false;
        esp_wifi_set_promiscuous_rx_cb(NULL);
        esp_wifi_set_promiscuous(false);
        if (meshIsEnabled()) {
            WiFi.disconnect(false, false);
            esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
        } else {
            WiFi.disconnect(true);
            WiFi.mode(WIFI_OFF);
        }
    }

    if (engineGetState(ENGINE_WARDRIVE) == ESTATE_DISABLED) {
        if (bleScan && bleScan->isScanning()) bleScan->stop();
        if (bleScan) bleScan->setAdvertisedDeviceCallbacks(nullptr, false);
    }
    bleScan = nullptr;

    Serial.println("[DETECTOR] Stopped");
}

static void detectorLoop(void) {
    if (meshIsEnabled() && meshInMeshWindow()) return;
    if (!scanning) return;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;

    if (wifiActive && millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % channelCount;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        if (meshIsEnabled() && channels[channelIdx] == 1) meshNoteOnHome();
    }

    if (bleScan && millis() - lastScanStart >= SCAN_INTERVAL_MS) {
        if (!bleScan->isScanning()) {
            bleScan->start(SCAN_DURATION_S, false);
            lastScanStart = millis();
        }
    }
}

static void detectorApplyPrefs(void) {
    dedup.setCooldownMs(engineGetRediscoverMs());
}

const EngineCallbacks detectorCallbacks = {
    .init       = detectorInit,
    .start      = detectorStart,
    .stop       = detectorStop,
    .loop       = detectorLoop,
    .config     = detectorConfig,
    .applyPrefs = detectorApplyPrefs,
    .name       = "Detector"
};
