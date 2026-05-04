#include "wardrive.h"
#include "../protocol.h"
#include "flock_oui.h"
#include "detector.h"
#include "foxhunter.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>

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

static volatile bool wardriveActive = false;
static unsigned long lastWifiScan = 0;
static unsigned long lastBleScan = 0;
static volatile bool wifiScanInProgress = false;

static volatile uint8_t wardriveRadio = 0x03;

// Channel range for orchestrated scanning (1-14 default = all)
static uint8_t wardriveChanStart = 1;
static uint8_t wardriveChanEnd   = 14;

// Scan timing — configurable via BLE config
static uint16_t wifiScanIntervalMs = 1200;  // gap between WiFi scans
static uint16_t wifiDwellPerChMs   = 250;   // per-channel dwell time
static uint16_t bleScanDurationMs  = 1500;  // BLE scan window
static uint16_t bleScanIntervalMs  = 2000;  // gap between BLE scans

#define WARDRIVE_DEDUP_SIZE    150
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

static uint8_t mapAuthMode(wifi_auth_mode_t mode) {
    switch (mode) {
        case WIFI_AUTH_OPEN:            return 0;
        case WIFI_AUTH_WEP:             return 1;
        case WIFI_AUTH_WPA_PSK:         return 2;
        case WIFI_AUTH_WPA2_PSK:        return 3;
        case WIFI_AUTH_WPA_WPA2_PSK:    return 4;
        case WIFI_AUTH_WPA2_ENTERPRISE: return 5;
        case WIFI_AUTH_WPA3_PSK:        return 6;
        default:                        return 0;
    }
}

// ============================================================================
// WiFi — async scan, harvest in loop. Non-blocking.
// ============================================================================

static void wardriveWifiScanStart(void) {
    if (!wardriveActive || wifiScanInProgress) return;
    // async=true, show_hidden=true, passive=false, dwell per channel
    WiFi.scanNetworks(true, true, false, wifiDwellPerChMs);
    wifiScanInProgress = true;
}

static void wardriveWifiScanHarvest(void) {
    int n = WiFi.scanComplete();
    if (n == WIFI_SCAN_RUNNING) return;
    if (n == WIFI_SCAN_FAILED) { wifiScanInProgress = false; return; }
    wifiScanInProgress = false;

    for (int i = 0; i < n; i++) {
        if (!wardriveActive) break;
        uint8_t* bssid = WiFi.BSSID(i);
        if (bssid == NULL) continue;

        // Channel range filter for orchestrated scanning
        uint8_t ch = (uint8_t)WiFi.channel(i);
        if (ch < wardriveChanStart || ch > wardriveChanEnd) continue;

        if (wardriveIsDedupCooldown(bssid)) continue;

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, bssid, 6);
        evt.rssi = WiFi.RSSI(i);
        evt.channel = WiFi.channel(i);
        evt.timestamp_ms = millis();
        evt.method = METHOD_WIFI_AP;
        memset(evt.source_node_id, 0, MESH_NODE_ID_LEN);

        String ssid = WiFi.SSID(i);
        strncpy(evt.ext.wardrive.ssid, ssid.c_str(), 32);
        evt.ext.wardrive.ssid[32] = '\0';
        evt.ext.wardrive.auth_mode = mapAuthMode(WiFi.encryptionType(i));
        memset(evt.ext.wardrive.device_name, 0, 21);
        pushDetection(&evt);

        if (flockMatchOui(bssid)) {
            DetectionEvent fEvt = {};
            fEvt.engine_id = ENGINE_FLOCK_WIFI;
            memcpy(fEvt.mac, bssid, 6);
            fEvt.rssi = evt.rssi;
            fEvt.channel = evt.channel;
            fEvt.timestamp_ms = evt.timestamp_ms;
            fEvt.method = METHOD_OUI_ADDR2;
            memset(fEvt.source_node_id, 0, MESH_NODE_ID_LEN);
            memset(&fEvt.ext, 0, sizeof(fEvt.ext));
            pushDetection(&fEvt);
        }
    }
    WiFi.scanDelete();
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

// Scan-complete callback — auto-restarts scan if still active
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
    Serial.println("[WARDRIVE] Initialized");
}

