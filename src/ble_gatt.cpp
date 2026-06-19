/**
 * NimBLE GATT Server implementation.
 *
 * Single service with characteristics for:
 * - Device info (READ)
 * - Engine control (READ, WRITE, NOTIFY)
 * - Detection events (NOTIFY)
 * - Device status (READ, NOTIFY)
 * - GPS receive (WRITE)
 * - Hardware config (READ, WRITE)
 * - Alert config (READ, WRITE)
 * - Foxhunter RSSI (NOTIFY)
 */
#include "ble_gatt.h"
#include "det_spool.h"
#include "engine_registry.h"
#include "ignore_list.h"
#include "engines/pcap.h"
#include "engines/detector.h"
#include "engines/flock_wifi.h"
#include "engines/flock_ble.h"
#include "engines/wardrive.h"
#include "mesh_espnow.h"
#include "ota_handler.h"
#include "wifi_ota_handler.h"
#include <Arduino.h>
#include <Preferences.h>
#include <NimBLEDevice.h>
#include <nvs_flash.h>
#include <esp_ota_ops.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>

// Forward declarations
static NimBLEServer* pServer = nullptr;
static NimBLECharacteristic* chrDeviceInfo = nullptr;
static NimBLECharacteristic* chrEngineControl = nullptr;
static NimBLECharacteristic* chrDetectionEvents = nullptr;
static NimBLECharacteristic* chrDeviceStatus = nullptr;
static NimBLECharacteristic* chrGpsReceive = nullptr;
static NimBLECharacteristic* chrHardwareConfig = nullptr;
static NimBLECharacteristic* chrAlertConfig = nullptr;
static NimBLECharacteristic* chrIgnoreList = nullptr;
static NimBLECharacteristic* chrNodeRadio = nullptr;
static NimBLECharacteristic* chrFoxhunterRssi = nullptr;
static NimBLECharacteristic* chrFoxhunterConfig = nullptr;
static NimBLECharacteristic* chrUnipwnCommand = nullptr;
static NimBLECharacteristic* chrMeshConfig = nullptr;
static NimBLECharacteristic* chrMeshStatus = nullptr;
static NimBLECharacteristic* chrDfuControl = nullptr;
static NimBLECharacteristic* chrDfuData = nullptr;
static NimBLECharacteristic* chrSystemControl = nullptr;
static NimBLECharacteristic* chrWifiConfig = nullptr;
static NimBLECharacteristic* chrPcapControl = nullptr;
static NimBLECharacteristic* chrPcapStats = nullptr;
static NimBLECharacteristic* chrPcapData = nullptr;

static bool phoneConnected = false;
static volatile bool pcapDownloadRunning = false;
static volatile uint32_t mgrPhoneGoneMs = 0;
static volatile bool mgrTornDown = false;
static bool offlineScanEnabled = false;
bool bleGattOfflineScanEnabled() { return offlineScanEnabled; }
void offlineScanEnabledSetFromPref(bool v) { offlineScanEnabled = v; }
#define MGR_PHONE_GRACE_MS 8000

#ifdef OUISPY_ROLE_MANAGER
static volatile uint8_t  mgrCommandedMask = 0;
static volatile uint8_t  mgrCommandedStates[ENGINE_COUNT] = {0};
static volatile uint8_t  mgrPcapMode = 0;
static volatile uint8_t  mgrPcapChStart = 1;
static volatile uint8_t  mgrPcapChEnd = 11;
static volatile uint32_t mgrPcapStartedMs = 0;
static volatile uint8_t  mgrAutoPcapEnabled = 0;
static volatile uint16_t mgrAutoPcapDurationSec = 10;
static volatile uint16_t mgrAutoPcapCooldownSec = 0;
static void mgrAutoPcapSyncToNodes(void);

static void mgrAutoPcapSave(void) {
    Preferences p;
    p.begin("ouispy-mgrap", false);
    p.putBool("en", mgrAutoPcapEnabled != 0);
    p.putUShort("dur", mgrAutoPcapDurationSec);
    p.putUShort("cool", mgrAutoPcapCooldownSec);
    p.end();
}

static void mgrAutoPcapLoad(void) {
    Preferences p;
    p.begin("ouispy-mgrap", true);
    mgrAutoPcapEnabled = p.getBool("en", false) ? 1 : 0;
    mgrAutoPcapDurationSec = p.getUShort("dur", 10);
    mgrAutoPcapCooldownSec = p.getUShort("cool", 0);
    p.end();
}

static uint8_t mgrWardriveCfg[16] = {
    0x03, 0xFA, 0x00, 0x96, 0x00, 0x20, 0x03, 0xDC, 0x05, 0x01, 0x0B
};
static uint8_t mgrWardriveCfgLen = 11;

#define MGR_NODE_RADIO_MAX MESH_LIVE_NODES_MAX
static struct { char id[MESH_NODE_ID_LEN]; uint8_t radio; } mgrNodeRadio[MGR_NODE_RADIO_MAX];
static uint8_t mgrNodeRadioCount = 0;

static uint8_t mgrGetNodeRadio(const char* id) {
    for (uint8_t i = 0; i < mgrNodeRadioCount; i++)
        if (memcmp(mgrNodeRadio[i].id, id, MESH_NODE_ID_LEN - 1) == 0)
            return mgrNodeRadio[i].radio;
    return 0x03;
}

static void mgrApplyLocalRadio(void) {
    uint8_t r = mgrGetNodeRadio(meshGetLocalNodeId());
    if (r == 0) r = 0x03;
    flockWifiSetRadioGate((r & 0x01) != 0);
    flockBleSetRadioGate((r & 0x02) != 0);
    wardriveSetRadioMask(r);
}

static void mgrNodeRadioSave(void) {
    Preferences p;
    p.begin("ouispy-nrad", false);
    p.putUChar("n", mgrNodeRadioCount);
    p.putBytes("map", mgrNodeRadio, (size_t)mgrNodeRadioCount * sizeof(mgrNodeRadio[0]));
    p.end();
}

static void mgrNodeRadioLoad(void) {
    Preferences p;
    p.begin("ouispy-nrad", true);
    uint8_t n = p.getUChar("n", 0);
    if (n > MGR_NODE_RADIO_MAX) n = MGR_NODE_RADIO_MAX;
    size_t want = (size_t)n * sizeof(mgrNodeRadio[0]);
    size_t got = p.getBytes("map", mgrNodeRadio, want);
    mgrNodeRadioCount = (got == want) ? n : 0;
    p.end();
}

static const uint8_t kHopperMask = ENGINE_BITMASK(ENGINE_WARDRIVE) | ENGINE_BITMASK(ENGINE_FLOCK_WIFI)
                                 | ENGINE_BITMASK(ENGINE_DETECTOR) | ENGINE_BITMASK(ENGINE_FOXHUNTER);

static bool mgrFanoutSkyspyNode(char* outId) {
    if (!(mgrCommandedMask & ENGINE_BITMASK(ENGINE_SKYSPY))) return false;
    if (!(mgrCommandedMask & kHopperMask)) return false;
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    char ids[MESH_LIVE_NODES_MAX][MESH_NODE_ID_LEN];
    uint8_t nn = 0;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        memcpy(ids[nn++], live[i].id, MESH_NODE_ID_LEN);
    }
    if (nn < 2) return false;
    int lo = 0;
    for (int i = 1; i < nn; i++)
        if (memcmp(ids[i], ids[lo], MESH_NODE_ID_LEN - 1) < 0) lo = i;
    memcpy(outId, ids[lo], MESH_NODE_ID_LEN);
    return true;
}

static uint8_t mgrNodeDenyMask(const char* id) {
    char skyId[MESH_NODE_ID_LEN];
    if (!mgrFanoutSkyspyNode(skyId)) return 0;
    return (memcmp(id, skyId, MESH_NODE_ID_LEN - 1) == 0)
             ? kHopperMask : ENGINE_BITMASK(ENGINE_SKYSPY);
}

static uint32_t mgrLastDenyHash = 0xFFFFFFFFu;
static void mgrPushEngineDeny(void) {
    if (!meshIsEnabled()) return;
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    uint32_t h = 2166136261u;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        uint8_t deny = mgrNodeDenyMask(live[i].id);
        for (int j = 0; j < MESH_NODE_ID_LEN; j++) { h ^= (uint8_t)live[i].id[j]; h *= 16777619u; }
        h ^= deny; h *= 16777619u;
    }
    bool changed = (h != mgrLastDenyHash);
    mgrLastDenyHash = h;
    const uint8_t pcapBit = ENGINE_BITMASK(ENGINE_PCAP);
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        uint8_t deny = mgrNodeDenyMask(live[i].id);
        bool nonCompliant = (live[i].active_engines & deny & ~pcapBit) != 0;
        if (!changed && !nonCompliant) continue;
        uint8_t out[CFG_TGT_OVERHEAD + 1];
        out[0] = CFG_TGT_PREFIX;
        memcpy(out + 1, live[i].id, MESH_NODE_ID_LEN - 1);
        out[5] = 0x00;
        out[CFG_TGT_OVERHEAD] = deny;
        meshBroadcastCommand(0x12, 0, out, (uint8_t)(CFG_TGT_OVERHEAD + 1));
        Serial.printf("[MGR-FANOUT] node=%.4s deny=0x%02x%s\n",
                      live[i].id, deny, nonCompliant ? " (re-push)" : "");
    }
}

static void mgrBroadcastWardriveSliced(const uint8_t* cfg, uint8_t len) {
    if (len < 11) { meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, len); return; }

    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    MeshLiveNode nodes[MESH_LIVE_NODES_MAX];
    uint8_t radios[MESH_LIVE_NODES_MAX];
    size_t nn = 0;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        nodes[nn] = live[i];
        radios[nn] = mgrGetNodeRadio(live[i].id);
        nn++;
    }
    if (nn == 0) { meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, len); return; }

    uint8_t cs = cfg[9], ce = cfg[10];
    if (cs < 1 || cs > 14) cs = 1;
    if (ce < cs || ce > 14) ce = 11;
    uint16_t span = (uint16_t)(ce - cs + 1);

    char skyId[MESH_NODE_ID_LEN];
    bool fanout = mgrFanoutSkyspyNode(skyId);

    uint8_t wifiCount = 0;
    for (size_t i = 0; i < nn; i++) {
        if (fanout && memcmp(nodes[i].id, skyId, MESH_NODE_ID_LEN - 1) == 0) continue;
        if (radios[i] & 0x01) wifiCount++;
    }

    uint8_t wifiIdx = 0;
    for (size_t i = 0; i < nn; i++) {
        uint8_t r = radios[i];
        bool isSky = fanout && memcmp(nodes[i].id, skyId, MESH_NODE_ID_LEN - 1) == 0;
        uint8_t sStart = cs, sEnd = ce;
        if (!isSky && (r & 0x01) && wifiCount > 1) {
            sStart = (uint8_t)(cs + (span * wifiIdx) / wifiCount);
            sEnd   = (uint8_t)(cs + (span * (wifiIdx + 1)) / wifiCount - 1);
            if (sEnd < sStart) sEnd = sStart;
        }
        if (!isSky && (r & 0x01)) wifiIdx++;

        uint8_t clen = len > 64 ? 64 : len;
        uint8_t out[CFG_TGT_OVERHEAD + 64];
        out[0] = CFG_TGT_PREFIX;
        memcpy(out + 1, nodes[i].id, MESH_NODE_ID_LEN - 1);
        out[5] = 0x00;
        memcpy(out + CFG_TGT_OVERHEAD, cfg, clen);
        out[CFG_TGT_OVERHEAD + 0]  = r;
        out[CFG_TGT_OVERHEAD + 9]  = sStart;
        out[CFG_TGT_OVERHEAD + 10] = sEnd;
        meshBroadcastCommand(0x10, ENGINE_WARDRIVE, out, (uint8_t)(CFG_TGT_OVERHEAD + clen));
        Serial.printf("[MGR-SLICE] node=%.4s radio=0x%02X ch=%u-%u (%u nodes, %u wifi)\n",
                      nodes[i].id, r, sStart, sEnd, (unsigned)nn, wifiCount);
    }
}

