#include "mesh_espnow.h"
#include "engine_registry.h"
#include "ble_gatt.h"
#include <Arduino.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <WiFi.h>
#include <mbedtls/gcm.h>
#include <string.h>

volatile MeshConfig meshCurrentConfig = {};
volatile MeshStatus meshCurrentStatus = {};

static mbedtls_gcm_context gcmCtx;
static bool gcmReady = false;
static uint64_t txCounter = 0;
static char localNodeId[MESH_NODE_ID_LEN] = {};
static SemaphoreHandle_t meshMutex = NULL;

#define MESH_CMD_PENDING_MAX  16
#define MESH_CMD_RETRY_MS     300
#define MESH_CMD_MAX_RETRIES  20
#define MESH_ACK_DEDUPE_SLOTS 8

struct PendingCmd {
    bool     in_use;
    uint8_t  seq;
    uint8_t  command;
    uint8_t  engine_id;
    uint8_t  payload[32];
    uint8_t  payload_len;
    uint32_t last_send_ms;
    uint8_t  retries_left;
    bool     acked;
    uint8_t  acks;
    uint8_t  expected;
};
static PendingCmd pendingCmds[MESH_CMD_PENDING_MAX] = {};
static SemaphoreHandle_t pendingMutex = NULL;
static TaskHandle_t      retryTaskHandle = NULL;
static uint8_t           seqCounter = 0;
static const uint8_t     kBroadcastDst[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};

static void sendAckPacket(const MeshCommandPacket* cmd);
static void sendOneSweep(const uint8_t* encrypted, size_t encLen);
static void sendOnRendezvous(const uint8_t* data, size_t len);
static void retryTaskFn(void* arg);

static volatile bool      pendingInviteApply = false;
static MeshConfig         pendingInviteCfg = {};
static SemaphoreHandle_t  inviteMutex = NULL;
static SemaphoreHandle_t  txMutex = NULL;

#define MESH_RENDEZVOUS_CH      1
#define MESH_TX_QUEUE_DEPTH     128
#define MESH_TX_MAX_LEN         250
#define MESH_TX_DRAIN_PERIOD_MS 20
#define MESH_TX_DRAIN_BURST     32

#define MESH_TX_DEDUP_SLOTS     128
#define MESH_TX_DEDUP_MS        60000

struct TxDedupSlot {
    uint32_t hash;
    uint32_t ts;
};
static TxDedupSlot txDedup[MESH_TX_DEDUP_SLOTS] = {};

static inline uint32_t fnv1a(const uint8_t* p, size_t n) {
    uint32_t h = 0x811c9dc5u;
    for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 0x01000193u; }
    return h;
}

static bool txDedupCheck(uint8_t engine_id, const uint8_t mac[6], uint8_t channel) {
    uint8_t buf[8] = { engine_id, channel, mac[0],mac[1],mac[2],mac[3],mac[4],mac[5] };
    uint32_t h = fnv1a(buf, sizeof(buf));
    uint32_t now = millis();
    uint32_t oldest = 0xFFFFFFFFu;
    int oldestIdx = 0;
    for (int i = 0; i < MESH_TX_DEDUP_SLOTS; i++) {
        if (txDedup[i].hash == h && (now - txDedup[i].ts) < MESH_TX_DEDUP_MS) {
            return true;
        }
        if (txDedup[i].ts < oldest) { oldest = txDedup[i].ts; oldestIdx = i; }
    }
    txDedup[oldestIdx].hash = h;
    txDedup[oldestIdx].ts = now;
    return false;
}

struct MeshTxItem {
    uint16_t len;
    uint8_t  data[MESH_TX_MAX_LEN];
};
static QueueHandle_t meshTxQueue = NULL;
static TaskHandle_t  meshTxTaskHandle = NULL;
static void meshTxTaskFn(void* arg);
static bool enqueueTx(const uint8_t* data, size_t len);

static MeshAutoPcapEventPacket latestAutoPcapEvent = {};
static uint32_t                latestAutoPcapEventMs = 0;
static SemaphoreHandle_t       autoPcapEventMutex = NULL;

static MeshLiveNode liveNodes[MESH_LIVE_NODES_MAX] = {};
static SemaphoreHandle_t liveMutex = NULL;

static void recordLiveNode(const char* id, uint8_t role, uint8_t engines) {
    if (!liveMutex) return;
    if (id[0] == 0) return;
    if (memcmp(id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(5)) != pdTRUE) return;
    int freeSlot = -1;
    int oldest = 0;
    uint32_t oldestMs = 0xFFFFFFFFu;
    uint32_t now = millis();
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (liveNodes[i].id[0] == 0) {
            if (freeSlot < 0) freeSlot = i;
            continue;
        }
        if (memcmp(liveNodes[i].id, id, MESH_NODE_ID_LEN) == 0) {
            liveNodes[i].last_ms = now;
            liveNodes[i].role = role;
            liveNodes[i].active_engines = engines;
            xSemaphoreGive(liveMutex);
            return;
        }
        if (liveNodes[i].last_ms < oldestMs) {
            oldestMs = liveNodes[i].last_ms;
            oldest = i;
        }
    }
    int slot = (freeSlot >= 0) ? freeSlot : oldest;
    memcpy(liveNodes[slot].id, id, MESH_NODE_ID_LEN);
    liveNodes[slot].last_ms = now;
    liveNodes[slot].role = role;
    liveNodes[slot].active_engines = engines;
    xSemaphoreGive(liveMutex);
}

