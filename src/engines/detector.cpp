#include "detector.h"
#include "protocol.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"
#include "dedup_ring.h"
#include "camera_oui.h"
#include "wifi_auth.h"
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
#ifdef OUISPY_DUAL_BAND
static const uint8_t channels[] = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14,
    36, 40, 44, 48, 149, 153, 157, 161, 165
};
#else
static const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
#endif
static const int channelCount = sizeof(channels) / sizeof(channels[0]);
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 120;

static DedupRing<32, 3000> dedup;
static DedupRingISR<32, 3000> wifiDedupISR;
static DedupRing<32, 10000> sigDedup;
static DedupRingISR<32, 8000> probeDedup;
static DedupRingISR<16, 8000> axonDedupISR;
static DedupRingISR<32, 8000> cameraDedupISR;

static const uint8_t AXON_OUI[3] = {0x00, 0x25, 0xdf};

struct LeVendorOui { uint8_t b[3]; const char* desc; };
static const LeVendorOui LE_VENDOR_OUIS[] = {
    {{0x00, 0x00, 0xC3}, "Harris radio"},
    {{0x00, 0x04, 0x7D}, "Motorola Solutions"},
    {{0x00, 0x06, 0xEC}, "Harris radio"},
    {{0x00, 0x0D, 0x4F}, "Kenwood radio"},
    {{0x00, 0x0D, 0xCA}, "Tait radio"},
    {{0x00, 0x17, 0xF3}, "Harris radio"},
    {{0x00, 0x18, 0x85}, "Motorola Solutions"},
    {{0x00, 0x1D, 0x96}, "WatchGuard Video"},
    {{0x00, 0x1F, 0x92}, "Motorola Solutions"},
    {{0x00, 0x23, 0xBD}, "Digital Ally"},
    {{0x10, 0x74, 0x6F}, "Motorola Solutions"},
    {{0x38, 0x1D, 0x14}, "Skydio drone"},
    {{0x4C, 0xCC, 0x34}, "Motorola Solutions"},
    {{0x64, 0x69, 0xBC}, "Hytera radio"},
    {{0x9C, 0x06, 0x6E}, "Hytera radio"},
    {{0x9C, 0x86, 0x2B}, "Motorola Solutions"},
    {{0xB8, 0xE2, 0x8C}, "Motorola Solutions"},
    {{0xE0, 0xDA, 0xDC}, "Kenwood radio"},
};

static const char* IRAM_ATTR leVendorForMac(const uint8_t* mac) {
    for (const auto& v : LE_VENDOR_OUIS) {
        if (mac[0] == v.b[0] && mac[1] == v.b[1] && mac[2] == v.b[2]) return v.desc;
    }
    return nullptr;
}

struct DeauthSender { uint8_t mac[6]; uint32_t windowStart; uint16_t count; uint32_t lastAlert; };
static const int DEAUTH_SENDER_SLOTS = 8;
static DeauthSender deauthSenders[DEAUTH_SENDER_SLOTS];
static const uint16_t DEAUTH_THRESHOLD = 10;
static const unsigned long DEAUTH_ALERT_COOLDOWN_MS = 10000;
static volatile unsigned long lastPwnAlert = 0;
static uint16_t sigMask = 0;

struct SsidOwner { uint32_t hash; uint8_t bssid[6]; uint32_t lastMs; bool alerted; uint8_t auth; };
struct BssidSsids { uint8_t bssid[6]; uint32_t hashes[8]; uint8_t n; uint32_t lastMs; bool alerted; };
static const int SSID_OWNER_SLOTS = 48;
static const int BSSID_SSID_SLOTS = 24;
static SsidOwner* ssidOwners = nullptr;
static BssidSsids* bssidSsids = nullptr;
static const uint32_t AP_STALE_MS = 300000;
static const uint8_t KARMA_MIN_SSIDS = 5;

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

static const char* const TRACKER_FAMILY[] = {"Find My", "SmartTag", "Tile", "Google Find Hub"};
enum { TRK_APPLE = 0, TRK_SAMSUNG, TRK_TILE, TRK_GOOGLE };

struct FindMyTrack {
    uint8_t  mac[6];
    uint32_t firstMs;
    uint32_t lastMs;
    uint16_t hits;
    uint8_t  windows;
    uint8_t  family;
    uint8_t  alertedTier;
};
static FindMyTrack fmTracks[24];
static const uint32_t FM_PERSIST_MS      = 3000;
static const uint16_t FM_MIN_HITS        = 3;
static const uint32_t FM_FOLLOW_MS       = 300000;
static const uint32_t FM_GAP_MS          = 60000;
static const uint8_t  FM_RETURN_WINDOWS  = 3;
static const uint32_t FM_RETURN_SPAN_MS  = 600000;
static const uint32_t FM_STALE_MS        = 1800000;

static uint32_t fmClockMillis(void) { return millis(); }
static uint32_t (*fmClock)(void) = fmClockMillis;