static void mgrBroadcastNodeRadioConfig(uint8_t engineId) {
    if (!meshIsEnabled()) return;
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        uint8_t r = mgrGetNodeRadio(live[i].id);
        if (r == 0) r = 0x03;
        uint8_t out[CFG_TGT_OVERHEAD + 1];
        out[0] = CFG_TGT_PREFIX;
        memcpy(out + 1, live[i].id, MESH_NODE_ID_LEN - 1);
        out[5] = 0x00;
        out[CFG_TGT_OVERHEAD] = r;
        meshBroadcastCommand(0x10, engineId, out, (uint8_t)(CFG_TGT_OVERHEAD + 1));
        Serial.printf("[NODE-RADIO] eng=%u node=%.4s radio=0x%02X\n",
                      engineId, live[i].id, r);
    }
}

static void mgrSetNodeRadioList(const uint8_t* data, size_t len) {
    if (len < 1) return;
    uint8_t count = data[0];
    if ((size_t)1 + (size_t)count * 5 > len) return;
    if (count > MGR_NODE_RADIO_MAX) count = MGR_NODE_RADIO_MAX;
    mgrNodeRadioCount = 0;
    for (uint8_t i = 0; i < count; i++) {
        const uint8_t* e = data + 1 + (size_t)i * 5;
        memcpy(mgrNodeRadio[mgrNodeRadioCount].id, e, MESH_NODE_ID_LEN - 1);
        mgrNodeRadio[mgrNodeRadioCount].id[MESH_NODE_ID_LEN - 1] = 0;
        uint8_t r = e[4] & 0x03;
        mgrNodeRadio[mgrNodeRadioCount].radio = r ? r : 0x03;
        mgrNodeRadioCount++;
    }
    mgrNodeRadioSave();
    Serial.printf("[NODE-RADIO] set %u entries\n", mgrNodeRadioCount);
    mgrApplyLocalRadio();
    if ((mgrCommandedMask & ENGINE_BITMASK(ENGINE_WARDRIVE)) && meshIsEnabled())
        mgrBroadcastWardriveSliced(mgrWardriveCfg, mgrWardriveCfgLen);
}

#define MGR_SLICE_DEBOUNCE 3
static uint32_t mgrLastSliceSetHash = 0xFFFFFFFFu;
static uint32_t mgrPendingSetHash = 0;
static uint8_t  mgrPendingStable = 0;
#endif

void bleGattMaybeResliceWardrive(void) {
#ifdef OUISPY_ROLE_MANAGER
    if (!(mgrCommandedMask & ENGINE_BITMASK(ENGINE_WARDRIVE)) || !meshIsEnabled()) {
        mgrLastSliceSetHash = 0xFFFFFFFFu;
        mgrPendingStable = 0;
        return;
    }
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    char ids[MESH_LIVE_NODES_MAX][MESH_NODE_ID_LEN];
    uint8_t nn = 0;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        memcpy(ids[nn++], live[i].id, MESH_NODE_ID_LEN);
    }
    for (int a = 1; a < nn; a++) {
        char tmp[MESH_NODE_ID_LEN];
        memcpy(tmp, ids[a], MESH_NODE_ID_LEN);
        int b = a - 1;
        while (b >= 0 && memcmp(ids[b], tmp, MESH_NODE_ID_LEN) > 0) {
            memcpy(ids[b + 1], ids[b], MESH_NODE_ID_LEN);
            b--;
        }
        memcpy(ids[b + 1], tmp, MESH_NODE_ID_LEN);
    }
    uint32_t h = 2166136261u;
    h ^= nn; h *= 16777619u;
    for (int i = 0; i < nn; i++) {
        for (int j = 0; j < MESH_NODE_ID_LEN; j++) {
            h ^= (uint8_t)ids[i][j]; h *= 16777619u;
        }
    }
    if (h == mgrLastSliceSetHash) { mgrPendingStable = 0; return; }
    if (h == mgrPendingSetHash) {
        if (mgrPendingStable < 255) mgrPendingStable++;
    } else {
        mgrPendingSetHash = h;
        mgrPendingStable = 1;
    }
    if (mgrPendingStable < MGR_SLICE_DEBOUNCE) return;
    mgrLastSliceSetHash = h;
    mgrPendingStable = 0;
    Serial.printf("[MGR-SLICE] node set changed (n=%u, stable) — re-slicing wardrive\n", nn);
    mgrBroadcastWardriveSliced(mgrWardriveCfg, mgrWardriveCfgLen);
#endif
}

#if defined(OUISPY_STOP_SELFTEST) || defined(OUISPY_ENGSTRESS)
void mgrDebugSetCommanded(uint8_t mask) {
    mgrCommandedMask = mask;
    for (int i = 0; i < ENGINE_COUNT; i++)
        mgrCommandedStates[i] = (mask & (1u << i)) ? (uint8_t)ESTATE_SCANNING : (uint8_t)ESTATE_DISABLED;
}
#endif

#ifdef OUISPY_NETCOUNT
void bleGattNetcountDrive(void) {
#ifdef OUISPY_ROLE_MANAGER
    mgrCommandedMask |= ENGINE_BITMASK(ENGINE_WARDRIVE);
    mgrCommandedStates[ENGINE_WARDRIVE] = (uint8_t)ESTATE_SCANNING;
    mgrBroadcastWardriveSliced(mgrWardriveCfg, mgrWardriveCfgLen);
    delay(120);
    meshBroadcastCommand(0x01, ENGINE_WARDRIVE, nullptr, 0);
#ifdef OUISPY_NC_ALLENGINES
    const uint8_t ncExtra[] = { ENGINE_DETECTOR, ENGINE_FLOCK_BLE, ENGINE_FLOCK_WIFI, ENGINE_SKYSPY };
    for (uint8_t i = 0; i < sizeof(ncExtra); i++) {
        mgrCommandedMask |= ENGINE_BITMASK(ncExtra[i]);
        mgrCommandedStates[ncExtra[i]] = (uint8_t)ESTATE_SCANNING;
        delay(120);
        meshBroadcastCommand(0x01, ncExtra[i], nullptr, 0);
    }
#endif
#endif
}
#endif

void bleGattReconcileEngines(void) {
#ifdef OUISPY_ROLE_MANAGER
    // Advertising watchdog: if no phone is connected, ensure we are advertising.
    // Under heavy mesh load NimBLE can leave advertising stopped after a
    // disconnect, making the manager invisible/unconnectable until a power-cycle.
    if (!phoneConnected) {
        NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
        if (adv && !adv->isAdvertising()) {
            NimBLEDevice::startAdvertising();
            Serial.println("[MGR] advertising was DOWN — restarted (watchdog)");
        }
    }
    if (mgrPhoneGoneMs != 0 && !phoneConnected && !mgrTornDown &&
        (millis() - mgrPhoneGoneMs) > MGR_PHONE_GRACE_MS) {
        if (offlineScanEnabled) {
            mgrPhoneGoneMs = 0;
        } else {
            mgrTornDown = true;
            g_meshManagerActive = false;
            mgrCommandedMask = 0;
            for (int i = 0; i < ENGINE_COUNT; i++) {
                mgrCommandedStates[i] = (uint8_t)ESTATE_DISABLED;
                if (i != ENGINE_PCAP) meshMarkNodesEngine((uint8_t)i, false);
            }
            if (meshIsEnabled()) meshBroadcastCommand(0x0F, 0, nullptr, 0);
            Serial.println("[BLE] App gone (grace expired) — DISABLE_ALL + manager demoted (nodes will self-idle)");
        }
    }
    if (!meshIsEnabled()) return;
    mgrPushEngineDeny();
    const uint8_t pcapBit = ENGINE_BITMASK(ENGINE_PCAP);
    uint8_t desired = (uint8_t)(mgrCommandedMask & ~pcapBit);
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    uint8_t missingAny = 0;
    uint8_t extraAny = 0;
    uint8_t nodeCount = 0;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        nodeCount++;
        if (live[i].active_engines & pcapBit) continue;
        uint8_t nodeDesired = (uint8_t)(desired & ~mgrNodeDenyMask(live[i].id));
        uint8_t have = (uint8_t)(live[i].active_engines & ~pcapBit);
        missingAny |= (uint8_t)(nodeDesired & ~have);
        extraAny   |= (uint8_t)(have & ~desired);
    }
    if (nodeCount == 0) return;
    static uint32_t lastEnable[ENGINE_COUNT] = {0};
    static uint32_t lastDisable[ENGINE_COUNT] = {0};
    uint32_t now = millis();
    for (int e = 0; e < ENGINE_COUNT; e++) {
        if (e == ENGINE_PCAP || kEngineTargetable[e]) continue;
        if (missingAny & ENGINE_BITMASK(e)) {
            if (lastEnable[e] != 0 && (now - lastEnable[e]) < 6000) continue;
            lastEnable[e] = now;
            meshBroadcastCommand(0x01, (uint8_t)e, nullptr, 0);
            meshMarkNodesEngine((uint8_t)e, true);
            if (e == ENGINE_FLOCK_WIFI || e == ENGINE_FLOCK_BLE ||
                e == ENGINE_DETECTOR || e == ENGINE_SKYSPY) {
                mgrBroadcastNodeRadioConfig((uint8_t)e);
            }
            Serial.printf("[MGR-RECONCILE] engine %d missing — re-enable\n", e);
        } else if (extraAny & ENGINE_BITMASK(e)) {
            if (lastDisable[e] != 0 && (now - lastDisable[e]) < 6000) continue;
            lastDisable[e] = now;
            meshBroadcastCommand(0x00, (uint8_t)e, nullptr, 0);
            meshMarkNodesEngine((uint8_t)e, false);
            Serial.printf("[MGR-RECONCILE] engine %d not commanded — disable\n", e);
        }
    }
#endif
}

class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* server) override {
        phoneConnected = true;
#ifdef OUISPY_ROLE_MANAGER
        mgrPhoneGoneMs = 0;
        mgrTornDown = false;
        g_meshManagerActive = true;
#endif
        NimBLEScan* scan = NimBLEDevice::getScan();
        if (scan && scan->isScanning()) {
            scan->stop();
        }

        // Request tight conn params for OTA throughput.
        // iOS honors within its limits — Apple accepts 15ms minimum for
        // peripherals. Units: interval * 1.25ms, timeout * 10ms.
        // min=12 (15ms), max=24 (30ms), latency=0, timeout=400 (4s).
        uint16_t connHandle = server->getPeerInfo(0).getConnHandle();
        server->updateConnParams(connHandle, 12, 24, 0, 400);
        Serial.println("[BLE] Phone connected, requested fast conn params");
    }

    void onDisconnect(NimBLEServer* server) override {
        phoneConnected = false;
        hwAlertsSuppressed = false;
#ifdef OUISPY_ROLE_MANAGER
        mgrPhoneGoneMs = millis();
        Serial.println("[BLE] Phone disconnected (manager) — teardown deferred (grace)");
#else
        if (!offlineScanEnabled) {
            engineDisableAll();
            Serial.println("[BLE] Phone disconnected — engines off");
        } else {
            Serial.println("[BLE] Phone disconnected — offline scan, engines kept");
        }
#endif
        NimBLEDevice::startAdvertising();
    }
};

class EngineControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 2) return;

        EngineCommand cmd;
        cmd.command = (uint8_t)val[0];
        cmd.engine_id = (uint8_t)val[1];
        cmd.payload_len = 0;

        if (val.length() > 2) {
            cmd.payload_len = (val.length() - 2 > 64) ? 64 : (val.length() - 2);
            memcpy(cmd.payload, val.data() + 2, cmd.payload_len);
        }

