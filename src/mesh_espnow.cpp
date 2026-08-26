#include "mesh_espnow.h"
#include "engine_registry.h"
#include "engines/wardrive.h"
#include "ignore_list.h"
#include "engines/detector.h"
#include "wifi_ota_handler.h"
#include <stddef.h>
#include "ble_gatt.h"
#include <Arduino.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <WiFi.h>
#include <mbedtls/gcm.h>
#include <string.h>
#include <esp_ota_ops.h>

volatile MeshConfig meshCurrentConfig = {};
volatile MeshStatus meshCurrentStatus = {};

static mbedtls_gcm_context gcmCtx;
static bool gcmReady = false;
static uint64_t txCounter = 0;
static uint32_t g_meshSessionSalt = 0;
static char localNodeId[MESH_NODE_ID_LEN] = {};
static volatile bool g_mgrPhoneConnected = false;
static volatile uint32_t g_mgrPhoneSeenMs = 0;
#ifdef OUISPY_SPOOL_STRESS
volatile uint32_t g_spoolStressAwayRx = 0;
#endif
static SemaphoreHandle_t meshMutex = NULL;
static SemaphoreHandle_t gcmMutex = NULL;

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
    uint8_t  max_retries;
    bool     acked;
    uint8_t  acks;
    uint8_t  expected;
    uint32_t created_ms;
};
static PendingCmd pendingCmds[MESH_CMD_PENDING_MAX] = {};
static SemaphoreHandle_t pendingMutex = NULL;

#define MESH_CMD_DEAF_THRESHOLD 3
struct CmdHealth {
    char     id[MESH_NODE_ID_LEN];
    uint8_t  misses;
    uint32_t last_ack_ms;
};
static CmdHealth cmdHealth[MESH_LIVE_NODES_MAX] = {};

static CmdHealth* cmdHealthSlot(const char* id) {
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (memcmp(cmdHealth[i].id, id, MESH_NODE_ID_LEN) == 0 && cmdHealth[i].id[0]) {
            return &cmdHealth[i];
        }
    }
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (cmdHealth[i].id[0] == 0) {
            memcpy(cmdHealth[i].id, id, MESH_NODE_ID_LEN);
            return &cmdHealth[i];
        }
    }
    return &cmdHealth[0];
}

static void cmdHealthAck(const char* id) {
    CmdHealth* h = cmdHealthSlot(id);
    if (h->misses >= MESH_CMD_DEAF_THRESHOLD) {
        Serial.printf("[MESH-CMD-HEALTH] node %.4s recovered (was deaf)\n", id);
    }
    h->misses = 0;
    h->last_ack_ms = millis();
}

static bool cmdNodeDeaf(const char* id) {
    CmdHealth* h = cmdHealthSlot(id);
    return h->misses >= MESH_CMD_DEAF_THRESHOLD;
}

static void cmdHealthMiss(const char* id) {
    CmdHealth* h = cmdHealthSlot(id);
    if (h->misses < 255) h->misses++;
    if (h->misses == MESH_CMD_DEAF_THRESHOLD) {
        Serial.printf("[MESH-CMD-HEALTH] node %.4s marked DEAF (%u consec misses) — dropped from ACK expected\n",
                      id, h->misses);
    }
}

volatile uint32_t g_meshCmdRx = 0;
volatile uint32_t g_meshRxWin = 0;
volatile bool g_meshManagerActive = true;
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
#ifdef OUISPY_LOWRAM
#define MESH_TX_QUEUE_DEPTH     12
#else
#define MESH_TX_QUEUE_DEPTH     128
#endif
#define MESH_TX_MAX_LEN         250
#define MESH_TX_DRAIN_PERIOD_MS 20
#define MESH_TX_DRAIN_BURST     64

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

void meshResetTxDedup(void) {
    memset(txDedup, 0, sizeof(txDedup));
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

#ifndef OUISPY_ROLE_MANAGER
#define MESH_DET_BATCH_MAX_FRAMES 16
typedef struct {
    uint8_t mac[6];
    int8_t  rssi;
    uint8_t channel;
    uint8_t method;
    uint8_t auth;
    uint8_t namelen;
    char    name[MESH_DET_REC_NAME_MAX];
} DetRec;
static QueueHandle_t detRecQueue = NULL;
static void flushDetBatches(void);
#ifdef OUISPY_NETCOUNT
static void ncInjectTaskFn(void* arg);
#endif
#endif

static MeshAutoPcapEventPacket latestAutoPcapEvent = {};
static uint32_t                latestAutoPcapEventMs = 0;
static SemaphoreHandle_t       autoPcapEventMutex = NULL;

static MeshLiveNode liveNodes[MESH_LIVE_NODES_MAX] = {};
static volatile bool gNewNodeJoined = false;
static SemaphoreHandle_t liveMutex = NULL;

#define MESH_FLEET_MAC_MAX 24
static uint8_t fleetMacs[MESH_FLEET_MAC_MAX][6];
static volatile int fleetMacCount = 0;

void meshAddFleetMac(const uint8_t* mac) {
    if (!mac) return;
    static const uint8_t zero[6]  = {0, 0, 0, 0, 0, 0};
    static const uint8_t bcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
    if (memcmp(mac, zero, 6) == 0 || memcmp(mac, bcast, 6) == 0) return;
    int n = fleetMacCount;
    for (int i = 0; i < n; i++)
        if (memcmp(fleetMacs[i], mac, 6) == 0) return;
    if (n < MESH_FLEET_MAC_MAX) {
        memcpy(fleetMacs[n], mac, 6);
        fleetMacCount = n + 1;
    }
}

bool meshIsFleetMac(const uint8_t* mac) {
    if (!mac) return false;
    int n = fleetMacCount;
    for (int i = 0; i < n; i++)
        if (memcmp(fleetMacs[i], mac, 6) == 0) return true;
    return false;
}

static void recordLiveNode(const char* id, uint8_t role, uint8_t engines, uint32_t fw_version = 0) {
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
            if (fw_version) liveNodes[i].fw_version = fw_version;
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
    liveNodes[slot].fw_version = fw_version;
    gNewNodeJoined = true;
    xSemaphoreGive(liveMutex);
}

// A brand-new node took a slot since the last check — the manager uses this to
// push the full current config immediately instead of making the node wait up
// to ~21s for the next 7s rebroadcast cycle.
bool meshConsumeNewNodeJoined(void) {
    bool v = gNewNodeJoined;
    gNewNodeJoined = false;
    return v;
}

// Optimistically reflect a just-issued engine command in every live node's
// mask, so reconcile sees intent satisfied immediately instead of spamming the
// command for the ~5s until the next heartbeat confirms it. A heartbeat that
// disagrees later re-reveals genuine drift (bounded to one re-issue per HB).
void meshMarkNodesEngine(uint8_t engine, bool on) {
    if (!liveMutex || engine >= 8) return;
    uint8_t bit = (uint8_t)(1u << engine);
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(5)) != pdTRUE) return;
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (liveNodes[i].id[0] == 0) continue;
        if (liveNodes[i].role == MESH_ROLE_MANAGER) continue;
        if (on) liveNodes[i].active_engines |= bit;
        else    liveNodes[i].active_engines &= (uint8_t)~bit;
    }
    xSemaphoreGive(liveMutex);
}