static void findMyObserve(const uint8_t* mac, int rssi, uint8_t family) {
    uint32_t now = fmClock();
    const int n = sizeof(fmTracks) / sizeof(fmTracks[0]);
    int slot = -1, freeSlot = -1, oldest = -1;
    uint32_t oldestMs = 0xFFFFFFFF;
    for (int i = 0; i < n; i++) {
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
        fmTracks[slot].windows = 1;
        fmTracks[slot].alertedTier = DET_CONF_NONE;
    } else if (now - fmTracks[slot].lastMs > FM_GAP_MS && fmTracks[slot].windows < 0xFF) {
        fmTracks[slot].windows++;
    }
    FindMyTrack& t = fmTracks[slot];
    t.family = family;
    t.lastMs = now;
    if (t.hits < 0xFFFF) t.hits++;
    if (t.hits < FM_MIN_HITS) return;

    uint32_t span = now - t.firstMs;
    uint8_t tier = DET_CONF_NONE;
    if (t.windows >= FM_RETURN_WINDOWS && span >= FM_RETURN_SPAN_MS) tier = DET_CONF_VERIFIED;
    else if (span >= FM_FOLLOW_MS) tier = DET_CONF_HIGH;
    else if (span >= FM_PERSIST_MS) tier = DET_CONF_SUSPECTED;
    if (tier <= t.alertedTier) return;
    t.alertedTier = tier;

    const char* fam = TRACKER_FAMILY[family < 4 ? family : 0];
    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.timestamp_ms = now;
    evt.method = METHOD_DET_TRACKER;
    evt.ext.detector.confidence = tier;
    if (tier == DET_CONF_VERIFIED) {
        snprintf(evt.ext.detector.filter_desc, sizeof(evt.ext.detector.filter_desc),
                 "%s returned %ux in %lum", fam, (unsigned)t.windows, (unsigned long)(span / 60000));
    } else if (tier == DET_CONF_HIGH) {
        snprintf(evt.ext.detector.filter_desc, sizeof(evt.ext.detector.filter_desc),
                 "%s following %lum", fam, (unsigned long)(span / 60000));
    } else {
        snprintf(evt.ext.detector.filter_desc, sizeof(evt.ext.detector.filter_desc),
                 "%s tracker nearby %lus", fam, (unsigned long)(span / 1000));
    }
    pushDetection(&evt);
    Serial.printf("[DETECTOR] STALKER %s %02x:%02x:%02x:%02x:%02x:%02x tier=%u span=%lus windows=%u\n",
                  fam, mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], (unsigned)tier,
                  (unsigned long)(span / 1000), (unsigned)t.windows);
}

static bool appleFindMySeparated(const std::string& md) {
    if (md.size() < 4 || (uint8_t)md[0] != 0x4C || (uint8_t)md[1] != 0x00) return false;
    size_t i = 2;
    while (i + 2 <= md.size()) {
        uint8_t type = (uint8_t)md[i];
        uint8_t len = (uint8_t)md[i + 1];
        if (i + 2 + len > md.size()) return false;
        if (type == 0x12 && len == 0x19) return true;
        i += 2 + len;
    }
    return false;
}

static int otherTrackerFamily(NimBLEAdvertisedDevice* dev) {
    if (!dev->haveServiceData()) return -1;
    std::string s = dev->getServiceData(NimBLEUUID((uint16_t)0xFD5A));
    if (s.size() >= 1 && ((uint8_t)s[0] & 0xF8) == 0x10) return TRK_SAMSUNG;
    s = dev->getServiceData(NimBLEUUID((uint16_t)0xFEED));
    if (s.size() >= 2 && (uint8_t)s[0] == 0x02 && (uint8_t)s[1] == 0x00) return TRK_TILE;
    if (!dev->getServiceData(NimBLEUUID((uint16_t)0xFEEC)).empty()) return TRK_TILE;
    if (!dev->getServiceData(NimBLEUUID((uint16_t)0xFD84)).empty()) return TRK_TILE;
    s = dev->getServiceData(NimBLEUUID((uint16_t)0xFEAA));
    if (s.size() >= 1 && ((uint8_t)s[0] == 0x40 || (uint8_t)s[0] == 0x41)) return TRK_GOOGLE;
    return -1;
}

static void pushSig(const uint8_t* mac, int rssi, uint8_t method, uint8_t conf, const char* desc) {
    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.timestamp_ms = millis();
    evt.method = method;
    evt.ext.detector.confidence = conf;
    strncpy(evt.ext.detector.filter_desc, desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetection(&evt);
    Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d conf=%u [%s]\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi, (unsigned)conf, desc);
}