#ifndef OUISPY_ROLE_MANAGER
        bool targetOk = true;
        bool targetableEngine = (cmd.engine_id < ENGINE_COUNT)
                                 && kEngineTargetable[cmd.engine_id];
        if (targetableEngine &&
            (cmd.command == 0x01 || cmd.command == 0x00) &&
            cmd.payload_len >= MESH_NODE_ID_LEN) {
            const char* self = meshGetLocalNodeId();
            if (memcmp(cmd.payload, self, MESH_NODE_ID_LEN) != 0) {
                targetOk = false;
                Serial.printf("[BLE] eng=%u target=%.4s != self=%s — ignored\n",
                              cmd.engine_id, (const char*)cmd.payload, self);
            }
        }
        if (targetOk && engineCmdQueue != NULL) {
            xQueueSend(engineCmdQueue, &cmd, pdMS_TO_TICKS(10));
        }
#endif

        const char* cmdName = cmd.command == 0x01 ? "ENABLE"
                             : cmd.command == 0x0F ? "DISABLE_ALL"
                             : cmd.command == 0x10 ? "CONFIG"
                             : "DISABLE";
        Serial.printf("[BLE] Engine command: %s engine %d\n", cmdName, cmd.engine_id);

#ifdef OUISPY_ROLE_MANAGER
        if (cmd.command == 0x01 && cmd.engine_id < ENGINE_COUNT) {
            mgrCommandedMask |= (1u << cmd.engine_id);
            mgrCommandedStates[cmd.engine_id] = (uint8_t)ESTATE_SCANNING;
            if (cmd.engine_id == ENGINE_PCAP) mgrPcapStartedMs = millis();
            if (cmd.engine_id != ENGINE_PCAP) meshMarkNodesEngine(cmd.engine_id, true);
            if (cmd.engine_id == ENGINE_FLOCK_WIFI || cmd.engine_id == ENGINE_FLOCK_BLE ||
                cmd.engine_id == ENGINE_WARDRIVE)
                mgrApplyLocalRadio();
        } else if (cmd.command == 0x00 && cmd.engine_id < ENGINE_COUNT) {
            mgrCommandedMask &= ~(1u << cmd.engine_id);
            mgrCommandedStates[cmd.engine_id] = (uint8_t)ESTATE_DISABLED;
            if (cmd.engine_id == ENGINE_PCAP) mgrPcapStartedMs = 0;
            if (cmd.engine_id != ENGINE_PCAP) meshMarkNodesEngine(cmd.engine_id, false);
        } else if (cmd.command == 0x0F) {
            mgrCommandedMask = 0;
            for (int i = 0; i < ENGINE_COUNT; i++) {
                mgrCommandedStates[i] = (uint8_t)ESTATE_DISABLED;
                if (i != ENGINE_PCAP) meshMarkNodesEngine((uint8_t)i, false);
            }
            mgrPcapStartedMs = 0;
        }
        if (cmd.command == 0x10 && cmd.engine_id == ENGINE_PCAP && cmd.payload_len >= 2) {
            const uint8_t* p = cmd.payload;
            uint8_t plen = cmd.payload_len;
            if (plen >= 4 && p[0] == 0x01) {
                mgrPcapMode = p[1];
                mgrPcapChStart = p[2];
                mgrPcapChEnd = p[3];
            } else if (p[0] == 0x10 && plen >= 2) {
                mgrAutoPcapEnabled = (p[1] != 0) ? 1 : 0;
                mgrAutoPcapSave();
            } else if (p[0] == 0x11 && plen >= 3) {
                mgrAutoPcapDurationSec = (uint16_t)(p[1] | (p[2] << 8));
                mgrAutoPcapSave();
            } else if (p[0] == 0x12 && plen >= 3) {
                mgrAutoPcapCooldownSec = (uint16_t)(p[1] | (p[2] << 8));
                mgrAutoPcapSave();
            }
            if (p[0] == 0x10 || p[0] == 0x11 || p[0] == 0x12) {
                mgrAutoPcapSyncToNodes();
            }
        }
        if (cmd.engine_id == ENGINE_WARDRIVE && cmd.command == 0x10) {
            if (cmd.payload_len >= 11) {
                mgrWardriveCfgLen = cmd.payload_len > sizeof(mgrWardriveCfg)
                                      ? sizeof(mgrWardriveCfg) : cmd.payload_len;
                memcpy(mgrWardriveCfg, cmd.payload, mgrWardriveCfgLen);
            } else if (cmd.payload_len >= 1) {
                mgrWardriveCfg[0] = cmd.payload[0] & 0x03;
                if (mgrWardriveCfg[0] == 0) mgrWardriveCfg[0] = 0x03;
            }
        }
        if (meshIsEnabled()) {
            if (cmd.engine_id == ENGINE_WARDRIVE &&
                (cmd.command == 0x10 || cmd.command == 0x01)) {
                mgrBroadcastWardriveSliced(mgrWardriveCfg, mgrWardriveCfgLen);
                if (cmd.command == 0x01) {
                    meshBroadcastCommand(cmd.command, cmd.engine_id,
                        cmd.payload_len > 0 ? cmd.payload : nullptr, cmd.payload_len);
                }
            } else {
                meshBroadcastCommand(cmd.command, cmd.engine_id,
                    cmd.payload_len > 0 ? cmd.payload : nullptr,
                    cmd.payload_len);
                if (cmd.command == 0x01 &&
                    (cmd.engine_id == ENGINE_DETECTOR ||
                     cmd.engine_id == ENGINE_SKYSPY ||
                     cmd.engine_id == ENGINE_FLOCK_WIFI ||
                     cmd.engine_id == ENGINE_FLOCK_BLE)) {
                    mgrBroadcastNodeRadioConfig(cmd.engine_id);
                }
            }
        }
        bleGattNotifyEngineState();
        if (cmd.engine_id == ENGINE_PCAP || cmd.command == 0x0F) {
            bleGattNotifyPcapStats();
        }
#endif
    }

    void onRead(NimBLECharacteristic* chr) override {
        uint8_t buf[2 + ENGINE_COUNT];
#ifdef OUISPY_ROLE_MANAGER
        buf[0] = (1u << ENGINE_COUNT) - 1u;
        buf[1] = mgrCommandedMask;
        for (int i = 0; i < ENGINE_COUNT; i++) {
            buf[2 + i] = mgrCommandedStates[i];
        }
#else
        buf[0] = engineGetAvailableMask();
        buf[1] = engineGetActiveMask();
        for (int i = 0; i < ENGINE_COUNT; i++) {
            buf[2 + i] = (uint8_t)engineGetState((EngineId)i);
        }
#endif
        chr->setValue(buf, 2 + ENGINE_COUNT);
    }
};

class GpsReceiveCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < sizeof(GpsData)) return;

        GpsData gps;
        memcpy(&gps, val.data(), sizeof(GpsData));
        memcpy((void*)&currentGps, &gps, sizeof(GpsData));
        gpsValid = true;

        if (val.length() > sizeof(GpsData)) {
            hwAlertsSuppressed = ((const uint8_t*)val.data())[sizeof(GpsData)] != 0;
        }
    }
};

void hardwareConfigApply(const uint8_t* data, size_t len) {
    if (len < 3) return;
    static uint8_t lastCfg[8]; static size_t lastCfgLen = 0; static bool haveCfg = false;
    if (haveCfg && len == lastCfgLen && len <= sizeof(lastCfg) && memcmp(lastCfg, data, len) == 0) return;
    if (len <= sizeof(lastCfg)) { memcpy(lastCfg, data, len); lastCfgLen = len; haveCfg = true; }
    bool buzzer = data[0] != 0;
    bool led = data[1] != 0;
    uint8_t brightness = data[2];
    uint8_t buzzerVol = (len >= 4) ? data[3] : 100;

    hwBuzzerEnabled = buzzer;
    hwBuzzerVolume = buzzerVol;
    hwLedEnabled = led;
    hwNeopixelBrightness = brightness;

    Preferences p;
    p.begin("ouispy-hw", false);
    p.putBool("buzzer", buzzer);
    p.putUChar("bz_vol", buzzerVol);
    p.putBool("led", led);
    p.putUChar("neo_brt", brightness);
    if (len >= 5) {
        bool flockExt = data[4] != 0;
        p.putBool("flock_ext", flockExt);
        flockSetExtendedOui(flockExt);
    }
    if (len >= 6) {
        offlineScanEnabled = data[5] != 0;
        p.putBool("offl_scan", offlineScanEnabled);
    }
    p.end();

    Serial.printf("[CFG] Hardware: buzzer=%d vol=%d led=%d brightness=%d flock_ext=%d\n",
                  buzzer, buzzerVol, led, brightness, (int)flockGetExtendedOui());
}

void alertConfigApply(const uint8_t* data, size_t len) {
    if (len < 8) return;
    static uint8_t lastCfg[16]; static size_t lastCfgLen = 0; static bool haveCfg = false;
    if (haveCfg && len == lastCfgLen && len <= sizeof(lastCfg) && memcmp(lastCfg, data, len) == 0) return;
    if (len <= sizeof(lastCfg)) { memcpy(lastCfg, data, len); lastCfgLen = len; haveCfg = true; }
    uint16_t cooldown   = data[0] | (data[1] << 8);
    uint16_t heartbeat  = data[2] | (data[3] << 8);
    uint16_t rediscover = data[4] | (data[5] << 8);
    uint16_t hbActive   = data[6] | (data[7] << 8);

    Preferences p;
    p.begin("ouispy-alert", false);
    p.putUShort("cooldown", cooldown);
    p.putUShort("heartbeat", heartbeat);
    p.putUShort("rediscover", rediscover);
    p.putUShort("hb_active", hbActive);
    p.end();

    engineLoadAlertPrefs();

    Serial.printf("[CFG] Alert: cool=%d hb=%d redis=%d active=%d\n",
                  cooldown, heartbeat, rediscover, hbActive);
}

void autoPcapConfigApply(const uint8_t* data, size_t len) {
    if (len < 1) return;
    static uint8_t lastCfg[8]; static size_t lastCfgLen = 0; static bool haveCfg = false;
    if (haveCfg && len == lastCfgLen && len <= sizeof(lastCfg) && memcmp(lastCfg, data, len) == 0) return;
    if (len <= sizeof(lastCfg)) { memcpy(lastCfg, data, len); lastCfgLen = len; haveCfg = true; }
    uint16_t dur  = (len >= 3) ? (uint16_t)(data[1] | (data[2] << 8)) : 0;
    uint16_t cool = (len >= 5) ? (uint16_t)(data[3] | (data[4] << 8)) : 0;
    engineSetAutoPcap(data[0] != 0);
    if (len >= 3) engineSetAutoPcapDuration(dur);
    if (len >= 5) engineSetAutoPcapCooldown(cool);
    Serial.printf("[CFG] AutoPcap: en=%d dur=%us cool=%us\n", data[0], dur, cool);
}

#ifdef OUISPY_ROLE_MANAGER
static uint8_t mgrHwCfg[8]    = {0}; static uint8_t mgrHwCfgLen = 0;
static uint8_t mgrAlertCfg[8] = {0}; static uint8_t mgrAlertCfgLen = 0;
static uint8_t mgrApCfg[5]    = {0}; static uint8_t mgrApCfgLen = 0;
static uint8_t mgrFoxCfg[7]   = {0}; static uint8_t mgrFoxCfgLen = 0;

