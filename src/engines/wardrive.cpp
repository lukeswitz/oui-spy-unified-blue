#include "wardrive.h"
#include "../protocol.h"
#include "flock_oui.h"
#include "detector.h"
#include "foxhunter.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>

// ============================================================================
// BLE flock detection helpers (shared with BLE callback)
// ============================================================================

static const char* flockNamePatterns[] = {
    "FS Ext Battery", "Penguin", "Flock", "Pigvision"
};
static const int flockNamePatternCount = sizeof(flockNamePatterns) / sizeof(flockNamePatterns[0]);

static const uint16_t flockMfgIds[] = { 0x09C8 }; // XUNTONG
static const int flockMfgIdCount = sizeof(flockMfgIds) / sizeof(flockMfgIds[0]);

static const char* ravenUuids[] = {
    "0000180a-0000-1000-8000-00805f9b34fb",
    "00003100-0000-1000-8000-00805f9b34fb",
    "00003200-0000-1000-8000-00805f9b34fb",
    "00003300-0000-1000-8000-00805f9b34fb",
    "00003400-0000-1000-8000-00805f9b34fb",
    "00003500-0000-1000-8000-00805f9b34fb",
    "00001809-0000-1000-8000-00805f9b34fb",
    "00001819-0000-1000-8000-00805f9b34fb",
};
static const int ravenUuidCount = sizeof(ravenUuids) / sizeof(ravenUuids[0]);

static bool flockMatchName(const char* name) {
    if (!name || !name[0]) return false;
    for (int i = 0; i < flockNamePatternCount; i++) {
        if (strcasestr(name, flockNamePatterns[i])) return true;
    }
    return false;
}

static bool flockMatchMfgId(NimBLEAdvertisedDevice* dev) {
    if (!dev->haveManufacturerData()) return false;
    std::string data = dev->getManufacturerData();
    if (data.size() < 2) return false;
    uint16_t code = ((uint16_t)(uint8_t)data[1] << 8) | (uint16_t)(uint8_t)data[0];
    for (int i = 0; i < flockMfgIdCount; i++) {
        if (flockMfgIds[i] == code) return true;
    }
    return false;
}

static bool flockMatchRavenUuid(NimBLEAdvertisedDevice* dev) {
    if (!dev->haveServiceUUID()) return false;
    int count = dev->getServiceUUIDCount();
    for (int i = 0; i < count; i++) {
        std::string str = dev->getServiceUUID(i).toString();
        for (int j = 0; j < ravenUuidCount; j++) {
            if (strcasecmp(str.c_str(), ravenUuids[j]) == 0) return true;
        }
    }
    return false;
}

// ============================================================================
// Wildcard probe IE parser (shared logic with flock_wifi.cpp)
// ============================================================================

static int IRAM_ATTR isWildcardProbeIE(const uint8_t* body, int len) {
    if (!body || len < 2) return -1;
    while (len >= 2) {
        uint8_t id   = body[0];
        uint8_t elen = body[1];
        if ((int)elen + 2 > len) break;
        if (id == 0) return (elen == 0) ? 1 : 0;
        body += elen + 2;
        len  -= elen + 2;
    }
    return -1;
}

// ============================================================================
// State
// ============================================================================

static volatile bool wardriveActive = false;
static unsigned long lastBleScan = 0;
static volatile uint8_t wardriveRadio = 0x03;

// Channel hopping — configurable per-channel dwell
static uint8_t channelStart = 1;
static uint8_t channelEnd   = 14;
static uint8_t currentChannel = 1;
static unsigned long lastChannelHop = 0;

// Per-channel dwell: configurable base values, adaptive adjustment
static uint16_t priorityDwellMs = 350;  // base for ch 1, 6, 11
static uint16_t normalDwellMs   = 150;  // base for other channels

// Adaptive dwell — like Atomgps_wigler: channels with more traffic get more time
static uint16_t timePerChannel[14] = {
    350, 150, 150, 150, 150, 350, 150, 150, 150, 150, 350, 150, 150, 150
};
static volatile uint8_t beaconsThisHop = 0;  // count beacons on current channel

// BLE scan timing — conservative to avoid starving WiFi promisc on shared radio.
// ESP32 single 2.4GHz radio uses TDM: BLE active = WiFi capture drops 30-60%.
// 800ms scan every 3000ms = ~27% BLE duty (was 75% at 1500/2000).
static uint16_t bleScanDurationMs  = 800;
static uint16_t bleScanIntervalMs  = 3000;

