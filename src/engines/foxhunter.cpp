/**
 * Foxhunter Engine — single-target RSSI proximity tracker.
 * Scans BLE for a specific MAC, streams RSSI to app via dedicated notification.
 * Ported from raw/foxhunter.cpp.
 */
#include "foxhunter.h"
#include "protocol.h"
#include "ble_gatt.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;
static uint8_t targetMac[6] = {0};
static bool hasTarget = false;
static int currentRssi = -100;
static unsigned long lastTargetSeen = 0;
static bool targetInRange = false;

static int calculateBeepInterval(int rssi) {
    if (rssi >= -35) return 15;
    if (rssi >= -45) return 40;
    if (rssi >= -55) return 75;
    if (rssi >= -65) return 150;
    if (rssi >= -75) return 350;
    if (rssi >= -85) return 750;
    return 3000;
}

// ============================================================================
// BLE Scan Callback
// ============================================================================

class FoxhunterCallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        if (!hasTarget) return;

        std::string addrStr = dev->getAddress().toString();
        unsigned int m[6];
        sscanf(addrStr.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t mac[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                          (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};

        if (memcmp(mac, targetMac, 6) != 0) return;

        currentRssi = dev->getRSSI();
        lastTargetSeen = millis();
        targetInRange = true;

        int interval = calculateBeepInterval(currentRssi);
        bleGattNotifyFoxhunterRssi(currentRssi, interval);

        // Also push as detection event
        DetectionEvent evt;
        memset(&evt, 0, sizeof(evt));
        evt.engine_id = ENGINE_FOXHUNTER;
        memcpy(evt.mac, mac, 6);
        evt.rssi = currentRssi;
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = 0; // proximity

        pushDetection(&evt);
    }
};

static FoxhunterCallback scanCb;

// ============================================================================
// Target management (called from GATT write)
// ============================================================================

void foxhunterSetTarget(const uint8_t* mac) {
    memcpy(targetMac, mac, 6);
    hasTarget = true;
    targetInRange = false;
    currentRssi = -100;
    Serial.printf("[FOXHUNTER] Target set: %02x:%02x:%02x:%02x:%02x:%02x\n",
                  mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
}

// ============================================================================
// Lifecycle
// ============================================================================

static void foxhunterInit(void) {
    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&scanCb, true);
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);

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
    lastScanStart = 0;
    Serial.println("[FOXHUNTER] Started");
}

static void foxhunterStop(void) {
    if (bleScan && bleScan->isScanning()) bleScan->stop();
    scanning = false;
    Serial.println("[FOXHUNTER] Stopped");
}

static void foxhunterLoop(void) {
    if (!scanning || !bleScan) return;

    // Timeout: target lost after 7 seconds
    if (targetInRange && millis() - lastTargetSeen > 7000) {
        targetInRange = false;
        Serial.println("[FOXHUNTER] Target lost");
    }

    // Continuous fast scanning for proximity tracking
    if (millis() - lastScanStart >= 1500) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }
}

const EngineCallbacks foxhunterCallbacks = {
    .init  = foxhunterInit,
    .start = foxhunterStart,
    .stop  = foxhunterStop,
    .loop  = foxhunterLoop,
    .name  = "Foxhunter"
};