static void mgrCacheConfig(uint8_t kind, const uint8_t* data, size_t len) {
    if (kind == MESH_CFG_KIND_HW) {
        mgrHwCfgLen = len > sizeof(mgrHwCfg) ? sizeof(mgrHwCfg) : (uint8_t)len;
        memcpy(mgrHwCfg, data, mgrHwCfgLen);
    } else if (kind == MESH_CFG_KIND_ALERT) {
        mgrAlertCfgLen = len > sizeof(mgrAlertCfg) ? sizeof(mgrAlertCfg) : (uint8_t)len;
        memcpy(mgrAlertCfg, data, mgrAlertCfgLen);
    } else if (kind == MESH_CFG_KIND_AUTOPCAP) {
        mgrApCfgLen = len > sizeof(mgrApCfg) ? sizeof(mgrApCfg) : (uint8_t)len;
        memcpy(mgrApCfg, data, mgrApCfgLen);
    } else if (kind == MESH_CFG_KIND_FOXHUNTER) {
        mgrFoxCfgLen = len > sizeof(mgrFoxCfg) ? sizeof(mgrFoxCfg) : (uint8_t)len;
        memcpy(mgrFoxCfg, data, mgrFoxCfgLen);
    }
}

static void mgrAutoPcapSyncToNodes(void) {
    uint8_t ap[5] = {
        (uint8_t)mgrAutoPcapEnabled,
        (uint8_t)(mgrAutoPcapDurationSec & 0xFF), (uint8_t)(mgrAutoPcapDurationSec >> 8),
        (uint8_t)(mgrAutoPcapCooldownSec & 0xFF), (uint8_t)(mgrAutoPcapCooldownSec >> 8)
    };
    mgrCacheConfig(MESH_CFG_KIND_AUTOPCAP, ap, sizeof(ap));
    if (meshIsEnabled()) meshBroadcastConfig(MESH_CFG_KIND_AUTOPCAP, ap, sizeof(ap));
}

void bleGattRebroadcastConfigs(void) {
    if (!meshIsEnabled()) return;
    if (mgrHwCfgLen)    meshBroadcastConfig(MESH_CFG_KIND_HW, mgrHwCfg, mgrHwCfgLen);
    if (mgrAlertCfgLen) meshBroadcastConfig(MESH_CFG_KIND_ALERT, mgrAlertCfg, mgrAlertCfgLen);
    if (mgrApCfgLen)    meshBroadcastConfig(MESH_CFG_KIND_AUTOPCAP, mgrApCfg, mgrApCfgLen);
    if (mgrFoxCfgLen)   meshBroadcastConfig(MESH_CFG_KIND_FOXHUNTER, mgrFoxCfg, mgrFoxCfgLen);

    uint8_t m = mgrCommandedMask;
    if (m & ENGINE_BITMASK(ENGINE_FLOCK_WIFI)) mgrBroadcastNodeRadioConfig(ENGINE_FLOCK_WIFI);
    if (m & ENGINE_BITMASK(ENGINE_FLOCK_BLE))  mgrBroadcastNodeRadioConfig(ENGINE_FLOCK_BLE);
    if (m & ENGINE_BITMASK(ENGINE_DETECTOR))   mgrBroadcastNodeRadioConfig(ENGINE_DETECTOR);
    if (m & ENGINE_BITMASK(ENGINE_SKYSPY))     mgrBroadcastNodeRadioConfig(ENGINE_SKYSPY);
    mgrApplyLocalRadio();
}

static void mgrLoadConfigCaches(void) {
    Preferences p;
    p.begin("ouispy-hw", true);
    uint8_t hw[4];
    hw[0] = p.getBool("buzzer", true) ? 1 : 0;
    hw[1] = p.getBool("led", true) ? 1 : 0;
    hw[2] = p.getUChar("neo_brt", 50);
    hw[3] = p.getUChar("bz_vol", 100);
    p.end();
    mgrCacheConfig(MESH_CFG_KIND_HW, hw, 4);

    Preferences q;
    q.begin("ouispy-alert", true);
    uint16_t cool = q.getUShort("cooldown", 5000);
    uint16_t hb   = q.getUShort("heartbeat", 30000);
    uint16_t rd   = q.getUShort("rediscover", 30000);
    uint16_t act  = q.getUShort("hb_active", 3000);
    q.end();
    uint8_t al[8] = { (uint8_t)(cool & 0xFF), (uint8_t)(cool >> 8),
                      (uint8_t)(hb & 0xFF),   (uint8_t)(hb >> 8),
                      (uint8_t)(rd & 0xFF),   (uint8_t)(rd >> 8),
                      (uint8_t)(act & 0xFF),  (uint8_t)(act >> 8) };
    mgrCacheConfig(MESH_CFG_KIND_ALERT, al, 8);

    uint8_t ap[5] = { (uint8_t)mgrAutoPcapEnabled,
                      (uint8_t)(mgrAutoPcapDurationSec & 0xFF), (uint8_t)(mgrAutoPcapDurationSec >> 8),
                      (uint8_t)(mgrAutoPcapCooldownSec & 0xFF),  (uint8_t)(mgrAutoPcapCooldownSec >> 8) };
    mgrCacheConfig(MESH_CFG_KIND_AUTOPCAP, ap, 5);
}
#endif

class HardwareConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        hardwareConfigApply((const uint8_t*)val.data(), val.length());
#ifdef OUISPY_ROLE_MANAGER
        mgrCacheConfig(MESH_CFG_KIND_HW, (const uint8_t*)val.data(), val.length());
        if (meshIsEnabled())
            meshBroadcastConfig(MESH_CFG_KIND_HW, (const uint8_t*)val.data(), val.length());
#endif
    }

    void onRead(NimBLECharacteristic* chr) override {
        Preferences p;
        p.begin("ouispy-hw", true);
        uint8_t buf[6];
        buf[0] = p.getBool("buzzer", true) ? 1 : 0;
        buf[1] = p.getBool("led", true) ? 1 : 0;
        buf[2] = p.getUChar("neo_brt", 50);
        buf[3] = p.getUChar("bz_vol", 100);
        buf[4] = p.getBool("flock_ext", false) ? 1 : 0;
        buf[5] = p.getBool("offl_scan", false) ? 1 : 0;
        p.end();
        chr->setValue(buf, 6);
    }
};

class AlertConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        alertConfigApply((const uint8_t*)val.data(), val.length());
#ifdef OUISPY_ROLE_MANAGER
        mgrCacheConfig(MESH_CFG_KIND_ALERT, (const uint8_t*)val.data(), val.length());
        if (meshIsEnabled())
            meshBroadcastConfig(MESH_CFG_KIND_ALERT, (const uint8_t*)val.data(), val.length());
#endif
    }

    void onRead(NimBLECharacteristic* chr) override {
        Preferences p;
        p.begin("ouispy-alert", true);
        uint8_t buf[8];
        uint16_t cool = p.getUShort("cooldown", 5000);
        uint16_t hb   = p.getUShort("heartbeat", 30000);
        uint16_t redis = p.getUShort("rediscover", 30000);
        uint16_t active = p.getUShort("hb_active", 3000);
        p.end();

        buf[0] = cool & 0xFF; buf[1] = (cool >> 8) & 0xFF;
        buf[2] = hb & 0xFF;   buf[3] = (hb >> 8) & 0xFF;
        buf[4] = redis & 0xFF; buf[5] = (redis >> 8) & 0xFF;
        buf[6] = active & 0xFF; buf[7] = (active >> 8) & 0xFF;
        chr->setValue(buf, 8);
    }
};

extern void foxhunterSetTarget(const uint8_t* mac, uint8_t channel);

void foxhunterConfigApply(const uint8_t* data, size_t len) {
    if (len < 6) return;
    foxhunterSetTarget(data, len >= 7 ? data[6] : 0);
}

class IgnoreListCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        ignoreListSet((const uint8_t*)val.data(), val.length());
#ifdef OUISPY_ROLE_MANAGER
        if (meshIsEnabled()) meshBroadcastIgnoreList((const uint8_t*)val.data(), val.length());
#endif
        Serial.printf("[BLE] Ignore list write: %u bytes -> %u entries\n",
                      (unsigned)val.length(), ignoreListCount());
    }
};
static IgnoreListCallbacks ignoreListCb;

class NodeRadioCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
#ifdef OUISPY_ROLE_MANAGER
        std::string val = chr->getValue();
        mgrSetNodeRadioList((const uint8_t*)val.data(), val.length());
#endif
    }
};
static NodeRadioCallbacks nodeRadioCb;

class DetectorConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 1) return;
        const uint8_t* data = (const uint8_t*)val.data();
        uint8_t op = data[0];
        switch (op) {
            case 0x00:
                detectorClearFilters();
                break;
            case 0x01: {
                if (val.length() < 8) return;
                uint8_t prefixLen = data[1];
                const uint8_t* mac = &data[2];
                char desc[32] = {0};
                if (val.length() > 8) {
                    size_t dlen = val.length() - 8;
                    if (dlen > 31) dlen = 31;
                    memcpy(desc, &data[8], dlen);
                }
                detectorAddFilter(mac, prefixLen, desc);
                break;
            }
            case 0x02: {
                if (val.length() < 3) return;
                uint16_t uuid = data[1] | (data[2] << 8);
                char desc[32] = {0};
                if (val.length() > 3) {
                    size_t dlen = val.length() - 3;
                    if (dlen > 31) dlen = 31;
                    memcpy(desc, &data[3], dlen);
                }
                detectorAddUuidFilter(uuid, desc);
                break;
            }
            default:
                Serial.printf("[BLE] DetectorConfig unknown op=0x%02x\n", op);
                break;
        }
#ifdef OUISPY_ROLE_MANAGER
        if (meshIsEnabled()) {
            uint8_t db[256];
            size_t dn = detectorSerialize(db, sizeof(db));
            meshBroadcastDetectorList(db, dn);
        }
#endif
    }
};

class FoxhunterConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 6) return;
        uint8_t channel = val.length() >= 7 ? (uint8_t)val[6] : 0;
        foxhunterSetTarget((const uint8_t*)val.data(), channel);
#ifdef OUISPY_ROLE_MANAGER
        mgrCacheConfig(MESH_CFG_KIND_FOXHUNTER, (const uint8_t*)val.data(), val.length());
        if (meshIsEnabled())
            meshBroadcastConfig(MESH_CFG_KIND_FOXHUNTER, (const uint8_t*)val.data(), val.length());
#endif
        Serial.printf("[BLE] Foxhunter target set via app (ch=%d)\n", channel);
    }
};

class UnipwnCommandCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 8) return;
        // Parse: target_mac[6] command_type[1] payload_len[1] payload[N]
        const uint8_t* data = (const uint8_t*)val.data();
        uint8_t cmdType = data[6];
        uint8_t payloadLen = data[7];
        Serial.printf("[BLE] UniPwn command: type=%d target=%02x:%02x:%02x:%02x:%02x:%02x payload=%d bytes\n",
                      cmdType, data[0], data[1], data[2], data[3], data[4], data[5], payloadLen);
        // UniPwn exploitation requires BLE client mode — queued for engine to process
        // Full exploitation chain not implemented in v3 (requires dedicated BLE client task)
    }
};

class MeshConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 3) return;

        MeshConfig cfg = {};
        cfg.enabled = (uint8_t)val[0];
        cfg.encryption_enabled = (uint8_t)val[1];

        size_t offset = 2;
        if (cfg.encryption_enabled && val.length() >= offset + MESH_KEY_LEN) {
            memcpy(cfg.key, val.data() + offset, MESH_KEY_LEN);
            offset += MESH_KEY_LEN;
        } else if (cfg.encryption_enabled) {
            Serial.println("[BLE] Mesh config: encryption key too short");
            return;
        }

        if (val.length() > offset) {
            cfg.peer_count = (uint8_t)val[offset++];
            for (uint8_t i = 0; i < cfg.peer_count && i < MESH_MAX_PEERS; i++) {
                if (val.length() >= offset + 6) {
                    memcpy(cfg.peers[i], val.data() + offset, 6);
                    offset += 6;
                }
            }
        }

        if (cfg.enabled) {
            meshEnable(&cfg);
        } else {
            meshDisable();
        }

        Serial.printf("[BLE] Mesh config: enabled=%d enc=%d peers=%d\n",
                      cfg.enabled, cfg.encryption_enabled, cfg.peer_count);
    }

    void onRead(NimBLECharacteristic* chr) override {
        uint8_t buf[3];
        buf[0] = meshCurrentConfig.enabled;
        buf[1] = meshCurrentConfig.encryption_enabled;
        buf[2] = meshCurrentConfig.peer_count;
        chr->setValue(buf, 3);
    }
};

class DfuDataCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.empty()) return;
        otaOnDataWrite((const uint8_t*)val.data(), val.length());
    }
};

// System control opcodes
#define SYS_CMD_REBOOT            0x01
#define SYS_CMD_FACTORY_RESET     0x02
#define SYS_CMD_CONFIRM_OTA       0x03  // mark current image valid (cancels rollback)
#define SYS_CMD_OTA_VIA_WIFI      0x04
#define SYS_CMD_FLEET_OTA         0x05
#define SYS_CMD_WIFI_DISCONNECT   0x06
#define SYS_CMD_WIFI_WIPE         0x07
#define SYS_OP_FLEET_PROGRESS     0x08
#define SYS_CMD_FLEET_WIFI_OTA    0x0A  // push mgr WiFi creds + node URL to nodes

#ifdef OUISPY_ROLE_MANAGER
static void fleetOtaNotify(uint8_t phase, uint8_t pct, uint8_t done, uint8_t seen) {
    if (!chrSystemControl) return;
    uint8_t b[6] = { SYS_OP_FLEET_PROGRESS, phase, pct, done, seen, 0 };
    chrSystemControl->setValue(b, sizeof(b));
    chrSystemControl->notify();
}

static void fleetProgressCb(uint8_t phase, uint8_t pct, uint8_t done, uint8_t seen) {
    fleetOtaNotify(phase, pct, done, seen);
}
void bleGattStartFleetProgress(void) {
    meshOtaSetProgressCb(fleetProgressCb);
}

static uint8_t g_fleetWifiBlob[MESH_WIFIOTA_MAX];
static size_t  g_fleetWifiBlobLen = 0;
static void fleetWifiOtaPushTask(void* arg) {
    (void)arg;
    for (int i = 0; i < 10; i++) {
        meshBroadcastWifiOta(g_fleetWifiBlob, g_fleetWifiBlobLen);
        vTaskDelay(pdMS_TO_TICKS(350));
    }
    vTaskDelete(NULL);
}
#endif

class SystemControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.empty()) return;
        uint8_t cmd = (uint8_t)val[0];

        // Magic byte required for destructive ops to avoid accidental triggers
        // Format: [cmd][magic1][magic2] = 0xC0 0xDE
        bool magicOk = val.length() >= 3
                       && (uint8_t)val[1] == 0xC0
                       && (uint8_t)val[2] == 0xDE;

        switch (cmd) {
            case SYS_CMD_REBOOT:
                if (!magicOk) {
                    Serial.println("[SYS] Reboot rejected — missing magic");
                    return;
                }
                Serial.println("[SYS] Reboot requested via BLE");
                delay(200);
                esp_restart();
                break;

            case SYS_CMD_FACTORY_RESET:
                if (!magicOk) {
                    Serial.println("[SYS] Factory reset rejected — missing magic");
                    return;
                }
                Serial.println("[SYS] FACTORY RESET — erasing NVS and rebooting");
                nvs_flash_erase();
                nvs_flash_init();
                delay(200);
                esp_restart();
                break;

            case SYS_CMD_CONFIRM_OTA: {
                esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
                Serial.printf("[SYS] OTA confirm: %s\n",
                              err == ESP_OK ? "OK" : esp_err_to_name(err));
                uint8_t ack = (err == ESP_OK) ? 0x00 : 0x01;
                chr->setValue(&ack, 1);
                chr->notify();
                break;
            }

            case SYS_CMD_OTA_VIA_WIFI: {
                if (!magicOk) {
                    Serial.println("[SYS] WiFi OTA rejected");
                    return;
                }
                if (val.length() < 4) return;
                std::string url(val.data() + 3, val.length() - 3);
                Serial.printf("[SYS] WiFi OTA: %s\n", url.c_str());
#ifdef OUISPY_ROLE_MANAGER
                if (wifiOtaSetPending(url.c_str())) {
                    Serial.println("[SYS] Manager: reboot into WiFi OTA mode (heap-constrained)");
                    delay(300);
                    esp_restart();
                }
#else
                Serial.println("[SYS] Node: in-place WiFi OTA, BLE stays up for progress");
                wifiOtaDispatch(url.c_str());
#endif
                break;
            }

            case SYS_CMD_FLEET_OTA: {
                if (!magicOk) { Serial.println("[SYS] Fleet OTA rejected"); return; }
                if (val.length() < 4) return;
                std::string url(val.data() + 3, val.length() - 3);
                Serial.printf("[SYS] Fleet OTA: %s\n", url.c_str());
#ifdef OUISPY_ROLE_MANAGER
                if (wifiOtaSetFleetPending(url.c_str())) {
                    Serial.println("[SYS] Reboot to stage node image (full heap), then relay");
                    delay(300);
                    esp_restart();
                }
#endif
                break;
            }

            case SYS_CMD_FLEET_WIFI_OTA: {
                if (!magicOk) { Serial.println("[SYS] Fleet WiFi OTA rejected"); return; }
                if (val.length() < 4) return;
                std::string url(val.data() + 3, val.length() - 3);
#ifdef OUISPY_ROLE_MANAGER
                char ssid[33] = {0}, pass[65] = {0};
                if (!wifiOtaLoadCreds(ssid, sizeof(ssid), pass, sizeof(pass))) {
                    Serial.println("[SYS] Fleet WiFi OTA: no manager WiFi creds saved");
                    uint8_t b[6] = { SYS_OP_FLEET_PROGRESS, 0x80, 0, 0, 0, 0 };
                    chr->setValue(b, sizeof(b)); chr->notify();
                    return;
                }
                size_t sl = strlen(ssid), pl = strlen(pass), ul = url.length();
                if (sl > 32) sl = 32;
                if (pl > 64) pl = 64;
                if (1 + sl + 1 + pl + 1 + ul > MESH_WIFIOTA_MAX) {
                    Serial.println("[SYS] Fleet WiFi OTA: creds+url too large for mesh packet");
                    uint8_t b[6] = { SYS_OP_FLEET_PROGRESS, 0x81, 0, 0, 0, 0 };
                    chr->setValue(b, sizeof(b)); chr->notify();
                    return;
                }
                size_t off = 0;
                g_fleetWifiBlob[off++] = (uint8_t)sl;
                memcpy(g_fleetWifiBlob + off, ssid, sl); off += sl;
                g_fleetWifiBlob[off++] = (uint8_t)pl;
                memcpy(g_fleetWifiBlob + off, pass, pl); off += pl;
                g_fleetWifiBlob[off++] = (uint8_t)ul;
                memcpy(g_fleetWifiBlob + off, url.data(), ul); off += ul;
                g_fleetWifiBlobLen = off;
                Serial.printf("[SYS] Fleet WiFi OTA: push creds(%s)+url to nodes (%u bytes)\n",
                              ssid, (unsigned)off);
                xTaskCreatePinnedToCore(fleetWifiOtaPushTask, "fleet_wifi", 3072, NULL, 1, NULL, 1);
                uint8_t b[6] = { SYS_OP_FLEET_PROGRESS, 2, 100, 0, 0, 0 };
                chr->setValue(b, sizeof(b)); chr->notify();
#endif
                break;
            }

            case SYS_CMD_WIFI_DISCONNECT: {
                if (!magicOk) return;
                Serial.println("[SYS] WiFi disconnect");
                wifiStaDisconnect();
                break;
            }

            case SYS_CMD_WIFI_WIPE: {
                if (!magicOk) return;
                Serial.println("[SYS] WiFi wipe creds + disconnect");
                wifiStaDisconnect();
                wifiOtaWipeCreds();
                break;
            }

            default:
                Serial.printf("[SYS] Unknown command: 0x%02X\n", cmd);
                break;
        }
    }
};

class WifiConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 1) return;
        const uint8_t* data = (const uint8_t*)val.data();

        if (data[0] == 0xF1) {
            if (val.length() < 2) return;
            bool en = data[1] != 0;
            wifiStaSetEnabled(en);
            if (en) wifiStaConnectAsync();
            return;
        }
        if (data[0] == 0xF2) {
            wifiStaDisconnect();
            wifiOtaWipeCreds();
            wifiStaSetEnabled(false);
            return;
        }

        if (val.length() < 2) return;
        uint8_t ssidLen = data[0];
        if (ssidLen == 0 || ssidLen > 32 || val.length() < 1u + ssidLen + 1u) {
            Serial.println("[WIFI] bad payload");
            return;
        }
        char ssid[33] = {0};
        memcpy(ssid, data + 1, ssidLen);
        uint8_t passLen = data[1 + ssidLen];
        if (passLen > 64 || val.length() < 1u + ssidLen + 1u + passLen) {
            Serial.println("[WIFI] bad pass len");
            return;
        }
        char pass[65] = {0};
        if (passLen > 0) memcpy(pass, data + 2 + ssidLen, passLen);
        wifiOtaSaveCreds(ssid, pass);
        wifiStaSetEnabled(true);
        wifiStaConnectAsync();
    }

    void onRead(NimBLECharacteristic* chr) override {
        char ssid[33] = {0};
        char pass[65] = {0};
        bool hasCreds = wifiOtaLoadCreds(ssid, sizeof(ssid), pass, sizeof(pass));
        bool connected = wifiStaIsConnected();
        bool enabled = wifiStaIsEnabled();
        char liveSsid[33] = {0};
        wifiStaGetSsid(liveSsid, sizeof(liveSsid));
        uint32_t ip = wifiStaGetIp();
        int8_t rssi = wifiStaGetRssi();
        const char* reportSsid = connected ? liveSsid : ssid;
        size_t slen = strlen(reportSsid);
        if (slen > 32) slen = 32;

        uint8_t buf[41] = {0};
        buf[0] = hasCreds ? 1 : 0;
        buf[1] = connected ? 1 : 0;
        buf[2] = (uint8_t)(ip & 0xFF);
        buf[3] = (uint8_t)((ip >> 8) & 0xFF);
        buf[4] = (uint8_t)((ip >> 16) & 0xFF);
        buf[5] = (uint8_t)((ip >> 24) & 0xFF);
        buf[6] = (uint8_t)rssi;
        buf[7] = (uint8_t)slen;
        memcpy(buf + 8, reportSsid, slen);
        buf[8 + slen] = enabled ? 1 : 0;
        chr->setValue(buf, 8 + slen + 1);
    }
};

static void dfuNotifyTrampoline(const uint8_t* data, size_t len) {
    if (chrDfuControl == nullptr) return;
    chrDfuControl->setValue((uint8_t*)data, len);
    chrDfuControl->notify();
}

static volatile bool     pcapIndInFlight = false;
static volatile uint32_t pcapIndSentMs   = 0;
class PcapDataCallbacks : public NimBLECharacteristicCallbacks {
    void onStatus(NimBLECharacteristic* /*chr*/, Status /*s*/, int /*code*/) override {
        pcapIndInFlight = false;
    }
};
static PcapDataCallbacks pcapDataCallbacks;

#ifdef OUISPY_ROLE_MANAGER
#define MGR_PCAP_REASM_SLOTS  4
#define MGR_PCAP_REASM_MAX    3072
struct PcapReasmSlot {
    char     src[MESH_NODE_ID_LEN];
    uint16_t seq;
    uint32_t last_ms;
    uint32_t recv_mask;
    uint8_t  highest_idx;
    bool     last_seen;
    uint16_t total_len;
    uint8_t  buf[MGR_PCAP_REASM_MAX];
    bool     in_use;
};
static PcapReasmSlot pcapReasm[MGR_PCAP_REASM_SLOTS] = {};
static SemaphoreHandle_t pcapReasmMutex = NULL;

