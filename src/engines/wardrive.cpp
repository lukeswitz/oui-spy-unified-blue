#include "wardrive.h"
#include "../protocol.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>

static bool wardriveActive = false;
static unsigned long lastWifiScan = 0;
static unsigned long lastBleScan = 0;

#define WIFI_SCAN_INTERVAL_MS  3000
#define BLE_SCAN_DURATION_MS   2000
#define BLE_SCAN_INTERVAL_MS   3000
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

static void wardriveWifiScan(void) {
    if (!wardriveActive) return;
    int n = WiFi.scanNetworks(false, true, false, 200);
    if (n <= 0) return;

    for (int i = 0; i < n; i++) {
        if (!wardriveActive) break;
        uint8_t* bssid = WiFi.BSSID(i);
        if (bssid == NULL) continue;
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
    }

    WiFi.scanDelete();
}

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
    }
};

static WardriveAdvCallbacks wardriveBleCallbacks;

static void wardriveInit(void) {
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;
    Serial.println("[WARDRIVE] Initialized");
}

static void wardriveStart(void) {
    wardriveActive = true;
    lastWifiScan = 0;
    lastBleScan = 0;
    wardriveDedupHead = 0;
    wardriveDedupCount = 0;

    WiFi.mode(WIFI_STA);
    WiFi.disconnect();

    pWardriveScan = NimBLEDevice::getScan();
    pWardriveScan->setAdvertisedDeviceCallbacks(&wardriveBleCallbacks, true);
    pWardriveScan->setActiveScan(true);
    pWardriveScan->setInterval(100);
    pWardriveScan->setWindow(99);

    engineSetState(ENGINE_WARDRIVE, ESTATE_SCANNING);
    Serial.println("[WARDRIVE] Started — scanning all WiFi + BLE");
}

static void wardriveStop(void) {
    Serial.println("[WARDRIVE] Stopping...");
    wardriveActive = false;

    if (pWardriveScan != nullptr) {
        if (pWardriveScan->isScanning()) {
            pWardriveScan->stop();
            delay(50);
        }
        pWardriveScan->clearResults();
        pWardriveScan->setAdvertisedDeviceCallbacks(nullptr, false);
        pWardriveScan = nullptr;
    }

    WiFi.scanDelete();
    esp_wifi_set_promiscuous(false);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);

    engineSetState(ENGINE_WARDRIVE, ESTATE_DISABLED);
    Serial.println("[WARDRIVE] Stopped");
}

static void wardriveLoop(void) {
    if (!wardriveActive) return;
    unsigned long now = millis();

    if (now - lastWifiScan >= WIFI_SCAN_INTERVAL_MS) {
        lastWifiScan = now;
        wardriveWifiScan();
    }

    if (now - lastBleScan >= BLE_SCAN_INTERVAL_MS) {
        lastBleScan = now;
        if (pWardriveScan != nullptr && !pWardriveScan->isScanning()) {
            pWardriveScan->start(BLE_SCAN_DURATION_MS / 1000, false);
        }
    }
}

const EngineCallbacks wardriveCallbacks = {
    .init  = wardriveInit,
    .start = wardriveStart,
    .stop  = wardriveStop,
    .loop  = wardriveLoop,
    .name  = "Wardrive",
};