// Liveness-only refresh. ACK and detection RX must NOT clobber the node's
// engine mask/role — only HEARTBEAT carries those. Zeroing them here makes
// reconcile see engines as "missing" between heartbeats and storm re-enables.
static void recordLiveSeen(const char* id) {
    if (!liveMutex) return;
    if (id[0] == 0) return;
    if (memcmp(id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(5)) != pdTRUE) return;
    uint32_t now = millis();
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (liveNodes[i].id[0] == 0) continue;
        if (memcmp(liveNodes[i].id, id, MESH_NODE_ID_LEN) == 0) {
            liveNodes[i].last_ms = now;
            xSemaphoreGive(liveMutex);
            return;
        }
    }
    xSemaphoreGive(liveMutex);
    recordLiveNode(id, 0, 0);  // first sight only — HEARTBEAT fills in role+engines
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
    memcpy(nonce + 4, &g_meshSessionSalt, 4);
    uint32_t c = (uint32_t)counter;
    memcpy(nonce + 8, &c, 4);
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

    if (gcmMutex) xSemaphoreTake(gcmMutex, portMAX_DELAY);
    int ret = mbedtls_gcm_crypt_and_tag(
        &gcmCtx, MBEDTLS_GCM_ENCRYPT,
        plainLen,
        nonce, MESH_NONCE_LEN,
        NULL, 0,
        plain,
        out + MESH_NONCE_LEN,
        MESH_TAG_LEN, tag
    );
    if (gcmMutex) xSemaphoreGive(gcmMutex);

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

    if (gcmMutex) xSemaphoreTake(gcmMutex, portMAX_DELAY);
    int ret = mbedtls_gcm_auth_decrypt(
        &gcmCtx,
        cipherLen,
        nonce, MESH_NONCE_LEN,
        NULL, 0,
        tag, MESH_TAG_LEN,
        cipher,
        out
    );
    if (gcmMutex) xSemaphoreGive(gcmMutex);

    if (ret != 0) {
        Serial.printf("[MESH] Decrypt failed: %d\n", ret);
        return false;
    }

    *outLen = cipherLen;
    return true;
}

#ifndef OUISPY_ROLE_MANAGER
// ---- Mesh OTA byte-relay responder (node) ----
#define MESH_OTA_MAX_CHUNKS 16384
static struct {
    bool active;
    esp_ota_handle_t handle;
    const esp_partition_t* part;
    uint32_t total_size;
    uint16_t total_chunks;
    uint32_t fw_version;
    uint16_t recv_count;
    uint32_t last_ack_ms;
    uint8_t  bitmap[MESH_OTA_MAX_CHUNKS / 8];
} g_otaRx = {};