#define PCAP_BLE_COALESCE_BUF  2048
#define PCAP_BLE_MAX_PERNOTIFY 240
static uint8_t  pcapCoalesceBuf[PCAP_BLE_COALESCE_BUF];
static volatile size_t pcapCoalesceLen = 0;
static portMUX_TYPE pcapCoalesceMux = portMUX_INITIALIZER_UNLOCKED;
static uint32_t pcapLastFlushMs = 0;
static volatile uint32_t mgrPcapRecsOk = 0;
static volatile uint32_t mgrPcapRecsDropped = 0;
static volatile uint32_t mgrPcapBytesToPhone = 0;

struct PerNodeStats {
    char     id[5];
    PcapStats st;
    uint32_t last_update_ms;
    bool     in_use;
};
static const uint32_t PER_NODE_STATS_TTL_MS = 10000;
static PerNodeStats perNode[8] = {};
static SemaphoreHandle_t aggMutex = NULL;

#define PCAP_FLUSH_WATERMARK   480
#define PCAP_FLUSH_MAX_AGE_MS  100
#define PCAP_IND_MAX_CHUNK     480
#define PCAP_IND_WATCHDOG_MS   2000

static bool mgrAutoPcapActive(void);

static void flushPcapCoalesced(void) {
    if (!phoneConnected || chrPcapData == nullptr) return;
    if (!(mgrCommandedMask & ENGINE_BITMASK(ENGINE_PCAP)) && !mgrAutoPcapActive()) {
        portENTER_CRITICAL(&pcapCoalesceMux);
        pcapCoalesceLen = 0;
        portEXIT_CRITICAL(&pcapCoalesceMux);
        return;
    }
    if (chrPcapData->getSubscribedCount() == 0) return;
    if (pcapIndInFlight) {
        if (millis() - pcapIndSentMs > PCAP_IND_WATCHDOG_MS) pcapIndInFlight = false;
        else return;
    }

    portENTER_CRITICAL(&pcapCoalesceMux);
    size_t n = pcapCoalesceLen;
    uint32_t age = millis() - pcapLastFlushMs;
    if (n == 0 || (n < PCAP_FLUSH_WATERMARK && age < PCAP_FLUSH_MAX_AGE_MS)) {
        portEXIT_CRITICAL(&pcapCoalesceMux);
        return;
    }
    size_t chunk = n > PCAP_IND_MAX_CHUNK ? PCAP_IND_MAX_CHUNK : n;
    static uint8_t tmp[PCAP_IND_MAX_CHUNK];
    memcpy(tmp, pcapCoalesceBuf, chunk);
    size_t rem = n - chunk;
    if (rem) memmove(pcapCoalesceBuf, pcapCoalesceBuf + chunk, rem);
    pcapCoalesceLen = rem;
    portEXIT_CRITICAL(&pcapCoalesceMux);

    pcapIndInFlight = true;
    pcapIndSentMs = millis();
    chrPcapData->setValue(tmp, chunk);
    chrPcapData->notify(false);   // is_notification=false -> INDICATION (ACK-gated, one in flight)
    mgrPcapBytesToPhone += chunk;
    pcapLastFlushMs = millis();
}

static void pcapBleFlushTaskFn(void* arg) {
    (void)arg;
    uint32_t lastLog = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(25));
        flushPcapCoalesced();
        uint32_t now = millis();
        if (now - lastLog >= 2000) {
            lastLog = now;
            size_t backlog;
            portENTER_CRITICAL(&pcapCoalesceMux);
            backlog = pcapCoalesceLen;
            portEXIT_CRITICAL(&pcapCoalesceMux);
            uint32_t aggFrames = 0; int aggNodes = 0;
            if (aggMutex && xSemaphoreTake(aggMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
                for (int i = 0; i < 8; i++) {
                    if (!perNode[i].in_use) continue;
                    aggNodes++;
                    aggFrames += perNode[i].st.beacon_count + perNode[i].st.probe_req_count
                               + perNode[i].st.probe_resp_count + perNode[i].st.data_count
                               + perNode[i].st.ctrl_count + perNode[i].st.mgmt_other_count
                               + perNode[i].st.deauth_count + perNode[i].st.disassoc_count;
                }
                xSemaphoreGive(aggMutex);
            }
            if (mgrPcapRecsOk || mgrPcapRecsDropped || backlog || aggNodes) {
                Serial.printf("[PCAP-MGR] recsOk=%lu recsDrop=%lu toPhone=%luB backlog=%uB sub=%u | statsNodes=%d statsFrames=%lu\n",
                    (unsigned long)mgrPcapRecsOk, (unsigned long)mgrPcapRecsDropped,
                    (unsigned long)mgrPcapBytesToPhone, (unsigned)backlog,
                    chrPcapData ? (unsigned)chrPcapData->getSubscribedCount() : 0u,
                    aggNodes, (unsigned long)aggFrames);
            }
        }
    }
}
static TaskHandle_t pcapBleFlushTaskHandle = NULL;

static bool mgrAutoPcapActive(void) {
    MeshAutoPcapEventPacket ev;
    uint32_t age = 0;
    if (!meshGetLatestAutoPcapEvent(20000, &ev, &age)) return false;
    return age < ((uint32_t)ev.duration_sec * 1000U);
}

void mgrPcapReasmAdd(const char* src, uint16_t seq,
                     const uint8_t* fragPayload, uint8_t fragLen) {
    if (fragLen < 1) return;
    if (!(mgrCommandedMask & ENGINE_BITMASK(ENGINE_PCAP)) && !mgrAutoPcapActive()) return;
    const uint8_t hdr = fragPayload[0];
    const bool isLast = (hdr & 0x80) != 0;
    const uint8_t idx = hdr & 0x7F;
    const uint8_t* data = fragPayload + 1;
    const uint8_t dataLen = fragLen - 1;
    const size_t fragData = (size_t)MESH_RAW_PAYLOAD_MAX - 1u;
    if (idx >= 32) return;
    if (!pcapReasmMutex) return;
    if (xSemaphoreTake(pcapReasmMutex, pdMS_TO_TICKS(10)) != pdTRUE) return;

    int slot = -1;
    int freeIdx = -1;
    uint32_t oldest = 0xFFFFFFFFu;
    int oldestIdx = 0;
    for (int i = 0; i < MGR_PCAP_REASM_SLOTS; i++) {
        if (pcapReasm[i].in_use &&
            memcmp(pcapReasm[i].src, src, MESH_NODE_ID_LEN) == 0) {
            slot = i;
            break;
        }
        if (!pcapReasm[i].in_use && freeIdx < 0) freeIdx = i;
        if (pcapReasm[i].last_ms < oldest) {
            oldest = pcapReasm[i].last_ms;
            oldestIdx = i;
        }
    }
    if (slot < 0) slot = (freeIdx >= 0) ? freeIdx : oldestIdx;
    if (!pcapReasm[slot].in_use ||
        memcmp(pcapReasm[slot].src, src, MESH_NODE_ID_LEN) != 0 ||
        pcapReasm[slot].seq != seq) {
        pcapReasm[slot].in_use = true;
        memcpy(pcapReasm[slot].src, src, MESH_NODE_ID_LEN);
        pcapReasm[slot].seq = seq;
        pcapReasm[slot].recv_mask = 0;
        pcapReasm[slot].highest_idx = 0;
        pcapReasm[slot].last_seen = false;
        pcapReasm[slot].total_len = 0;
    }
    pcapReasm[slot].last_ms = millis();
    const size_t off = (size_t)idx * fragData;
    if (off + dataLen > MGR_PCAP_REASM_MAX) {
        pcapReasm[slot].in_use = false;
        xSemaphoreGive(pcapReasmMutex);
        return;
    }
    memcpy(pcapReasm[slot].buf + off, data, dataLen);
    pcapReasm[slot].recv_mask |= (1u << idx);
    if (idx > pcapReasm[slot].highest_idx) pcapReasm[slot].highest_idx = idx;
    if (isLast) {
        pcapReasm[slot].last_seen = true;
        pcapReasm[slot].total_len = (uint16_t)(off + dataLen);
    }
    if (pcapReasm[slot].last_seen) {
        const uint8_t expected = pcapReasm[slot].highest_idx + 1;
        const uint32_t fullMask = (expected >= 32) ? 0xFFFFFFFFu
                                : ((1u << expected) - 1u);
        if ((pcapReasm[slot].recv_mask & fullMask) == fullMask) {
            const uint16_t total = pcapReasm[slot].total_len;
            uint8_t tmp[MGR_PCAP_REASM_MAX];
            memcpy(tmp, pcapReasm[slot].buf, total);
            pcapReasm[slot].in_use = false;
            xSemaphoreGive(pcapReasmMutex);
            bool stashed = false;
            portENTER_CRITICAL(&pcapCoalesceMux);
            if (pcapCoalesceLen + total <= PCAP_BLE_COALESCE_BUF) {
                memcpy(pcapCoalesceBuf + pcapCoalesceLen, tmp, total);
                pcapCoalesceLen += total;
                stashed = true;
            }
            portEXIT_CRITICAL(&pcapCoalesceMux);
            if (stashed) mgrPcapRecsOk++; else mgrPcapRecsDropped++;
            (void)seq;
            return;
        }
    }
    xSemaphoreGive(pcapReasmMutex);
}
#endif

void bleGattDispatchMeshNotify(uint8_t kind, const char source_node_id[5],
                               uint16_t seq, const uint8_t* payload, uint8_t len) {
    if (payload == nullptr || len == 0) return;
    switch (kind) {
        case RAW_NOTIFY_PCAP_DATA:
#ifdef OUISPY_ROLE_MANAGER
            {
                extern void mgrPcapReasmAdd(const char* src, uint16_t seq,
                                            const uint8_t* fragPayload, uint8_t fragLen);
                mgrPcapReasmAdd(source_node_id, seq, payload, len);
            }
#else
            if (phoneConnected && chrPcapData) {
                chrPcapData->setValue((uint8_t*)(payload + 1), (uint16_t)(len - 1));
                chrPcapData->notify();
            }
#endif
            break;
        case RAW_NOTIFY_PCAP_STATS:
#ifdef OUISPY_ROLE_MANAGER
            if (len >= sizeof(PcapStats) + 1 && aggMutex &&
                xSemaphoreTake(aggMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
                int slot = -1;
                for (int i = 0; i < 8; i++) {
                    if (perNode[i].in_use &&
                        memcmp(perNode[i].id, source_node_id, 5) == 0) {
                        slot = i; break;
                    }
                }
                if (slot < 0) {
                    for (int i = 0; i < 8; i++) {
                        if (!perNode[i].in_use) {
                            slot = i;
                            perNode[i].in_use = true;
                            memcpy(perNode[i].id, source_node_id, 5);
                            break;
                        }
                    }
                }
                if (slot >= 0) {
                    memcpy(&perNode[slot].st, payload + 1, sizeof(PcapStats));
                    perNode[slot].last_update_ms = millis();
                }
                xSemaphoreGive(aggMutex);
            }
#endif
            break;
        case RAW_NOTIFY_FOXHUNTER_RSSI:
            if (chrFoxhunterRssi && len >= 1) {
                chrFoxhunterRssi->setValue((uint8_t*)(payload + 1), (uint16_t)(len - 1));
                chrFoxhunterRssi->notify();
            }
            break;
        default:
            break;
    }
}

#ifndef OUISPY_ROLE_MANAGER
static void meshForwardPcapRecordAligned(const uint8_t* buf, size_t len) {
    size_t i = 0;
    while (i + 12 <= len) {
        uint32_t m =  (uint32_t)buf[i]
                   | ((uint32_t)buf[i+1] << 8)
                   | ((uint32_t)buf[i+2] << 16)
                   | ((uint32_t)buf[i+3] << 24);
        if (m != 0xCAFEBABEu) { i++; continue; }
        uint32_t recLen = (uint32_t)buf[i+4]
                       | ((uint32_t)buf[i+5] << 8)
                       | ((uint32_t)buf[i+6] << 16)
                       | ((uint32_t)buf[i+7] << 24);
        const size_t fullLen = 8u + recLen + 4u;
        if (i + fullLen > len) break;
        meshForwardPcapRecord(buf + i, fullLen);
        i += fullLen;
    }
}
#endif

void bleGattStreamPcapBytes(const uint8_t* buf, size_t len) {
    if (len == 0) return;
#ifndef OUISPY_ROLE_MANAGER
    if (!phoneConnected) {
        if (meshIsEnabled()) meshForwardPcapRecordAligned(buf, len);
        return;
    }
#endif
    if (!phoneConnected || chrPcapData == nullptr) return;
    if (chrPcapData->getSubscribedCount() == 0) return;
    size_t chunk = 180;
    if (pServer != nullptr) {
        auto peers = pServer->getPeerDevices();
        if (!peers.empty()) {
            uint16_t mtu = pServer->getPeerMTU(peers.front());
            if (mtu > 23) chunk = (size_t)(mtu - 3);
            if (chunk > 480) chunk = 480;
        }
    }
    while (len > 0) {
        size_t n = (len > chunk) ? chunk : len;
        uint32_t t0 = millis();
        while (pcapIndInFlight && (millis() - t0) < 1000) vTaskDelay(pdMS_TO_TICKS(2));
        pcapIndInFlight = true;
        pcapIndSentMs = millis();
        chrPcapData->setValue((uint8_t*)buf, n);
        chrPcapData->notify(false);
        buf += n;
        len -= n;
    }
}

class PcapControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override { }
};

