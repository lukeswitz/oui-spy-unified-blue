#include "mesh_espnow.h"
#include "engine_registry.h"
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

    if (plainLen == sizeof(MeshCommandPacket) && plainBuf[0] == MESH_PKT_COMMAND) {
        MeshCommandPacket cmd;
        memcpy(&cmd, plainBuf, sizeof(MeshCommandPacket));
        Serial.printf("[MESH-CMD] cmd=0x%02x engine=%u plen=%u from=%.5s\n",
            cmd.command, cmd.engine_id, cmd.payload_len, cmd.source_node_id);
        EngineCommand ec = {};
        ec.command = cmd.command;
        ec.engine_id = cmd.engine_id;
        ec.payload_len = cmd.payload_len > sizeof(ec.payload) ? sizeof(ec.payload) : cmd.payload_len;
        if (ec.payload_len > 0) memcpy(ec.payload, cmd.payload, ec.payload_len);
        engineProcessCommand(&ec);
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

void meshInit(void) {
    meshMutex = xSemaphoreCreateMutex();
    mbedtls_gcm_init(&gcmCtx);
    memset((void*)&meshCurrentConfig, 0, sizeof(MeshConfig));
    memset((void*)&meshCurrentStatus, 0, sizeof(MeshStatus));

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(localNodeId, MESH_NODE_ID_LEN, "%02X%02X", mac[4], mac[5]);

    Serial.printf("[MESH] Initialized, localNodeId=%s\n", localNodeId);
}

static bool g_meshEverInit = false;
void meshEnable(const MeshConfig* cfg) {
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

    uint8_t saved_ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&saved_ch, &sec);
    bool changed = (saved_ch != 1);
    if (changed) esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    static const uint8_t kBroadcastDst[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    esp_err_t result = esp_now_send(kBroadcastDst, encrypted, encLen);
    if (changed) esp_wifi_set_channel(saved_ch, WIFI_SECOND_CHAN_NONE);

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

void meshBroadcastCommand(uint8_t command, uint8_t engine_id, const uint8_t* payload, uint8_t payload_len) {
    if (!meshCurrentConfig.enabled) return;

    MeshCommandPacket pkt = {};
    pkt.pkt_type = MESH_PKT_COMMAND;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    pkt.command = command;
    pkt.engine_id = engine_id;
    if (payload && payload_len > 0 && payload_len <= sizeof(pkt.payload)) {
        memcpy(pkt.payload, payload, payload_len);
        pkt.payload_len = payload_len;
    }

    uint8_t encrypted[256];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, sizeof(MeshCommandPacket), encrypted, &encLen)) return;

    uint8_t saved_ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&saved_ch, &sec);
    static const uint8_t kBroadcastDst[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};
    int okCount = 0;
    for (uint8_t ch = 1; ch <= 11; ch++) {
        esp_wifi_set_channel(ch, WIFI_SECOND_CHAN_NONE);
        esp_err_t r = esp_now_send(kBroadcastDst, encrypted, encLen);
        if (r == ESP_OK) okCount++;
        vTaskDelay(pdMS_TO_TICKS(5));
    }
    esp_wifi_set_channel(saved_ch != 0 ? saved_ch : 1, WIFI_SECOND_CHAN_NONE);

    Serial.printf("[MESH-CMD-TX] cmd=0x%02x engine=%u sent_ok=%d/11\n", command, engine_id, okCount);

    if (okCount > 0 && xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
        MeshStatus s; memcpy(&s, (void*)&meshCurrentStatus, sizeof(s));
        s.tx_count++;
        memcpy((void*)&meshCurrentStatus, &s, sizeof(s));
        xSemaphoreGive(meshMutex);
    }
}

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
