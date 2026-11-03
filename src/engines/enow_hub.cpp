#include "enow_hub.h"
#include "detector.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <mbedtls/sha256.h>

#define ENOW_CHANNEL             6
#define ENOW_TEXT_MAX            200
#define ENOW_MAX_NODES           24
#define ENOW_NODE_TIMEOUT_MS     60000
#define ENOW_SCAN_CHANNEL_COUNT  40
#define ENOW_REFRESH_MS          5000

static const uint8_t ENOW_BCAST[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

enum : uint8_t {
    ENOW_CORE_REQUEST = 1,
    ENOW_CORE_REPLY   = 2,
    ENOW_HEARTBEAT    = 3,
    ENOW_TEXT         = 4,
    ENOW_ADMIN        = 5,
};

typedef struct __attribute__((packed)) {
    char     magic[4];
    uint8_t  type;
    uint32_t counter;
    uint16_t len;
    char     text[ENOW_TEXT_MAX + 1];
} EnowTextMsg;
static_assert(sizeof(EnowTextMsg) == 212, "ENOW text frame size");

typedef struct __attribute__((packed)) {
    char    magic[4];
    uint8_t type;
    uint8_t version;
    uint8_t index;
    uint8_t count;
    uint8_t start;
    uint8_t end;
} EnowAdminMsg;
static_assert(sizeof(EnowAdminMsg) == 10, "ENOW admin frame size");

struct EnowNode {
    uint8_t  mac[6];
    uint32_t lastMs;
    uint8_t  index;
    uint8_t  start;
    uint8_t  end;
    uint8_t  sentVersion;
    bool     active;
    bool     encrypted;
};

static const char ENOW_MAGIC[4] = {'E', 'N', 'O', 'W'};
static EnowNode* s_nodes = nullptr;
static volatile bool s_active = false;
static bool s_encrypt = false;
static uint8_t s_pmk[16];
static uint8_t s_lmk[16];
static uint8_t s_allow[ENOW_HUB_MAX_ALLOW][6];
static uint8_t s_allowCount = 0;
static uint8_t s_version = 0;
static volatile uint32_t s_pendingReply = 0;
static volatile uint32_t s_pendingAdmin = 0;
static volatile bool s_topologyDirty = false;
static volatile uint32_t s_records = 0;
static portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;

#define ENOW_SEEN_MAX   16
#define ENOW_CAP_SLOTS  16
#define ENOW_CAP_BYTES  48

struct EnowSeen {
    uint8_t  mac[6];
    int8_t   rssi;
    uint32_t lastMs;
    uint32_t records;
    char     name[24];
    bool     used;
    bool     dirty;
};

struct EnowCap {
    uint8_t  src[6];
    uint8_t  dst[6];
    uint16_t len;
    uint8_t  body[ENOW_CAP_BYTES];
};

static EnowSeen s_seen[ENOW_SEEN_MAX];
static EnowCap s_cap[ENOW_CAP_SLOTS];
static volatile uint8_t s_capHead = 0;
static volatile uint8_t s_capTail = 0;
static volatile bool s_capture = false;
static EnowNodeSink s_nodeSink = nullptr;
static EnowFrameSink s_frameSink = nullptr;

static void deriveKey16(const char* pass, const char* suffix, uint8_t out[16]) {
    uint8_t hash[32];
    mbedtls_sha256_context ctx;
    mbedtls_sha256_init(&ctx);
    mbedtls_sha256_starts(&ctx, 0);
    mbedtls_sha256_update(&ctx, (const unsigned char*)pass, strlen(pass));
    mbedtls_sha256_update(&ctx, (const unsigned char*)suffix, strlen(suffix));
    mbedtls_sha256_finish(&ctx, hash);
    mbedtls_sha256_free(&ctx);
    memcpy(out, hash, 16);
}

bool enowHubSelfTest(void) {
    static const uint8_t wantPmk[16] = {0x16, 0xed, 0x53, 0x88, 0x99, 0xe1, 0x7a, 0x1a,
                                        0xcd, 0x47, 0x3e, 0xa9, 0x52, 0xbf, 0xaa, 0x95};
    static const uint8_t wantLmk[16] = {0xb3, 0x94, 0x73, 0x58, 0xb8, 0x1d, 0x3a, 0x3d,
                                        0x92, 0xf7, 0xd5, 0x0c, 0x62, 0xcd, 0x41, 0x07};
    uint8_t pmk[16], lmk[16];
    deriveKey16("test", "_pmk", pmk);
    deriveKey16("test", "_lmk", lmk);
    bool ok = memcmp(pmk, wantPmk, 16) == 0 && memcmp(lmk, wantLmk, 16) == 0;
    Serial.printf("[ENOW] key derivation self-test %s\n", ok ? "PASS" : "FAIL");
    return ok;
}

static bool allowed(const uint8_t* mac) {
    for (uint8_t i = 0; i < s_allowCount; i++) {
        if (memcmp(s_allow[i], mac, 6) == 0) return true;
    }
    return false;
}

static int findNode(const uint8_t* mac) {
    for (int i = 0; i < ENOW_MAX_NODES; i++) {
        if (s_nodes[i].active && memcmp(s_nodes[i].mac, mac, 6) == 0) return i;
    }
    return -1;
}

static int findTrusted(const uint8_t* mac) {
    for (int i = 0; i < ENOW_MAX_NODES; i++) {
        if (s_nodes[i].encrypted && memcmp(s_nodes[i].mac, mac, 6) == 0) return i;
    }
    return -1;
}

static int touchNode(const uint8_t* mac) {
    int slot = findNode(mac);
    if (slot >= 0) {
        s_nodes[slot].lastMs = millis();
        return slot;
    }
    slot = findTrusted(mac);
    if (slot >= 0) {
        s_nodes[slot].lastMs = millis();
        s_nodes[slot].active = true;
        s_nodes[slot].sentVersion = 0;
        s_topologyDirty = true;
        return slot;
    }
    for (int i = 0; i < ENOW_MAX_NODES; i++) {
        if (!s_nodes[i].active && !s_nodes[i].encrypted) {
            memset(&s_nodes[i], 0, sizeof(EnowNode));
            memcpy(s_nodes[i].mac, mac, 6);
            s_nodes[i].lastMs = millis();
            s_nodes[i].active = true;
            s_topologyDirty = true;
            return i;
        }
    }
    return -1;
}

static int parseHexByte(const char* p) {
    int v = 0;
    for (int k = 0; k < 2; k++) {
        char c = p[k];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= c - '0';
        else if (c >= 'a' && c <= 'f') v |= c - 'a' + 10;
        else if (c >= 'A' && c <= 'F') v |= c - 'A' + 10;
        else return -1;
    }
    return v;
}

static bool parseMac(const char* s, int n, uint8_t out[6]) {
    if (n != 17) return false;
    for (int i = 0; i < 6; i++) {
        int b = parseHexByte(s + i * 3);
        if (b < 0) return false;
        if (i < 5 && s[i * 3 + 2] != ':' && s[i * 3 + 2] != '-') return false;
        out[i] = (uint8_t)b;
    }
    return true;
}

static uint8_t authFromSecurity(const char* s, int n) {
    auto is = [&](const char* w) { return (int)strlen(w) == n && memcmp(s, w, n) == 0; };
    if (is("[OPEN]")) return 0;
    if (is("[WEP]")) return 1;
    if (is("[WPA_PSK]")) return 2;
    if (is("[WPA2_PSK]")) return 3;
    if (is("[WPA_WPA2_PSK]")) return 4;
    if (is("[WPA2]")) return 5;
    if (is("[WPA3_PSK]") || is("[WPA2_WPA3_PSK]")) return 6;
    if (is("OPEN")) return 0;
    if (is("WEP")) return 1;
    if (is("WPA")) return 2;
    if (is("WPA2")) return 3;
    if (is("WPAWPA2")) return 4;
    if (is("WPA2EAP") || is("[WPA2_ENTERPRISE]")) return 5;
    if (is("WPA3") || is("WPA2WPA3")) return 6;
    return 3;
}

static int seenSlot(const uint8_t* mac) {
    int freeSlot = -1, oldest = -1;
    for (int i = 0; i < ENOW_SEEN_MAX; i++) {
        if (s_seen[i].used && memcmp(s_seen[i].mac, mac, 6) == 0) return i;
        if (!s_seen[i].used) { if (freeSlot < 0) freeSlot = i; continue; }
        if (allowed(s_seen[i].mac)) continue;
        if (oldest < 0 || (int32_t)(s_seen[i].lastMs - s_seen[oldest].lastMs) < 0) oldest = i;
    }
    int slot = freeSlot >= 0 ? freeSlot : oldest;
    if (slot < 0) return -1;
    memset(&s_seen[slot], 0, sizeof(EnowSeen));
    memcpy(s_seen[slot].mac, mac, 6);
    s_seen[slot].used = true;
    s_seen[slot].dirty = true;
    return slot;
}

static void noteSeen(const uint8_t* mac, int8_t rssi, const EnowTextMsg* hello) {
    portENTER_CRITICAL(&s_mux);
    int s = seenSlot(mac);
    if (s >= 0) {
        s_seen[s].rssi = rssi;
        s_seen[s].lastMs = millis();
        if (hello && hello->len > 0) {
            size_t n = hello->len < sizeof(s_seen[s].name) - 1 ? hello->len : sizeof(s_seen[s].name) - 1;
            if (memcmp(s_seen[s].name, hello->text, n) != 0 || s_seen[s].name[n] != 0) {
                memcpy(s_seen[s].name, hello->text, n);
                s_seen[s].name[n] = 0;
                s_seen[s].dirty = true;
            }
        }
    }
    portEXIT_CRITICAL(&s_mux);
}

static void countRecord(const uint8_t* mac) {
    portENTER_CRITICAL(&s_mux);
    for (int i = 0; i < ENOW_SEEN_MAX; i++) {
        if (s_seen[i].used && memcmp(s_seen[i].mac, mac, 6) == 0) { s_seen[i].records++; break; }
    }
    portEXIT_CRITICAL(&s_mux);
}

static void capturePush(const uint8_t* src, const uint8_t* dst, const uint8_t* body, int len) {
    portENTER_CRITICAL(&s_mux);
    uint8_t next = (uint8_t)((s_capHead + 1) % ENOW_CAP_SLOTS);
    if (next != s_capTail) {
        EnowCap& c = s_cap[s_capHead];
        memcpy(c.src, src, 6);
        memcpy(c.dst, dst, 6);
        c.len = (uint16_t)len;
        memcpy(c.body, body, len < ENOW_CAP_BYTES ? len : ENOW_CAP_BYTES);
        s_capHead = next;
    }
    portEXIT_CRITICAL(&s_mux);
}

static void enowSniff(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!s_capture || type != WIFI_PKT_MGMT) return;
    const wifi_promiscuous_pkt_t* p = (const wifi_promiscuous_pkt_t*)buf;
    const uint8_t* f = p->payload;
    int len = (int)p->rx_ctrl.sig_len - 4;
    if (len < 44 || f[0] != 0xD0 || f[24] != 0x7F) return;
    if (f[25] != 0x18 || f[26] != 0xFE || f[27] != 0x34) return;
    if (f[32] != 0xDD || f[34] != 0x18 || f[35] != 0xFE || f[36] != 0x34 || f[37] != 0x04) return;
    int bodyLen = (int)f[33] - 5;
    if (bodyLen < 5 || 39 + bodyLen > len) return;
    const uint8_t* body = f + 39;
    if (memcmp(body, ENOW_MAGIC, 4) != 0) return;
    if (body[4] == ENOW_TEXT && allowed(f + 10)) return;
    capturePush(f + 10, f + 4, body, bodyLen);
}