size_t meshGetLiveNodes(MeshLiveNode* out, size_t maxOut, uint32_t ttl_ms) {
    if (!liveMutex || !out || maxOut == 0) return 0;
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(20)) != pdTRUE) return 0;
    uint32_t now = millis();
    size_t n = 0;
    for (int i = 0; i < MESH_LIVE_NODES_MAX && n < maxOut; i++) {
        if (liveNodes[i].id[0] == 0) continue;
        if ((now - liveNodes[i].last_ms) > ttl_ms) {
            memset(&liveNodes[i], 0, sizeof(liveNodes[i]));
            continue;
        }
        out[n++] = liveNodes[i];
    }
    xSemaphoreGive(liveMutex);
    return n;
}


static void deriveNonce(uint8_t nonce[MESH_NONCE_LEN], uint64_t counter) {
    memcpy(nonce, localNodeId, 4);
    memcpy(nonce + 4, &counter, 8);
}

static bool encryptPacket(const uint8_t* plain, size_t plainLen,
                          uint8_t* out, size_t* outLen) {
    if (!gcmReady || !meshCurrentConfig.encryption_enabled) {
        memcpy(out, plain, plainLen);
        *outLen = plainLen;
        return true;
    }

    uint8_t nonce[MESH_NONCE_LEN];
    deriveNonce(nonce, txCounter++);

    uint8_t tag[MESH_TAG_LEN];
    memcpy(out, nonce, MESH_NONCE_LEN);

    int ret = mbedtls_gcm_crypt_and_tag(
        &gcmCtx, MBEDTLS_GCM_ENCRYPT,
        plainLen,
        nonce, MESH_NONCE_LEN,
        NULL, 0,
        plain,
        out + MESH_NONCE_LEN,
        MESH_TAG_LEN, tag
    );

    if (ret != 0) {
        Serial.printf("[MESH] Encrypt failed: %d\n", ret);
        return false;
    }

    memcpy(out + MESH_NONCE_LEN + plainLen, tag, MESH_TAG_LEN);
    *outLen = MESH_NONCE_LEN + plainLen + MESH_TAG_LEN;
    return true;
}

static bool decryptPacket(const uint8_t* data, size_t dataLen,
                          uint8_t* out, size_t* outLen) {
    if (!gcmReady || !meshCurrentConfig.encryption_enabled) {
        memcpy(out, data, dataLen);
        *outLen = dataLen;
        return true;
    }

    if (dataLen < MESH_NONCE_LEN + MESH_TAG_LEN + 1) return false;

    const uint8_t* nonce = data;
    size_t cipherLen = dataLen - MESH_NONCE_LEN - MESH_TAG_LEN;
    const uint8_t* cipher = data + MESH_NONCE_LEN;
    const uint8_t* tag = data + MESH_NONCE_LEN + cipherLen;

    int ret = mbedtls_gcm_auth_decrypt(
        &gcmCtx,
        cipherLen,
        nonce, MESH_NONCE_LEN,
        NULL, 0,
        tag, MESH_TAG_LEN,
        cipher,
        out
    );

    if (ret != 0) {
        Serial.printf("[MESH] Decrypt failed: %d\n", ret);
        return false;
    }

    *outLen = cipherLen;
    return true;
}

