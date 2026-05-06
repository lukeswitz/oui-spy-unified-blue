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
// State
// ============================================================================

static volatile bool wardriveActive = false;
static unsigned long lastBleScan = 0;
static volatile uint8_t wardriveRadio = 0x03;

// Channel hopping — configurable per-channel dwell
static uint8_t channelStart = 1;
static uint8_t channelEnd   = 11;
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

// BLE scan timing
static uint16_t bleScanDurationMs  = 1500;
static uint16_t bleScanIntervalMs  = 2000;

// Dedup ring — shared by WiFi promisc + BLE callbacks
#define WARDRIVE_DEDUP_SIZE    200
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

static uint8_t IRAM_ATTR parseAuthFromFrame(const uint8_t* p, int len) {
    // Walk tagged parameters starting after fixed fields
    // Beacon: 24-byte header + 12 bytes fixed (timestamp[8]+interval[2]+capability[2])
    int offset = 36;
    bool hasRSN = false;
    bool hasWPA = false;

    while (offset + 2 <= len) {
        uint8_t tagId = p[offset];
        uint8_t tagLen = p[offset + 1];
        if (offset + 2 + tagLen > len) break;

        if (tagId == 48) hasRSN = true;       // RSN (WPA2/WPA3)
        if (tagId == 221 && tagLen >= 4) {     // Vendor-specific (WPA1)
            if (p[offset+2]==0x00 && p[offset+3]==0x50 &&
                p[offset+4]==0xF2 && p[offset+5]==0x01) {
                hasWPA = true;
            }
        }
        offset += 2 + tagLen;
    }

    if (hasRSN && hasWPA) return 4;  // WPA_WPA2
    if (hasRSN) return 3;            // WPA2
    if (hasWPA) return 2;            // WPA
    return 0;                         // Open
}

// ============================================================================
// WiFi Promiscuous Callback — THE wardrive WiFi scanner.
// Pure promiscuous mode: catches beacons (SSID/auth for WiGLE), flock OUI
// frames, and foxhunter targets. No WiFi.scanNetworks() needed.
// ============================================================================

static void IRAM_ATTR wardriveWifiCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!wardriveActive) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    uint8_t frameType = (p[0] >> 2) & 0x03;
    uint8_t frameSubtype = (p[0] >> 4) & 0x0F;

    const uint8_t* addr1 = &p[4];   // destination
    const uint8_t* addr2 = &p[10];  // source/transmitter
    const uint8_t* addr3 = &p[16];  // BSSID

    // --- 1. Flock OUI check on ALL frames (not just beacons) ---
    // This is what flock_wifi.cpp does — check addr2/addr1/addr3 for OUI match.
    // Must run before beacon dedup so flock cameras get reported even if
    // their BSSID was already seen as an AP.
    {
        const uint8_t* flockMac = NULL;
        uint8_t flockMethod = 0xFF;

        if (flockMatchOuiISR(addr2)) {
            flockMac = addr2;
            flockMethod = METHOD_OUI_ADDR2;
            // Wildcard probe check (type=0 subtype=4 empty SSID)
            if (frameType == 0 && frameSubtype == 4 && len > 25 && p[25] == 0) {
                flockMethod = METHOD_WILDCARD_PROBE;
            }
        } else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
            flockMac = addr1;
            flockMethod = METHOD_OUI_ADDR1;
        } else if (frameType == 0 && flockMatchOuiISR(addr3)) {
            flockMac = addr3;
            flockMethod = METHOD_OUI_ADDR3;
        }

        if (flockMac != NULL) {
            // Flock has its own dedup — use addr2 as key (transmitter = camera)
            // Don't share dedup ring with wardrive beacon BSSID tracking
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
                memcpy(ssid, &p[tagOffset + 2], tagLen);
                ssid[tagLen] = '\0';
            }
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

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = METHOD_BLE_ADV;
        memset(evt.source_node_id, 0, MESH_NODE_ID_LEN);
        memset(evt.ext.wardrive.ssid, 0, 33);
        evt.ext.wardrive.auth_mode = 0;
        std::string name = dev->getName();
        strncpy(evt.ext.wardrive.device_name, name.c_str(), 20);
        evt.ext.wardrive.device_name[20] = '\0';
        pushDetection(&evt);

        // Full flock detection: OUI, name, mfg ID, Raven UUID
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
            fEvt.rssi = evt.rssi;
            fEvt.channel = 0;
            fEvt.timestamp_ms = evt.timestamp_ms;
            fEvt.method = flockMethod;
            memset(fEvt.source_node_id, 0, MESH_NODE_ID_LEN);
            memset(&fEvt.ext, 0, sizeof(fEvt.ext));
            fEvt.ext.flock.is_raven = isRaven ? 1 : 0;
            memset(fEvt.ext.flock.raven_fw, 0, sizeof(fEvt.ext.flock.raven_fw));
            pushDetection(&fEvt);
        }

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
    Serial.println("[WARDRIVE] Initialized");
}

static void wardriveStart(void) {
    wardriveActive = true;
    lastBleScan = 0;
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;
    wifiDedupHead = 0;
    wifiDedupCount = 0;
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
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wardriveWifiCb);
        esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
    }

    // BLE scanner
    if (wardriveRadio & 0x02) {
        pWardriveScan = NimBLEDevice::getScan();
        pWardriveScan->setAdvertisedDeviceCallbacks(&wardriveBleCallbacks, true);
        pWardriveScan->setActiveScan(true);
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