// Dedup ring — shared by WiFi promisc + BLE callbacks.
// 512 entries handles dense urban (200+ BSSIDs per sweep) without premature eviction.
#define WARDRIVE_DEDUP_SIZE    512
#define WARDRIVE_DEDUP_COOL_MS 10000

static struct {
    uint8_t mac[6];
    unsigned long ts;
} wardriveDedup[WARDRIVE_DEDUP_SIZE];
static int wardriveDedupHead = 0;
static int wardriveDedupCount = 0;

static bool wardriveIsDedupCooldown(const uint8_t* mac) {
    unsigned long now = millis();
    for (int i = 0; i < wardriveDedupCount; i++) {
        if (memcmp(wardriveDedup[i].mac, mac, 6) == 0) {
            if (now - wardriveDedup[i].ts < WARDRIVE_DEDUP_COOL_MS) return true;
            wardriveDedup[i].ts = now;
            return false;
        }
    }
    int idx;
    if (wardriveDedupCount < WARDRIVE_DEDUP_SIZE) {
        idx = wardriveDedupCount++;
    } else {
        idx = wardriveDedupHead;
        wardriveDedupHead = (wardriveDedupHead + 1) % WARDRIVE_DEDUP_SIZE;
    }
    memcpy(wardriveDedup[idx].mac, mac, 6);
    wardriveDedup[idx].ts = now;
    return false;
}

// ISR-safe flock dedup — separate from wardrive beacon dedup so flock cameras
// don't get suppressed by the 10s wardrive cooldown, but still avoids flooding
// the queue with every CTRL/DATA frame from the same camera.
#define FLOCK_WIFI_DEDUP_SIZE 16
#define FLOCK_WIFI_DEDUP_COOL_MS 5000
static struct {
    uint8_t mac[6];
    unsigned long ts;
} flockWifiDedup[FLOCK_WIFI_DEDUP_SIZE];
static int flockWifiDedupHead = 0;
static int flockWifiDedupCount = 0;

static bool IRAM_ATTR flockWifiIsDedupISR(const uint8_t* mac) {
    uint32_t now = millis();
    for (int i = 0; i < flockWifiDedupCount; i++) {
        if (memcmp(flockWifiDedup[i].mac, mac, 6) == 0) {
            if (now - flockWifiDedup[i].ts < FLOCK_WIFI_DEDUP_COOL_MS) return true;
            flockWifiDedup[i].ts = now;
            return false;
        }
    }
    int idx;
    if (flockWifiDedupCount < FLOCK_WIFI_DEDUP_SIZE) {
        idx = flockWifiDedupCount++;
    } else {
        idx = flockWifiDedupHead;
        flockWifiDedupHead = (flockWifiDedupHead + 1) % FLOCK_WIFI_DEDUP_SIZE;
    }
    memcpy(flockWifiDedup[idx].mac, mac, 6);
    flockWifiDedup[idx].ts = now;
    return false;
}

// ISR-safe dedup (separate ring to avoid contention with BLE callback)
static struct {
    uint8_t mac[6];
    unsigned long ts;
} wifiDedup[WARDRIVE_DEDUP_SIZE];
static int wifiDedupHead = 0;
static int wifiDedupCount = 0;

static bool IRAM_ATTR wifiIsDedupISR(const uint8_t* mac) {
    uint32_t now = millis();
    for (int i = 0; i < wifiDedupCount; i++) {
        if (memcmp(wifiDedup[i].mac, mac, 6) == 0) {
            if (now - wifiDedup[i].ts < WARDRIVE_DEDUP_COOL_MS) return true;
            wifiDedup[i].ts = now;
            return false;
        }
    }
    int idx;
    if (wifiDedupCount < WARDRIVE_DEDUP_SIZE) {
        idx = wifiDedupCount++;
    } else {
        idx = wifiDedupHead;
        wifiDedupHead = (wifiDedupHead + 1) % WARDRIVE_DEDUP_SIZE;
    }
    memcpy(wifiDedup[idx].mac, mac, 6);
    wifiDedup[idx].ts = now;
    return false;
}

static bool isPriorityChannel(uint8_t ch) {
    return ch == 1 || ch == 6 || ch == 11;
}

