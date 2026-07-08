#include "detector.h"
#include "protocol.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"
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

struct UuidFilter {
    uint16_t uuid;
    NimBLEUUID nim;
    char desc[32];
};

static TargetFilter filters[50];
static int filterCount = 0;
static UuidFilter uuidFilters[50];
static int uuidFilterCount = 0;
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
static DedupRingISR<32, 3000> wifiDedupISR;
static DedupRing<32, 10000> sigDedup;
static DedupRingISR<32, 8000> probeDedup;

static volatile unsigned long deauthWindowStart = 0;
static volatile uint16_t deauthCount = 0;
static volatile unsigned long lastDeauthAlert = 0;
static const uint16_t DEAUTH_THRESHOLD = 10;
static const unsigned long DEAUTH_ALERT_COOLDOWN_MS = 10000;
static volatile unsigned long lastPwnAlert = 0;
static uint8_t sigMask = 0;

static void detectorStart(void);
static void detectorStop(void);

static const TargetFilter* matchFilterBytes(const uint8_t* mac) {
    for (int i = 0; i < filterCount; i++) {
        if (memcmp(mac, filters[i].macBytes, filters[i].prefixLen) == 0) {
            return &filters[i];
        }
    }
    return nullptr;
}

static const UuidFilter* matchUuidFilter(NimBLEAdvertisedDevice* dev) {
    if (uuidFilterCount == 0) return nullptr;
    if (!dev->haveServiceUUID()) return nullptr;
    int n = dev->getServiceUUIDCount();
    for (int i = 0; i < n; i++) {
        NimBLEUUID u = dev->getServiceUUID(i);
        for (int j = 0; j < uuidFilterCount; j++) {
            if (u.equals(uuidFilters[j].nim)) return &uuidFilters[j];
        }
    }
    return nullptr;
}

struct FindMyTrack {
    uint8_t  mac[6];
    uint32_t firstMs;
    uint32_t lastMs;
    uint16_t hits;
    bool     alerted;
};
static FindMyTrack fmTracks[16];
static const uint32_t FM_PERSIST_MS = 3000;
static const uint16_t FM_MIN_HITS   = 3;
static const uint32_t FM_STALE_MS   = 120000;

static void findMyObserve(const uint8_t* mac, int rssi) {
    uint32_t now = millis();
    int slot = -1, freeSlot = -1, oldest = -1;
    uint32_t oldestMs = 0xFFFFFFFF;
    for (int i = 0; i < 16; i++) {
        if (fmTracks[i].hits == 0) { if (freeSlot < 0) freeSlot = i; continue; }
        if (now - fmTracks[i].lastMs > FM_STALE_MS) {
            fmTracks[i].hits = 0;
            if (freeSlot < 0) freeSlot = i;
            continue;
        }
        if (memcmp(fmTracks[i].mac, mac, 6) == 0) { slot = i; break; }
        if (fmTracks[i].lastMs < oldestMs) { oldestMs = fmTracks[i].lastMs; oldest = i; }
    }
    if (slot < 0) {
        slot = (freeSlot >= 0) ? freeSlot : oldest;
        if (slot < 0) return;
        memcpy(fmTracks[slot].mac, mac, 6);
        fmTracks[slot].firstMs = now;
        fmTracks[slot].hits = 0;
        fmTracks[slot].alerted = false;
    }
    fmTracks[slot].lastMs = now;
    if (fmTracks[slot].hits < 0xFFFF) fmTracks[slot].hits++;

    if (!fmTracks[slot].alerted && fmTracks[slot].hits >= FM_MIN_HITS &&
        (now - fmTracks[slot].firstMs) >= FM_PERSIST_MS) {
        fmTracks[slot].alerted = true;
        uint32_t secs = (now - fmTracks[slot].firstMs) / 1000;
        DetectionEvent evt = {};
        evt.engine_id = ENGINE_DETECTOR;
        memcpy(evt.mac, mac, 6);
        evt.rssi = rssi;
        evt.timestamp_ms = now;
        evt.method = METHOD_DET_TRACKER;
        snprintf(evt.ext.detector.filter_desc, sizeof(evt.ext.detector.filter_desc),
                 "Find My tracker following %lus", (unsigned long)secs);
        pushDetection(&evt);
        Serial.printf("[DETECTOR] STALKER Find My %02x:%02x:%02x:%02x:%02x:%02x following %lus\n",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], (unsigned long)secs);
    }
}