static void wardriveStart(void) {
    wardriveActive = true;
    lastWifiScan = 0;
    lastBleScan = 0;
    wifiScanInProgress = false;
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;

    // Init WiFi first — coex manager needs WiFi registered before BLE scan
    if (wardriveRadio & 0x01) {
        WiFi.mode(WIFI_STA);
        WiFi.disconnect();
    }

    // Init BLE scanner
    if (wardriveRadio & 0x02) {
        pWardriveScan = NimBLEDevice::getScan();
        pWardriveScan->setAdvertisedDeviceCallbacks(&wardriveBleCallbacks, true);
        pWardriveScan->setActiveScan(true);
        pWardriveScan->setInterval(80);
        pWardriveScan->setWindow(79);
    }

    engineSetState(ENGINE_WARDRIVE, ESTATE_SCANNING);
    Serial.printf("[WARDRIVE] Started (radio=0x%02X wifi=%d/%d ble=%d/%d)\n",
        wardriveRadio, wifiScanIntervalMs, wifiDwellPerChMs,
        bleScanDurationMs, bleScanIntervalMs);
}

static void wardriveStop(void) {
    Serial.println("[WARDRIVE] Stopping...");

    // 1. Flag off — callbacks will early-return
    wardriveActive = false;

    // 2. Stop BLE scan FIRST, then delay, then clear callbacks
    if (pWardriveScan != nullptr) {
        if (pWardriveScan->isScanning()) {
            pWardriveScan->stop();
        }
        vTaskDelay(pdMS_TO_TICKS(200));
        pWardriveScan->setAdvertisedDeviceCallbacks(nullptr, false);
        pWardriveScan->clearResults();
        pWardriveScan = nullptr;
    }

    // 3. Wait for any in-flight WiFi scan to finish
    if (wifiScanInProgress) {
        unsigned long deadline = millis() + 3000;
        while (WiFi.scanComplete() == WIFI_SCAN_RUNNING && millis() < deadline) {
            vTaskDelay(pdMS_TO_TICKS(50));
        }
        wifiScanInProgress = false;
    }

    // 4. Clean up WiFi
    WiFi.scanDelete();
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);

    engineSetState(ENGINE_WARDRIVE, ESTATE_DISABLED);
    Serial.println("[WARDRIVE] Stopped");
}

static void wardriveLoop(void) {
    if (!wardriveActive) return;
    unsigned long now = millis();

    // WiFi: kick off async scan, harvest results when ready
    if (wardriveRadio & 0x01) {
        if (wifiScanInProgress) {
            wardriveWifiScanHarvest();
        }
        if (!wifiScanInProgress && now - lastWifiScan >= wifiScanIntervalMs) {
            lastWifiScan = now;
            wardriveWifiScanStart();
        }
    }

    // BLE: timed scans with explicit duration (never 0 = continuous)
    if (wardriveRadio & 0x02) {
        if (now - lastBleScan >= bleScanIntervalMs) {
            lastBleScan = now;
            if (pWardriveScan != nullptr && !pWardriveScan->isScanning()) {
                // NimBLE 1.4: start(seconds, callback, is_continue)
                // Duration must be >= 1 to avoid continuous mode
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
        wifiScanIntervalMs = payload[1] | (payload[2] << 8);
        wifiDwellPerChMs   = payload[3] | (payload[4] << 8);
        if (wifiScanIntervalMs < 500) wifiScanIntervalMs = 500;
        if (wifiDwellPerChMs < 110) wifiDwellPerChMs = 110;
    }
    if (len >= 9) {
        bleScanDurationMs = payload[5] | (payload[6] << 8);
        bleScanIntervalMs = payload[7] | (payload[8] << 8);
        if (bleScanDurationMs < 500) bleScanDurationMs = 500;
        if (bleScanIntervalMs < 1000) bleScanIntervalMs = 1000;
    }

    // Channel range for orchestrated multi-node scanning (bytes 9-10)
    if (len >= 11) {
        uint8_t chStart = payload[9];
        uint8_t chEnd   = payload[10];
        if (chStart >= 1 && chStart <= 14 && chEnd >= chStart && chEnd <= 14) {
            wardriveChanStart = chStart;
            wardriveChanEnd   = chEnd;
        }
    }

    Serial.printf("[WARDRIVE] Config: radio=0x%02X wifi=%d/%d ble=%d/%d ch=%d-%d\n",
        wardriveRadio, wifiScanIntervalMs, wifiDwellPerChMs,
        bleScanDurationMs, bleScanIntervalMs, wardriveChanStart, wardriveChanEnd);
}

const EngineCallbacks wardriveCallbacks = {
    .init   = wardriveInit,
    .start  = wardriveStart,
    .stop   = wardriveStop,
    .loop   = wardriveLoop,
    .config = wardriveConfig,
    .name   = "Wardrive",
};
