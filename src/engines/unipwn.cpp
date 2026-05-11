/**
 * UniPwn Engine — Unitree robot BLE discovery.
 * Scans for Go2_, G1_, H1_, B2_, X1_ device names.
 * Exploitation handled separately via GATT command characteristic.
 * Ported from raw/unipwn_main.cpp scanning logic.
 */
#include "unipwn.h"
#include "protocol.h"
#include "../ble_compat.h"

static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;

#define DEDUP_SIZE 8
#define DEDUP_COOLDOWN_MS 10000
static struct { uint8_t mac[6]; unsigned long ts; } dedup[DEDUP_SIZE];
static int dedupCount = 0;

static const char* robotPrefixes[] = {"Go2_", "G1_", "H1_", "B2_", "X1_"};
static const int prefixCount = 5;

static bool isUnitreeDevice(const char* name) {
    if (!name || !name[0]) return false;
    for (int i = 0; i < prefixCount; i++) {
        if (strncmp(name, robotPrefixes[i], strlen(robotPrefixes[i])) == 0)
            return true;
    }
    return false;
}

static const char* getRobotType(const char* name) {
    if (strncmp(name, "Go2_", 4) == 0) return "Go2";
    if (strncmp(name, "G1_", 3) == 0) return "G1";
    if (strncmp(name, "H1_", 3) == 0) return "H1";
    if (strncmp(name, "B2_", 3) == 0) return "B2";
    if (strncmp(name, "X1_", 3) == 0) return "X1";
    return "?";
}

static bool isDedupCooldown(const uint8_t* mac) {
    unsigned long now = millis();
    for (int i = 0; i < dedupCount; i++) {
        if (memcmp(dedup[i].mac, mac, 6) == 0) {
            if (now - dedup[i].ts < DEDUP_COOLDOWN_MS) return true;
            dedup[i].ts = now;
            return false;
        }
    }
    static int dedupHead = 0;
    int idx;
    if (dedupCount < DEDUP_SIZE) {
        idx = dedupCount++;
    } else {
        idx = dedupHead;
        dedupHead = (dedupHead + 1) % DEDUP_SIZE;
    }
    memcpy(dedup[idx].mac, mac, 6);
    dedup[idx].ts = now;
    return false;
}

// ============================================================================
// BLE Callback
// ============================================================================

class UnipwnCallback : public BLE_SCAN_CB_CLASS {
    BLE_SCAN_CB_ONRESULT(dev) {
        std::string name = dev->haveName() ? dev->getName() : "";
        if (!isUnitreeDevice(name.c_str())) return;

        std::string addrStr = dev->getAddress().toString();
        unsigned int m[6];
        sscanf(addrStr.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
               &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
        uint8_t mac[6] = {(uint8_t)m[0], (uint8_t)m[1], (uint8_t)m[2],
                          (uint8_t)m[3], (uint8_t)m[4], (uint8_t)m[5]};

        if (isDedupCooldown(mac)) return;

        DetectionEvent evt;
        memset(&evt, 0, sizeof(evt));
        evt.engine_id = ENGINE_UNIPWN;
        memcpy(evt.mac, mac, 6);
        evt.rssi = dev->getRSSI();
        evt.channel = 0;
        evt.timestamp_ms = millis();
        evt.method = 0; // unitree_ble

        const char* type = getRobotType(name.c_str());
        strncpy(evt.ext.unipwn.robot_type, type, sizeof(evt.ext.unipwn.robot_type) - 1);
        evt.ext.unipwn.exploited = 0;

        pushDetection(&evt);

        Serial.printf("[UNIPWN] Robot found: %s (%s) RSSI:%d\n",
                      name.c_str(), addrStr.c_str(), dev->getRSSI());
    }
};

static UnipwnCallback scanCb;

// ============================================================================
// Lifecycle
// ============================================================================

static void unipwnInit(void) {
    bleScan = NimBLEDevice::getScan();
    bleScanSetCallbacks(bleScan, &scanCb);
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    dedupCount = 0;
    Serial.println("[UNIPWN] Initialized");
}

static void unipwnStart(void) {
    scanning = true;
    lastScanStart = 0;
    Serial.println("[UNIPWN] Started — scanning for Unitree robots");
}

static void unipwnStop(void) {
    if (bleScan && bleScan->isScanning()) bleScan->stop();
    scanning = false;
    Serial.println("[UNIPWN] Stopped");
}

static void unipwnLoop(void) {
    if (!scanning || !bleScan) return;
    if (millis() - lastScanStart >= 2000) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }
}

const EngineCallbacks unipwnCallbacks = {
    .init   = unipwnInit,
    .start  = unipwnStart,
    .stop   = unipwnStop,
    .loop   = unipwnLoop,
    .config = NULL,
    .name   = "UniPwn"
};