static void detectorCheckSignatures(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi) {
    if (dev->haveManufacturerData()) {
        std::string md = dev->getManufacturerData();
#ifdef OUISPY_FM_DEBUG
        if (md.size() >= 4 && (uint8_t)md[0] == 0x4C && (uint8_t)md[1] == 0x00 &&
            ((uint8_t)md[2] == 0x12 || (uint8_t)md[2] == 0x07)) {
            Serial.printf("[FM-DBG] %02x:%02x:%02x:%02x:%02x:%02x type=0x%02x len=0x%02x size=%u rssi=%d sig=0x%02x\n",
                mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                (uint8_t)md[2], (uint8_t)md[3], (unsigned)md.size(), rssi, sigMask);
        }
#endif
        if (md.size() >= 24 && (uint8_t)md[0] == 0x4C && (uint8_t)md[1] == 0x00 &&
            (uint8_t)md[2] == 0x12 && (uint8_t)md[3] == 0x19) {
            if (sigMask & SIG_TRACKER) findMyObserve(mac, rssi);
            return;
        }
    }
    if (sigMask & SIG_FLIPPER) {
        bool flip = dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3081)) ||
                    dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3082)) ||
                    dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3083));
        if (flip) {
            if (sigDedup.check(mac)) return;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = METHOD_DET_FLIPPER;
            strncpy(evt.ext.detector.filter_desc, "Flipper Zero",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetection(&evt);
            Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [Flipper Zero]\n",
                          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi);
        }
    }
    if (sigMask & SIG_GLASSES) {
        bool metaMfg = false;
        if (dev->haveManufacturerData()) {
            std::string gm = dev->getManufacturerData();
            if (gm.size() >= 2) {
                uint16_t cid = (uint16_t)((uint8_t)gm[0] | ((uint8_t)gm[1] << 8));
                metaMfg = (cid == 0x01AB || cid == 0x058E || cid == 0x0D53);
            }
        }
        bool metaSvc = dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFD5F)) ||
                       dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFEB7)) ||
                       dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFEB8));
        if (metaMfg || metaSvc) {
            if (sigDedup.check(mac)) return;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = METHOD_DET_GLASSES;
            strncpy(evt.ext.detector.filter_desc, "Meta smart glasses",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetection(&evt);
            Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [Meta glasses]\n",
                          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi);
        }
    }
}

class DetectorCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        if (!scanning) return;
        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);
        detectorCheckSignatures(dev, mac, dev->getRSSI());

        const TargetFilter* hit = matchFilterBytes(mac);
        if (!hit) { detectorCheckBleUuid(dev, mac, dev->getRSSI()); return; }
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

    uint8_t fctl = p[0];
    if ((sigMask & SIG_DEAUTH) && (fctl == 0xC0 || fctl == 0xA0)) {
        unsigned long now = millis();
        if (now - deauthWindowStart > 1000) { deauthWindowStart = now; deauthCount = 0; }
        if (deauthCount < 0xFFFF) deauthCount++;
        if (deauthCount >= DEAUTH_THRESHOLD && now - lastDeauthAlert > DEAUTH_ALERT_COOLDOWN_MS) {
            lastDeauthAlert = now;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, &p[10], 6);
            evt.rssi = pkt->rx_ctrl.rssi;
            evt.channel = pkt->rx_ctrl.channel;
            evt.timestamp_ms = now;
            evt.method = METHOD_DET_DEAUTH;
            strncpy(evt.ext.detector.filter_desc, "Deauth/Disassoc storm",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetectionFromISR(&evt);
        }
        return;
    }

    if ((sigMask & SIG_PROBE) && fctl == 0x40) {
        if (len >= 28 && p[24] == 0x00) {
            uint8_t ssidLen = p[25];
            if (ssidLen > 0 && ssidLen <= 32 && 26 + ssidLen <= len) {
                const uint8_t* src = &p[10];
                if (!probeDedup.check(src)) {
                    DetectionEvent evt = {};
                    evt.engine_id = ENGINE_DETECTOR;
                    memcpy(evt.mac, src, 6);
                    evt.rssi = pkt->rx_ctrl.rssi;
                    evt.channel = pkt->rx_ctrl.channel;
                    evt.timestamp_ms = millis();
                    evt.method = METHOD_DET_PROBE;
                    uint8_t n = ssidLen < 31 ? ssidLen : 31;
                    memcpy(evt.ext.detector.filter_desc, &p[26], n);
                    evt.ext.detector.filter_desc[n] = 0;
                    pushDetectionFromISR(&evt);
                }
            }
        }
        return;
    }

    static const uint8_t pwnMac[6] = {0xde, 0xad, 0xbe, 0xef, 0xde, 0xad};
    if ((sigMask & SIG_PWNAGOTCHI) && fctl == 0x80 && memcmp(&p[10], pwnMac, 6) == 0) {
        unsigned long now = millis();
        if (now - lastPwnAlert > 15000) {
            lastPwnAlert = now;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, &p[10], 6);
            evt.rssi = pkt->rx_ctrl.rssi;
            evt.channel = pkt->rx_ctrl.channel;
            evt.timestamp_ms = now;
            evt.method = METHOD_DET_PWNAGOTCHI;
            strncpy(evt.ext.detector.filter_desc, "Pwnagotchi",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetectionFromISR(&evt);
        }
        return;
    }

    const uint8_t* addr2 = &p[10];
    const TargetFilter* hit = matchFilterBytes(addr2);
    if (!hit) return;
    if (wifiDedupISR.check(addr2)) return;

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