static void handleText(const uint8_t* src, const EnowTextMsg* m) {
    uint16_t n = m->len;
    if (n == 0 || n > ENOW_TEXT_MAX) return;
    const char* t = m->text;
    int commas[64];
    int nc = 0;
    for (int i = 0; i < n && nc < 64; i++) if (t[i] == ',') commas[nc++] = i;
    if (nc < 5) return;
    int cType = commas[nc - 1], cRssi = commas[nc - 2], cChan = commas[nc - 3], cSec = commas[nc - 4];
    int cMac = commas[0];
    uint8_t mac[6];
    if (!parseMac(t, cMac, mac)) return;
    bool ble = (n - cType - 1) == 1 && t[cType + 1] == 'B';
    int channel = atoi(t + cChan + 1);
    int rssi = atoi(t + cRssi + 1);
    DetectionEvent evt = {};
    evt.engine_id = ENGINE_WARDRIVE;
    memcpy(evt.mac, mac, 6);
    evt.rssi = (int8_t)(rssi < -127 ? -127 : rssi > 0 ? 0 : rssi);
    evt.channel = ble ? 0 : (uint8_t)channel;
    evt.timestamp_ms = millis();
    evt.method = ble ? METHOD_BLE_ADV : METHOD_WIFI_AP;
    snprintf(evt.source_node_id, sizeof(evt.source_node_id), "E%03X",
             (unsigned)(((src[4] << 8) | src[5]) & 0xFFF));
    if (!ble) {
        int ssidLen = cSec - cMac - 1;
        if (ssidLen > 32) ssidLen = 32;
        if (ssidLen > 0) memcpy(evt.ext.wardrive.ssid, t + cMac + 1, ssidLen);
        evt.ext.wardrive.auth_mode = authFromSecurity(t + cSec + 1, cChan - cSec - 1);
    }
    if (pushDetection(&evt)) {
        s_records++;
        countRecord(src);
    }
}