static uint16_t dwellForChannel(uint8_t ch) {
    if (ch >= 1 && ch <= 14) return timePerChannel[ch - 1];
    return isPriorityChannel(ch) ? priorityDwellMs : normalDwellMs;
}

// Adaptive: adjust dwell based on beacon count (like Atomgps_wigler)
static void updateAdaptiveDwell(uint8_t ch, uint8_t beaconCount) {
    if (ch < 1 || ch > 14) return;
    const uint16_t minDwell = 50;
    const uint16_t maxDwell = 500;
    const uint16_t step = 50;

    if (beaconCount >= 5) {
        timePerChannel[ch - 1] = min((int)(timePerChannel[ch - 1] + step), (int)maxDwell);
    } else if (beaconCount <= 1) {
        uint16_t floor = isPriorityChannel(ch) ? 200 : minDwell;
        timePerChannel[ch - 1] = max((int)(timePerChannel[ch - 1] - step), (int)floor);
    }
}

// ============================================================================
// Auth mode mapping from 802.11 RSN/WPA IE to our compact enum
// ============================================================================

// AKM suite selectors (OUI 00-0F-AC):
// 1 = 802.1X (WPA2-Enterprise)
// 2 = PSK (WPA2-Personal)
// 6 = SAE (WPA3-Personal)
// 8 = SAE (WPA3-Personal, FT)
// 12 = SAE-EXT (WPA3-Enterprise 192-bit)
#define AKM_OUI_00   0x00
#define AKM_OUI_0F   0x0F
#define AKM_OUI_AC   0xAC
#define AKM_SUITE_EAP     1
#define AKM_SUITE_PSK     2
#define AKM_SUITE_SAE     8
#define AKM_SUITE_FT_SAE  9
#define AKM_SUITE_SAE_EXT 12

static uint8_t IRAM_ATTR parseAuthFromFrame(const uint8_t* p, int len) {
    // Walk tagged parameters starting after fixed fields
    // Beacon: 24-byte header + 12 bytes fixed (timestamp[8]+interval[2]+capability[2])
    int offset = 36;
    bool hasRSN = false;
    bool hasWPA = false;
    bool hasWPA3 = false;
    bool hasEAP = false;

    while (offset + 2 <= len) {
        uint8_t tagId = p[offset];
        uint8_t tagLen = p[offset + 1];
        if (offset + 2 + tagLen > len) break;

        if (tagId == 48 && tagLen >= 2) {
            // RSN Information Element — parse AKM suite list
            hasRSN = true;
            // RSN IE: version[2] + group_cipher[4] + pairwise_count[2] + pairwise_suites[n*4] + akm_count[2] + akm_suites[n*4]
            int rsnOff = offset + 2;
            int rsnEnd = offset + 2 + tagLen;
            // Skip version (2 bytes)
            rsnOff += 2;
            if (rsnOff + 4 > rsnEnd) goto next_tag;
            // Skip group cipher suite (4 bytes)
            rsnOff += 4;
            if (rsnOff + 2 > rsnEnd) goto next_tag;
            // Pairwise cipher count + suites
            uint16_t pairCount = p[rsnOff] | (p[rsnOff + 1] << 8);
            rsnOff += 2 + pairCount * 4;
            if (rsnOff + 2 > rsnEnd) goto next_tag;
            // AKM suite count + suites
            uint16_t akmCount = p[rsnOff] | (p[rsnOff + 1] << 8);
            rsnOff += 2;
            for (uint16_t i = 0; i < akmCount && rsnOff + 4 <= rsnEnd; i++) {
                // AKM suite: OUI[3] + type[1]
                uint8_t akmType = p[rsnOff + 3];
                if (p[rsnOff] == 0x00 && p[rsnOff + 1] == 0x0F && p[rsnOff + 2] == 0xAC) {
                    if (akmType == 8 || akmType == 9 || akmType == 12) {
                        hasWPA3 = true;
                    }
                    if (akmType == 1 || akmType == 5) {
                        hasEAP = true;
                    }
                }
                rsnOff += 4;
            }
        }

        if (tagId == 221 && tagLen >= 4) {     // Vendor-specific (WPA1)
            if (p[offset+2]==0x00 && p[offset+3]==0x50 &&
                p[offset+4]==0xF2 && p[offset+5]==0x01) {
                hasWPA = true;
            }
        }

        next_tag:
        offset += 2 + tagLen;
    }

    if (hasWPA3)            return 6;  // WPA3
    if (hasEAP && hasRSN)   return 5;  // WPA2_ENT
    if (hasRSN && hasWPA)   return 4;  // WPA_WPA2
    if (hasRSN)             return 3;  // WPA2
    if (hasWPA)             return 2;  // WPA
    return 0;                           // Open
}

