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
#include "engine_registry.h"
#include "engines/pcap.h"
#include "engines/detector.h"
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

static void mgrBroadcastWardriveSliced(const uint8_t* cfg, uint8_t len) {
    if (len < 11) { meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, len); return; }

    MeshLiveNode live[MESH_LIVE_NODES_MAX];
    size_t total = meshGetLiveNodes(live, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    MeshLiveNode nodes[MESH_LIVE_NODES_MAX];
    size_t nn = 0;
    for (size_t i = 0; i < total; i++) {
        if (live[i].role == MESH_ROLE_MANAGER) continue;
        nodes[nn++] = live[i];
    }
    if (nn <= 1) { meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, len); return; }

    uint8_t cs = cfg[9], ce = cfg[10];
    if (cs < 1 || cs > 14) cs = 1;
    if (ce < cs || ce > 14) ce = 11;
    uint16_t span = (uint16_t)(ce - cs + 1);

    for (size_t i = 0; i < nn; i++) {
        uint8_t sStart = (uint8_t)(cs + (span * i) / nn);
        uint8_t sEnd   = (uint8_t)(cs + (span * (i + 1)) / nn - 1);
        if (sEnd < sStart) sEnd = sStart;

        uint8_t clen = len > 64 ? 64 : len;
        uint8_t out[CFG_TGT_OVERHEAD + 64];
        out[0] = CFG_TGT_PREFIX;
        memcpy(out + 1, nodes[i].id, MESH_NODE_ID_LEN - 1);
        out[5] = 0x00;
        memcpy(out + CFG_TGT_OVERHEAD, cfg, clen);
        out[CFG_TGT_OVERHEAD + 9]  = sStart;
        out[CFG_TGT_OVERHEAD + 10] = sEnd;
        meshBroadcastCommand(0x10, ENGINE_WARDRIVE, out, (uint8_t)(CFG_TGT_OVERHEAD + clen));
        Serial.printf("[MGR-SLICE] node=%.4s ch=%u-%u (%u nodes)\n",
                      nodes[i].id, sStart, sEnd, (unsigned)nn);
    }
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

void bleGattReconcileEngines(void) {
#ifdef OUISPY_ROLE_MANAGER
    if (mgrPhoneGoneMs != 0 && !phoneConnected && !mgrTornDown &&
        (millis() - mgrPhoneGoneMs) > MGR_PHONE_GRACE_MS) {
        mgrTornDown = true;
        mgrCommandedMask = 0;
        for (int i = 0; i < ENGINE_COUNT; i++) mgrCommandedStates[i] = (uint8_t)ESTATE_DISABLED;
        if (meshIsEnabled()) meshBroadcastCommand(0x0F, 0, nullptr, 0);
        Serial.println("[BLE] App gone (grace expired) — DISABLE_ALL to nodes");
    }
    if (!meshIsEnabled()) return;
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
        uint8_t have = (uint8_t)(live[i].active_engines & ~pcapBit);
        missingAny |= (uint8_t)(desired & ~have);
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
            Serial.printf("[MGR-RECONCILE] engine %d missing — re-enable\n", e);
        } else if (extraAny & ENGINE_BITMASK(e)) {
            if (lastDisable[e] != 0 && (now - lastDisable[e]) < 6000) continue;
            lastDisable[e] = now;
            meshBroadcastCommand(0x00, (uint8_t)e, nullptr, 0);
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
#ifdef OUISPY_ROLE_MANAGER
        mgrPhoneGoneMs = millis();
        Serial.println("[BLE] Phone disconnected (manager) — teardown deferred (grace)");
#else
        engineDisableAll();
        Serial.println("[BLE] Phone disconnected — engines off");
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
        } else if (cmd.command == 0x00 && cmd.engine_id < ENGINE_COUNT) {
            mgrCommandedMask &= ~(1u << cmd.engine_id);
            mgrCommandedStates[cmd.engine_id] = (uint8_t)ESTATE_DISABLED;
            if (cmd.engine_id == ENGINE_PCAP) mgrPcapStartedMs = 0;
        } else if (cmd.command == 0x0F) {
            mgrCommandedMask = 0;
            for (int i = 0; i < ENGINE_COUNT; i++) mgrCommandedStates[i] = (uint8_t)ESTATE_DISABLED;
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
        }
        if (cmd.engine_id == ENGINE_WARDRIVE && cmd.command == 0x10 && cmd.payload_len >= 11) {
            mgrWardriveCfgLen = cmd.payload_len > sizeof(mgrWardriveCfg)
                                  ? sizeof(mgrWardriveCfg) : cmd.payload_len;
            memcpy(mgrWardriveCfg, cmd.payload, mgrWardriveCfgLen);
        }
        if (meshIsEnabled()) {
            if (cmd.engine_id == ENGINE_WARDRIVE && cmd.command == 0x10) {
                mgrBroadcastWardriveSliced(cmd.payload, cmd.payload_len);
            } else if (cmd.engine_id == ENGINE_WARDRIVE && cmd.command == 0x01) {
                mgrBroadcastWardriveSliced(mgrWardriveCfg, mgrWardriveCfgLen);
                meshBroadcastCommand(cmd.command, cmd.engine_id,
                    cmd.payload_len > 0 ? cmd.payload : nullptr, cmd.payload_len);
            } else {
                meshBroadcastCommand(cmd.command, cmd.engine_id,
                    cmd.payload_len > 0 ? cmd.payload : nullptr,
                    cmd.payload_len);
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
    }
};

class HardwareConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 3) return;

        bool buzzer = val[0] != 0;
        bool led = val[1] != 0;
        uint8_t brightness = (uint8_t)val[2];
        uint8_t buzzerVol = (val.length() >= 4) ? (uint8_t)val[3] : 100;

        // Update runtime state immediately
        hwBuzzerEnabled = buzzer;
        hwBuzzerVolume = buzzerVol;
        hwLedEnabled = led;
        hwNeopixelBrightness = brightness;

        // Persist to NVS
        Preferences p;
        p.begin("ouispy-hw", false);
        p.putBool("buzzer", buzzer);
        p.putUChar("bz_vol", buzzerVol);
        p.putBool("led", led);
        p.putUChar("neo_brt", brightness);
        p.end();

        Serial.printf("[BLE] Hardware config: buzzer=%d vol=%d led=%d brightness=%d\n",
                      buzzer, buzzerVol, led, brightness);
    }

    void onRead(NimBLECharacteristic* chr) override {
        Preferences p;
        p.begin("ouispy-hw", true);
        uint8_t buf[4];
        buf[0] = p.getBool("buzzer", true) ? 1 : 0;
        buf[1] = p.getBool("led", true) ? 1 : 0;
        buf[2] = p.getUChar("neo_brt", 50);
        buf[3] = p.getUChar("bz_vol", 100);
        p.end();
        chr->setValue(buf, 4);
    }
};

class AlertConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 8) return;

        const uint8_t* data = (const uint8_t*)val.data();
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

        Serial.printf("[BLE] Alert config: cool=%d hb=%d redis=%d active=%d\n",
                      cooldown, heartbeat, rediscover, hbActive);
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
            default:
                Serial.printf("[BLE] DetectorConfig unknown op=0x%02x\n", op);
                break;
        }
    }
};

class FoxhunterConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 6) return;
        uint8_t channel = val.length() >= 7 ? (uint8_t)val[6] : 0;
        foxhunterSetTarget((const uint8_t*)val.data(), channel);
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
#define SYS_CMD_WIFI_DISCONNECT   0x06
#define SYS_CMD_WIFI_WIPE         0x07

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
                Serial.printf("[SYS] WiFi OTA dispatch: %s\n", url.c_str());
                wifiOtaDispatch(url.c_str());
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
            if (en) wifiStaConnect();
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
        wifiStaConnect();
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
    if (!phoneConnected || chrDetectionEvents == nullptr) return;

    uint8_t buf[160];
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
            len = 101;
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

    uint8_t buf[12 + MESH_LIVE_NODES_MAX * 7];
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
        off += 7;
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