static void detectorCheckSignatures(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi) {
#ifdef OUISPY_SIG_DEBUG
    {
        std::string dbgName = dev->getName();
        Serial.printf("[SIG-DBG] %02x:%02x:%02x:%02x:%02x:%02x rssi=%d name='%s'",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi,
                      dbgName.c_str());
        if (dev->haveManufacturerData()) {
            std::string dm = dev->getManufacturerData();
            if (dm.size() >= 2) {
                Serial.printf(" cid=0x%04X mlen=%u",
                              (unsigned)((uint8_t)dm[0] | ((uint8_t)dm[1] << 8)),
                              (unsigned)dm.size());
            }
        }
        if (dev->haveServiceUUID()) {
            int un = dev->getServiceUUIDCount();
            for (int i = 0; i < un; i++) {
                Serial.printf(" svc=%s", dev->getServiceUUID(i).toString().c_str());
            }
        }
        Serial.printf(" sig=0x%03X\n", (unsigned)sigMask);
    }
#endif
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
        if (appleFindMySeparated(md)) {
            if (sigMask & SIG_TRACKER) findMyObserve(mac, rssi, TRK_APPLE);
            return;
        }
    }
    if (sigMask & SIG_TRACKER) {
        int fam = otherTrackerFamily(dev);
        if (fam >= 0) {
            findMyObserve(mac, rssi, (uint8_t)fam);
            return;
        }
    }
    if (sigMask & SIG_MESH) {
        static const NimBLEUUID MESHTASTIC_SVC("6ba1b218-15a8-461f-9fa8-5dcae273eafd");
        const char* kind = nullptr;
        uint8_t conf = DET_CONF_NONE;
        if (dev->isAdvertisingService(MESHTASTIC_SVC)) {
            kind = "Meshtastic node";
            conf = DET_CONF_VERIFIED;
        } else if (dev->haveName()) {
            std::string nm = dev->getName();
            if (strcasestr(nm.c_str(), "meshtastic")) { kind = "Meshtastic node"; conf = DET_CONF_HIGH; }
            else if (strcasestr(nm.c_str(), "meshcore")) { kind = "MeshCore node"; conf = DET_CONF_HIGH; }
        }
        if (kind && !sigDedup.check(mac)) pushSig(mac, rssi, METHOD_DET_MESH, conf, kind);
    }
    if (sigMask & SIG_FLIPPER) {
        bool flip = dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3081)) ||
                    dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3082)) ||
                    dev->isAdvertisingService(NimBLEUUID((uint16_t)0x3083));
        if (flip && !sigDedup.check(mac)) {
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = METHOD_DET_FLIPPER;
            evt.ext.detector.confidence = DET_CONF_HIGH;
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
                metaMfg = (cid == 0x0D53);
            }
        }
        bool metaSvc = dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFD5F));
        bool metaName = false;
        if (dev->haveName()) {
            std::string nm = dev->getName();
            metaName = nm.find("Ray-Ban") != std::string::npos ||
                       nm.find("Wayfarer") != std::string::npos ||
                       nm.find("Oakley Meta") != std::string::npos;
        }
        static const uint8_t META_OUIS[][3] = {
            {0x98, 0x59, 0x49}, {0x80, 0xAA, 0x1C}, {0x38, 0x47, 0x12}};
        bool metaMac = false;
        for (const auto& oui : META_OUIS) {
            if (memcmp(mac, oui, 3) == 0) { metaMac = true; break; }
        }
        if ((metaMfg || metaSvc || metaName || metaMac) && !sigDedup.check(mac)) {
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = METHOD_DET_GLASSES;
            int sigs = (int)metaMfg + (int)metaSvc + (int)metaName + (int)metaMac;
            evt.ext.detector.confidence = sigs >= 2 ? DET_CONF_VERIFIED
                                        : metaMac ? DET_CONF_SUSPECTED : DET_CONF_HIGH;
            strncpy(evt.ext.detector.filter_desc, "Meta smart glasses",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetection(&evt);
            Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [Meta glasses]\n",
                          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi);
        }
    }
    if (sigMask & SIG_AXON) {
        bool axonMfg = false;
        if (dev->haveManufacturerData()) {
            std::string am = dev->getManufacturerData();
            if (am.size() >= 2) {
                uint16_t cid = (uint16_t)((uint8_t)am[0] | ((uint8_t)am[1] << 8));
                axonMfg = (cid == 0x034D);
            }
        }
        bool axonSvc = dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFC81)) ||
                       dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFE6B)) ||
                       dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFE6C));
        bool axonMac = (memcmp(mac, AXON_OUI, 3) == 0);
        if ((axonMac || axonMfg || axonSvc) && !sigDedup.check(mac)) {
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = METHOD_DET_AXON;
            evt.ext.detector.confidence = (axonMac && (axonMfg || axonSvc)) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
            strncpy(evt.ext.detector.filter_desc, "Axon (Law Enforcement)",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetection(&evt);
            Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [Axon LE]\n",
                          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi);
        } else if (!(axonMac || axonMfg || axonSvc)) {
            const char* le = leVendorForMac(mac);
            if (le && !sigDedup.check(mac)) pushSig(mac, rssi, METHOD_DET_AXON, DET_CONF_SUSPECTED, le);
        }
    }
    if (sigMask & SIG_CAMERA) {
        int brand = cameraBrandForMac(mac);
        bool amazonMfg = false;
        if (dev->haveManufacturerData()) {
            std::string zm = dev->getManufacturerData();
            if (zm.size() >= 2) {
                uint16_t cid = (uint16_t)((uint8_t)zm[0] | ((uint8_t)zm[1] << 8));
                amazonMfg = (cid == 0x0171);
            }
        }
        bool sidewalkSvc = dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFE03));
        bool amazonSvc = dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFE00)) ||
                         dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFE15)) ||
                         dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFCDC)) ||
                         dev->isAdvertisingService(NimBLEUUID((uint16_t)0xFD41));
        bool isCamera = brand >= 0 && brand < CAMERA_BRAND_COUNT;
        bool isAmazon = amazonMfg || sidewalkSvc || amazonSvc;
        if ((isCamera || isAmazon) && !sigDedup.check(mac)) {
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, mac, 6);
            evt.rssi = rssi;
            evt.timestamp_ms = millis();
            evt.method = isCamera ? METHOD_DET_CAMERA : METHOD_DET_AMAZON;
            evt.ext.detector.confidence = (isCamera && isAmazon) ? DET_CONF_VERIFIED
                                        : isAmazon ? DET_CONF_HIGH : DET_CONF_SUSPECTED;
            const char* desc = isCamera ? CAMERA_BRANDS[brand]
                             : (sidewalkSvc || amazonMfg) ? "Amazon Sidewalk" : "Amazon";
            strncpy(evt.ext.detector.filter_desc, desc, sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetection(&evt);
            Serial.printf("[DETECTOR] SIG %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [%s]\n",
                          mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], rssi, desc);
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
        evt.ext.detector.confidence = (hit->prefixLen == 6) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
        strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
        pushDetection(&evt);

        Serial.printf("[DETECTOR] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [%s] %s\n",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                      dev->getRSSI(),
                      hit->prefixLen == 6 ? "MAC" : "OUI", hit->desc);
    }
};