static void onEspNowRecv(const uint8_t* macAddr, const uint8_t* data, int len) {
    if (!meshCurrentConfig.enabled) return;

    if (len == (int)sizeof(MeshInvitePacket) && data[0] == MESH_PKT_INVITE) {
        MeshInvitePacket inv;
        memcpy(&inv, data, sizeof(inv));
        if (memcmp(inv.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        bool sameCfg =
            (inv.encryption_enabled == meshCurrentConfig.encryption_enabled) &&
            (memcmp(inv.key, (const void*)meshCurrentConfig.key, MESH_KEY_LEN) == 0);
        if (sameCfg) return;
        Serial.printf("[MESH-INVITE-RX] from=%.5s enc=%u ch=%u (new cfg)\n",
            inv.source_node_id, inv.encryption_enabled, inv.channel);
        if (inviteMutex && xSemaphoreTake(inviteMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
            MeshConfig newCfg = {};
            newCfg.enabled = 1;
            newCfg.encryption_enabled = inv.encryption_enabled;
            memcpy(newCfg.key, inv.key, MESH_KEY_LEN);
            newCfg.peer_count = 0;
            memcpy(&pendingInviteCfg, &newCfg, sizeof(newCfg));
            pendingInviteApply = true;
            xSemaphoreGive(inviteMutex);
        }
        return;
    }

    uint8_t plainBuf[256];
    size_t plainLen = 0;

    if (!decryptPacket(data, (size_t)len, plainBuf, &plainLen)) {
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s;
            memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
            s.rx_errors++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen == sizeof(MeshAckPacket) && plainBuf[0] == MESH_PKT_ACK) {
        MeshAckPacket ack;
        memcpy(&ack, plainBuf, sizeof(MeshAckPacket));
        static struct { uint8_t seq; char src[MESH_NODE_ID_LEN]; uint32_t ts; } dedupe[MESH_ACK_DEDUPE_SLOTS] = {};
        uint32_t now = millis();
        bool seen = false;
        for (int i = 0; i < MESH_ACK_DEDUPE_SLOTS; i++) {
            if (dedupe[i].seq == ack.ack_seq &&
                memcmp(dedupe[i].src, ack.source_node_id, MESH_NODE_ID_LEN) == 0 &&
                (now - dedupe[i].ts) < 2000) {
                seen = true; break;
            }
        }
        if (seen) return;
        static int dedupeIdx = 0;
        dedupe[dedupeIdx].seq = ack.ack_seq;
        memcpy(dedupe[dedupeIdx].src, ack.source_node_id, MESH_NODE_ID_LEN);
        dedupe[dedupeIdx].ts = now;
        dedupeIdx = (dedupeIdx + 1) % MESH_ACK_DEDUPE_SLOTS;
        Serial.printf("[MESH-ACK] seq=%u cmd=0x%02x engine=%u from=%.5s\n",
            ack.ack_seq, ack.ack_cmd, ack.ack_engine_id, ack.source_node_id);
        recordLiveNode(ack.source_node_id, 0, 0);
        if (pendingMutex && xSemaphoreTake(pendingMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            for (int i = 0; i < MESH_CMD_PENDING_MAX; i++) {
                if (pendingCmds[i].in_use && pendingCmds[i].seq == ack.ack_seq) {
                    pendingCmds[i].acks++;
                    if (pendingCmds[i].acks >= pendingCmds[i].expected) {
                        pendingCmds[i].acked = true;
                        pendingCmds[i].in_use = false;
                    }
                    break;
                }
            }
            xSemaphoreGive(pendingMutex);
        }
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen == sizeof(MeshCommandPacket) && plainBuf[0] == MESH_PKT_COMMAND) {
        MeshCommandPacket cmd;
        memcpy(&cmd, plainBuf, sizeof(MeshCommandPacket));
        static struct { char src[MESH_NODE_ID_LEN]; uint8_t seq; uint32_t ts; }
            cmdDedupe[32] = {};
        static int cmdDedupeIdx = 0;
        const uint32_t nowDedup = millis();
        bool dupe = false;
        for (int i = 0; i < 32; i++) {
            if (cmdDedupe[i].ts == 0) continue;
            if ((nowDedup - cmdDedupe[i].ts) > 5000) continue;
            if (cmdDedupe[i].seq == cmd.seq &&
                memcmp(cmdDedupe[i].src, cmd.source_node_id, MESH_NODE_ID_LEN) == 0) {
                dupe = true; break;
            }
        }
        if (dupe) {
            sendAckPacket(&cmd);
            return;
        }
        memcpy(cmdDedupe[cmdDedupeIdx].src, cmd.source_node_id, MESH_NODE_ID_LEN);
        cmdDedupe[cmdDedupeIdx].seq = cmd.seq;
        cmdDedupe[cmdDedupeIdx].ts = nowDedup;
        cmdDedupeIdx = (cmdDedupeIdx + 1) % 32;
        Serial.printf("[MESH-CMD] seq=%u cmd=0x%02x engine=%u plen=%u from=%.5s\n",
            cmd.seq, cmd.command, cmd.engine_id, cmd.payload_len, cmd.source_node_id);
        bool targetMatch = true;
        bool targetableEngine = (cmd.engine_id < ENGINE_COUNT)
                                 && kEngineTargetable[cmd.engine_id];
        if (targetableEngine && cmd.command == 0x01) {
            if (cmd.payload_len < MESH_NODE_ID_LEN ||
                memcmp(cmd.payload, localNodeId, MESH_NODE_ID_LEN) != 0) {
                targetMatch = false;
                Serial.printf("[MESH-CMD] ENABLE eng=%u target=%.4s != self=%s — ignored\n",
                              cmd.engine_id,
                              cmd.payload_len >= MESH_NODE_ID_LEN
                                ? (const char*)cmd.payload : "(none)",
                              localNodeId);
            }
        }
        if (targetMatch) {
            EngineCommand ec = {};
            ec.command = cmd.command;
            ec.engine_id = cmd.engine_id;
            ec.payload_len = cmd.payload_len > sizeof(ec.payload) ? sizeof(ec.payload) : cmd.payload_len;
            if (ec.payload_len > 0) memcpy(ec.payload, cmd.payload, ec.payload_len);
            engineProcessCommand(&ec);
        }
        sendAckPacket(&cmd);
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen == sizeof(MeshHeartbeatPacket) && plainBuf[0] == MESH_PKT_HEARTBEAT) {
        MeshHeartbeatPacket hb;
        memcpy(&hb, plainBuf, sizeof(hb));
        if (memcmp(hb.source_node_id, localNodeId, MESH_NODE_ID_LEN) != 0) {
            recordLiveNode(hb.source_node_id, hb.role, hb.active_engines_mask);
        }
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen == sizeof(MeshAutoPcapEventPacket) && plainBuf[0] == MESH_PKT_AUTOPCAP_EVENT) {
        MeshAutoPcapEventPacket ev;
        memcpy(&ev, plainBuf, sizeof(ev));
        if (memcmp(ev.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        if (autoPcapEventMutex &&
            xSemaphoreTake(autoPcapEventMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            memcpy(&latestAutoPcapEvent, &ev, sizeof(ev));
            latestAutoPcapEventMs = millis();
            xSemaphoreGive(autoPcapEventMutex);
        }
        Serial.printf("[MESH-AUTOPCAP-RX] from=%.5s src=%u mac=%02X:%02X:%02X:%02X:%02X:%02X ch=%u dur=%us\n",
            ev.source_node_id, ev.trigger_src,
            ev.trigger_mac[0],ev.trigger_mac[1],ev.trigger_mac[2],
            ev.trigger_mac[3],ev.trigger_mac[4],ev.trigger_mac[5],
            ev.channel, ev.duration_sec);
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        bleGattNotifyPcapStats();
        return;
    }

    if (plainLen >= 10 && plainBuf[0] == MESH_PKT_RAW_NOTIFY) {
        MeshRawNotifyPacket raw;
        size_t copyLen = plainLen <= sizeof(raw) ? plainLen : sizeof(raw);
        memcpy(&raw, plainBuf, copyLen);
        if (memcmp(raw.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        if (raw.payload_len > MESH_RAW_PAYLOAD_MAX) return;
        bleGattDispatchMeshNotify(raw.kind, raw.source_node_id,
                                  raw.seq, raw.payload, raw.payload_len);
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen < sizeof(MeshDetectionPacket)) return;

    MeshDetectionPacket pkt;
    memcpy(&pkt, plainBuf, sizeof(MeshDetectionPacket));

    DetectionEvent evt = {};
    memcpy(evt.source_node_id, pkt.source_node_id, MESH_NODE_ID_LEN);
    evt.engine_id = pkt.engine_id;
    memcpy(evt.mac, pkt.mac, 6);
    evt.rssi = pkt.rssi;
    evt.channel = pkt.channel;
    evt.timestamp_ms = pkt.timestamp_ms;
    evt.method = pkt.method;

    if (pkt.ext_len > 0 && pkt.ext_len <= sizeof(evt.ext)) {
        memcpy(&evt.ext, pkt.ext_data, pkt.ext_len);
    }

    pushDetection(&evt);
    recordLiveNode(pkt.source_node_id, 0, 0);

    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        MeshStatus s;
        memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
        s.rx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
        xSemaphoreGive(meshMutex);
    }
}

static void onEspNowSend(const uint8_t* macAddr, esp_now_send_status_t status) {
    (void)macAddr;
    (void)status;
}

#define MESH_SCAN_WINDOW_MS  900
#define MESH_RX_WINDOW_MS    450
static volatile bool g_meshWindow = false;
static TaskHandle_t  meshSchedTaskHandle = NULL;
bool meshInMeshWindow(void) { return g_meshWindow; }

#ifndef OUISPY_ROLE_MANAGER
static void meshSchedTaskFn(void* arg) {
    (void)arg;
    for (;;) {
        g_meshWindow = false;
        vTaskDelay(pdMS_TO_TICKS(MESH_SCAN_WINDOW_MS));
        if (!meshCurrentConfig.enabled) { g_meshWindow = false; continue; }
        g_meshWindow = true;
        if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
            xSemaphoreGive(txMutex);
        }
        if (meshTxTaskHandle) xTaskNotifyGive(meshTxTaskHandle);
        vTaskDelay(pdMS_TO_TICKS(MESH_RX_WINDOW_MS));
    }
}
#endif

void meshInit(void) {
    meshMutex = xSemaphoreCreateMutex();
    pendingMutex = xSemaphoreCreateMutex();
    inviteMutex = xSemaphoreCreateMutex();
    txMutex = xSemaphoreCreateMutex();
    autoPcapEventMutex = xSemaphoreCreateMutex();
    liveMutex = xSemaphoreCreateMutex();
    memset(liveNodes, 0, sizeof(liveNodes));
    mbedtls_gcm_init(&gcmCtx);
    memset((void*)&meshCurrentConfig, 0, sizeof(MeshConfig));
    memset((void*)&meshCurrentStatus, 0, sizeof(MeshStatus));
    memset(pendingCmds, 0, sizeof(pendingCmds));

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(localNodeId, MESH_NODE_ID_LEN, "%02X%02X", mac[4], mac[5]);

    meshTxQueue = xQueueCreate(MESH_TX_QUEUE_DEPTH, sizeof(MeshTxItem));
    if (!meshTxQueue) {
        Serial.println("[MESH] tx queue create FAIL");
    }
    xTaskCreate(retryTaskFn, "meshRetry", 4096, NULL, 1, &retryTaskHandle);
    xTaskCreate(meshTxTaskFn, "meshTx", 4096, NULL, 3, &meshTxTaskHandle);
#ifndef OUISPY_ROLE_MANAGER
    xTaskCreate(meshSchedTaskFn, "meshSched", 3072, NULL, 2, &meshSchedTaskHandle);
#endif

    Serial.printf("[MESH] Initialized, localNodeId=%s\n", localNodeId);
}

static bool g_meshEverInit = false;
void meshEnable(const MeshConfig* cfg) {
    meshEnableEx(cfg, true);
}

void meshEnableEx(const MeshConfig* cfg, bool sendInvite) {
    if (g_meshEverInit) {
        meshDisable();
    }
    g_meshEverInit = true;

    xSemaphoreTake(meshMutex, portMAX_DELAY);
    memcpy((void*)&meshCurrentConfig, cfg, sizeof(MeshConfig));

    MeshStatus st = {};
    st.enabled = 1;
    st.peer_count = cfg->peer_count;
    memcpy((void*)&meshCurrentStatus, &st, sizeof(MeshStatus));
    xSemaphoreGive(meshMutex);

    if (cfg->encryption_enabled) {
        mbedtls_gcm_free(&gcmCtx);
        mbedtls_gcm_init(&gcmCtx);
        int ret = mbedtls_gcm_setkey(&gcmCtx, MBEDTLS_CIPHER_ID_AES,
                                      cfg->key, 256);
        if (ret != 0) {
            Serial.printf("[MESH] GCM setkey failed: %d\n", ret);
            gcmReady = false;
            return;
        }
        gcmReady = true;
        Serial.println("[MESH] AES-256-GCM encryption enabled");
    } else {
        gcmReady = false;
        Serial.println("[MESH] Encryption disabled, plaintext mode");
    }

    txCounter = 0;

    WiFi.mode(WIFI_STA);
    WiFi.disconnect(false, false);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    esp_wifi_start();
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);

    if (esp_now_init() != ESP_OK) {
        Serial.println("[MESH] ESP-NOW init failed");
        return;
    }

    esp_now_register_recv_cb(onEspNowRecv);
    esp_now_register_send_cb(onEspNowSend);

    {
        static const uint8_t kBroadcast[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
        esp_now_peer_info_t bp = {};
        memcpy(bp.peer_addr, kBroadcast, 6);
        bp.channel = 0;
        bp.ifidx = WIFI_IF_STA;
        bp.encrypt = false;
        if (esp_now_add_peer(&bp) != ESP_OK) {
            Serial.println("[MESH] add broadcast peer failed");
        }
    }

    for (uint8_t i = 0; i < cfg->peer_count && i < MESH_MAX_PEERS; i++) {
        esp_now_peer_info_t peer = {};
        memcpy(peer.peer_addr, cfg->peers[i], 6);
        peer.channel = 0;
        peer.encrypt = false;

        if (esp_now_add_peer(&peer) != ESP_OK) {
            Serial.printf("[MESH] Failed to add peer %d\n", i);
        } else {
            Serial.printf("[MESH] Added peer %02x:%02x:%02x:%02x:%02x:%02x\n",
                          cfg->peers[i][0], cfg->peers[i][1], cfg->peers[i][2],
                          cfg->peers[i][3], cfg->peers[i][4], cfg->peers[i][5]);
        }
    }

    Serial.printf("[MESH] Enabled with %d peers\n", cfg->peer_count);

#ifdef OUISPY_ROLE_MANAGER
    if (sendInvite) {
        for (int i = 0; i < 3; i++) {
            meshSendInvite();
            vTaskDelay(pdMS_TO_TICKS(150));
        }
    }
#else
    (void)sendInvite;
#endif
}

void meshSendInvite(void) {
    if (!meshCurrentConfig.enabled) return;
    MeshInvitePacket inv = {};
    inv.pkt_type = MESH_PKT_INVITE;
    memcpy(inv.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    uint8_t mac[6];
    esp_wifi_get_mac(WIFI_IF_STA, mac);
    memcpy(inv.primary_mac, mac, 6);
    inv.encryption_enabled = meshCurrentConfig.encryption_enabled;
    memcpy(inv.key, (const void*)meshCurrentConfig.key, MESH_KEY_LEN);
    inv.channel = 1;
    sendOneSweep((const uint8_t*)&inv, sizeof(inv));
    Serial.printf("[MESH-INVITE-TX] enc=%u\n", inv.encryption_enabled);
}

void meshDisable(void) {
    esp_now_unregister_recv_cb();
    esp_now_unregister_send_cb();
    esp_now_deinit();

    xSemaphoreTake(meshMutex, portMAX_DELAY);
    MeshConfig cfg = {};
    memcpy((void*)&meshCurrentConfig, &cfg, sizeof(MeshConfig));
    MeshStatus st = {};
    memcpy((void*)&meshCurrentStatus, &st, sizeof(MeshStatus));
    xSemaphoreGive(meshMutex);

    gcmReady = false;
    txCounter = 0;

    Serial.println("[MESH] Disabled");
}

void meshBroadcastDetection(const DetectionEvent* evt) {
    if (!meshCurrentConfig.enabled) return;
    if (evt->source_node_id[0] != '\0') return;
    if (txDedupCheck(evt->engine_id, evt->mac, evt->channel)) return;

    MeshDetectionPacket pkt = {};
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.engine_id = evt->engine_id;
    memcpy(pkt.mac, evt->mac, 6);
    pkt.rssi = evt->rssi;
    pkt.channel = evt->channel;
    pkt.timestamp_ms = evt->timestamp_ms;
    pkt.method = evt->method;

    size_t extSize = 0;
    switch ((EngineId)evt->engine_id) {
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
            extSize = sizeof(evt->ext.flock);
            break;
        case ENGINE_SKYSPY:
            extSize = sizeof(evt->ext.odid);
            break;
        case ENGINE_UNIPWN:
            extSize = sizeof(evt->ext.unipwn);
            break;
        case ENGINE_DETECTOR:
            extSize = sizeof(evt->ext.detector);
            break;
        default:
            break;
    }
    if (extSize > 0 && extSize <= sizeof(pkt.ext_data)) {
        memcpy(pkt.ext_data, &evt->ext, extSize);
        pkt.ext_len = (uint8_t)extSize;
    }

    uint8_t encrypted[256];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, sizeof(MeshDetectionPacket),
                       encrypted, &encLen)) {
        return;
    }

    sendOnRendezvous(encrypted, encLen);
    esp_err_t result = ESP_OK;

    if (result == ESP_OK) {
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s;
            memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
            s.tx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
            xSemaphoreGive(meshMutex);
        }
    }
}

static bool enqueueTx(const uint8_t* data, size_t len) {
    if (!meshTxQueue || len == 0 || len > MESH_TX_MAX_LEN) return false;
    MeshTxItem item;
    item.len = (uint16_t)len;
    memcpy(item.data, data, len);
    BaseType_t ok = xQueueSend(meshTxQueue, &item, 0);
    if (ok != pdTRUE) {
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(2)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_errors++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return false;
    }
    if (meshTxTaskHandle) xTaskNotifyGive(meshTxTaskHandle);
    return true;
}

static void sendOnRendezvous(const uint8_t* data, size_t len) {
    enqueueTx(data, len);
}

static void meshTxTaskFn(void* arg) {
    (void)arg;
    MeshTxItem item;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(MESH_TX_DRAIN_PERIOD_MS));
        if (!meshCurrentConfig.enabled) {
            while (xQueueReceive(meshTxQueue, &item, 0) == pdTRUE) { }
            continue;
        }
        if (uxQueueMessagesWaiting(meshTxQueue) == 0) continue;

        if (!txMutex || xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) != pdTRUE) continue;

        uint8_t cur_ch = 0; wifi_second_chan_t sec;
        esp_wifi_get_channel(&cur_ch, &sec);
        if (cur_ch != MESH_RENDEZVOUS_CH) {
            esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
        }

        int sent = 0;
        while (sent < MESH_TX_DRAIN_BURST) {
            if (xQueueReceive(meshTxQueue, &item, 0) != pdTRUE) break;
            esp_err_t r = ESP_OK;
            for (int retry = 0; retry < 3; retry++) {
                r = esp_now_send(kBroadcastDst, item.data, item.len);
                if (r == ESP_OK) break;
                vTaskDelay(pdMS_TO_TICKS(1));
            }
            sent++;
        }

        xSemaphoreGive(txMutex);
    }
}

static void sendOneSweep(const uint8_t* data, size_t len) {
    if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(200)) != pdTRUE) return;
    uint8_t saved_ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&saved_ch, &sec);
    for (uint8_t ch = 1; ch <= 14; ch++) {
        esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE);
        esp_now_send(kBroadcastDst, data, len);
        vTaskDelay(pdMS_TO_TICKS(6));
    }
    esp_wifi_set_channel(saved_ch != 0 ? saved_ch : 1, WIFI_SECOND_CHAN_NONE);
    if (txMutex) xSemaphoreGive(txMutex);
}