class DeviceInfoCallbacks : public NimBLECharacteristicCallbacks {
    void onRead(NimBLECharacteristic* chr) override {
        char info[96];
        int len = snprintf(info, sizeof(info), "%s", FW_VERSION);
        len++;
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_BT);
        len += snprintf(info + len, sizeof(info) - len, "OUISPY-%02X%02X",
                        mac[4], mac[5]);
        len++;
        len += snprintf(info + len, sizeof(info) - len, "%s", OUISPY_BOARD);
        len++;
#ifdef OUISPY_ROLE_MANAGER
        len += snprintf(info + len, sizeof(info) - len, "mgr");
#else
        len += snprintf(info + len, sizeof(info) - len, "node");
#endif
        len++;
        len += snprintf(info + len, sizeof(info) - len, "%u",
                        (unsigned)ESP.getFreeHeap());
        chr->setValue((uint8_t*)info, len + 1);
    }
};

// ============================================================================
// Static callback instances
// ============================================================================
static ServerCallbacks serverCb;
static FoxhunterConfigCallbacks foxhunterConfigCb;
static DetectorConfigCallbacks detectorConfigCb;
static UnipwnCommandCallbacks unipwnCommandCb;
static EngineControlCallbacks engineControlCb;
static GpsReceiveCallbacks gpsReceiveCb;
static HardwareConfigCallbacks hwConfigCb;
static AlertConfigCallbacks alertConfigCb;
static MeshConfigCallbacks meshConfigCb;
static DfuDataCallbacks dfuDataCb;
static SystemControlCallbacks systemControlCb;
static WifiConfigCallbacks wifiConfigCb;
static PcapControlCallbacks pcapControlCb;
static DeviceInfoCallbacks deviceInfoCb;

static void wifiOtaNotifyTrampoline(const uint8_t* data, size_t len) {
    if (chrSystemControl == nullptr) return;
    chrSystemControl->setValue((uint8_t*)data, len);
    chrSystemControl->notify();
}