static DetectorCallback scanCb;

static void IRAM_ATTR detectorCameraFrameISR(const uint8_t* p, int rssi, uint8_t channel) {
    const uint8_t* a1 = &p[4];
    const uint8_t* a2 = &p[10];
    const uint8_t* cam = a2;
    int brand = cameraBrandForMac(a2);
    if (brand < 0 && !(a1[0] & 0x01)) {
        cam = a1;
        brand = cameraBrandForMac(a1);
    }
    if (brand < 0 || brand >= CAMERA_BRAND_COUNT || cameraDedupISR.check(cam)) return;
    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, cam, 6);
    evt.rssi = rssi;
    evt.channel = channel;
    evt.timestamp_ms = millis();
    evt.method = METHOD_DET_CAMERA;
    evt.ext.detector.confidence = DET_CONF_SUSPECTED;
    strncpy(evt.ext.detector.filter_desc, CAMERA_BRANDS[brand],
            sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetectionFromISR(&evt);
}

static inline bool IRAM_ATTR sameApVendor(const uint8_t* a, const uint8_t* b) {
    if ((a[0] & 0xFD) == (b[0] & 0xFD) && a[1] == b[1] && a[2] == b[2]) return true;
    return a[3] == b[3] && a[4] == b[4];
}

static void IRAM_ATTR pushApSigISR(const uint8_t* bssid, int rssi, uint8_t channel,
                                   uint8_t method, uint8_t conf, const char* desc) {
    DetectionEvent evt = {};
    evt.engine_id = ENGINE_DETECTOR;
    memcpy(evt.mac, bssid, 6);
    evt.rssi = rssi;
    evt.channel = channel;
    evt.timestamp_ms = millis();
    evt.method = method;
    evt.ext.detector.confidence = conf;
    strncpy(evt.ext.detector.filter_desc, desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetectionFromISR(&evt);
}

static void IRAM_ATTR detectorRogueApISR(const uint8_t* p, int len, int rssi, uint8_t channel) {
    if (!ssidOwners || !bssidSsids) return;
    if (len < 38 || p[36] != 0x00) return;
    uint8_t slen = p[37];
    if (slen == 0 || slen > 32 || 38 + slen > len) return;
    const uint8_t* ssid = &p[38];
    bool allZero = true;
    uint32_t h = 2166136261u;
    for (uint8_t i = 0; i < slen; i++) {
        if (ssid[i]) allZero = false;
        h = (h ^ ssid[i]) * 16777619u;
    }
    if (allZero) return;
    if (h == 0) h = 1;
    const uint8_t* bssid = &p[16];
    uint32_t now = millis();

    int freeSlot = -1;
    bool known = false;
    for (int oi = 0; oi < SSID_OWNER_SLOTS; oi++) {
        SsidOwner& o = ssidOwners[oi];
        if (o.hash != 0 && now - o.lastMs > AP_STALE_MS) o.hash = 0;
        if (o.hash == 0) { if (freeSlot < 0) freeSlot = oi; continue; }
        if (o.hash != h) continue;
        known = true;
        if (memcmp(o.bssid, bssid, 6) == 0) { o.lastMs = now; break; }
        if (!o.alerted) {
            const uint8_t twinAuth = wifiAuthFromMgmt(p, len);
            const bool downgrade = (o.auth >= AUTHC_WPA) != (twinAuth >= AUTHC_WPA);
            if (downgrade || !sameApVendor(o.bssid, bssid)) {
                o.alerted = true;
                char desc[32];
                uint8_t n = slen < 18 ? slen : 18;
                int k = 0;
                for (uint8_t i = 0; i < n; i++) desc[k++] = (ssid[i] >= 0x20 && ssid[i] < 0x7F) ? (char)ssid[i] : '?';
                desc[k] = 0;
                strncat(desc, downgrade ? " open twin" : " twin BSSID", sizeof(desc) - strlen(desc) - 1);
                const uint8_t* report = downgrade && twinAuth >= AUTHC_WPA ? o.bssid : bssid;
                pushApSigISR(report, rssi, channel, METHOD_DET_EVILTWIN,
                             downgrade ? DET_CONF_HIGH : DET_CONF_SUSPECTED, desc);
            }
        }
        break;
    }
    if (!known && freeSlot >= 0) {
        SsidOwner& o = ssidOwners[freeSlot];
        o.hash = h;
        memcpy(o.bssid, bssid, 6);
        o.lastMs = now;
        o.alerted = false;
        o.auth = wifiAuthFromMgmt(p, len);
    }

    int bFree = -1;
    for (int bi = 0; bi < BSSID_SSID_SLOTS; bi++) {
        BssidSsids& b = bssidSsids[bi];
        if (b.n != 0 && now - b.lastMs > AP_STALE_MS) b.n = 0;
        if (b.n == 0) { if (bFree < 0) bFree = bi; continue; }
        if (memcmp(b.bssid, bssid, 6) != 0) continue;
        b.lastMs = now;
        for (uint8_t k = 0; k < b.n; k++) if (b.hashes[k] == h) return;
        if (b.n < 8) b.hashes[b.n++] = h;
        if (b.n >= KARMA_MIN_SSIDS && !b.alerted) {
            b.alerted = true;
            pushApSigISR(bssid, rssi, channel, METHOD_DET_KARMA, DET_CONF_HIGH, "KARMA AP: many SSIDs, 1 BSSID");
        }
        return;
    }
    if (bFree >= 0) {
        BssidSsids& b = bssidSsids[bFree];
        memcpy(b.bssid, bssid, 6);
        b.hashes[0] = h;
        b.n = 1;
        b.lastMs = now;
        b.alerted = false;
    }
}

static bool IRAM_ATTR detectorSigFrameISR(const uint8_t* p, int len, int rssi, uint8_t channel) {
    uint8_t fctl = p[0];
    if (sigMask & SIG_CAMERA) detectorCameraFrameISR(p, rssi, channel);
    if ((sigMask & SIG_DEAUTH) && (fctl == 0xC0 || fctl == 0xA0)) {
        if (len < 26) return true;
        unsigned long now = millis();
        const uint8_t* tx = &p[10];
        int slot = -1, oldest = 0;
        for (int i = 0; i < DEAUTH_SENDER_SLOTS; i++) {
            if (memcmp(deauthSenders[i].mac, tx, 6) == 0) { slot = i; break; }
            if (deauthSenders[i].windowStart < deauthSenders[oldest].windowStart) oldest = i;
        }
        if (slot < 0) {
            slot = oldest;
            memcpy(deauthSenders[slot].mac, tx, 6);
            deauthSenders[slot].windowStart = now;
            deauthSenders[slot].count = 0;
            deauthSenders[slot].lastAlert = 0;
        }
        DeauthSender& s = deauthSenders[slot];
        if (now - s.windowStart > 1000) { s.windowStart = now; s.count = 0; }
        if (s.count < 0xFFFF) s.count++;
        if (s.count >= DEAUTH_THRESHOLD && (s.lastAlert == 0 || now - s.lastAlert > DEAUTH_ALERT_COOLDOWN_MS)) {
            s.lastAlert = now;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, tx, 6);
            evt.rssi = rssi;
            evt.channel = channel;
            evt.timestamp_ms = now;
            evt.method = METHOD_DET_DEAUTH;
            evt.ext.detector.confidence = DET_CONF_HIGH;
            strncpy(evt.ext.detector.filter_desc, "Deauth/Disassoc storm",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetectionFromISR(&evt);
        }
        return true;
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
                    evt.rssi = rssi;
                    evt.channel = channel;
                    evt.timestamp_ms = millis();
                    evt.method = METHOD_DET_PROBE;
                    evt.ext.detector.confidence = DET_CONF_SUSPECTED;
                    uint8_t n = ssidLen < 31 ? ssidLen : 31;
                    uint8_t k = 0;
                    for (uint8_t i = 0; i < n; i++) {
                        uint8_t c = p[26 + i];
                        if (c >= 0x20 && c < 0x7F) evt.ext.detector.filter_desc[k++] = (char)c;
                    }
                    evt.ext.detector.filter_desc[k] = 0;
                    if (k > 0) pushDetectionFromISR(&evt);
                }
            }
        }
        return true;
    }

    if ((sigMask & SIG_PROBE) && fctl == 0x80) detectorRogueApISR(p, len, rssi, channel);

    static const uint8_t pwnMac[6] = {0xde, 0xad, 0xbe, 0xef, 0xde, 0xad};
    if ((sigMask & SIG_PWNAGOTCHI) && fctl == 0x80 && memcmp(&p[10], pwnMac, 6) == 0) {
        unsigned long now = millis();
        if (now - lastPwnAlert > 15000) {
            lastPwnAlert = now;
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_DETECTOR;
            memcpy(evt.mac, &p[10], 6);
            evt.rssi = rssi;
            evt.channel = channel;
            evt.timestamp_ms = now;
            evt.method = METHOD_DET_PWNAGOTCHI;
            evt.ext.detector.confidence = DET_CONF_HIGH;
            strncpy(evt.ext.detector.filter_desc, "Pwnagotchi",
                    sizeof(evt.ext.detector.filter_desc) - 1);
            pushDetectionFromISR(&evt);
        }
        return true;
    }

    if (sigMask & SIG_AXON) {
        const uint8_t* src = &p[10];
        if (memcmp(src, AXON_OUI, 3) == 0) {
            if (!axonDedupISR.check(src)) {
                DetectionEvent evt = {};
                evt.engine_id = ENGINE_DETECTOR;
                memcpy(evt.mac, src, 6);
                evt.rssi = rssi;
                evt.channel = channel;
                evt.timestamp_ms = millis();
                evt.method = METHOD_DET_AXON;
                evt.ext.detector.confidence = DET_CONF_HIGH;
                strncpy(evt.ext.detector.filter_desc, "Axon (Law Enforcement)",
                        sizeof(evt.ext.detector.filter_desc) - 1);
                pushDetectionFromISR(&evt);
            }
            return true;
        }
        const char* le = leVendorForMac(src);
        if (le) {
            if (!axonDedupISR.check(src)) pushApSigISR(src, rssi, channel, METHOD_DET_AXON, DET_CONF_SUSPECTED, le);
            return true;
        }
    }

    return false;
}