void detectorCheckBleUuid(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi) {
    if (!scanning) return;
    const UuidFilter* hit = matchUuidFilter(dev);
    if (!hit) return;
    if (dedup.check(mac)) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.timestamp_ms = millis();
    evt.ext.detector.is_full_mac = 0;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetection(&evt);

    Serial.printf("[DETECTOR] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [UUID:%04X] %s\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                  rssi, hit->uuid, hit->desc);
}

void IRAM_ATTR detectorCheckWifiDeviceISR(const uint8_t* mac, int rssi, uint8_t channel) {
    if (!scanning) return;
    const TargetFilter* hit = matchFilterBytes(mac);
    if (!hit) return;
    if (wifiDedupISR.check(mac)) return;

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
    uuidFilterCount = 0;
    Serial.println("[DETECTOR] Filters cleared");
}

void detectorAddUuidFilter(uint16_t uuid, const char* desc) {
    if (uuidFilterCount >= 50) return;
    UuidFilter f = {};
    f.uuid = uuid;
    f.nim = NimBLEUUID(uuid);
    if (desc) strncpy(f.desc, desc, sizeof(f.desc) - 1);
    uuidFilters[uuidFilterCount++] = f;
    Serial.printf("[DETECTOR] +uuid filter 0x%04X desc=%s (total=%d)\n",
                  uuid, f.desc, uuidFilterCount);
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

const char* detectorLookupDesc(const uint8_t* mac) {
    if (!mac) return "";
    const TargetFilter* f = matchFilterBytes(mac);
    return f ? f->desc : "";
}

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

    if (off + 1 <= maxLen) {
        size_t ucntPos = off++;
        uint8_t ucnt = 0;
        for (int i = 0; i < uuidFilterCount; i++) {
            if (off + 2 > maxLen) break;
            out[off++] = uuidFilters[i].uuid & 0xFF;
            out[off++] = (uuidFilters[i].uuid >> 8) & 0xFF;
            ucnt++;
        }
        out[ucntPos] = ucnt;
    }
    return off;
}

void detectorSetFilters(const uint8_t* data, size_t len) {
    if (data == nullptr || len < 1) return;
    static uint8_t lastFilters[512]; static size_t lastFilterLen = 0; static bool haveFilters = false;
    if (haveFilters && len == lastFilterLen && len <= sizeof(lastFilters) && memcmp(lastFilters, data, len) == 0) return;
    if (len <= sizeof(lastFilters)) { memcpy(lastFilters, data, len); lastFilterLen = len; haveFilters = true; }
    detectorClearFilters();
    uint8_t cnt = data[0];
    size_t off = 1;
    for (uint8_t i = 0; i < cnt; i++) {
        if (off + 7 > len) break;
        uint8_t prefixLen = data[off];
        detectorAddFilter(data + off + 1, prefixLen, "");
        off += 7;
    }
    if (off < len) {
        uint8_t ucnt = data[off++];
        for (uint8_t i = 0; i < ucnt; i++) {
            if (off + 2 > len) break;
            uint16_t uuid = data[off] | (data[off + 1] << 8);
            detectorAddUuidFilter(uuid, "");
            off += 2;
        }
    }
    Serial.printf("[CFG] Detector watchlist: %u mac + %u uuid filters sig=0x%02X\n",
                  detectorFilterCount(), uuidFilterCount, sigMask);
}

void detectorSetSigMask(uint8_t mask) {
    const uint8_t wifiBits = SIG_DEAUTH | SIG_PROBE | SIG_PWNAGOTCHI;
    bool prevWifi = (sigMask & wifiBits) != 0;
    sigMask = mask;
    bool newWifi = (sigMask & wifiBits) != 0;
    if (scanning && prevWifi != newWifi &&
        engineGetState(ENGINE_WARDRIVE) == ESTATE_DISABLED) {
        detectorStop();
        detectorStart();
    }
}
uint8_t detectorGetSigMask(void) { return sigMask; }

bool detectorUsesWifi(void) {
    return (detectorRadioMask & 0x01) != 0 &&
           (sigMask & (SIG_DEAUTH | SIG_PROBE | SIG_PWNAGOTCHI)) != 0;
}

static void detectorInit(void) {
    dedup.reset();
    wifiDedupISR.reset();
    Serial.printf("[DETECTOR] Initialized (preserved filters=%d)\n", filterCount);
}

static void detectorStart(void) {
    scanning = true;
    dedup.setCooldownMs(engineGetRediscoverMs());
    wifiDedupISR.setCooldownMs(engineGetRediscoverMs());
    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);
    bool wantBle  = (detectorRadioMask & 0x02) != 0;
    bool wantWifi = (detectorRadioMask & 0x01) != 0 &&
                    (sigMask & (SIG_DEAUTH | SIG_PROBE | SIG_PWNAGOTCHI)) != 0;

    if (!wardriveOwns && wantBle) {
        bleScan = NimBLEDevice::getScan();
        bleCoexRegister(&scanCb, true);
        bleScan->setActiveScan(true);
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

    if (!wardriveOwns && wantWifi) {
        if (!meshIsEnabled()) {
            WiFi.mode(WIFI_STA);
        }
        wifiSnifferApplyPs();
        wifiCoexRegister(wifiSnifferCb, WIFI_PROMIS_FILTER_MASK_MGMT);
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
    const char* self = meshGetLocalNodeId();
    if (!cfgTgtStrip(&payload, &len, self)) return;
    if (len < 1) return;
    uint8_t mask = payload[0] & 0x03;
    if (mask == 0) mask = 0x03;
    uint8_t prev = detectorRadioMask;
    detectorRadioMask = mask;
    Serial.printf("[DETECTOR] Config radio mask=0x%02x\n", detectorRadioMask);
    if (scanning && mask != prev) {
        Serial.printf("[DETECTOR] radio 0x%02x->0x%02x while running — restart\n", prev, mask);
        detectorStop();
        detectorStart();
    }
}

static void detectorStop(void) {
    scanning = false;

    if (wifiActive) {
        wifiActive = false;
        wifiCoexUnregister(wifiSnifferCb);
        if (meshIsEnabled()) {
            WiFi.disconnect(false, false);
            esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
        } else {
            WiFi.disconnect(true);
            WiFi.mode(WIFI_OFF);
        }
    }

    bleCoexUnregister(&scanCb);
    bleScan = nullptr;

    Serial.println("[DETECTOR] Stopped");
}

void detectorHostSuspend(bool suspend) {
    if (suspend) {
        wifiCoexUnregister(wifiSnifferCb);
        bleCoexUnregister(&scanCb);
    } else if (scanning) {
        if (detectorRadioMask & 0x02) {
            bleScan = NimBLEDevice::getScan();
            bleCoexRegister(&scanCb, true);
        }
        if ((detectorRadioMask & 0x01) &&
            (sigMask & (SIG_DEAUTH | SIG_PROBE | SIG_PWNAGOTCHI))) {
            if (!meshIsEnabled()) WiFi.mode(WIFI_STA);
            wifiSnifferApplyPs();
            wifiCoexRegister(wifiSnifferCb, WIFI_PROMIS_FILTER_MASK_MGMT);
        }
    }
}

static void detectorLoop(void) {
    if (meshIsEnabled() && (meshInMeshWindow() || meshInRidWindow())) return;
    if (!scanning) return;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;

    if (wifiActive && wifiCoexShouldHop(ENGINE_DETECTOR) &&
        millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % channelCount;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        if (meshIsEnabled() && channels[channelIdx] == 1) meshNoteOnHome();
    }

    if (detectorRadioMask & 0x02) bleCoexEnsureScanning();
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