static void sendOnHome(const uint8_t* data, size_t len) {
    if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;
    esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
    esp_now_send(kBroadcastDst, data, len);
    vTaskDelay(pdMS_TO_TICKS(3));
    esp_now_send(kBroadcastDst, data, len);
    if (txMutex) xSemaphoreGive(txMutex);
}

static void sendAckPacket(const MeshCommandPacket* cmd) {
    MeshAckPacket ack = {};
    ack.pkt_type = MESH_PKT_ACK;
    memcpy(ack.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    ack.ack_seq = cmd->seq;
    ack.ack_cmd = cmd->command;
    ack.ack_engine_id = cmd->engine_id;
    uint8_t enc[64];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&ack, sizeof(MeshAckPacket), enc, &encLen)) return;
    sendOneSweep(enc, encLen);
    Serial.printf("[MESH-ACK-TX] seq=%u cmd=0x%02x engine=%u\n",
        ack.ack_seq, ack.ack_cmd, ack.ack_engine_id);
}

void meshBroadcastCommand(uint8_t command, uint8_t engine_id, const uint8_t* payload, uint8_t payload_len) {
    if (!meshCurrentConfig.enabled) return;

    uint8_t seq;
    if (xSemaphoreTake(pendingMutex, pdMS_TO_TICKS(20)) != pdTRUE) return;
    seq = ++seqCounter;
    int slot = -1;
    for (int i = 0; i < MESH_CMD_PENDING_MAX; i++) {
        if (!pendingCmds[i].in_use) { slot = i; break; }
    }
    if (slot < 0) {
        for (int i = 0; i < MESH_CMD_PENDING_MAX; i++) {
            pendingCmds[i].in_use = false;
        }
        slot = 0;
        Serial.println("[MESH-CMD] pending table full, flushed");
    }
    PendingCmd& p = pendingCmds[slot];
    p.in_use = true;
    p.seq = seq;
    p.command = command;
    p.engine_id = engine_id;
    p.payload_len = (payload && payload_len <= sizeof(p.payload)) ? payload_len : 0;
    if (p.payload_len > 0) memcpy(p.payload, payload, p.payload_len);
    p.last_send_ms = millis();
    p.retries_left = MESH_CMD_MAX_RETRIES;
    p.acked = false;
    p.acks = 0;
    {
        MeshLiveNode ln[MESH_LIVE_NODES_MAX];
        size_t lc = meshGetLiveNodes(ln, MESH_LIVE_NODES_MAX, 30000);
        p.expected = (lc == 0) ? 1 : (uint8_t)lc;
    }
    xSemaphoreGive(pendingMutex);

    MeshCommandPacket pkt = {};
    pkt.pkt_type = MESH_PKT_COMMAND;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.command = command;
    pkt.engine_id = engine_id;
    pkt.seq = seq;
    if (p.payload_len > 0) {
        memcpy(pkt.payload, p.payload, p.payload_len);
        pkt.payload_len = p.payload_len;
    }

    uint8_t encrypted[256];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, sizeof(MeshCommandPacket), encrypted, &encLen)) return;
    sendOnHome(encrypted, encLen);

    Serial.printf("[MESH-CMD-TX] seq=%u cmd=0x%02x engine=%u retries=%u\n",
        seq, command, engine_id, MESH_CMD_MAX_RETRIES);

    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
        s.tx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
        xSemaphoreGive(meshMutex);
    }
}

