#include "foxhunter.h"
#include "protocol.h"
#include "ble_gatt.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"
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

// WiFi promiscuous — scan all channels 1-14.
// Channel hint from feed = start channel + extra dwell (priority), not a lock.
static volatile bool wifiActive = false;
static uint8_t hintChannel = 0;           // 0 = no hint, 1-14 = priority channel
static uint8_t currentChannel = 1;
static unsigned long lastChannelHop = 0;
static const uint16_t NORMAL_DWELL_MS  = 120;  // regular channels
static const uint16_t PRIORITY_DWELL_MS = 350;  // hint channel + 1/6/11

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
        g_engRawSeen++;
        if (!hasTarget || !scanning) return;

        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);
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
    g_engRawSeen++;
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

    // Auto-hint: remember channel where target was found for priority dwell
    if (hintChannel == 0 && pkt->rx_ctrl.channel >= 1 && pkt->rx_ctrl.channel <= 14) {
        hintChannel = pkt->rx_ctrl.channel;
    }

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_FOXHUNTER;
    memcpy(evt.mac, matchMac, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    pushDetectionFromISR(&evt);
}

void foxhunterSetTarget(const uint8_t* mac, uint8_t channel) {
    memcpy(targetMac, mac, 6);
    hasTarget = true;
    targetInRange = false;
    currentRssi = -100;
    hintChannel = (channel >= 1 && channel <= 14) ? channel : 0;
    // Start scanning from hint channel if provided
    if (hintChannel > 0) currentChannel = hintChannel;
    Serial.printf("[FOXHUNTER] Target set: %02x:%02x:%02x:%02x:%02x:%02x hint_ch=%d\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5],
                  hintChannel);
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

// ISR-safe: check 3 802.11 address fields from promiscuous callback
void IRAM_ATTR foxhunterCheckWifiDeviceISR(
    const uint8_t* addr1, const uint8_t* addr2, const uint8_t* addr3,
    int rssi, uint8_t channel) {
    if (!scanning || !hasTarget) return;

    const uint8_t* matchMac = NULL;
    if (memcmp(addr2, targetMac, 6) == 0) matchMac = addr2;
    else if (memcmp(addr1, targetMac, 6) == 0) matchMac = addr1;
    else if (memcmp(addr3, targetMac, 6) == 0) matchMac = addr3;
    if (!matchMac) return;

    currentRssi = rssi;
    lastTargetSeen = millis();
    targetInRange = true;

    DetectionEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.engine_id = ENGINE_FOXHUNTER;
    memcpy(evt.mac, matchMac, 6);
    evt.rssi = rssi;
    evt.channel = channel;
    evt.timestamp_ms = millis();
    evt.method = 1;
    pushDetectionFromISR(&evt);
}

// Exported: check a MAC from wardrive's WiFi scan harvest
void foxhunterCheckWifiDevice(const uint8_t* mac, int rssi, uint8_t channel) {
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
    evt.channel = channel;
    evt.timestamp_ms = millis();
    evt.method = 1;  // WiFi method
    pushDetection(&evt);
}

static void foxhunterInit(void) {
    Preferences p;
    p.begin("tracker", true);
    String mac = p.getString("targetMAC", "");
    uint8_t ch = p.getUChar("targetCh", 0);  // stored hint channel
    p.end();
    if (mac.length() == 17) {
        unsigned int m[6];
        sscanf(mac.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t bytes[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                            (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};
        foxhunterSetTarget(bytes, ch);
    }
    Serial.println("[FOXHUNTER] Initialized");
}

static void foxhunterStart(void) {
    scanning = true;

    bool wardriveOwns = (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED);

    // Foxhunter needs exclusive WiFi — pause any other WiFi engine
    if (!wardriveOwns) {
        static const EngineId wifiEngines[] = {
            ENGINE_DETECTOR, ENGINE_FLOCK_WIFI, ENGINE_SKYSPY
        };
        bool paused = false;
        for (auto eid : wifiEngines) {
            if (engineGetState(eid) != ESTATE_DISABLED) {
                engineDisable(eid);
                Serial.printf("[FOXHUNTER] Paused engine %d (foxhunter owns WiFi)\n", eid);
                paused = true;
            }
        }
        if (paused) bleGattNotifyEngineState();
    }

    if (!wardriveOwns) {
        bleScan = NimBLEDevice::getScan();
        bleCoexRegister(&scanCb, true);
        bleScan->setActiveScan(true);
        bleScan->setInterval(100);
        bleScan->setWindow(99);
        lastScanStart = 0;
    }

    // WiFi promiscuous only when wardrive doesn't own WiFi
    if (!wardriveOwns) {
        if (!meshIsEnabled()) {
            WiFi.mode(WIFI_STA);
        }
        // MGMT+DATA only. CTRL frames (ACK/CTS/RTS/BlockAck) outnumber legit
        // target frames 10-100x on busy networks; including them overloads
        // the ISR and drops the very frames foxhunter needs to track RSSI on.
        esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
        wifiCoexRegister(wifiSnifferCb,
                         WIFI_PROMIS_FILTER_MASK_MGMT | WIFI_PROMIS_FILTER_MASK_DATA);
        uint8_t startCh = (hintChannel > 0) ? hintChannel : 1;
        currentChannel = startCh;
        esp_wifi_set_channel(startCh, WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        wifiActive = true;
    }

    Serial.printf("[FOXHUNTER] Started (%s hint_ch=%d)\n",
        wardriveOwns ? "passive — wardrive feeds" : "WiFi+BLE ch1-14",
        hintChannel);
}

static void foxhunterStop(void) {
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
    if (meshIsEnabled() && meshInMeshWindow()) return;
    if (!scanning) return;

    if (targetInRange && millis() - lastTargetSeen > 7000) {
        targetInRange = false;
        bleGattNotifyFoxhunterRssi(currentRssi, 0);
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

    // Channel hop — all channels 1-14, priority dwell on hint + 1/6/11
    if (wifiActive) {
        bool isPriority = (currentChannel == hintChannel) ||
                          currentChannel == 1 || currentChannel == 6 || currentChannel == 11;
        uint16_t dwell = isPriority ? PRIORITY_DWELL_MS : NORMAL_DWELL_MS;
        if (millis() - lastChannelHop >= dwell) {
            currentChannel++;
            if (currentChannel > 14) currentChannel = 1;
            esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
            lastChannelHop = millis();
            if (meshIsEnabled() && currentChannel == 1) meshNoteOnHome();
        }
    }

    if (bleScan && millis() - lastScanStart >= 1500) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }
}

static void foxhunterConfigCb(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    const char* self = meshGetLocalNodeId();
    if (!cfgTgtStrip(&payload, &len, self)) {
        Serial.printf("[FOXHUNTER] cfg target mismatch self=%s — ignored\n", self);
        return;
    }
    if (len < 6) return;
    uint8_t channel = (len >= 7) ? payload[6] : 0;
    foxhunterSetTarget(payload, channel);
    Serial.printf("[FOXHUNTER] target via engineConfig ch=%u\n", channel);
}

const EngineCallbacks foxhunterCallbacks = {
    .init   = foxhunterInit,
    .start  = foxhunterStart,
    .stop   = foxhunterStop,
    .loop   = foxhunterLoop,
    .config = foxhunterConfigCb,
    .name   = "Foxhunter"
};