void IRAM_ATTR detectorCheckWifiSignaturesISR(const uint8_t* payload, int len, int rssi,
                                              uint8_t channel) {
    if (!scanning || sigMask == 0 || payload == nullptr || len < 24) return;
    detectorSigFrameISR(payload, len, rssi, channel);
}

static void IRAM_ATTR wifiSnifferCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    g_engRawSeen++;
    if (!scanning || !wifiActive) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = (int)pkt->rx_ctrl.sig_len - 4;
    if (len < 24) return;

    if (detectorSigFrameISR(p, len, pkt->rx_ctrl.rssi, pkt->rx_ctrl.channel)) return;

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
    evt.method = METHOD_DET_WIFI_WATCH;
    evt.ext.detector.is_full_mac = (hit->prefixLen == 6) ? 1 : 0;
    evt.ext.detector.confidence = (hit->prefixLen == 6) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
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
    evt.ext.detector.confidence = (hit->prefixLen == 6) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
    strncpy(evt.ext.detector.filter_desc, hit->desc, sizeof(evt.ext.detector.filter_desc) - 1);
    pushDetection(&evt);

    Serial.printf("[DETECTOR] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d [%s] %s (via wardrive)\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                  rssi, hit->prefixLen == 6 ? "MAC" : "OUI", hit->desc);
}