static void retryTaskFn(void* arg) {
    (void)arg;
    uint32_t lastInviteBeacon = 0;
    uint32_t lastHeartbeat = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(50));
        if (!meshCurrentConfig.enabled) continue;
        if (!pendingMutex) continue;

        {
            uint32_t nowHb = millis();
            if (nowHb - lastHeartbeat >= 5000u) {
                lastHeartbeat = nowHb;
                meshSendHeartbeat(engineGetActiveMask());
            }
        }

        if (pendingInviteApply && inviteMutex &&
            xSemaphoreTake(inviteMutex, pdMS_TO_TICKS(20)) == pdTRUE) {
            MeshConfig cfg;
            memcpy(&cfg, &pendingInviteCfg, sizeof(cfg));
            pendingInviteApply = false;
            xSemaphoreGive(inviteMutex);
            Serial.println("[MESH] Applying invite — reconfiguring");
            meshEnableEx(&cfg, false);
            continue;
        }

        uint32_t now = millis();
#ifdef OUISPY_ROLE_MANAGER
        (void)lastInviteBeacon;
#endif
        for (int i = 0; i < MESH_CMD_PENDING_MAX; i++) {
            if (xSemaphoreTake(pendingMutex, pdMS_TO_TICKS(10)) != pdTRUE) break;
            PendingCmd p = pendingCmds[i];
            if (!p.in_use || p.acked) { xSemaphoreGive(pendingMutex); continue; }
            if ((now - p.last_send_ms) < MESH_CMD_RETRY_MS) {
                xSemaphoreGive(pendingMutex);
                continue;
            }
            if (p.retries_left == 0) {
                Serial.printf("[MESH-CMD-TIMEOUT] seq=%u cmd=0x%02x engine=%u — %u/%u nodes acked after %u tries\n",
                    p.seq, p.command, p.engine_id, p.acks, p.expected, MESH_CMD_MAX_RETRIES);
                pendingCmds[i].in_use = false;
                xSemaphoreGive(pendingMutex);
                continue;
            }
            pendingCmds[i].retries_left -= 1;
            pendingCmds[i].last_send_ms = now;
            uint8_t retries_now = pendingCmds[i].retries_left;
            xSemaphoreGive(pendingMutex);

            MeshCommandPacket pkt = {};
            pkt.pkt_type = MESH_PKT_COMMAND;
            memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
            pkt.command = p.command;
            pkt.engine_id = p.engine_id;
            pkt.seq = p.seq;
            pkt.payload_len = p.payload_len;
            if (p.payload_len > 0) memcpy(pkt.payload, p.payload, p.payload_len);
            uint8_t enc[256]; size_t encLen = 0;
            if (encryptPacket((const uint8_t*)&pkt, sizeof(MeshCommandPacket), enc, &encLen)) {
                sendOnHome(enc, encLen);
                Serial.printf("[MESH-CMD-RETRY] seq=%u cmd=0x%02x engine=%u retries_left=%u\n",
                    p.seq, p.command, p.engine_id, retries_now);
            }
        }
    }
}