#ifdef OUISPY_NIMBLE2
static void enowRecv(const esp_now_recv_info_t* info, const uint8_t* data, int len) {
    const uint8_t* src = info ? info->src_addr : nullptr;
    int8_t rssi = (info && info->rx_ctrl) ? (int8_t)info->rx_ctrl->rssi : 0;
#else
static void enowRecv(const uint8_t* src, const uint8_t* data, int len) {
    int8_t rssi = 0;
#endif
    if (!s_active || !s_nodes || !src || !data || len < 5) return;
    if (memcmp(data, ENOW_MAGIC, 4) != 0) return;
    uint8_t type = data[4];
    noteSeen(src, rssi, (type == 7 && len >= (int)sizeof(EnowTextMsg)) ? (const EnowTextMsg*)data : nullptr);
    if (!allowed(src)) return;
    if (s_encrypt && type != ENOW_CORE_REQUEST && findTrusted(src) < 0) return;
    if (type == ENOW_CORE_REQUEST || type == ENOW_HEARTBEAT) {
        portENTER_CRITICAL(&s_mux);
        int slot = touchNode(src);
        if (slot >= 0) {
            if (type == ENOW_CORE_REQUEST) s_pendingReply |= (1u << slot);
            s_pendingAdmin |= (1u << slot);
        }
        portEXIT_CRITICAL(&s_mux);
    } else if (type == ENOW_TEXT) {
        if (len < (int)sizeof(EnowTextMsg)) return;
        handleText(src, (const EnowTextMsg*)data);
    }
}

static bool ensurePeer(const uint8_t* mac, bool encrypt) {
    if (esp_now_is_peer_exist(mac)) {
        esp_now_peer_info_t cur = {};
        if (esp_now_get_peer(mac, &cur) == ESP_OK && cur.encrypt == encrypt) return true;
        esp_now_del_peer(mac);
    }
    esp_now_peer_info_t p = {};
    memcpy(p.peer_addr, mac, 6);
    p.channel = 0;
    p.encrypt = encrypt;
    if (encrypt) memcpy(p.lmk, s_lmk, 16);
    return esp_now_add_peer(&p) == ESP_OK;
}

static void reassign(void) {
    uint8_t act[ENOW_MAX_NODES];
    uint8_t n = 0;
    for (uint8_t i = 0; i < ENOW_MAX_NODES; i++) if (s_nodes[i].active) act[n++] = i;
    if (++s_version == 0) s_version = 1;
    for (uint8_t k = 0; k < n; k++) {
        EnowNode& nd = s_nodes[act[k]];
        nd.index = k;
        nd.start = (uint8_t)((k * ENOW_SCAN_CHANNEL_COUNT) / n);
        nd.end = (uint8_t)((((k + 1) * ENOW_SCAN_CHANNEL_COUNT) / n) - 1);
    }
    Serial.printf("[ENOW] assignment v%u across %u nodes\n", (unsigned)s_version, (unsigned)n);
}

static void enowHubListOne(int i) {
    EnowSeen e;
    portENTER_CRITICAL(&s_mux);
    e = s_seen[i];
    portEXIT_CRITICAL(&s_mux);
    if (!e.used || !s_nodeSink) return;
    uint8_t flags = 0;
    if (allowed(e.mac)) flags |= ENOW_NODE_PAIRED;
    int slot = s_nodes ? findNode(e.mac) : -1;
    if (slot >= 0) {
        flags |= ENOW_NODE_ONLINE;
        if (s_nodes[slot].encrypted) flags |= ENOW_NODE_ENCRYPTED;
    }
    s_nodeSink(e.mac, e.rssi, flags, e.records, e.name);
}

void enowHubTick(void) {
    if (!s_active || !s_nodes) return;
    uint32_t now = millis();
    portENTER_CRITICAL(&s_mux);
    for (int i = 0; i < ENOW_MAX_NODES; i++) {
        if (s_nodes[i].active && now - s_nodes[i].lastMs > ENOW_NODE_TIMEOUT_MS) {
            s_nodes[i].active = false;
            s_topologyDirty = true;
        }
    }
    bool topo = s_topologyDirty;
    s_topologyDirty = false;
    uint32_t reply = s_pendingReply, admin = s_pendingAdmin;
    s_pendingReply = 0;
    s_pendingAdmin = 0;
    portEXIT_CRITICAL(&s_mux);
    if (topo) {
        reassign();
        portENTER_CRITICAL(&s_mux);
        for (int i = 0; i < ENOW_SEEN_MAX; i++) if (s_seen[i].used) s_seen[i].dirty = true;
        portEXIT_CRITICAL(&s_mux);
    }
    if (s_nodeSink) {
        for (int i = 0; i < ENOW_SEEN_MAX; i++) {
            portENTER_CRITICAL(&s_mux);
            bool send = s_seen[i].used && s_seen[i].dirty;
            s_seen[i].dirty = false;
            portEXIT_CRITICAL(&s_mux);
            if (send) enowHubListOne(i);
        }
    }
    for (int k = 0; k < 4 && s_capTail != s_capHead; k++) {
        EnowCap c;
        portENTER_CRITICAL(&s_mux);
        c = s_cap[s_capTail];
        s_capTail = (uint8_t)((s_capTail + 1) % ENOW_CAP_SLOTS);
        portEXIT_CRITICAL(&s_mux);
        if (s_frameSink) s_frameSink(c.src, c.dst, c.body, c.len < ENOW_CAP_BYTES ? c.len : ENOW_CAP_BYTES, c.len);
    }
    uint8_t count = enowHubNodeCount();
    static uint32_t lastRefresh = 0;
    bool refresh = now - lastRefresh >= ENOW_REFRESH_MS;
    if (refresh) {
        lastRefresh = now;
        EnowTextMsg hb = {};
        memcpy(hb.magic, ENOW_MAGIC, 4);
        hb.type = ENOW_HEARTBEAT;
        hb.counter = now;
        if (ensurePeer(ENOW_BCAST, false)) esp_now_send(ENOW_BCAST, (const uint8_t*)&hb, sizeof(hb));
    }
    for (int i = 0; i < ENOW_MAX_NODES; i++) {
        EnowNode& nd = s_nodes[i];
        if (!nd.active) continue;
        if (reply & (1u << i)) {
            EnowTextMsg m = {};
            memcpy(m.magic, ENOW_MAGIC, 4);
            m.type = ENOW_CORE_REPLY;
            if (ensurePeer(nd.mac, false)) esp_now_send(nd.mac, (const uint8_t*)&m, sizeof(m));
            nd.encrypted = s_encrypt && ensurePeer(nd.mac, true);
        }
        bool assign = (admin & (1u << i)) && nd.sentVersion != s_version;
        if (!assign && !refresh) continue;
        if (!ensurePeer(nd.mac, nd.encrypted)) continue;
        EnowAdminMsg a = {};
        memcpy(a.magic, ENOW_MAGIC, 4);
        a.type = ENOW_ADMIN;
        a.version = s_version;
        a.index = nd.index;
        a.count = count;
        a.start = nd.start;
        a.end = nd.end;
        if (esp_now_send(nd.mac, (const uint8_t*)&a, sizeof(a)) == ESP_OK) nd.sentVersion = s_version;
    }
}

bool enowHubBlocksEngine(EngineId id) {
    if (!s_active) return false;
    return id == ENGINE_FLOCK_WIFI || id == ENGINE_SKYSPY || id == ENGINE_WARDRIVE ||
           id == ENGINE_PCAP || id == ENGINE_FOXHUNTER ||
           (id == ENGINE_DETECTOR && detectorUsesWifi());
}

uint8_t enowHubStart(const char* passphrase, const uint8_t* allow, uint8_t allowCount) {
    if (s_active) return ENOW_HUB_OK;
    if (allowCount > ENOW_HUB_MAX_ALLOW || (allowCount && !allow)) return ENOW_HUB_REFUSE_ARGS;
    if (meshIsEnabled()) return ENOW_HUB_REFUSE_MESH;
    for (int e = 0; e < ENGINE_COUNT; e++) {
        if (engineGetState((EngineId)e) == ESTATE_DISABLED) continue;
        s_active = true;
        bool blocks = enowHubBlocksEngine((EngineId)e);
        s_active = false;
        if (blocks) return ENOW_HUB_REFUSE_WIFI;
    }
    if (!enowHubSelfTest()) return ENOW_HUB_REFUSE_INIT;
    if (!s_nodes) s_nodes = (EnowNode*)calloc(ENOW_MAX_NODES, sizeof(EnowNode));
    if (!s_nodes) return ENOW_HUB_REFUSE_INIT;
    memset(s_nodes, 0, ENOW_MAX_NODES * sizeof(EnowNode));
    s_encrypt = passphrase && passphrase[0];
    if (s_encrypt) {
        deriveKey16(passphrase, "_pmk", s_pmk);
        deriveKey16(passphrase, "_lmk", s_lmk);
    }
    s_allowCount = allowCount;
    if (allowCount) memcpy(s_allow, allow, (size_t)allowCount * 6);
    WiFi.mode(WIFI_STA);
    esp_wifi_set_channel(ENOW_CHANNEL, WIFI_SECOND_CHAN_NONE);
    if (esp_now_init() != ESP_OK) return ENOW_HUB_REFUSE_INIT;
    if (s_encrypt) esp_now_set_pmk(s_pmk);
    esp_now_register_recv_cb(enowRecv);
    s_records = 0;
    s_version = 0;
    s_pendingReply = s_pendingAdmin = 0;
    memset(s_seen, 0, sizeof(s_seen));
    s_capHead = s_capTail = 0;
    s_active = true;
    Serial.printf("[ENOW] hub on ch%u encrypt=%d allow=%u\n", (unsigned)ENOW_CHANNEL, (int)s_encrypt,
                  (unsigned)allowCount);
    return ENOW_HUB_OK;
}

void enowHubSetSinks(EnowNodeSink node, EnowFrameSink frame) {
    s_nodeSink = node;
    s_frameSink = frame;
}

bool enowHubPair(const uint8_t mac[6]) {
    bool ok = true;
    portENTER_CRITICAL(&s_mux);
    if (!allowed(mac)) {
        if (s_allowCount >= ENOW_HUB_MAX_ALLOW) ok = false;
        else memcpy(s_allow[s_allowCount++], mac, 6);
    }
    if (ok) {
        int s = seenSlot(mac);
        if (s >= 0) s_seen[s].dirty = true;
    }
    portEXIT_CRITICAL(&s_mux);
    Serial.printf("[ENOW] pair %02X:%02X:%02X:%02X:%02X:%02X %s\n", mac[0], mac[1], mac[2], mac[3], mac[4],
                  mac[5], ok ? "ok" : "full");
    return ok;
}

bool enowHubForget(const uint8_t mac[6]) {
    bool found = false;
    portENTER_CRITICAL(&s_mux);
    for (uint8_t i = 0; i < s_allowCount; i++) {
        if (memcmp(s_allow[i], mac, 6) != 0) continue;
        memmove(s_allow[i], s_allow[i + 1], (size_t)(s_allowCount - i - 1) * 6);
        s_allowCount--;
        found = true;
        break;
    }
    if (s_nodes) {
        for (int i = 0; i < ENOW_MAX_NODES; i++) {
            if (memcmp(s_nodes[i].mac, mac, 6) != 0) continue;
            if (s_nodes[i].active) s_topologyDirty = true;
            s_nodes[i].active = false;
            s_nodes[i].encrypted = false;
        }
    }
    for (int i = 0; i < ENOW_SEEN_MAX; i++) {
        if (s_seen[i].used && memcmp(s_seen[i].mac, mac, 6) == 0) s_seen[i].dirty = true;
    }
    portEXIT_CRITICAL(&s_mux);
    if (s_active && esp_now_is_peer_exist(mac)) esp_now_del_peer(mac);
    return found;
}

void enowHubListNodes(void) {
    for (int i = 0; i < ENOW_SEEN_MAX; i++) enowHubListOne(i);
}

void enowHubSetCapture(bool on) {
    if (!s_active) on = false;
    if (on == s_capture) return;
    s_capture = on;
    if (on) {
        wifiCoexRegister(enowSniff, WIFI_PROMIS_FILTER_MASK_MGMT);
        esp_wifi_set_channel(ENOW_CHANNEL, WIFI_SECOND_CHAN_NONE);
    } else {
        wifiCoexUnregister(enowSniff);
    }
    Serial.printf("[ENOW] capture %s\n", on ? "on" : "off");
}

bool enowHubCaptureOn(void) { return s_capture; }

void enowHubStop(void) {
    if (!s_active) return;
    enowHubSetCapture(false);
    s_active = false;
    esp_now_unregister_recv_cb();
    esp_now_deinit();
    memset(s_pmk, 0, sizeof(s_pmk));
    memset(s_lmk, 0, sizeof(s_lmk));
    Serial.println("[ENOW] hub off");
}

bool enowHubActive(void) { return s_active; }

uint8_t enowHubNodeCount(void) {
    if (!s_nodes) return 0;
    uint8_t n = 0;
    for (int i = 0; i < ENOW_MAX_NODES; i++) if (s_nodes[i].active) n++;
    return n;
}

uint32_t enowHubRecordCount(void) { return s_records; }

#ifdef OUISPY_PORT_SELFTEST
static int pstFail = 0;
static void pstCheck(const char* name, bool ok, const char* detail = "") {
    Serial.printf("[PST] enow.%s %s %s\n", name, ok ? "PASS" : "FAIL", detail);
    if (!ok) pstFail++;
}

static void pstFeed(const uint8_t* src, const void* frame, int len) {
#ifdef OUISPY_NIMBLE2
    esp_now_recv_info_t info = {};
    info.src_addr = (uint8_t*)src;
    enowRecv(&info, (const uint8_t*)frame, len);
#else
    enowRecv(src, (const uint8_t*)frame, len);
#endif
}

static void pstFrame(EnowTextMsg* m, uint8_t type, const char* text) {
    memset(m, 0, sizeof(*m));
    memcpy(m->magic, ENOW_MAGIC, 4);
    m->type = type;
    if (text) {
        m->len = (uint16_t)strlen(text);
        memcpy(m->text, text, m->len);
    }
}

int enowHubPortSelfTest(void) {
    pstFail = 0;
    DetectionEvent e;
    while (xQueueReceive(detectionQueue, &e, 0) == pdTRUE) {}
    pstCheck("key_derivation_vectors", enowHubSelfTest());

    if (!s_nodes) s_nodes = (EnowNode*)calloc(ENOW_MAX_NODES, sizeof(EnowNode));
    memset(s_nodes, 0, ENOW_MAX_NODES * sizeof(EnowNode));
    s_allowCount = 0;
    s_encrypt = false;
    s_records = 0;
    s_version = 0;
    s_pendingReply = s_pendingAdmin = 0;
    s_active = true;

    pstCheck("blocks_wifi_engine", enowHubBlocksEngine(ENGINE_WARDRIVE) && enowHubBlocksEngine(ENGINE_FLOCK_WIFI));
    pstCheck("allows_ble_engine", !enowHubBlocksEngine(ENGINE_UNIPWN) && !enowHubBlocksEngine(ENGINE_FLOCK_BLE));
    pstCheck("engine_enable_refused", !engineEnable(ENGINE_WARDRIVE));
    memset(s_seen, 0, sizeof(s_seen));

    const uint8_t n1[6] = {0x02, 0x00, 0x00, 0x00, 0x10, 0x01};
    const uint8_t n2[6] = {0x02, 0x00, 0x00, 0x00, 0x10, 0x02};
    const uint8_t n3[6] = {0x02, 0x00, 0x00, 0x00, 0x10, 0x03};
    EnowTextMsg m;
    pstFrame(&m, ENOW_CORE_REQUEST, nullptr);
    pstFeed(n1, &m, sizeof(m));
    pstCheck("unpaired_request_seen_not_admitted",
             enowHubNodeCount() == 0 && s_pendingReply == 0 && s_seen[0].used && memcmp(s_seen[0].mac, n1, 6) == 0);
    pstFrame(&m, 7, "Piglet:v2.65");
    pstFeed(n1, &m, sizeof(m));
    pstCheck("hello_names_seen_node", strcmp(s_seen[0].name, "Piglet:v2.65") == 0, s_seen[0].name);
    enowHubPair(n1);
    enowHubPair(n2);
    enowHubPair(n3);
    pstFrame(&m, ENOW_CORE_REQUEST, nullptr);
    pstFeed(n1, &m, sizeof(m));
    pstCheck("core_request_registers_node", enowHubNodeCount() == 1 && (s_pendingReply & 1u) && (s_pendingAdmin & 1u));
    pstFrame(&m, ENOW_HEARTBEAT, nullptr);
    pstFeed(n2, &m, sizeof(m));
    pstFeed(n3, &m, sizeof(m));
    reassign();
    char d[64];
    snprintf(d, sizeof(d), "v%u %u-%u %u-%u %u-%u", s_version, s_nodes[0].start, s_nodes[0].end,
             s_nodes[1].start, s_nodes[1].end, s_nodes[2].start, s_nodes[2].end);
    pstCheck("channel_split_three_nodes",
             s_version == 1 && s_nodes[0].start == 0 && s_nodes[0].end == 12 && s_nodes[1].start == 13 &&
             s_nodes[1].end == 25 && s_nodes[2].start == 26 && s_nodes[2].end == 39, d);

    pstFrame(&m, ENOW_TEXT, "AA:BB:CC:DD:EE:01,My,Net,[WPA2_PSK],11,-61,W");
    pstFeed(n1, &m, sizeof(m));
    bool w = xQueueReceive(detectionQueue, &e, 0) == pdTRUE && e.engine_id == ENGINE_WARDRIVE &&
             e.method == METHOD_WIFI_AP && strcmp(e.ext.wardrive.ssid, "My,Net") == 0 &&
             e.ext.wardrive.auth_mode == 3 && e.channel == 11 && e.rssi == -61 && e.mac[5] == 0x01 &&
             e.source_node_id[0] == 'E';
    snprintf(d, sizeof(d), "ssid=%s auth=%u ch=%u rssi=%d src=%s", e.ext.wardrive.ssid,
             e.ext.wardrive.auth_mode, e.channel, e.rssi, e.source_node_id);
    pstCheck("text_wifi_comma_ssid", w, d);
    pstCheck("record_counted_per_node", s_seen[0].records == 1);
    pstFrame(&m, ENOW_TEXT, "AA:BB:CC:DD:EE:04,Cafe,OPEN,6,-55,W");
    pstFeed(n1, &m, sizeof(m));
    bool o = xQueueReceive(detectionQueue, &e, 0) == pdTRUE && e.ext.wardrive.auth_mode == 0;
    pstCheck("jcmk_bare_open_auth", o);
    pstFrame(&m, ENOW_TEXT, "AA:BB:CC:DD:EE:02,,[BLE],0,-70,B");
    pstFeed(n1, &m, sizeof(m));
    bool b = xQueueReceive(detectionQueue, &e, 0) == pdTRUE && e.method == METHOD_BLE_ADV && e.channel == 0;
    pstCheck("text_ble_line", b);
    pstFrame(&m, ENOW_TEXT, "garbage");
    pstFeed(n1, &m, sizeof(m));
    pstCheck("text_malformed_dropped", xQueueReceive(detectionQueue, &e, 0) != pdTRUE);

    s_encrypt = true;
    pstFrame(&m, ENOW_TEXT, "AA:BB:CC:DD:EE:03,X,[OPEN],1,-50,W");
    pstFeed(n2, &m, sizeof(m));
    pstCheck("encrypt_rejects_untrusted", xQueueReceive(detectionQueue, &e, 0) != pdTRUE);
    s_nodes[1].encrypted = true;
    pstFeed(n2, &m, sizeof(m));
    pstCheck("encrypt_accepts_trusted", xQueueReceive(detectionQueue, &e, 0) == pdTRUE);

    s_encrypt = false;
    enowHubForget(n3);
    pstFeed(n3, &m, sizeof(m));
    pstCheck("forgotten_node_rejected", xQueueReceive(detectionQueue, &e, 0) != pdTRUE && !allowed(n3));
    pstFeed(n1, &m, sizeof(m));
    pstCheck("paired_node_still_accepted", xQueueReceive(detectionQueue, &e, 0) == pdTRUE);

    s_active = false;
    s_allowCount = 0;
    s_encrypt = false;
    memset(s_nodes, 0, ENOW_MAX_NODES * sizeof(EnowNode));
    memset(s_seen, 0, sizeof(s_seen));
    return pstFail;
}
#endif