static inline bool otaBitTest(uint16_t i) { return g_otaRx.bitmap[i >> 3] & (1 << (i & 7)); }
static inline void otaBitSet(uint16_t i)  { g_otaRx.bitmap[i >> 3] |= (1 << (i & 7)); }
static uint16_t otaFirstMissing(void) {
    for (uint16_t i = 0; i < g_otaRx.total_chunks; i++) if (!otaBitTest(i)) return i;
    return g_otaRx.total_chunks;
}
static void otaRxSendAck(uint8_t status, uint16_t next, uint16_t count) {
    MeshOtaAckPacket a = {};
    a.pkt_type = MESH_PKT_OTA_ACK;
    memcpy(a.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    a.status = status;
    a.next_needed_seq = next;
    a.recv_count = count;
    uint8_t enc[96]; size_t el = 0;
    if (encryptPacket((const uint8_t*)&a, sizeof(a), enc, &el)) enqueueTx(enc, el);
}
static void otaRxBegin(const MeshOtaBeginPacket* b) {
    if (b->total_chunks == 0 || b->total_chunks > MESH_OTA_MAX_CHUNKS) {
        otaRxSendAck(MESH_OTA_ST_ERR, 0, 0); return;
    }
    engineDisableAll();
    esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
    if (g_otaRx.active && g_otaRx.handle) esp_ota_abort(g_otaRx.handle);
    memset(&g_otaRx, 0, sizeof(g_otaRx));
    g_otaRx.part = esp_ota_get_next_update_partition(NULL);
    if (!g_otaRx.part) { otaRxSendAck(MESH_OTA_ST_ERR, 0, 0); return; }
    esp_err_t e = esp_ota_begin(g_otaRx.part, b->total_size, &g_otaRx.handle);
    if (e != ESP_OK) {
        Serial.printf("[MESH-OTA-RX] esp_ota_begin fail %s\n", esp_err_to_name(e));
        otaRxSendAck(MESH_OTA_ST_ERR, 0, 0); return;
    }
    g_otaRx.active = true;
    g_otaRx.total_size = b->total_size;
    g_otaRx.total_chunks = b->total_chunks;
    g_otaRx.fw_version = b->fw_version_num;
    Serial.printf("[MESH-OTA-RX] BEGIN size=%u chunks=%u part=%s\n",
                  (unsigned)b->total_size, b->total_chunks, g_otaRx.part->label);
    otaRxSendAck(MESH_OTA_ST_READY, 0, 0);
}
static void otaRxData(const MeshOtaDataPacket* d) {
    if (!g_otaRx.active) return;
    if (d->seq >= g_otaRx.total_chunks) return;
    if (otaBitTest(d->seq)) return;
    uint8_t n = d->len > MESH_OTA_CHUNK_MAX ? MESH_OTA_CHUNK_MAX : d->len;
    uint32_t off = (uint32_t)d->seq * MESH_OTA_CHUNK_MAX;
    esp_err_t e = esp_ota_write_with_offset(g_otaRx.handle, d->payload, n, off);
    if (e != ESP_OK) {
        Serial.printf("[MESH-OTA-RX] write seq=%u fail %s\n", d->seq, esp_err_to_name(e));
        otaRxSendAck(MESH_OTA_ST_ERR, otaFirstMissing(), g_otaRx.recv_count);
        return;
    }
    otaBitSet(d->seq);
    g_otaRx.recv_count++;
    uint32_t now = millis();
    if (now - g_otaRx.last_ack_ms > 300) {
        g_otaRx.last_ack_ms = now;
        otaRxSendAck(MESH_OTA_ST_RECEIVING, otaFirstMissing(), g_otaRx.recv_count);
    }
}
static void otaRxEnd(const MeshOtaEndPacket* e) {
    if (!g_otaRx.active) return;
    if (g_otaRx.recv_count < g_otaRx.total_chunks) {
        otaRxSendAck(MESH_OTA_ST_RESUME, otaFirstMissing(), g_otaRx.recv_count);
        return;
    }
    esp_err_t er = esp_ota_end(g_otaRx.handle);
    if (er != ESP_OK) {
        Serial.printf("[MESH-OTA-RX] esp_ota_end fail %s\n", esp_err_to_name(er));
        g_otaRx.active = false;
        otaRxSendAck(MESH_OTA_ST_ERR, 0, g_otaRx.recv_count);
        return;
    }
    if (esp_ota_set_boot_partition(g_otaRx.part) != ESP_OK) {
        g_otaRx.active = false;
        otaRxSendAck(MESH_OTA_ST_ERR, 0, g_otaRx.recv_count);
        return;
    }
    g_otaRx.active = false;
    Serial.println("[MESH-OTA-RX] image complete + verified -> reboot into new firmware");
    otaRxSendAck(MESH_OTA_ST_DONE, 0, g_otaRx.recv_count);
    delay(500);
    esp_restart();
}
#endif

#ifdef OUISPY_ROLE_MANAGER
// ---- Mesh OTA byte-relay initiator (manager) ----
#include <esp_partition.h>
struct OtaNodeProg {
    char id[MESH_NODE_ID_LEN];
    bool seen;
    uint8_t status;
    uint16_t recv;
    uint16_t next;
};
static OtaNodeProg g_otaNodes[MESH_LIVE_NODES_MAX] = {};
static volatile bool g_otaInitRunning = false;
static volatile uint16_t g_otaTotalChunks = 0;
static uint32_t g_otaSize = 0, g_otaCrc = 0, g_otaVer = 0;
static TaskHandle_t g_otaInitTask = NULL;
static void (*g_otaProgCb)(uint8_t phase, uint8_t pct, uint8_t done, uint8_t seen) = nullptr;
void meshOtaSetProgressCb(void (*cb)(uint8_t, uint8_t, uint8_t, uint8_t)) { g_otaProgCb = cb; }

static OtaNodeProg* otaNodeSlot(const char* id) {
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++)
        if (g_otaNodes[i].seen && memcmp(g_otaNodes[i].id, id, MESH_NODE_ID_LEN) == 0)
            return &g_otaNodes[i];
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++)
        if (!g_otaNodes[i].seen) {
            memcpy(g_otaNodes[i].id, id, MESH_NODE_ID_LEN);
            g_otaNodes[i].seen = true;
            return &g_otaNodes[i];
        }
    return NULL;
}
static void otaInitOnAck(const MeshOtaAckPacket* a) {
    OtaNodeProg* s = otaNodeSlot(a->source_node_id);
    if (!s) return;
    s->status = a->status;
    s->recv = a->recv_count;
    s->next = a->next_needed_seq;
    Serial.printf("[MESH-OTA-MGR] ACK %.5s st=%u recv=%u/%u next=%u\n",
        a->source_node_id, a->status, a->recv_count, g_otaTotalChunks, a->next_needed_seq);
}
static void otaSendRawOnHome(const uint8_t* plain, size_t len) {
    uint8_t enc[256]; size_t el = 0;
    if (!encryptPacket(plain, len, enc, &el)) return;
    if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) != pdTRUE) return;
    esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
    for (int r = 0; r < 3; r++) {
        if (esp_now_send(kBroadcastDst, enc, el) == ESP_OK) break;
        vTaskDelay(pdMS_TO_TICKS(2));
    }
    if (txMutex) xSemaphoreGive(txMutex);
}
static void otaSendChunk(const esp_partition_t* src, uint16_t seq) {
    MeshOtaDataPacket d;
    d.pkt_type = MESH_PKT_OTA_DATA;
    memcpy(d.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    d.seq = seq;
    uint32_t off = (uint32_t)seq * MESH_OTA_CHUNK_MAX;
    uint32_t remain = g_otaSize - off;
    uint8_t n = remain >= MESH_OTA_CHUNK_MAX ? MESH_OTA_CHUNK_MAX : (uint8_t)remain;
    d.len = n;
    if (esp_partition_read(src, off, d.payload, n) != ESP_OK) return;
    otaSendRawOnHome((const uint8_t*)&d, offsetof(MeshOtaDataPacket, payload) + n);
}
static void otaInitTaskFn(void* arg) {
    (void)arg;
    const esp_partition_t* src = esp_ota_get_next_update_partition(NULL);
    if (!src) { Serial.println("[MESH-OTA-MGR] no staging partition"); g_otaInitRunning = false; g_otaInitTask = NULL; vTaskDelete(NULL); return; }
    memset(g_otaNodes, 0, sizeof(g_otaNodes));
    uint16_t chunks = (uint16_t)((g_otaSize + MESH_OTA_CHUNK_MAX - 1) / MESH_OTA_CHUNK_MAX);
    g_otaTotalChunks = chunks;
    Serial.printf("[MESH-OTA-MGR] BEGIN size=%u chunks=%u ver=0x%06X\n",
        (unsigned)g_otaSize, chunks, (unsigned)g_otaVer);

    MeshOtaBeginPacket b = {};
    b.pkt_type = MESH_PKT_OTA_BEGIN;
    memcpy(b.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    b.total_size = g_otaSize; b.crc32 = g_otaCrc; b.fw_version_num = g_otaVer; b.total_chunks = chunks;
    for (int i = 0; i < 5; i++) { otaSendRawOnHome((const uint8_t*)&b, sizeof(b)); vTaskDelay(pdMS_TO_TICKS(150)); }
    vTaskDelay(pdMS_TO_TICKS(2500));  // nodes erase + esp_ota_begin
    if (g_otaProgCb) g_otaProgCb(2, 0, 0, 0);

    for (uint16_t seq = 0; seq < chunks; seq++) {
        otaSendChunk(src, seq);
        vTaskDelay(pdMS_TO_TICKS(3));
        if (g_otaProgCb && (seq & 0x1FF) == 0) {
            g_otaProgCb(2, (uint8_t)((uint32_t)seq * 100 / chunks), 0, 0);
        }
    }

    uint8_t doneN = 0, seenN = 0;
    for (int round = 0; round < 10; round++) {
        MeshOtaEndPacket e = {};
        e.pkt_type = MESH_PKT_OTA_END;
        memcpy(e.source_node_id, localNodeId, MESH_NODE_ID_LEN);
        e.crc32 = g_otaCrc;
        for (int i = 0; i < 3; i++) { otaSendRawOnHome((const uint8_t*)&e, sizeof(e)); vTaskDelay(pdMS_TO_TICKS(40)); }
        vTaskDelay(pdMS_TO_TICKS(1500));
        uint16_t minNext = chunks; bool anyPending = false;
        doneN = 0; seenN = 0;
        for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
            if (!g_otaNodes[i].seen) continue;
            seenN++;
            if (g_otaNodes[i].status == MESH_OTA_ST_DONE) { doneN++; continue; }
            anyPending = true;
            if (g_otaNodes[i].next < minNext) minNext = g_otaNodes[i].next;
        }
        if (g_otaProgCb) {
            uint8_t pct = chunks ? (uint8_t)((uint32_t)minNext * 100 / chunks) : 100;
            g_otaProgCb(2, anyPending ? pct : 100, doneN, seenN);
        }
        if (!anyPending) { Serial.println("[MESH-OTA-MGR] all nodes DONE"); break; }
        Serial.printf("[MESH-OTA-MGR] resume round %d from seq=%u\n", round, minNext);
        for (uint16_t seq = minNext; seq < chunks; seq++) {
            otaSendChunk(src, seq);
            vTaskDelay(pdMS_TO_TICKS(3));
        }
    }
    if (g_otaProgCb) g_otaProgCb(3, 100, doneN, seenN);
    Serial.println("[MESH-OTA-MGR] fleet relay finished");
    g_otaInitRunning = false;
    g_otaInitTask = NULL;
    vTaskDelete(NULL);
}
bool meshOtaInitiatorStart(uint32_t size, uint32_t crc, uint32_t fw_version) {
    if (g_otaInitRunning || size == 0) return false;
    g_otaSize = size; g_otaCrc = crc; g_otaVer = fw_version;
    g_otaInitRunning = true;
    if (xTaskCreatePinnedToCore(otaInitTaskFn, "mesh_ota", 4096, NULL, 1, &g_otaInitTask, 0) != pdPASS) {
        g_otaInitRunning = false;
        Serial.printf("[MESH-OTA-MGR] task create FAILED (free heap=%u)\n",
                      (unsigned)ESP.getFreeHeap());
        return false;
    }
    return true;
}
bool meshOtaInitiatorRunning(void) { return g_otaInitRunning; }
void meshOtaProgress(uint16_t* total, uint16_t* minRecv, uint8_t* nodesDone, uint8_t* nodesSeen) {
    uint16_t mn = g_otaTotalChunks;
    uint8_t done = 0, seen = 0;
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (!g_otaNodes[i].seen) continue;
        seen++;
        if (g_otaNodes[i].status == MESH_OTA_ST_DONE) { done++; continue; }
        if (g_otaNodes[i].recv < mn) mn = g_otaNodes[i].recv;
    }
    if (total) *total = g_otaTotalChunks;
    if (minRecv) *minRecv = seen ? mn : 0;
    if (nodesDone) *nodesDone = done;
    if (nodesSeen) *nodesSeen = seen;
}
#endif

#ifdef OUISPY_NETCOUNT
#define NC_SET_SLOTS 512
static uint32_t ncSet[NC_SET_SLOTS];
static uint32_t ncSetCount = 0;
static uint32_t ncRxTotal  = 0;
static uint32_t ncFnv6(const uint8_t* m) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < 6; i++) { h ^= m[i]; h *= 16777619u; }
    return h ? h : 1;
}
static void ncRecordWifiMac(const uint8_t mac[6]) {
    ncRxTotal++;
    uint32_t h = ncFnv6(mac);
    uint32_t i = h & (NC_SET_SLOTS - 1);
    for (uint32_t n = 0; n < NC_SET_SLOTS; n++) {
        if (ncSet[i] == 0) { ncSet[i] = h; ncSetCount++; return; }
        if (ncSet[i] == h) return;
        i = (i + 1) & (NC_SET_SLOTS - 1);
    }
}
uint32_t ncUniqueCount(void)  { return ncSetCount; }
uint32_t ncRxTotalCount(void) { return ncRxTotal; }
#endif