void meshBroadcastAutoPcapEvent(uint8_t trigger_src, const uint8_t mac[6],
                                uint8_t channel, uint16_t duration_sec,
                                uint8_t paused_mask) {
    if (!meshCurrentConfig.enabled) return;
    MeshAutoPcapEventPacket ev = {};
    ev.pkt_type = MESH_PKT_AUTOPCAP_EVENT;
    memcpy(ev.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    ev.trigger_src = trigger_src;
    if (mac) memcpy(ev.trigger_mac, mac, 6);
    ev.channel = channel;
    ev.duration_sec = duration_sec;
    ev.paused_mask = paused_mask;

    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&ev, sizeof(ev), enc, &encLen)) return;
    sendOnRendezvous(enc, encLen);
    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
        s.tx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
        xSemaphoreGive(meshMutex);
    }
    Serial.printf("[MESH-AUTOPCAP-TX] src=%u ch=%u dur=%us\n",
                  trigger_src, channel, duration_sec);
}

void meshForwardNotify(uint8_t kind, const uint8_t* data, size_t len) {
    if (!meshCurrentConfig.enabled || !data || len == 0) return;
    if (len > MESH_RAW_PAYLOAD_MAX - 1) return;
    static uint16_t seqByKind[8] = {};
    uint8_t kIdx = (kind < 8) ? kind : 0;
    MeshRawNotifyPacket pkt = {};
    pkt.pkt_type = MESH_PKT_RAW_NOTIFY;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.kind = kind;
    pkt.seq = seqByKind[kIdx]++;
    pkt.payload[0] = 0x80;
    memcpy(pkt.payload + 1, data, len);
    pkt.payload_len = (uint8_t)(len + 1);
    size_t wireLen = sizeof(pkt) - MESH_RAW_PAYLOAD_MAX + pkt.payload_len;
    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, wireLen, enc, &encLen)) return;
    if (!enqueueTx(enc, encLen)) return;
    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
        MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
        s.tx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
        xSemaphoreGive(meshMutex);
    }
}