// ============================================================================
// Init
// ============================================================================
void bleGattInit(void) {
    Serial.println("[BLE] Initializing NimBLE...");
#ifdef OUISPY_ROLE_MANAGER
    mgrAutoPcapLoad();
    mgrNodeRadioLoad();
    mgrLoadConfigCaches();
    if (!aggMutex) aggMutex = xSemaphoreCreateMutex();
    if (!pcapReasmMutex) pcapReasmMutex = xSemaphoreCreateMutex();
    if (!pcapBleFlushTaskHandle) {
        xTaskCreate(pcapBleFlushTaskFn, "pcapBleFlush", 4096, NULL, 4, &pcapBleFlushTaskHandle);
    }
#endif

    {
        uint8_t bmac[6];
        esp_read_mac(bmac, ESP_MAC_BT);
        char devName[24];
#ifdef OUISPY_ROLE_MANAGER
        snprintf(devName, sizeof(devName), "OUI-SPY-MGR-%02X%02X", bmac[4], bmac[5]);
#else
        snprintf(devName, sizeof(devName), "OUI-SPY-%02X%02X", bmac[4], bmac[5]);
#endif
        NimBLEDevice::init(devName);
        Serial.printf("[BLE] device name: %s\n", devName);
    }
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setMTU(512);

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(&serverCb);

    NimBLEService* svc = pServer->createService(SVC_UUID);

    // -- Device Info (READ) --
    chrDeviceInfo = svc->createCharacteristic(
        CHR_DEVICE_INFO,
        NIMBLE_PROPERTY::READ
    );
    {
        char info[96];
        int len = snprintf(info, sizeof(info), "%s", FW_VERSION);
        len++;
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_BT);
        len += snprintf(info + len, sizeof(info) - len, "OUISPY-%02X%02X",
                        mac[4], mac[5]);
        len++;
        len += snprintf(info + len, sizeof(info) - len, "%s", OUISPY_BOARD);
        len++;
#ifdef OUISPY_ROLE_MANAGER
        len += snprintf(info + len, sizeof(info) - len, "mgr");
#else
        len += snprintf(info + len, sizeof(info) - len, "node");
#endif
        chrDeviceInfo->setValue((uint8_t*)info, len + 1);
    }
    chrDeviceInfo->setCallbacks(&deviceInfoCb);

    // -- Engine Control (READ, WRITE, NOTIFY) --
    chrEngineControl = svc->createCharacteristic(
        CHR_ENGINE_CONTROL,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
    );
    chrEngineControl->setCallbacks(&engineControlCb);

    // -- Detection Events (NOTIFY) --
    chrDetectionEvents = svc->createCharacteristic(
        CHR_DETECTION_EVENTS,
        NIMBLE_PROPERTY::NOTIFY
    );

    // -- Device Status (READ, NOTIFY) --
    chrDeviceStatus = svc->createCharacteristic(
        CHR_DEVICE_STATUS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    // -- GPS Receive (WRITE, WRITE_NR) --
    chrGpsReceive = svc->createCharacteristic(
        CHR_GPS_RECEIVE,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    chrGpsReceive->setCallbacks(&gpsReceiveCb);

    // -- Hardware Config (READ, WRITE) --
    chrHardwareConfig = svc->createCharacteristic(
        CHR_HARDWARE_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrHardwareConfig->setCallbacks(&hwConfigCb);

    // -- Alert Config (READ, WRITE) --
    chrAlertConfig = svc->createCharacteristic(
        CHR_ALERT_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrAlertConfig->setCallbacks(&alertConfigCb);

    // -- Ignore List (READ, WRITE) — mutes chime/auto-pcap for ignored MAC/OUI/SSID --
    chrIgnoreList = svc->createCharacteristic(
        CHR_IGNORE_LIST,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrIgnoreList->setCallbacks(&ignoreListCb);

    // -- Node Radio Role (WRITE) — per-node WiFi/BLE/Both for wardrive slicing --
    chrNodeRadio = svc->createCharacteristic(
        CHR_NODE_RADIO,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrNodeRadio->setCallbacks(&nodeRadioCb);

    // -- Foxhunter Config (WRITE) --
    chrFoxhunterConfig = svc->createCharacteristic(
        CHR_FOXHUNTER_CONFIG,
        NIMBLE_PROPERTY::WRITE
    );
    chrFoxhunterConfig->setCallbacks(&foxhunterConfigCb);

    NimBLECharacteristic* chrDetectorConfig = svc->createCharacteristic(
        CHR_DETECTOR_CONFIG,
        NIMBLE_PROPERTY::WRITE
    );
    chrDetectorConfig->setCallbacks(&detectorConfigCb);

    // -- Foxhunter RSSI (NOTIFY) --
    chrFoxhunterRssi = svc->createCharacteristic(
        CHR_FOXHUNTER_RSSI,
        NIMBLE_PROPERTY::NOTIFY
    );

    // -- UniPwn Command (WRITE, NOTIFY) --
    chrUnipwnCommand = svc->createCharacteristic(
        CHR_UNIPWN_COMMAND,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
    );
    chrUnipwnCommand->setCallbacks(&unipwnCommandCb);

    // -- Mesh Config (READ, WRITE) --
    chrMeshConfig = svc->createCharacteristic(
        CHR_MESH_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrMeshConfig->setCallbacks(&meshConfigCb);

    // -- Mesh Status (READ, NOTIFY) --
    chrMeshStatus = svc->createCharacteristic(
        CHR_MESH_STATUS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    chrDfuControl = svc->createCharacteristic(
        CHR_DFU_CONTROL,
        NIMBLE_PROPERTY::NOTIFY
    );

    chrDfuData = svc->createCharacteristic(
        CHR_DFU_DATA,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    chrDfuData->setCallbacks(&dfuDataCb);

    chrSystemControl = svc->createCharacteristic(
        CHR_SYSTEM_CONTROL,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
    );
    chrSystemControl->setCallbacks(&systemControlCb);

    chrWifiConfig = svc->createCharacteristic(
        CHR_WIFI_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrWifiConfig->setCallbacks(&wifiConfigCb);

    // -- PCAP Control (WRITE) --
    chrPcapControl = svc->createCharacteristic(
        CHR_PCAP_CONTROL,
        NIMBLE_PROPERTY::WRITE
    );
    chrPcapControl->setCallbacks(&pcapControlCb);

    // -- PCAP Stats (NOTIFY) --
    chrPcapStats = svc->createCharacteristic(
        CHR_PCAP_STATS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    // -- PCAP Data (NOTIFY) — chunked file download --
    chrPcapData = svc->createCharacteristic(
        CHR_PCAP_DATA,
        NIMBLE_PROPERTY::INDICATE
    );
    chrPcapData->setCallbacks(&pcapDataCallbacks);

    otaInit();
    otaSetNotifyCallback(dfuNotifyTrampoline);
    wifiOtaSetNotifyCallback(wifiOtaNotifyTrampoline);

    svc->start();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SVC_UUID);
    adv->setScanResponse(true);
    adv->start();

    Serial.println("[BLE] GATT server started, advertising as OUI-SPY");
}

// ============================================================================
// Notifications
// ============================================================================
void bleGattNotifyDetection(const DetectionEvent* evt) {
    if (!phoneConnected) {
        if (offlineScanEnabled && evt && engineSpoolable(evt->engine_id)) detSpoolAppend(evt);
        return;
    }
    if (chrDetectionEvents == nullptr) return;

    uint8_t buf[200];
    size_t len = 19;

    // Common header: engine_id[1] mac[6] rssi[1] channel[1] ts_ms[4] method[1] source_node_id[5]
    buf[0] = evt->engine_id;
    memcpy(buf + 1, evt->mac, 6);
    buf[7] = (uint8_t)evt->rssi;
    buf[8] = evt->channel;
    memcpy(buf + 9, &evt->timestamp_ms, 4);
    buf[13] = evt->method;
    memcpy(buf + 14, evt->source_node_id, MESH_NODE_ID_LEN);

    // Engine-specific extension
    switch ((EngineId)evt->engine_id) {
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
            buf[19] = evt->ext.flock.is_raven;
            memcpy(buf + 20, evt->ext.flock.raven_fw, 16);
            buf[36] = evt->ext.flock.auth_mode;
            len = 37;
            break;

        case ENGINE_SKYSPY:
            memcpy(buf + 19, evt->ext.odid.uav_id, 21);
            memcpy(buf + 40, evt->ext.odid.op_id, 21);
            memcpy(buf + 61, &evt->ext.odid.drone_lat, 8);
            memcpy(buf + 69, &evt->ext.odid.drone_lon, 8);
            memcpy(buf + 77, &evt->ext.odid.altitude_msl, 2);
            memcpy(buf + 79, &evt->ext.odid.height_agl, 2);
            memcpy(buf + 81, &evt->ext.odid.speed, 2);
            memcpy(buf + 83, &evt->ext.odid.heading, 2);
            memcpy(buf + 85, &evt->ext.odid.pilot_lat, 8);
            memcpy(buf + 93, &evt->ext.odid.pilot_lon, 8);
            memcpy(buf + 101, evt->ext.odid.self_id, 24);
            memcpy(buf + 125, &evt->ext.odid.altitude_baro, 2);
            memcpy(buf + 127, &evt->ext.odid.vert_speed, 2);
            memcpy(buf + 129, &evt->ext.odid.operator_alt, 2);
            memcpy(buf + 131, &evt->ext.odid.area_count, 2);
            memcpy(buf + 133, &evt->ext.odid.area_radius, 2);
            memcpy(buf + 135, &evt->ext.odid.area_ceiling, 2);
            memcpy(buf + 137, &evt->ext.odid.area_floor, 2);
            memcpy(buf + 139, &evt->ext.odid.loc_timestamp, 2);
            buf[141] = evt->ext.odid.ua_type;
            buf[142] = evt->ext.odid.id_type;
            buf[143] = evt->ext.odid.op_id_type;
            buf[144] = evt->ext.odid.op_location_type;
            buf[145] = evt->ext.odid.classification;
            buf[146] = evt->ext.odid.category_eu;
            buf[147] = evt->ext.odid.class_eu;
            buf[148] = evt->ext.odid.height_type;
            buf[149] = evt->ext.odid.status;
            buf[150] = evt->ext.odid.horiz_acc;
            buf[151] = evt->ext.odid.vert_acc;
            buf[152] = evt->ext.odid.baro_acc;
            buf[153] = evt->ext.odid.speed_acc;
            buf[154] = evt->ext.odid.self_id_type;
            len = 155;
            break;

        case ENGINE_UNIPWN:
            memcpy(buf + 19, evt->ext.unipwn.robot_type, 8);
            buf[27] = evt->ext.unipwn.exploited;
            len = 28;
            break;

        case ENGINE_DETECTOR:
            buf[19] = evt->ext.detector.is_full_mac;
            memcpy(buf + 20, evt->ext.detector.filter_desc, 32);
            len = 52;
            break;

        case ENGINE_WARDRIVE:
            memcpy(buf + 19, evt->ext.wardrive.ssid, 33);
            buf[52] = evt->ext.wardrive.auth_mode;
            memcpy(buf + 53, evt->ext.wardrive.device_name, 21);
            len = 74;
            break;

        default:
            break;
    }

    chrDetectionEvents->setValue(buf, len);
    chrDetectionEvents->notify();
}

void bleGattNotifyFoxhunterRssi(int8_t rssi, uint16_t intervalMs) {
    uint8_t buf[3];
    buf[0] = (uint8_t)rssi;
    buf[1] = intervalMs & 0xFF;
    buf[2] = (intervalMs >> 8) & 0xFF;
    if (!phoneConnected) {
#ifndef OUISPY_ROLE_MANAGER
        if (meshIsEnabled()) meshForwardNotify(RAW_NOTIFY_FOXHUNTER_RSSI, buf, 3);
#endif
        return;
    }
    if (chrFoxhunterRssi == nullptr) return;
    chrFoxhunterRssi->setValue(buf, 3);
    chrFoxhunterRssi->notify();
}

void bleGattNotifyEngineState(void) {
    if (!phoneConnected || chrEngineControl == nullptr) return;

    uint8_t buf[2 + ENGINE_COUNT];
#ifdef OUISPY_ROLE_MANAGER
    buf[0] = (1u << ENGINE_COUNT) - 1u;
    buf[1] = mgrCommandedMask;
    for (int i = 0; i < ENGINE_COUNT; i++) {
        buf[2 + i] = mgrCommandedStates[i];
    }
#else
    buf[0] = engineGetAvailableMask();
    buf[1] = engineGetActiveMask();
    for (int i = 0; i < ENGINE_COUNT; i++) {
        buf[2 + i] = (uint8_t)engineGetState((EngineId)i);
    }
#endif
    chrEngineControl->setValue(buf, 2 + ENGINE_COUNT);
    chrEngineControl->notify();
}

bool bleGattIsConnected(void) {
    return phoneConnected;
}

void bleGattNotifyMeshStatus(void) {
    if (!phoneConnected || chrMeshStatus == nullptr) return;

    MeshStatus st = meshGetStatus();
    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t liveCount = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, 30000);

    uint8_t buf[12 + MESH_LIVE_NODES_MAX * 11];
    buf[0] = st.enabled;
    buf[1] = st.peer_count;
    buf[2] = st.connected_peers;
    memcpy(buf + 3, &st.rx_count, 4);
    memcpy(buf + 7, &st.tx_count, 4);
    buf[11] = (uint8_t)liveCount;
    size_t off = 12;
    for (size_t i = 0; i < liveCount; i++) {
        memcpy(buf + off, live[i].id, MESH_NODE_ID_LEN);
        buf[off + 5] = live[i].role;
        buf[off + 6] = live[i].active_engines;
        memcpy(buf + off + 7, &live[i].fw_version, 4);
        off += 11;
    }

    static uint8_t lastBuf[sizeof(buf)] = {};
    static size_t  lastLen = 0;
    static uint32_t lastForceMs = 0;
    uint32_t now = millis();
    bool changed = (off != lastLen) || (memcmp(lastBuf, buf, off) != 0);
    bool force = (now - lastForceMs) > 5000u;
    if (!changed && !force) return;
    memcpy(lastBuf, buf, off);
    lastLen = off;
    if (force) lastForceMs = now;

    chrMeshStatus->setValue(buf, (uint16_t)off);
    chrMeshStatus->notify();
}

void bleGattNotifyPcapStats(void) {
    PcapStats st;
    pcapGetStats(&st);
#ifdef OUISPY_ROLE_MANAGER
    bool pcapCommanded = (mgrCommandedMask & ENGINE_BITMASK(ENGINE_PCAP)) != 0;
    bool autoActive = mgrAutoPcapActive();
    st.state = (pcapCommanded || autoActive) ? 1 : 0;
    st.mode = mgrPcapMode;
    st.current_channel = mgrPcapChStart;
    st.auto_enabled = mgrAutoPcapEnabled;
    st.auto_duration_sec = mgrAutoPcapDurationSec;
    st.auto_cooldown_sec = mgrAutoPcapCooldownSec;
    {
        MeshAutoPcapEventPacket ev;
        uint32_t ageMs = 0;
        uint32_t maxAge = (uint32_t)mgrAutoPcapDurationSec * 1000U + 2000U;
        if (meshGetLatestAutoPcapEvent(maxAge, &ev, &ageMs)) {
            uint32_t durMs = (uint32_t)ev.duration_sec * 1000U;
            if (ageMs < durMs) {
                st.auto_trigger_src = ev.trigger_src;
                memcpy(st.auto_trigger_mac, ev.trigger_mac, 6);
                st.auto_remaining_ms = durMs - ageMs;
                if (!pcapCommanded) st.mode = ev.mode;
            }
        }
    }
    st.uptime_ms = (pcapCommanded && mgrPcapStartedMs)
                   ? (uint32_t)(millis() - mgrPcapStartedMs) : 0;
    {
        uint32_t newest = 0;
        int newestIdx = -1;
        if (aggMutex && xSemaphoreTake(aggMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
            for (int i = 0; i < 8; i++) {
                if (!perNode[i].in_use) continue;
                if (perNode[i].last_update_ms >= newest) {
                    newest = perNode[i].last_update_ms;
                    newestIdx = i;
                }
            }
            if (newestIdx >= 0) {
                st.current_channel = perNode[newestIdx].st.current_channel;
            }
            xSemaphoreGive(aggMutex);
        }
    }
    if (aggMutex && xSemaphoreTake(aggMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
        st.beacon_count = 0; st.probe_req_count = 0; st.probe_resp_count = 0;
        st.deauth_count = 0; st.disassoc_count = 0; st.data_count = 0;
        st.ctrl_count = 0; st.mgmt_other_count = 0;
        st.ble_adv_count = 0; st.ble_scan_count = 0;
        st.bytes_written = 0; st.dropped_frames = 0; st.file_size = 0;
        const uint32_t nowAgg = millis();
        for (int i = 0; i < 8; i++) {
            if (perNode[i].in_use &&
                (nowAgg - perNode[i].last_update_ms) > PER_NODE_STATS_TTL_MS) {
                perNode[i].in_use = false;
            }
        }
        for (int i = 0; i < 8; i++) {
            if (!perNode[i].in_use) continue;
            st.beacon_count      += perNode[i].st.beacon_count;
            st.probe_req_count   += perNode[i].st.probe_req_count;
            st.probe_resp_count  += perNode[i].st.probe_resp_count;
            st.deauth_count      += perNode[i].st.deauth_count;
            st.disassoc_count    += perNode[i].st.disassoc_count;
            st.data_count        += perNode[i].st.data_count;
            st.ctrl_count        += perNode[i].st.ctrl_count;
            st.mgmt_other_count  += perNode[i].st.mgmt_other_count;
            st.ble_adv_count     += perNode[i].st.ble_adv_count;
            st.ble_scan_count    += perNode[i].st.ble_scan_count;
            st.bytes_written     += perNode[i].st.bytes_written;
            st.dropped_frames    += perNode[i].st.dropped_frames;
            st.file_size         += perNode[i].st.file_size;
        }
        xSemaphoreGive(aggMutex);
    }
    if (!pcapCommanded && !autoActive) {
        for (int i = 0; i < 8; i++) perNode[i].in_use = false;
    }
#endif
#ifndef OUISPY_ROLE_MANAGER
    if (meshIsEnabled()) {
        meshForwardNotify(RAW_NOTIFY_PCAP_STATS, (const uint8_t*)&st, sizeof(PcapStats));
    }
#endif
    if (!phoneConnected) return;
    if (chrPcapStats == nullptr) return;

    static PcapStats lastSt = {};
    static uint32_t lastPcapForceMs = 0;
    static uint32_t lastPcapNotifyMs = 0;
    uint32_t now = millis();
    PcapStats stCmp = st;
    PcapStats lastCmp = lastSt;
    stCmp.uptime_ms = 0; lastCmp.uptime_ms = 0;
    stCmp.auto_remaining_ms = 0; lastCmp.auto_remaining_ms = 0;
    stCmp.auto_cooldown_remaining_ms = 0; lastCmp.auto_cooldown_remaining_ms = 0;
    bool changed = memcmp(&lastCmp, &stCmp, sizeof(PcapStats)) != 0;
    bool force = (now - lastPcapForceMs) > 2000u;
    bool minGap = (now - lastPcapNotifyMs) >= 250u;
    if (!minGap) return;
    if (!changed && !force) return;
    lastPcapNotifyMs = now;
    lastSt = st;
    if (force) lastPcapForceMs = now;

    chrPcapStats->setValue((uint8_t*)&st, sizeof(st));
    chrPcapStats->notify();
}