static void meshProcessRxPacket(const uint8_t* macAddr, const uint8_t* data, int len) {
    if (!meshCurrentConfig.enabled) return;

    if (macAddr) meshAddFleetMac(macAddr);

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
        recordLiveSeen(ack.source_node_id);
        cmdHealthAck(ack.source_node_id);
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
        recordLiveNode(cmd.source_node_id, MESH_ROLE_MANAGER, 0);
        g_meshCmdRx++;
        uint8_t rxch = 0; wifi_second_chan_t rxsec;
        esp_wifi_get_channel(&rxch, &rxsec);
        Serial.printf("[MESH-CMD] seq=%u cmd=0x%02x engine=%u plen=%u from=%.5s rxch=%u\n",
            cmd.seq, cmd.command, cmd.engine_id, cmd.payload_len, cmd.source_node_id, rxch);
        if (cmd.command == 0x12) {
            const uint8_t* dp = cmd.payload;
            uint8_t dl = cmd.payload_len;
            if (!bleGattIsConnected() && cfgTgtStrip(&dp, &dl, localNodeId) && dl >= 1) {
                engineSetDenyMask(dp[0]);
                Serial.printf("[MESH-CMD] fan-out deny mask=0x%02x\n", dp[0]);
            }
            sendAckPacket(&cmd);
            return;
        }
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
        if (targetMatch && !bleGattIsConnected()) {
            EngineCommand ec = {};
            ec.command = cmd.command;
            ec.engine_id = cmd.engine_id;
            ec.payload_len = cmd.payload_len;
            if (ec.payload_len > sizeof(ec.payload)) ec.payload_len = sizeof(ec.payload);
            if (ec.payload_len > sizeof(cmd.payload)) ec.payload_len = sizeof(cmd.payload);
            if (ec.payload_len > 0) memcpy(ec.payload, cmd.payload, ec.payload_len);
            engineProcessCommand(&ec);
        } else if (targetMatch) {
            Serial.printf("[MESH-CMD] phone-owned node — ignoring manager engine cmd 0x%02x eng=%u\n",
                          cmd.command, cmd.engine_id);
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
            recordLiveNode(hb.source_node_id, hb.role, hb.active_engines_mask, hb.fw_version);
            Serial.printf("[HB] rx id=%.4s role=%u eng=0x%02X fw=0x%06X phone=%u\n",
                          hb.source_node_id, hb.role, hb.active_engines_mask,
                          (unsigned)hb.fw_version, hb.phone_connected);
            if (hb.role == MESH_ROLE_MANAGER) {
                hwAlertsSuppressed = hb.alerts_suppressed != 0;
                g_mgrPhoneConnected = hb.phone_connected != 0;
                g_mgrPhoneSeenMs = millis();
            }
#ifdef OUISPY_ROLE_MANAGER
            else {
                bleGattMgrSyncNodeEngineState(hb.active_engines_mask);
            }
#endif
        }
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
        return;
    }

    if (plainLen >= 7 && plainBuf[0] == MESH_PKT_IGNORELIST) {
        MeshIgnoreListPacket il;
        size_t cp = plainLen <= sizeof(il) ? plainLen : sizeof(il);
        memcpy(&il, plainBuf, cp);
        if (memcmp(il.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        uint8_t n = il.len;
        if (n > MESH_IGNORELIST_MAX) n = MESH_IGNORELIST_MAX;
        size_t availIl = cp > offsetof(MeshIgnoreListPacket, data)
                           ? cp - offsetof(MeshIgnoreListPacket, data) : 0;
        if (n > availIl) n = (uint8_t)availIl;
        ignoreListSet(il.data, n);
        return;
    }

    if (plainLen >= 7 && plainBuf[0] == MESH_PKT_DETECTORLIST) {
        MeshIgnoreListPacket il;
        size_t cp = plainLen <= sizeof(il) ? plainLen : sizeof(il);
        memcpy(&il, plainBuf, cp);
        if (memcmp(il.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        uint8_t n = il.len;
        if (n > MESH_IGNORELIST_MAX) n = MESH_IGNORELIST_MAX;
        size_t availIl = cp > offsetof(MeshIgnoreListPacket, data)
                           ? cp - offsetof(MeshIgnoreListPacket, data) : 0;
        if (n > availIl) n = (uint8_t)availIl;
        detectorSetFilters(il.data, n);
        return;
    }

    if (plainLen >= offsetof(MeshConfigPacket, data) && plainBuf[0] == MESH_PKT_CONFIG) {
        MeshConfigPacket cp;
        size_t c = plainLen <= sizeof(cp) ? plainLen : sizeof(cp);
        memcpy(&cp, plainBuf, c);
        if (memcmp(cp.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        uint8_t n = cp.len;
        if (n > MESH_CONFIG_MAX) n = MESH_CONFIG_MAX;
        size_t availCfg = c > offsetof(MeshConfigPacket, data)
                            ? c - offsetof(MeshConfigPacket, data) : 0;
        if (n > availCfg) n = (uint8_t)availCfg;
        if (cp.cfg_kind == MESH_CFG_KIND_HW)         hardwareConfigApply(cp.data, n);
        else if (cp.cfg_kind == MESH_CFG_KIND_ALERT) alertConfigApply(cp.data, n);
        else if (cp.cfg_kind == MESH_CFG_KIND_AUTOPCAP) autoPcapConfigApply(cp.data, n);
        else if (cp.cfg_kind == MESH_CFG_KIND_FOXHUNTER) foxhunterConfigApply(cp.data, n);
        else if (cp.cfg_kind == MESH_CFG_KIND_SIGMASK) { if (n >= 1) detectorSetSigMask(cp.data[0]); }
        else if (cp.cfg_kind == MESH_CFG_KIND_WIFIBAND) { if (n >= 1) engineApplyWifiBand(cp.data[0]); }
#ifndef OUISPY_ROLE_MANAGER
        else if (cp.cfg_kind == MESH_CFG_KIND_ENGINE) {
            if (!bleGattIsConnected()) engineStateConfigApply(cp.data, n);
        }
#endif
        return;
    }

#ifndef OUISPY_ROLE_MANAGER
    if (plainLen >= offsetof(MeshWifiOtaPacket, data) && plainBuf[0] == MESH_PKT_WIFI_OTA) {
        static bool s_wifiOtaApplied = false;
        MeshWifiOtaPacket wp;
        size_t c = plainLen <= sizeof(wp) ? plainLen : sizeof(wp);
        memcpy(&wp, plainBuf, c);
        if (memcmp(wp.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        if (s_wifiOtaApplied) return;
        size_t n = wp.len; if (n > MESH_WIFIOTA_MAX) n = MESH_WIFIOTA_MAX;
        size_t availOta = c > offsetof(MeshWifiOtaPacket, data)
                            ? c - offsetof(MeshWifiOtaPacket, data) : 0;
        if (n > availOta) n = availOta;
        size_t off = 0;
        char ssid[33] = {0}, pass[65] = {0}, url[MESH_WIFIOTA_MAX + 1] = {0};
        if (off >= n) return;
        size_t sl = wp.data[off++];
        if (sl > 32 || off + sl > n) return;
        memcpy(ssid, wp.data + off, sl); off += sl;
        if (off >= n) return;
        size_t pl = wp.data[off++];
        if (pl > 64 || off + pl > n) return;
        memcpy(pass, wp.data + off, pl); off += pl;
        if (off >= n) return;
        size_t ul = wp.data[off++];
        if (ul == 0 || off + ul > n) return;
        memcpy(url, wp.data + off, ul);
        s_wifiOtaApplied = true;
        Serial.printf("[MESH-WIFIOTA] creds(%s)+url -> save + reboot to self-update\n", ssid);
        wifiOtaSaveCreds(ssid, pass);
        wifiOtaSetPending(url);
        delay(200);
        esp_restart();
        return;
    }
    if (plainLen == sizeof(MeshOtaBeginPacket) && plainBuf[0] == MESH_PKT_OTA_BEGIN) {
        MeshOtaBeginPacket b; memcpy(&b, plainBuf, sizeof(b)); otaRxBegin(&b); return;
    }
    if (plainLen >= offsetof(MeshOtaDataPacket, payload) && plainBuf[0] == MESH_PKT_OTA_DATA) {
        MeshOtaDataPacket d;
        size_t c = plainLen <= sizeof(d) ? plainLen : sizeof(d);
        memcpy(&d, plainBuf, c);
        size_t availChunk = c > offsetof(MeshOtaDataPacket, payload)
                              ? c - offsetof(MeshOtaDataPacket, payload) : 0;
        if (d.len > availChunk) d.len = (uint8_t)availChunk;
        otaRxData(&d); return;
    }
    if (plainLen == sizeof(MeshOtaEndPacket) && plainBuf[0] == MESH_PKT_OTA_END) {
        MeshOtaEndPacket e; memcpy(&e, plainBuf, sizeof(e)); otaRxEnd(&e); return;
    }
#endif
#ifdef OUISPY_ROLE_MANAGER
    if (plainLen == sizeof(MeshOtaAckPacket) && plainBuf[0] == MESH_PKT_OTA_ACK) {
        MeshOtaAckPacket a; memcpy(&a, plainBuf, sizeof(a)); otaInitOnAck(&a); return;
    }
#endif

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
        size_t availRaw = copyLen > offsetof(MeshRawNotifyPacket, payload)
                            ? copyLen - offsetof(MeshRawNotifyPacket, payload) : 0;
        if (raw.payload_len > availRaw) return;
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

    if (plainLen >= offsetof(MeshDetectionBatchPacket, data) &&
        plainBuf[0] == MESH_PKT_DETECTION_BATCH) {
#ifdef OUISPY_ROLE_MANAGER
        MeshDetectionBatchPacket b;
        size_t cp = plainLen <= sizeof(b) ? plainLen : sizeof(b);
        memcpy(&b, plainBuf, cp);
        if (memcmp(b.source_node_id, localNodeId, MESH_NODE_ID_LEN) == 0) return;
        size_t dataLen = plainLen - offsetof(MeshDetectionBatchPacket, data);
        if (dataLen > sizeof(b.data)) dataLen = sizeof(b.data);
        size_t off = 0; uint32_t got = 0;
        for (uint8_t i = 0; i < b.count && off + 11 <= dataLen; i++) {
            const uint8_t* p = b.data + off;
            uint8_t nl = p[10];
            if (off + 11 + nl > dataLen) break;
            DetectionEvent evt = {};
            memcpy(evt.source_node_id, b.source_node_id, MESH_NODE_ID_LEN);
            evt.engine_id = ENGINE_WARDRIVE;
            memcpy(evt.mac, p, 6);
            evt.rssi    = (int8_t)p[6];
            evt.channel = p[7];
            evt.method  = p[8];
            evt.ext.wardrive.auth_mode = p[9];
            if (evt.channel == 0) {
                size_t c = nl < sizeof(evt.ext.wardrive.device_name) - 1
                             ? nl : sizeof(evt.ext.wardrive.device_name) - 1;
                memcpy(evt.ext.wardrive.device_name, p + 11, c);
            } else {
                size_t c = nl < sizeof(evt.ext.wardrive.ssid) - 1
                             ? nl : sizeof(evt.ext.wardrive.ssid) - 1;
                memcpy(evt.ext.wardrive.ssid, p + 11, c);
            }
#ifdef OUISPY_NETCOUNT
            if (evt.channel != 0) ncRecordWifiMac(evt.mac);
#else
            pushDetection(&evt);
#endif
            off += 11 + nl;
            got++;
        }
        recordLiveSeen(b.source_node_id);
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
            s.rx_count += got;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
            xSemaphoreGive(meshMutex);
        }
#endif
        return;
    }

    if (plainBuf[0] < 0x20) return;
    if (plainLen < sizeof(MeshDetectionPacket)) {
        static unsigned long lastMismatchLog = 0;
        if (plainLen >= MESH_NODE_ID_LEN && millis() - lastMismatchLog > 3000) {
            lastMismatchLog = millis();
            char id[MESH_NODE_ID_LEN + 1] = {0};
            memcpy(id, plainBuf, MESH_NODE_ID_LEN);
            Serial.printf("[MGR] det DROP from %s: %u < %u bytes — node firmware mismatch?\n",
                          id, (unsigned)plainLen, (unsigned)sizeof(MeshDetectionPacket));
        }
        return;
    }

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

#ifdef OUISPY_ROLE_MANAGER
    if ((evt.engine_id & 0x7F) == ENGINE_DETECTOR && evt.ext.detector.filter_desc[0] == '\0') {
        const char* dsc = detectorLookupDesc(evt.mac);
        if (dsc && dsc[0]) {
            strncpy(evt.ext.detector.filter_desc, dsc,
                    sizeof(evt.ext.detector.filter_desc) - 1);
        }
    }
#endif

    pushDetection(&evt);
    recordLiveSeen(pkt.source_node_id);
#ifdef OUISPY_NETCOUNT
    if ((evt.engine_id & 0x7F) == ENGINE_WARDRIVE && evt.channel != 0) ncRecordWifiMac(evt.mac);
#endif
#ifdef OUISPY_SPOOL_STRESS
    if (evt.engine_id & DET_FLAG_AWAY) g_spoolStressAwayRx++;
#endif

    if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        MeshStatus s;
        memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
        s.rx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
        xSemaphoreGive(meshMutex);
    }
}

#ifndef OUISPY_ROLE_MANAGER
struct MeshRxItem {
    uint8_t  mac[6];
    uint16_t len;
    uint8_t  data[MESH_TX_MAX_LEN];
};
static QueueHandle_t meshRxQueue = NULL;
static TaskHandle_t  meshRxWorkerHandle = NULL;

static void meshRxWorkerFn(void* arg) {
    (void)arg;
    MeshRxItem item;
    for (;;) {
        if (xQueueReceive(meshRxQueue, &item, portMAX_DELAY) == pdTRUE) {
            meshProcessRxPacket(item.mac, item.data, (int)item.len);
        }
    }
}
#endif

#ifdef OUISPY_NIMBLE2
static void onEspNowRecv(const esp_now_recv_info_t* info, const uint8_t* data, int len) {
    const uint8_t* macAddr = info ? info->src_addr : nullptr;
#else
static void onEspNowRecv(const uint8_t* macAddr, const uint8_t* data, int len) {
#endif
    if (!meshCurrentConfig.enabled) return;
    if (len <= 0 || len > MESH_TX_MAX_LEN) return;
#ifdef OUISPY_ROLE_MANAGER
    meshProcessRxPacket(macAddr, data, len);
#else
    if (!meshRxQueue) return;
    MeshRxItem item;
    if (macAddr) memcpy(item.mac, macAddr, 6);
    else memset(item.mac, 0, 6);
    item.len = (uint16_t)len;
    memcpy(item.data, data, (size_t)len);
    if (xQueueSend(meshRxQueue, &item, 0) != pdTRUE) {
        if (meshMutex && xSemaphoreTake(meshMutex, 0) == pdTRUE) {
            meshCurrentStatus.rx_errors++;
            xSemaphoreGive(meshMutex);
        }
    }
#endif
}

#ifdef OUISPY_NIMBLE2
static void onEspNowSend(const wifi_tx_info_t* macAddr, esp_now_send_status_t status) {
#else
static void onEspNowSend(const uint8_t* macAddr, esp_now_send_status_t status) {
#endif
    (void)macAddr;
    (void)status;
}

#define MESH_RX_WINDOW_MS    300
#define MESH_RX_MIN_MS       100
// Backstop: if a scanning node hasn't naturally dwelt on the mesh channel
// within this window, force a brief ch1 visit so mesh stays alive. Normal
// scanning weaves through ch1 (a priority channel) every sweep, so this rarely
// fires — that's what recovers v0.3.9-class scan speed (no forced park).
#define MESH_HOME_MAX_GAP_MS 1500
#define MESH_MGR_SILENCE_FORCE_MS 6000
#define MESH_REACQUIRE_MS 3000
#define MESH_RID_WINDOW_MS 250
#define MESH_RID_SCAN_MS 500
#define MESH_DISCOVER_MS 30000
static volatile bool g_meshWindow = false;
static volatile bool g_ridWindow = false;
static volatile uint32_t g_lastHomeMs = 0;
static TaskHandle_t  meshSchedTaskHandle = NULL;
bool meshInMeshWindow(void) { return g_meshWindow; }
bool meshInRidWindow(void) { return g_ridWindow; }

// Called by a scanning engine when it dwells on the mesh channel (ch1). The
// radio is already there, so drain queued mesh TX now; ESP-NOW RX is active on
// the current channel. No channel change, no scan pause.
void meshNoteOnHome(void) {
    g_lastHomeMs = millis();
    if (meshTxTaskHandle) xTaskNotifyGive(meshTxTaskHandle);
}

bool meshMgrPhoneConnected(void) {
    if (g_mgrPhoneSeenMs == 0) return false;
    if (millis() - g_mgrPhoneSeenMs > 10000) return false;
    return g_mgrPhoneConnected;
}

bool meshManagerJoined(void) {
    if (!liveMutex) return false;
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(5)) != pdTRUE) return false;
    uint32_t now = millis();
    bool joined = false;
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (liveNodes[i].id[0] == 0) continue;
        if (liveNodes[i].role != MESH_ROLE_MANAGER) continue;
        if ((now - liveNodes[i].last_ms) > MESH_MANAGER_TTL_MS) continue;
        joined = true;
        break;
    }
    xSemaphoreGive(liveMutex);
    return joined;
}

#ifndef OUISPY_ROLE_MANAGER
static uint32_t meshMgrSilenceMs(void) {
    if (!liveMutex) return 0;
    if (xSemaphoreTake(liveMutex, pdMS_TO_TICKS(5)) != pdTRUE) return 0;
    uint32_t now = millis();
    uint32_t best = 0xFFFFFFFFu;
    for (int i = 0; i < MESH_LIVE_NODES_MAX; i++) {
        if (liveNodes[i].id[0] == 0) continue;
        if (liveNodes[i].role != MESH_ROLE_MANAGER) continue;
        uint32_t age = now - liveNodes[i].last_ms;
        if (age < best) best = age;
    }
    xSemaphoreGive(liveMutex);
    return best;
}
#endif

// True when this node is hopping WiFi channels (promiscuous scan). BLE-only
// engines (flock_ble, unipwn, wardrive radio=0x02) stay on the mesh channel,
// so they coexist with ESP-NOW without time-multiplexing.
static bool meshNodeHopsWifi(void) {
    uint8_t m = engineGetActiveMask();
    const uint8_t wifiHop = ENGINE_BITMASK(ENGINE_FLOCK_WIFI)
                          | ENGINE_BITMASK(ENGINE_FOXHUNTER)
                          | ENGINE_BITMASK(ENGINE_SKYSPY)
                          | ENGINE_BITMASK(ENGINE_PCAP);
    if (m & wifiHop) return true;
    if ((m & ENGINE_BITMASK(ENGINE_DETECTOR)) && detectorUsesWifi()) return true;
    if ((m & ENGINE_BITMASK(ENGINE_WARDRIVE)) && (wardriveGetRadio() & 0x01)) return true;
    return false;
}

static bool meshSkyspyOwnsChannel(void) {
    uint8_t m = engineGetActiveMask();
    if (!(m & ENGINE_BITMASK(ENGINE_SKYSPY))) return false;
    const uint8_t hoppers = ENGINE_BITMASK(ENGINE_FLOCK_WIFI)
                          | ENGINE_BITMASK(ENGINE_DETECTOR)
                          | ENGINE_BITMASK(ENGINE_FOXHUNTER)
                          | ENGINE_BITMASK(ENGINE_PCAP)
                          | ENGINE_BITMASK(ENGINE_WARDRIVE);
    return (m & hoppers) == 0;
}

static bool meshSkyspyActive(void) {
    return (engineGetActiveMask() & ENGINE_BITMASK(ENGINE_SKYSPY)) != 0;
}

bool meshTimeSlicingActive(void) {
    return meshCurrentConfig.enabled && meshManagerJoined() && meshNodeHopsWifi();
}

static bool meshIsStandalone(void) {
    if (meshManagerJoined()) return false;
    MeshLiveNode ln[MESH_LIVE_NODES_MAX];
    size_t n = meshGetLiveNodes(ln, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
    for (size_t i = 0; i < n; i++)
        if (ln[i].role != MESH_ROLE_MANAGER) return false;
    return true;
}

#if defined(OUISPY_AUTOPCAP_SELFTEST) || defined(OUISPY_WATCHDOG_SELFTEST)
void meshDebugForceManager(void) {
    recordLiveNode("MGRX", MESH_ROLE_MANAGER, 0);
}
#endif

#ifndef OUISPY_ROLE_MANAGER
static void meshSchedTaskFn(void* arg) {
    (void)arg;
    uint32_t discoverStartMs = millis();
    uint8_t lastMask = engineGetActiveMask();
    bool wasJoined = false;
    for (;;) {
        g_meshWindow = false;
        g_ridWindow = false;
        uint8_t curMask = engineGetActiveMask();
        if (curMask != lastMask) { lastMask = curMask; discoverStartMs = millis(); }
        bool joinedNow = meshManagerJoined();
        if (wasJoined && !joinedNow) discoverStartMs = millis();
        wasJoined = joinedNow;
        if (meshIsStandalone() &&
            (uint32_t)(millis() - discoverStartMs) >= MESH_DISCOVER_MS) {
            vTaskDelay(pdMS_TO_TICKS(200));
            continue;
        }
        bool ridScan = false;
        if (meshSkyspyOwnsChannel() && txMutex &&
            xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            esp_wifi_set_channel(6, WIFI_SECOND_CHAN_NONE);
            xSemaphoreGive(txMutex);
        } else if (meshSkyspyActive() && txMutex &&
            xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            g_ridWindow = true;
            esp_wifi_set_channel(6, WIFI_SECOND_CHAN_NONE);
            xSemaphoreGive(txMutex);
            vTaskDelay(pdMS_TO_TICKS(MESH_RID_WINDOW_MS));
            g_ridWindow = false;
            ridScan = true;
        }
        vTaskDelay(pdMS_TO_TICKS(ridScan ? MESH_RID_SCAN_MS : 150));
        bool sliceOn = meshTimeSlicingActive();
        bool reacquire =
            !sliceOn && meshCurrentConfig.enabled && meshNodeHopsWifi();
        if (!sliceOn && !reacquire) { g_lastHomeMs = millis(); continue; }
        uint32_t gap = (uint32_t)(millis() - g_lastHomeMs);
        if (sliceOn && gap < MESH_HOME_MAX_GAP_MS &&
            meshMgrSilenceMs() < MESH_MGR_SILENCE_FORCE_MS) continue;
        if (reacquire && gap < MESH_REACQUIRE_MS) continue;
        g_meshWindow = true;
        g_meshRxWin++;
        if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
            xSemaphoreGive(txMutex);
        }
        if (meshTxTaskHandle) xTaskNotifyGive(meshTxTaskHandle);
        uint32_t t0 = millis();
        for (;;) {
            uint32_t el = millis() - t0;
            if (el >= MESH_RX_WINDOW_MS) break;
            if (el >= MESH_RX_MIN_MS && meshTxQueue &&
                uxQueueMessagesWaiting(meshTxQueue) == 0 &&
                meshMgrSilenceMs() < MESH_MGR_SILENCE_FORCE_MS) break;
            vTaskDelay(pdMS_TO_TICKS(20));
        }
        g_lastHomeMs = millis();
    }
}
#endif

void meshInit(void) {
    meshMutex = xSemaphoreCreateMutex();
    gcmMutex = xSemaphoreCreateMutex();
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
    meshAddFleetMac(mac);
    if (esp_read_mac(mac, ESP_MAC_WIFI_STA) == ESP_OK) meshAddFleetMac(mac);
    if (esp_read_mac(mac, ESP_MAC_WIFI_SOFTAP) == ESP_OK) meshAddFleetMac(mac);

#ifndef OUISPY_NIMBLE2
    meshTxQueue = xQueueCreate(MESH_TX_QUEUE_DEPTH, sizeof(MeshTxItem));
    if (!meshTxQueue) {
        Serial.println("[MESH] tx queue create FAIL");
    }
#endif
#ifndef OUISPY_ROLE_MANAGER
#ifndef OUISPY_NIMBLE2
    meshRxQueue = xQueueCreate(8, sizeof(MeshRxItem));
    if (!meshRxQueue) {
        Serial.println("[MESH] rx queue create FAIL");
    }
#ifdef OUISPY_LOWRAM
    detRecQueue = xQueueCreate(24, sizeof(DetRec));
#else
    detRecQueue = xQueueCreate(128, sizeof(DetRec));
#endif
    if (!detRecQueue) {
        Serial.println("[MESH] detRec queue create FAIL");
    }
    xTaskCreate(meshRxWorkerFn, "meshRxWk", 6144, NULL, 4, &meshRxWorkerHandle);
#endif
#endif
#ifndef OUISPY_NIMBLE2
    xTaskCreate(retryTaskFn, "meshRetry", 4096, NULL, 1, &retryTaskHandle);
    xTaskCreate(meshTxTaskFn, "meshTx", 4096, NULL, 3, &meshTxTaskHandle);
#ifndef OUISPY_ROLE_MANAGER
    xTaskCreatePinnedToCore(meshSchedTaskFn, "meshSched", 4096, NULL, 2, &meshSchedTaskHandle, 0);
#endif
#endif
#if defined(OUISPY_NETCOUNT) && !defined(OUISPY_ROLE_MANAGER)
    xTaskCreate(ncInjectTaskFn, "ncInject", 4096, NULL, 1, NULL);
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
        if (gcmMutex) xSemaphoreTake(gcmMutex, portMAX_DELAY);
        mbedtls_gcm_free(&gcmCtx);
        mbedtls_gcm_init(&gcmCtx);
        int ret = mbedtls_gcm_setkey(&gcmCtx, MBEDTLS_CIPHER_ID_AES,
                                      cfg->key, 256);
        gcmReady = (ret == 0);
        if (gcmMutex) xSemaphoreGive(gcmMutex);
        if (ret != 0) {
            Serial.printf("[MESH] GCM setkey failed: %d\n", ret);
            return;
        }
        Serial.println("[MESH] AES-256-GCM encryption enabled");
    } else {
        gcmReady = false;
        Serial.println("[MESH] Encryption disabled, plaintext mode");
    }

    txCounter = 0;
    g_meshSessionSalt = esp_random();

#ifndef OUISPY_DONGLE
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(false, false);
    vTaskDelay(pdMS_TO_TICKS(100));
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
#endif
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
#ifdef OUISPY_DONGLE
    esp_err_t startRc = esp_wifi_start();
    esp_err_t chRc = esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    wifi_mode_t md = WIFI_MODE_NULL;
    esp_wifi_get_mode(&md);
    Serial.printf("[MESH] wifi start rc=0x%x ch rc=0x%x mode=%d\n",
                  (int)startRc, (int)chRc, (int)md);
#else
    esp_wifi_start();
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
#endif

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
    g_meshSessionSalt = esp_random();

    Serial.println("[MESH] Disabled");
}

void meshBroadcastDetectorList(const uint8_t* data, size_t len) {
    if (!meshCurrentConfig.enabled) return;
    if (len > MESH_IGNORELIST_MAX) len = MESH_IGNORELIST_MAX;
    MeshIgnoreListPacket pkt = {};
    pkt.pkt_type = MESH_PKT_DETECTORLIST;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.len = (uint8_t)len;
    if (len) memcpy(pkt.data, data, len);
    size_t pktSize = offsetof(MeshIgnoreListPacket, data) + len;
    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, pktSize, enc, &encLen)) return;
    enqueueTx(enc, encLen);
}

void meshBroadcastIgnoreList(const uint8_t* data, size_t len) {
    if (!meshCurrentConfig.enabled) return;
    if (len > MESH_IGNORELIST_MAX) len = MESH_IGNORELIST_MAX;
    MeshIgnoreListPacket pkt = {};
    pkt.pkt_type = MESH_PKT_IGNORELIST;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.len = (uint8_t)len;
    if (len) memcpy(pkt.data, data, len);
    size_t pktSize = offsetof(MeshIgnoreListPacket, data) + len;
    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, pktSize, enc, &encLen)) return;
    enqueueTx(enc, encLen);
}

