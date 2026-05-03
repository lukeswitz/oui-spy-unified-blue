#include "foxhunter.h"
#include "protocol.h"
#include "ble_gatt.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <Preferences.h>

static NimBLEScan* bleScan = nullptr;
static volatile bool scanning = false;
static unsigned long lastScanStart = 0;
static uint8_t targetMac[6] = {0};
static volatile bool hasTarget = false;
static volatile int currentRssi = -100;
static volatile unsigned long lastTargetSeen = 0;
static volatile bool targetInRange = false;
static unsigned long lastBeepTime = 0;

// WiFi promiscuous — scan all channels to find target regardless of channel
static volatile bool wifiActive = false;
static const uint8_t channels[] = {1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14};
static const int channelCount = 14;
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 100;

static int calculateBeepInterval(int rssi) {
    if (rssi >= -35) return 15;
    if (rssi >= -45) return 40;
    if (rssi >= -55) return 75;
    if (rssi >= -65) return 150;
    if (rssi >= -75) return 350;
    if (rssi >= -85) return 750;
    return 3000;
}

class FoxhunterCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        if (!hasTarget || !scanning) return;

        uint8_t mac[6];
        memcpy(mac, dev->getAddress().getNative(), 6);
        if (memcmp(mac, targetMac, 6) != 0) return;

        currentRssi = dev->getRSSI();
        lastTargetSeen = millis();
        targetInRange = true;

        int interval = calculateBeepInterval(currentRssi);
        bleGattNotifyFoxhunterRssi(currentRssi, interval);

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_FOXHUNTER;
        memcpy(evt.mac, mac, 6);
        evt.rssi = currentRssi;
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = 0;
        pushDetection(&evt);
    }
};

static FoxhunterCallback scanCb;

static void IRAM_ATTR wifiSnifferCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!scanning || !hasTarget || !wifiActive) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    const uint8_t* addr1 = &p[4];
    const uint8_t* addr2 = &p[10];
    const uint8_t* addr3 = &p[16];

    const uint8_t* matchMac = NULL;
    if (memcmp(addr2, targetMac, 6) == 0) matchMac = addr2;
    else if (memcmp(addr1, targetMac, 6) == 0) matchMac = addr1;
    else if (memcmp(addr3, targetMac, 6) == 0) matchMac = addr3;
    if (!matchMac) return;

    currentRssi = pkt->rx_ctrl.rssi;
    lastTargetSeen = millis();
    targetInRange = true;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_FOXHUNTER;
    memcpy(evt.mac, matchMac, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    pushDetectionFromISR(&evt);
}

void foxhunterSetTarget(const uint8_t* mac) {
    memcpy(targetMac, mac, 6);
    hasTarget = true;
    targetInRange = false;
    currentRssi = -100;
    Serial.printf("[FOXHUNTER] Target set: %02x:%02x:%02x:%02x:%02x:%02x\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

// Exported: check a MAC from wardrive's BLE callback
void foxhunterCheckBleDevice(const uint8_t* mac, int rssi) {
    if (!scanning || !hasTarget) return;
    if (memcmp(mac, targetMac, 6) != 0) return;

    currentRssi = rssi;
    lastTargetSeen = millis();
    targetInRange = true;

    int interval = calculateBeepInterval(rssi);
    bleGattNotifyFoxhunterRssi(rssi, interval);

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_FOXHUNTER;
    memcpy(evt.mac, mac, 6);
    evt.rssi = rssi;
    evt.channel = 0;
    evt.timestamp_ms = millis();
    evt.method = 0;
    pushDetection(&evt);
}

static void foxhunterInit(void) {
    Preferences p;
    p.begin("tracker", true);
    String mac = p.getString("targetMAC", "");
    p.end();
    if (mac.length() == 17) {
        unsigned int m[6];
        sscanf(mac.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t bytes[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                            (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};
        foxhunterSetTarget(bytes);
    }
    Serial.println("[FOXHUNTER] Initialized");
}

static void foxhunterStart(void) {
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

    // WiFi promiscuous only when wardrive doesn't own WiFi
    if (!wardriveOwns) {
        WiFi.mode(WIFI_STA);
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wifiSnifferCb);
        esp_wifi_set_channel(channels[0], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        wifiActive = true;
    }

    Serial.printf("[FOXHUNTER] Started (%s)\n", wardriveOwns ? "passive — wardrive feeds" : "WiFi+BLE");
}

static void foxhunterStop(void) {
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

    Serial.println("[FOXHUNTER] Stopped");
}

static void foxhunterProximityBeep(void) {
    if (!hwBuzzerEnabled || hwBuzzerVolume == 0) return;
    ledcSetup(0, 2400, 8);
    ledcAttachPin(PIN_BUZZER, 0);
    ledcWrite(0, hwBuzzerVolume);
    delay(30);
    ledcWrite(0, 0);
    ledcDetachPin(PIN_BUZZER);
}

static void foxhunterLoop(void) {
    if (!scanning) return;

    if (targetInRange && millis() - lastTargetSeen > 7000) {
        targetInRange = false;
        Serial.println("[FOXHUNTER] Target lost");
    }

    if (targetInRange) {
        int interval = calculateBeepInterval(currentRssi);
        if (millis() - lastBeepTime >= (unsigned long)interval) {
            foxhunterProximityBeep();
            lastBeepTime = millis();
            bleGattNotifyFoxhunterRssi(currentRssi, interval);
        }
    }

    if (wifiActive && millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % channelCount;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
    }

    if (bleScan && millis() - lastScanStart >= 1500) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }
}

const EngineCallbacks foxhunterCallbacks = {
    .init   = foxhunterInit,
    .start  = foxhunterStart,
    .stop   = foxhunterStop,
    .loop   = foxhunterLoop,
    .config = NULL,
    .name   = "Foxhunter"
};