void meshForwardPcapRecord(const uint8_t* record, size_t len) {
    if (!meshCurrentConfig.enabled || !record || len == 0) return;
    if (len > 32u * (MESH_RAW_PAYLOAD_MAX - 1)) return;
    static uint16_t pcapRecSeq = 0;
    uint16_t recSeq = pcapRecSeq++;
    const size_t fragData = (size_t)MESH_RAW_PAYLOAD_MAX - 1u;
    uint8_t totalFrags = (uint8_t)((len + fragData - 1) / fragData);
    if (totalFrags == 0) totalFrags = 1;
    if (uxQueueSpacesAvailable(meshTxQueue) < totalFrags) return;
    size_t off = 0;
    for (uint8_t idx = 0; idx < totalFrags; idx++) {
        size_t chunk = len - off;
        if (chunk > fragData) chunk = fragData;
        bool isLast = (idx == totalFrags - 1);
        MeshRawNotifyPacket pkt = {};
        pkt.pkt_type = MESH_PKT_RAW_NOTIFY;
        memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
        pkt.kind = RAW_NOTIFY_PCAP_DATA;
        pkt.seq = recSeq;
        pkt.payload[0] = (uint8_t)((isLast ? 0x80 : 0x00) | (idx & 0x7F));
        memcpy(pkt.payload + 1, record + off, chunk);
        pkt.payload_len = (uint8_t)(chunk + 1);
        size_t wireLen = sizeof(pkt) - MESH_RAW_PAYLOAD_MAX + pkt.payload_len;
        uint8_t enc[256]; size_t encLen = 0;
        if (!encryptPacket((const uint8_t*)&pkt, wireLen, enc, &encLen)) return;
        if (!enqueueTx(enc, encLen)) return;
        off += chunk;
    }
    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
        MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
        s.tx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
        xSemaphoreGive(meshMutex);
    }
}