void meshBroadcastWifiOta(const uint8_t* data, size_t len) {
    if (!meshCurrentConfig.enabled) return;
    if (len > MESH_WIFIOTA_MAX) len = MESH_WIFIOTA_MAX;
    MeshWifiOtaPacket pkt = {};
    pkt.pkt_type = MESH_PKT_WIFI_OTA;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.len = (uint8_t)len;
    if (len) memcpy(pkt.data, data, len);
    size_t pktSize = offsetof(MeshWifiOtaPacket, data) + len;
    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, pktSize, enc, &encLen)) return;
    enqueueTx(enc, encLen);
}

void meshBroadcastConfig(uint8_t kind, const uint8_t* data, size_t len) {
    if (!meshCurrentConfig.enabled) return;
    if (len > MESH_CONFIG_MAX) len = MESH_CONFIG_MAX;
    MeshConfigPacket pkt = {};
    pkt.pkt_type = MESH_PKT_CONFIG;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.cfg_kind = kind;
    pkt.len = (uint8_t)len;
    if (len) memcpy(pkt.data, data, len);
    size_t pktSize = offsetof(MeshConfigPacket, data) + len;
    uint8_t enc[256]; size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, pktSize, enc, &encLen)) return;
    enqueueTx(enc, encLen);
}

void meshEnqueueWardriveRecord(const DetectionEvent* evt) {
#ifndef OUISPY_ROLE_MANAGER
    if (!meshCurrentConfig.enabled) return;
    if (evt->source_node_id[0] != '\0') return;
    if (!detRecQueue) return;
    if (txDedupCheck(evt->engine_id, evt->mac, evt->channel)) return;

    DetRec r = {};
    memcpy(r.mac, evt->mac, 6);
    r.rssi    = evt->rssi;
    r.channel = evt->channel;
    r.method  = evt->method;
    r.auth    = (evt->engine_id == ENGINE_WARDRIVE) ? evt->ext.wardrive.auth_mode : 0;
    const char* nm = "";
    if (evt->engine_id == ENGINE_WARDRIVE)
        nm = (evt->channel == 0) ? evt->ext.wardrive.device_name : evt->ext.wardrive.ssid;
    size_t nl = strnlen(nm, MESH_DET_REC_NAME_MAX);
    r.namelen = (uint8_t)nl;
    memcpy(r.name, nm, nl);

    if (xQueueSend(detRecQueue, &r, 0) == pdTRUE && meshTxTaskHandle)
        xTaskNotifyGive(meshTxTaskHandle);
#else
    (void)evt;
#endif
}