// ============================================================================
// Check if SSID bytes are all zeroes (hidden network variant: tagLen > 0 but null-filled)
// ============================================================================

static bool IRAM_ATTR isNullSsid(const uint8_t* ssidBytes, uint8_t ssidLen) {
    for (uint8_t i = 0; i < ssidLen; i++) {
        if (ssidBytes[i] != 0) return false;
    }
    return true;
}

// ============================================================================
// Wildcard probe request — stimulates APs to respond immediately on channel hop.
// GhostESP technique: send broadcast probe with empty SSID after each hop.
// APs respond with probe response instead of waiting for next beacon (102.4ms).
// ============================================================================

static const uint8_t wildcardProbeTemplate[] = {
    // Frame control: probe request (type 0, subtype 4)
    0x40, 0x00,
    // Duration
    0x00, 0x00,
    // Destination: broadcast
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    // Source: random (filled at runtime)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    // BSSID: broadcast
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    // Sequence number
    0x00, 0x00,
    // SSID parameter set: tag 0, length 0 (wildcard)
    0x00, 0x00,
    // Supported rates: 1, 2, 5.5, 11 Mbps
    0x01, 0x04, 0x82, 0x84, 0x8B, 0x96,
};

static void sendWildcardProbe(void) {
    uint8_t probe[sizeof(wildcardProbeTemplate)];
    memcpy(probe, wildcardProbeTemplate, sizeof(probe));
    // Randomize source MAC (locally administered)
    probe[10] = 0x02 | (esp_random() & 0xFE);
    for (int i = 11; i < 16; i++) {
        probe[i] = esp_random() & 0xFF;
    }
    esp_wifi_80211_tx(WIFI_IF_STA, probe, sizeof(probe), false);
}

// ============================================================================
// WiFi Promiscuous Callback — THE wardrive WiFi scanner.
// Pure promiscuous mode: catches beacons (SSID/auth for WiGLE), flock OUI
// frames, and foxhunter targets. No WiFi.scanNetworks() needed.
// ============================================================================