void detectorCheckBleSignatures(NimBLEAdvertisedDevice* dev, const uint8_t* mac, int rssi) {
    if (!scanning || sigMask == 0 || dev == nullptr) return;
    detectorCheckSignatures(dev, mac, rssi);
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
    evt.ext.detector.confidence = DET_CONF_HIGH;
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
    evt.ext.detector.confidence = (hit->prefixLen == 6) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
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
    Serial.printf("[CFG] Detector watchlist: %u mac + %u uuid filters sig=0x%03X\n",
                  detectorFilterCount(), uuidFilterCount, (unsigned)sigMask);
}

static const uint16_t DETECTOR_WIFI_SIGS = SIG_DEAUTH | SIG_PROBE | SIG_PWNAGOTCHI | SIG_AXON | SIG_CAMERA;

static uint32_t detectorWifiFilter(void) {
    return (sigMask & SIG_CAMERA) ? (WIFI_PROMIS_FILTER_MASK_MGMT | WIFI_PROMIS_FILTER_MASK_DATA)
                                  : WIFI_PROMIS_FILTER_MASK_MGMT;
}

void detectorSetSigMask(uint16_t mask) {
    bool prevWifi = (sigMask & DETECTOR_WIFI_SIGS) != 0;
    uint32_t prevFilter = detectorWifiFilter();
    sigMask = mask;
    bool newWifi = (sigMask & DETECTOR_WIFI_SIGS) != 0;
    if (scanning && engineGetState(ENGINE_WARDRIVE) == ESTATE_DISABLED) {
        if (prevWifi != newWifi) {
            detectorStop();
            detectorStart();
        } else if (wifiActive && prevFilter != detectorWifiFilter()) {
            wifiCoexRegister(wifiSnifferCb, detectorWifiFilter());
        }
    }
}
uint16_t detectorGetSigMask(void) { return sigMask; }