#ifndef OUISPY_ROLE_MANAGER
static void flushDetBatches(void) {
    if (!detRecQueue || uxQueueMessagesWaiting(detRecQueue) == 0) return;
    DetRec r;
    bool have = (xQueueReceive(detRecQueue, &r, 0) == pdTRUE);
    int frames = 0;
    while (have && frames < MESH_DET_BATCH_MAX_FRAMES) {
        MeshDetectionBatchPacket pkt;
        pkt.pkt_type = MESH_PKT_DETECTION_BATCH;
        memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
        pkt.count = 0;
        size_t off = 0;
        while (have) {
            size_t recLen = 11 + r.namelen;
            if (off + recLen > MESH_DET_BATCH_BUDGET || pkt.count >= 255) break;
            uint8_t* p = pkt.data + off;
            memcpy(p, r.mac, 6);
            p[6]  = (uint8_t)r.rssi;
            p[7]  = r.channel;
            p[8]  = r.method;
            p[9]  = r.auth;
            p[10] = r.namelen;
            memcpy(p + 11, r.name, r.namelen);
            off += recLen;
            pkt.count++;
            have = (xQueueReceive(detRecQueue, &r, 0) == pdTRUE);
        }
        size_t plainLen = offsetof(MeshDetectionBatchPacket, data) + off;
        uint8_t enc[256]; size_t encLen = 0;
        if (encryptPacket((const uint8_t*)&pkt, plainLen, enc, &encLen)) {
            for (int retry = 0; retry < 3; retry++) {
                if (esp_now_send(kBroadcastDst, enc, encLen) == ESP_OK) break;
                vTaskDelay(pdMS_TO_TICKS(1));
            }
            if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(5)) == pdTRUE) {
                MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
                s.tx_count += pkt.count;
                memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
                xSemaphoreGive(meshMutex);
            }
        }
        frames++;
    }
    if (have) xQueueSendToFront(detRecQueue, &r, 0);
}
#endif