static void IRAM_ATTR wardriveWifiCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!wardriveActive) return;

    // Accept MGMT, DATA, and CTRL frames. Flock cameras appear as addr1
    // (destination) in frames from associated APs — these can be any type.
    // CTRL frames (ACK/CTS/RTS/BlockAck) may be short; len<24 check below
    // handles that. Standalone flock_wifi accepts all types and catches
    // cameras that were invisible when wardrive filtered to MGMT+DATA only.
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA && type != WIFI_PKT_CTRL) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    uint8_t frameType = (p[0] >> 2) & 0x03;
    uint8_t frameSubtype = (p[0] >> 4) & 0x0F;

    const uint8_t* addr1 = &p[4];   // destination
    const uint8_t* addr2 = &p[10];  // source/transmitter
    const uint8_t* addr3 = &p[16];  // BSSID

    // --- 1. Flock OUI check on all frames ---
    // check addr2/addr1/addr3 for OUI match.
    // Must run before beacon dedup so flock cameras get reported
    if (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED ||
        engineGetState(ENGINE_FLOCK_BLE) != ESTATE_DISABLED) {
        const uint8_t* flockMac = NULL;
        uint8_t flockMethod = 0xFF;

        if (flockMatchOuiISR(addr2)) {
            flockMac = addr2;
            flockMethod = METHOD_OUI_ADDR2;
            // Wildcard probe: Probe Request (type=0 subtype=4) with zero-length
            // SSID IE. Synced with flock_wifi.cpp DeFlockJoplin IE parser.
            if (frameType == 0 && frameSubtype == 4) {
                int bodyOff = 24;
                int bodyLen = len - bodyOff;
                const uint8_t* body = p + bodyOff;
                int r = (bodyLen > 0) ? isWildcardProbeIE(body, bodyLen) : -1;
                if (r == -1 && bodyLen > 4) r = isWildcardProbeIE(body, bodyLen - 4);
                if (r == 1) flockMethod = METHOD_WILDCARD_PROBE;
            }
        } else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
            flockMac = addr1;
            flockMethod = METHOD_OUI_ADDR1;
        } else if (frameType == 0 && flockMatchOuiISR(addr3)) {
            flockMac = addr3;
            flockMethod = METHOD_OUI_ADDR3;
        }

        if (flockMac != NULL && !flockWifiIsDedupISR(flockMac)) {
            DetectionEvent evt;
            memset(&evt, 0, sizeof(evt));
            evt.engine_id = ENGINE_FLOCK_WIFI;
            memcpy(evt.mac, flockMac, 6);
            evt.rssi = pkt->rx_ctrl.rssi;
            evt.channel = pkt->rx_ctrl.channel;
            evt.timestamp_ms = millis();
            evt.method = flockMethod;
            pushDetectionFromISR(&evt);
        }
    }

    // --- 2. Foxhunter target check on ALL frames ---
    if (engineGetState(ENGINE_FOXHUNTER) != ESTATE_DISABLED) {
        foxhunterCheckWifiDeviceISR(addr1, addr2, addr3,
                                     pkt->rx_ctrl.rssi,
                                     pkt->rx_ctrl.channel);
    }

    // --- 3. Beacon / Probe Response → wardrive AP capture (WiGLE data) ---
    if (frameType == 0 && (frameSubtype == 8 || frameSubtype == 5)) {
        if (wifiIsDedupISR(addr3)) return;  // dedup on BSSID

        int tagOffset = 36;
        char ssid[33] = {0};
        if (tagOffset + 2 <= len) {
            uint8_t tagId = p[tagOffset];
            uint8_t tagLen = p[tagOffset + 1];
            if (tagId == 0 && tagLen > 0 && tagLen <= 32 && tagOffset + 2 + tagLen <= len) {
                // Check for null-filled SSID (hidden network variant:
                // some APs broadcast tagLen=32 with all 0x00 bytes)
                if (!isNullSsid(&p[tagOffset + 2], tagLen)) {
                    memcpy(ssid, &p[tagOffset + 2], tagLen);
                    ssid[tagLen] = '\0';
                }
                // else: ssid stays empty — hidden network
            }
            // tagLen == 0: standard hidden network — ssid stays empty
        }

        uint8_t authMode = parseAuthFromFrame(p, len);
        beaconsThisHop++;

        DetectionEvent evt;
        memset(&evt, 0, sizeof(evt));
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, addr3, 6);
        evt.rssi = pkt->rx_ctrl.rssi;
        evt.channel = pkt->rx_ctrl.channel;
        evt.timestamp_ms = millis();
        evt.method = METHOD_WIFI_AP;
        memcpy(evt.ext.wardrive.ssid, ssid, 33);
        evt.ext.wardrive.auth_mode = authMode;
        memset(evt.ext.wardrive.device_name, 0, 21);
        pushDetectionFromISR(&evt);
    }
}

// ============================================================================
// BLE — timed scans via callback. NimBLE 1.4 API.
// ============================================================================

static NimBLEScan* pWardriveScan = nullptr;

class WardriveAdvCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        if (!wardriveActive) return;

        uint8_t mac[6];
        memcpy(mac, dev->getAddress().getNative(), 6);
        if (wardriveIsDedupCooldown(mac)) return;

        int rssi = dev->getRSSI();
        uint32_t now = millis();
        std::string name = dev->getName();

        // Flock detection FIRST — alertable events get queue priority over
        // passive wardrive collection. Only when any flock engine is active.
        if (engineGetState(ENGINE_FLOCK_BLE) != ESTATE_DISABLED ||
            engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED) {
            bool isFlock = false;
            uint8_t flockMethod = 0;
            bool isRaven = false;

            if (flockMatchOui(mac)) {
                isFlock = true;
                flockMethod = METHOD_OUI_MATCH;
            }
            if (!isFlock && name.length() > 0 && flockMatchName(name.c_str())) {
                isFlock = true;
                flockMethod = METHOD_NAME_MATCH;
            }
            if (!isFlock && flockMatchMfgId(dev)) {
                isFlock = true;
                flockMethod = METHOD_MFG_ID;
            }
            if (!isFlock && flockMatchRavenUuid(dev)) {
                isFlock = true;
                flockMethod = METHOD_RAVEN_UUID;
                isRaven = true;
            }

            if (isFlock) {
                DetectionEvent fEvt = {};
                fEvt.engine_id = ENGINE_FLOCK_BLE;
                memcpy(fEvt.mac, mac, 6);
                fEvt.rssi = rssi;
                fEvt.channel = 0;
                fEvt.timestamp_ms = now;
                fEvt.method = flockMethod;
                memset(fEvt.source_node_id, 0, MESH_NODE_ID_LEN);
                memset(&fEvt.ext, 0, sizeof(fEvt.ext));
                fEvt.ext.flock.is_raven = isRaven ? 1 : 0;
                memset(fEvt.ext.flock.raven_fw, 0, sizeof(fEvt.ext.flock.raven_fw));
                pushDetection(&fEvt);
            }
        }

        // Wardrive passive collection event
        DetectionEvent evt = {};
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, mac, 6);
        evt.rssi = rssi;
        evt.channel = 0;
        evt.timestamp_ms = now;
        evt.method = METHOD_BLE_ADV;
        memset(evt.source_node_id, 0, MESH_NODE_ID_LEN);
        memset(evt.ext.wardrive.ssid, 0, 33);
        evt.ext.wardrive.auth_mode = 0;
        strncpy(evt.ext.wardrive.device_name, name.c_str(), 20);
        evt.ext.wardrive.device_name[20] = '\0';
        pushDetection(&evt);

        // Dispatch to other active engines that went passive
        if (engineGetState(ENGINE_DETECTOR) != ESTATE_DISABLED) {
            detectorCheckBleDevice(mac, evt.rssi);
        }
        if (engineGetState(ENGINE_FOXHUNTER) != ESTATE_DISABLED) {
            foxhunterCheckBleDevice(mac, evt.rssi);
        }
    }
};

static void wardriveBleOnComplete(NimBLEScanResults results) {
    if (pWardriveScan && wardriveActive) {
        pWardriveScan->clearResults();
    }
}

static WardriveAdvCallbacks wardriveBleCallbacks;

// ============================================================================
// Lifecycle
// ============================================================================

static void wardriveInit(void) {
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;
    wifiDedupHead = 0;
    wifiDedupCount = 0;
    flockWifiDedupHead = 0;
    flockWifiDedupCount = 0;
    Serial.println("[WARDRIVE] Initialized");
}

static void wardriveStart(void) {
    wardriveActive = true;
    lastBleScan = 0;
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;
    wifiDedupHead = 0;
    wifiDedupCount = 0;
    flockWifiDedupHead = 0;
    flockWifiDedupCount = 0;
    currentChannel = channelStart;
    lastChannelHop = millis();
    beaconsThisHop = 0;

    // Reset adaptive dwell to base values
    for (int i = 0; i < 14; i++) {
        timePerChannel[i] = isPriorityChannel(i + 1) ? priorityDwellMs : normalDwellMs;
    }

    // WiFi: pure promiscuous mode — catches beacons (SSID/auth), flock
    // cameras, foxhunter targets. All in one callback, no WiFi.scanNetworks().
    if (wardriveRadio & 0x01) {
        WiFi.mode(WIFI_STA);
        WiFi.disconnect();

        // Set country to allow channels 1-14 (manual policy = user controls range)
        wifi_country_t country = {
            .cc = "JP",     // JP allows widest range (1-14)
            .schan = 1,
            .nchan = 14,
            .policy = WIFI_COUNTRY_POLICY_MANUAL
        };
        esp_wifi_set_country(&country);

        // Promiscuous filter: ALL frame types.
        // CTRL frames needed for flock OUI detection — cameras appear as
        // addr1 (destination) in data/ctrl frames from associated APs.
        // Standalone flock_wifi uses default (all types) and catches cameras
        // that wardrive missed when limited to MGMT+DATA only.
        wifi_promiscuous_filter_t filter = {
            .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT |
                           WIFI_PROMIS_FILTER_MASK_DATA |
                           WIFI_PROMIS_FILTER_MASK_CTRL
        };
        esp_wifi_set_promiscuous_filter(&filter);

        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wardriveWifiCb);
        esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);

        // Send wildcard probe on first channel to stimulate immediate AP responses
        sendWildcardProbe();
    }

    // BLE scanner
    if (wardriveRadio & 0x02) {
        pWardriveScan = NimBLEDevice::getScan();
        pWardriveScan->setAdvertisedDeviceCallbacks(&wardriveBleCallbacks, true);
        pWardriveScan->setActiveScan(true);
        // Interval == window: Espressif recommendation for WiFi/BLE coexistence.
        // Continuous BLE within its TDM slot, no wasted RF gaps.
        pWardriveScan->setInterval(80);
        pWardriveScan->setWindow(79);
    }

    engineSetState(ENGINE_WARDRIVE, ESTATE_SCANNING);
    Serial.printf("[WARDRIVE] Started (radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d)\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
}