void meshSendHeartbeat(uint8_t active_engines_mask) {
    if (!meshCurrentConfig.enabled) return;
    MeshHeartbeatPacket hb = {};
    hb.pkt_type = MESH_PKT_HEARTBEAT;
    memcpy(hb.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    hb.uptime_s = millis() / 1000u;
    hb.free_heap = (uint32_t)ESP.getFreeHeap();
#ifdef OUISPY_ROLE_MANAGER
    hb.role = 1;
#else
    hb.role = 0;
#endif
    hb.active_engines_mask = active_engines_mask;
    uint8_t enc[128]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&hb, sizeof(hb), enc, &encLen)) return;
    enqueueTx(enc, encLen);
}

bool meshGetLatestAutoPcapEvent(uint32_t max_age_ms, MeshAutoPcapEventPacket* out, uint32_t* age_ms_out) {
    if (!out) return false;
    bool ok = false;
    if (autoPcapEventMutex &&
        xSemaphoreTake(autoPcapEventMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        uint32_t age = millis() - latestAutoPcapEventMs;
        if (latestAutoPcapEventMs != 0 && age <= max_age_ms) {
            memcpy(out, &latestAutoPcapEvent, sizeof(*out));
            if (age_ms_out) *age_ms_out = age;
            ok = true;
        }
        xSemaphoreGive(autoPcapEventMutex);
    }
    return ok;
}

const char* meshGetLocalNodeId(void) { return localNodeId; }

bool meshIsEnabled(void) {
    return meshCurrentConfig.enabled != 0;
}

MeshStatus meshGetStatus(void) {
    MeshStatus s;
    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
        xSemaphoreGive(meshMutex);
    } else {
        memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
    }
    return s;
}