bool detectorUsesWifi(void) {
    return (detectorRadioMask & 0x01) != 0 &&
           (sigMask & DETECTOR_WIFI_SIGS) != 0;
}

static void detectorInit(void) {
    dedup.reset();
    wifiDedupISR.reset();
    Serial.printf("[DETECTOR] Initialized (preserved filters=%d)\n", filterCount);
}

static void detectorStart(void) {
    if (!ssidOwners) ssidOwners = (SsidOwner*)calloc(SSID_OWNER_SLOTS, sizeof(SsidOwner));
    if (!bssidSsids) bssidSsids = (BssidSsids*)calloc(BSSID_SSID_SLOTS, sizeof(BssidSsids));
    scanning = true;
    dedup.setCooldownMs(engineGetRediscoverMs());
    wifiDedupISR.setCooldownMs(engineGetRediscoverMs());
    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);
    bool wantBle  = (detectorRadioMask & 0x02) != 0;
    bool wantWifi = (detectorRadioMask & 0x01) != 0 &&
                    (sigMask & DETECTOR_WIFI_SIGS) != 0;

    if (!wardriveOwns && wantBle) {
        bleScan = NimBLEDevice::getScan();
        bleCoexRegister(&scanCb, true);
        bleScan->setActiveScan(bleCoexActiveScanAllowed());
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

    if (!wardriveOwns && wantWifi) {
        if (!meshIsEnabled()) {
            WiFi.mode(WIFI_STA);
        }
        wifiSnifferApplyPs();
        wifiApplyRegdomain();
        wifiCoexRegister(wifiSnifferCb, detectorWifiFilter());
        channelIdx = 0;
        while (channelIdx < channelCount - 1 && !wifiChanEnabled(channels[channelIdx])) channelIdx++;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
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
        if (meshIsEnabled() || wifiCoexActive() || wifiRadioExternallyOwned()) {
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
            (sigMask & DETECTOR_WIFI_SIGS)) {
            if (!meshIsEnabled()) WiFi.mode(WIFI_STA);
            wifiSnifferApplyPs();
            wifiCoexRegister(wifiSnifferCb, detectorWifiFilter());
            wifiActive = true;
        }
    }
}