#if defined(OUISPY_NETCOUNT) && !defined(OUISPY_ROLE_MANAGER)
static void ncInjectTaskFn(void* arg) {
    (void)arg;
    uint32_t counter = 0;
    uint8_t seed = (uint8_t)localNodeId[3];
    for (;;) {
        if (meshCurrentConfig.enabled && millis() > 15000) {
            for (int i = 0; i < 40; i++) {
                DetectionEvent evt = {};
                evt.engine_id = ENGINE_WARDRIVE;
                evt.channel   = 6;
                evt.rssi      = -50;
                evt.method    = 0;
                evt.mac[0] = 0x02;
                evt.mac[1] = seed;
                evt.mac[2] = (uint8_t)(counter >> 24);
                evt.mac[3] = (uint8_t)(counter >> 16);
                evt.mac[4] = (uint8_t)(counter >> 8);
                evt.mac[5] = (uint8_t)(counter);
                snprintf(evt.ext.wardrive.ssid, sizeof(evt.ext.wardrive.ssid), "NC-%lu", (unsigned long)counter);
                meshEnqueueWardriveRecord(&evt);
                counter++;
            }
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
#endif

void meshBroadcastDetection(const DetectionEvent* evt, bool spooled) {
    if (!meshCurrentConfig.enabled) return;
    if (evt->source_node_id[0] != '\0') return;
    if (!spooled && txDedupCheck(evt->engine_id, evt->mac, evt->channel)) return;

    MeshDetectionPacket pkt = {};
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.engine_id = spooled ? (uint8_t)(evt->engine_id | DET_FLAG_AWAY) : evt->engine_id;
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
        case ENGINE_WARDRIVE:
            extSize = sizeof(evt->ext.wardrive);
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
        bool haveGeneric = uxQueueMessagesWaiting(meshTxQueue) > 0;
#ifndef OUISPY_ROLE_MANAGER
        bool haveRec = (detRecQueue && uxQueueMessagesWaiting(detRecQueue) > 0);
#else
        bool haveRec = false;
#endif
        if (!haveGeneric && !haveRec) continue;

        if (!txMutex || xSemaphoreTake(txMutex, pdMS_TO_TICKS(50)) != pdTRUE) continue;

        uint8_t cur_ch = 0; wifi_second_chan_t sec;
        esp_wifi_get_channel(&cur_ch, &sec);
#ifdef OUISPY_ROLE_MANAGER
        // Manager has no scan to disrupt — it lives on ch1; force it if drifted.
        if (cur_ch != MESH_RENDEZVOUS_CH) {
            esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
        }
#else
        // Node: never yank the radio off the scan channel. Send only while the
        // scan is naturally dwelling on ch1 (meshNoteOnHome fired); otherwise
        // wait for the next ch1 dwell. Keeps the scan sweep unbroken.
        if (cur_ch != MESH_RENDEZVOUS_CH) {
            xSemaphoreGive(txMutex);
            continue;
        }
#endif

#ifndef OUISPY_ROLE_MANAGER
        flushDetBatches();
#endif

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

void meshFlushPendingTxAllChannels(void) {
    if (!meshCurrentConfig.enabled || !meshTxQueue) return;
    if (uxQueueMessagesWaiting(meshTxQueue) == 0) return;
    if (!txMutex || xSemaphoreTake(txMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;
    uint8_t saved_ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&saved_ch, &sec);
    MeshTxItem item;
    int drained = 0;
    while (drained < MESH_TX_DRAIN_BURST &&
           xQueueReceive(meshTxQueue, &item, 0) == pdTRUE) {
        for (uint8_t ch = 1; ch <= 14; ch++) {
            esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE);
            esp_now_send(kBroadcastDst, item.data, item.len);
            vTaskDelay(pdMS_TO_TICKS(3));
        }
        drained++;
    }
    esp_wifi_set_channel(saved_ch != 0 ? saved_ch : MESH_RENDEZVOUS_CH,
                         WIFI_SECOND_CHAN_NONE);
    xSemaphoreGive(txMutex);
}

static void sendOnHome(const uint8_t* data, size_t len) {
    if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(100)) != pdTRUE) return;
    esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
    esp_now_send(kBroadcastDst, data, len);
    vTaskDelay(pdMS_TO_TICKS(3));
    esp_now_send(kBroadcastDst, data, len);
    if (txMutex) xSemaphoreGive(txMutex);
}

static void sendOnHomeRestore(const uint8_t* data, size_t len) {
    if (txMutex && xSemaphoreTake(txMutex, pdMS_TO_TICKS(200)) != pdTRUE) return;
    uint8_t saved_ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&saved_ch, &sec);
    esp_wifi_set_channel(MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
    esp_now_send(kBroadcastDst, data, len);
    vTaskDelay(pdMS_TO_TICKS(3));
    esp_now_send(kBroadcastDst, data, len);
    esp_wifi_set_channel(saved_ch != 0 ? saved_ch : MESH_RENDEZVOUS_CH, WIFI_SECOND_CHAN_NONE);
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
    sendOnHomeRestore(enc, encLen);
    Serial.printf("[MESH-ACK-TX] seq=%u cmd=0x%02x engine=%u\n",
        ack.ack_seq, ack.ack_cmd, ack.ack_engine_id);
}

void meshBroadcastCommand(uint8_t command, uint8_t engine_id, const uint8_t* payload, uint8_t payload_len, uint8_t maxRetries) {
    if (!meshCurrentConfig.enabled) return;
    if (command == 0x00 || command == 0x01 || command == 0x0F) maxRetries = 0;

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
    p.created_ms = millis();
    p.retries_left = maxRetries;
    p.max_retries = maxRetries;
    p.acked = false;
    p.acks = 0;
    {
        MeshLiveNode ln[MESH_LIVE_NODES_MAX];
        size_t lc = meshGetLiveNodes(ln, MESH_LIVE_NODES_MAX, 30000);
        uint8_t reachable = 0;
        for (size_t i = 0; i < lc; i++) {
            if (ln[i].role == MESH_ROLE_MANAGER) continue;
            if (cmdNodeDeaf(ln[i].id)) continue;
            reachable++;
        }
        p.expected = (reachable == 0) ? 1 : reachable;
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
        seq, command, engine_id, maxRetries);

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
            if (nowHb - lastHeartbeat >= 1500u) {
                uint8_t hbCh = 0; wifi_second_chan_t hbSec;
                esp_wifi_get_channel(&hbCh, &hbSec);
                bool onHomeChannel = !meshTimeSlicingActive() ||
                                     meshInMeshWindow() ||
                                     hbCh == MESH_RENDEZVOUS_CH;
                if (onHomeChannel) {
                    lastHeartbeat = nowHb;
                    meshSendHeartbeat(engineGetActiveMask());
                    Serial.printf("[HB] tx id=%s ch=%u slicing=%d\n",
                                  localNodeId, hbCh, meshTimeSlicingActive() ? 1 : 0);
                }
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
                    p.seq, p.command, p.engine_id, p.acks, p.expected, p.max_retries);
                pendingCmds[i].in_use = false;
                xSemaphoreGive(pendingMutex);
                MeshLiveNode ln[MESH_LIVE_NODES_MAX];
                size_t lc = meshGetLiveNodes(ln, MESH_LIVE_NODES_MAX, 30000);
                for (size_t k = 0; k < lc; k++) {
                    if (ln[k].role == MESH_ROLE_MANAGER) continue;
                    CmdHealth* h = cmdHealthSlot(ln[k].id);
                    if (h->last_ack_ms < p.created_ms) cmdHealthMiss(ln[k].id);
                }
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
                                uint8_t paused_mask, uint8_t mode) {
    if (!meshCurrentConfig.enabled) return;
    MeshAutoPcapEventPacket ev = {};
    ev.pkt_type = MESH_PKT_AUTOPCAP_EVENT;
    memcpy(ev.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    ev.trigger_src = trigger_src;
    if (mac) memcpy(ev.trigger_mac, mac, 6);
    ev.channel = channel;
    ev.duration_sec = duration_sec;
    ev.paused_mask = paused_mask;
    ev.mode = mode;

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
    if (!meshTxQueue) return;
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
    hb.role = g_meshManagerActive ? 1 : 0;
#else
    hb.role = 0;
#endif
    hb.active_engines_mask = active_engines_mask;
    hb.alerts_suppressed = hwAlertsSuppressed ? 1 : 0;
    hb.fw_version = FW_VERSION_NUM;
    hb.phone_connected = bleGattIsConnected() ? 1 : 0;
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