static void wardriveStop(void) {
    Serial.println("[WARDRIVE] Stopping...");
    wardriveActive = false;

    // Stop BLE
    if (pWardriveScan != nullptr) {
        if (pWardriveScan->isScanning()) pWardriveScan->stop();
        vTaskDelay(pdMS_TO_TICKS(200));
        pWardriveScan->setAdvertisedDeviceCallbacks(nullptr, false);
        pWardriveScan->clearResults();
        pWardriveScan = nullptr;
    }

    // Stop WiFi promiscuous
    esp_wifi_set_promiscuous_rx_cb(NULL);
    esp_wifi_set_promiscuous(false);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);

    engineSetState(ENGINE_WARDRIVE, ESTATE_DISABLED);
    Serial.println("[WARDRIVE] Stopped");
}

static void wardriveLoop(void) {
    if (!wardriveActive) return;
    unsigned long now = millis();

    // WiFi: channel hopping with adaptive per-channel dwell time
    if (wardriveRadio & 0x01) {
        uint16_t dwell = dwellForChannel(currentChannel);
        if (now - lastChannelHop >= dwell) {
            // Adapt dwell for channel we're leaving
            updateAdaptiveDwell(currentChannel, beaconsThisHop);
            beaconsThisHop = 0;

            currentChannel++;
            if (currentChannel > channelEnd) currentChannel = channelStart;
            esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
            lastChannelHop = now;

            // Wildcard probe on each hop — APs respond immediately instead of
            // waiting up to 102.4ms for next beacon interval. Free speed boost.
            sendWildcardProbe();
        }
    }

    // BLE: timed scans
    if (wardriveRadio & 0x02) {
        if (now - lastBleScan >= bleScanIntervalMs) {
            lastBleScan = now;
            if (pWardriveScan != nullptr && !pWardriveScan->isScanning()) {
                int durSec = bleScanDurationMs / 1000;
                if (durSec < 1) durSec = 1;
                pWardriveScan->start(durSec, wardriveBleOnComplete, false);
            }
        }
    }
}

static void wardriveConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    uint8_t newRadio = payload[0] & 0x03;
    if (newRadio == 0) newRadio = 0x03;
    wardriveRadio = newRadio;

    if (len >= 5) {
        // bytes[1:2] = priority dwell (was wifiScanInterval)
        // bytes[3:4] = normal dwell (was wifiDwellPerCh)
        priorityDwellMs = payload[1] | (payload[2] << 8);
        normalDwellMs   = payload[3] | (payload[4] << 8);
        if (priorityDwellMs < 50) priorityDwellMs = 50;
        if (normalDwellMs < 50) normalDwellMs = 50;
    }
    if (len >= 9) {
        bleScanDurationMs = payload[5] | (payload[6] << 8);
        bleScanIntervalMs = payload[7] | (payload[8] << 8);
        if (bleScanDurationMs < 500) bleScanDurationMs = 500;
        if (bleScanIntervalMs < 1000) bleScanIntervalMs = 1000;
    }
    if (len >= 11) {
        uint8_t cs = payload[9];
        uint8_t ce = payload[10];
        if (cs >= 1 && cs <= 14) channelStart = cs;
        if (ce >= channelStart && ce <= 14) channelEnd = ce;
        currentChannel = channelStart;
    }

    Serial.printf("[WARDRIVE] Config: radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
}

const EngineCallbacks wardriveCallbacks = {
    .init   = wardriveInit,
    .start  = wardriveStart,
    .stop   = wardriveStop,
    .loop   = wardriveLoop,
    .config = wardriveConfig,
    .name   = "Wardrive",
};