static void detectorLoop(void) {
    if (meshIsEnabled() && (meshInMeshWindow() || meshInRidWindow())) return;
    if (!scanning) return;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;

    if (wifiActive && wifiCoexShouldHop(ENGINE_DETECTOR) &&
        millis() - lastChannelHop >= DWELL_MS) {
        int guard = 0;
        do {
            channelIdx = (channelIdx + 1) % channelCount;
        } while (!wifiChanEnabled(channels[channelIdx]) && ++guard < channelCount);
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

#ifdef OUISPY_PORT_SELFTEST
static uint32_t pstNow = 0;
static uint32_t pstClock(void) { return pstNow; }

static int pstFail = 0;
static void pstCheck(const char* name, bool ok, const char* detail = "") {
    Serial.printf("[PST] detector.%s %s %s\n", name, ok ? "PASS" : "FAIL", detail);
    if (!ok) pstFail++;
}

static bool pstPop(DetectionEvent* e) { return xQueueReceive(detectionQueue, e, 0) == pdTRUE; }

static void pstDrain(void) { DetectionEvent e; while (pstPop(&e)) {} }

static int pstBeacon(uint8_t* f, const uint8_t bssid[6], const char* ssid) {
    memset(f, 0, 80);
    f[0] = 0x80;
    memcpy(&f[10], bssid, 6);
    memcpy(&f[16], bssid, 6);
    uint8_t n = (uint8_t)strlen(ssid);
    f[36] = 0x00;
    f[37] = n;
    memcpy(&f[38], ssid, n);
    return 38 + n + 4;
}

int detectorPortSelfTest(void) {
    pstFail = 0;
    uint16_t savedMask = sigMask;
    DetectionEvent e;

    std::string md = std::string("\x4c\x00\x10\x02\x01\x02\x12\x19", 8) + std::string(25, '\x01');
    pstCheck("tlv_second_record", appleFindMySeparated(md));
    pstCheck("tlv_nearby_only", !appleFindMySeparated(std::string("\x4c\x00\x10\x02\x01\x02", 6)));
    pstCheck("tlv_truncated", !appleFindMySeparated(std::string("\x4c\x00\x12\x19\x01\x02", 6)));

    sigMask = SIG_TRACKER;
    pstDrain();
    fmClock = pstClock;
    memset(fmTracks, 0, sizeof(fmTracks));
    const uint8_t tag[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01};
    pstNow = 100000; findMyObserve(tag, -60, TRK_SAMSUNG);
    pstNow = 101000; findMyObserve(tag, -60, TRK_SAMSUNG);
    pstNow = 103500; findMyObserve(tag, -60, TRK_SAMSUNG);
    bool s1 = pstPop(&e) && e.ext.detector.confidence == DET_CONF_SUSPECTED && strncmp(e.ext.detector.filter_desc, "SmartTag", 8) == 0;
    pstCheck("tracker_nearby_suspected", s1, e.ext.detector.filter_desc);
    pstNow = 401000; findMyObserve(tag, -60, TRK_SAMSUNG);
    bool s2 = pstPop(&e) && e.ext.detector.confidence == DET_CONF_HIGH;
    pstCheck("tracker_following_high", s2, e.ext.detector.filter_desc);
    pstNow = 470000; findMyObserve(tag, -60, TRK_SAMSUNG);
    pstNow = 710000; findMyObserve(tag, -60, TRK_SAMSUNG);
    bool s3 = pstPop(&e) && e.ext.detector.confidence == DET_CONF_VERIFIED;
    pstCheck("tracker_returning_verified", s3, e.ext.detector.filter_desc);
    pstCheck("tracker_one_alert_per_tier", !pstPop(&e));
    fmClock = fmClockMillis;

    const uint8_t moto[6] = {0x00, 0x04, 0x7D, 0x11, 0x22, 0x33};
    const uint8_t rnd[6] = {0x02, 0x11, 0x22, 0x33, 0x44, 0x55};
    pstCheck("le_vendor_motorola", leVendorForMac(moto) != nullptr);
    pstCheck("le_vendor_none", leVendorForMac(rnd) == nullptr);

    if (!ssidOwners) ssidOwners = (SsidOwner*)calloc(SSID_OWNER_SLOTS, sizeof(SsidOwner));
    if (!bssidSsids) bssidSsids = (BssidSsids*)calloc(BSSID_SSID_SLOTS, sizeof(BssidSsids));
    memset(ssidOwners, 0, SSID_OWNER_SLOTS * sizeof(SsidOwner));
    memset(bssidSsids, 0, BSSID_SSID_SLOTS * sizeof(BssidSsids));
    sigMask = SIG_PROBE;
    pstDrain();
    uint8_t f[80];
    const uint8_t ap1[6] = {0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x01};
    const uint8_t ap2[6] = {0x11, 0x22, 0x33, 0x44, 0x55, 0x66};
    int n = pstBeacon(f, ap1, "MyNetwork"); detectorSigFrameISR(f, n, -50, 6);
    n = pstBeacon(f, ap2, "MyNetwork"); detectorSigFrameISR(f, n, -50, 6);
    bool twin = pstPop(&e) && e.method == METHOD_DET_EVILTWIN && e.ext.detector.confidence == DET_CONF_SUSPECTED &&
                memcmp(e.mac, ap2, 6) == 0;
    pstCheck("evil_twin_other_vendor", twin, e.ext.detector.filter_desc);
    const uint8_t ap3[6] = {0xAA, 0xBB, 0xCC, 0x00, 0x00, 0x02};
    const uint8_t ap4[6] = {0xAA, 0xBB, 0xCC, 0x09, 0x09, 0x09};
    n = pstBeacon(f, ap3, "Office"); detectorSigFrameISR(f, n, -50, 6);
    n = pstBeacon(f, ap4, "Office"); detectorSigFrameISR(f, n, -50, 6);
    pstCheck("no_twin_same_vendor", !pstPop(&e));
    const uint8_t karma[6] = {0x66, 0x77, 0x88, 0x99, 0xAA, 0xBB};
    const char* names[] = {"A1", "B2", "C3", "D4", "E5"};
    for (const char* s : names) { n = pstBeacon(f, karma, s); detectorSigFrameISR(f, n, -50, 6); }
    bool k = pstPop(&e) && e.method == METHOD_DET_KARMA && e.ext.detector.confidence == DET_CONF_HIGH;
    pstCheck("karma_five_ssids", k, e.ext.detector.filter_desc);

    memset(f, 0, sizeof(f));
    f[0] = 0x40;
    const uint8_t prober[6] = {0x02, 0x55, 0x55, 0x55, 0x55, 0x01};
    memcpy(&f[10], prober, 6);
    const uint8_t raw[] = {'A', 'b', 0x01, 'c', 0xFF, 'D'};
    f[24] = 0x00; f[25] = sizeof(raw); memcpy(&f[26], raw, sizeof(raw));
    detectorSigFrameISR(f, 26 + sizeof(raw) + 4, -60, 1);
    bool pr = pstPop(&e) && e.method == METHOD_DET_PROBE && strcmp(e.ext.detector.filter_desc, "AbcD") == 0;
    pstCheck("probe_ssid_ascii_only", pr, e.ext.detector.filter_desc);

    detectorSetSigMask(SIG_ALL);
    pstCheck("sigmask_9bit", detectorGetSigMask() == 0x1FF);

    pstDrain();
    detectorSetSigMask(savedMask);
    return pstFail;
}
#endif
