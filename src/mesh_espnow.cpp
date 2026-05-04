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
QueueHandle_t peerStatusQueue = NULL;

static uint32_t meshDetectionCount = 0;
static uint32_t meshEnableTime = 0;

static mbedtls_gcm_context gcmCtx;
static bool gcmReady = false;
static uint64_t txCounter = 0;
static char localNodeId[MESH_NODE_ID_LEN] = {};
static SemaphoreHandle_t meshMutex = NULL;
static bool espNowInitialized = false;

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

static void handleInvitePacket(const uint8_t* data, size_t len);

static void handleDetectionPacket(const uint8_t* plainBuf, size_t plainLen) {
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
}

static void handleCommandPacket(const uint8_t* plainBuf, size_t plainLen) {
    if (plainLen < sizeof(MeshCommandPacket)) return;

    MeshCommandPacket cmd;
    memcpy(&cmd, plainBuf, sizeof(MeshCommandPacket));

    // Don't execute commands we originated
    if (memcmp(cmd.source_node_id, localNodeId, 4) == 0) return;

    // Route to engine command queue
    EngineCommand ecmd = {};
    ecmd.command = cmd.command;
    ecmd.engine_id = cmd.engine_id;
    if (cmd.payload_len > 0 && cmd.payload_len <= sizeof(ecmd.payload)) {
        memcpy(ecmd.payload, cmd.payload, cmd.payload_len);
        ecmd.payload_len = cmd.payload_len;
    }

    xQueueSend(engineCmdQueue, &ecmd, pdMS_TO_TICKS(10));
    Serial.printf("[MESH] Relay cmd: engine=%d cmd=0x%02X from=%s\n",
                  cmd.engine_id, cmd.command, cmd.source_node_id);
}

static void handleStatusPacket(const uint8_t* plainBuf, size_t plainLen) {
    if (plainLen < sizeof(MeshStatusPacket)) return;

    MeshStatusPacket status;
    memcpy(&status, plainBuf, sizeof(MeshStatusPacket));

    // Don't process our own status
    if (memcmp(status.source_node_id, localNodeId, 4) == 0) return;

    // Forward to BLE notification queue for companion app
    if (peerStatusQueue != NULL) {
        xQueueSend(peerStatusQueue, &status, pdMS_TO_TICKS(5));
    }
}

static void onEspNowRecv(const uint8_t* macAddr, const uint8_t* data, int len) {
    if (len < 1) return;

    // Check for unencrypted invite packets FIRST (before mesh is enabled)
    // Invite packets are always plaintext with MESH_PKT_INVITE as first byte
    if (data[0] == MESH_PKT_INVITE && !meshCurrentConfig.enabled) {
        handleInvitePacket(data, (size_t)len);
        return;
    }

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

    if (plainLen < 1) return;

    // Dispatch by packet type (first byte)
    uint8_t pktType = plainBuf[0];

    if (pktType == MESH_PKT_COMMAND) {
        handleCommandPacket(plainBuf, plainLen);
    } else if (pktType == MESH_PKT_STATUS) {
        handleStatusPacket(plainBuf, plainLen);
    } else if (pktType == MESH_PKT_INVITE) {
        // Already in mesh, ignore duplicate invites
    } else {
        if (pktType == MESH_PKT_DETECTION) {
            handleDetectionPacket(plainBuf + 1, plainLen - 1);
        } else {
            handleDetectionPacket(plainBuf, plainLen);
        }
    }

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

static uint8_t localStaMac[6] = {};
static bool autoJoinListening = false;
static volatile bool pendingInvite = false;
static MeshInvitePacket pendingInviteData = {};

static void handleInvitePacket(const uint8_t* data, size_t len) {
    if (len < sizeof(MeshInvitePacket)) return;
    if (pendingInvite) return;
    if (meshCurrentConfig.enabled) return;

    MeshInvitePacket invite;
    memcpy(&invite, data, sizeof(MeshInvitePacket));
    if (memcmp(invite.source_node_id, localNodeId, 4) == 0) return;

    memcpy(&pendingInviteData, &invite, sizeof(MeshInvitePacket));
    pendingInvite = true;
}

void meshProcessPendingInvite(void) {
    if (!pendingInvite) return;
    pendingInvite = false;

    MeshInvitePacket invite;
    memcpy(&invite, &pendingInviteData, sizeof(MeshInvitePacket));

    MeshConfig cfg = {};
    cfg.enabled = 1;
    cfg.encryption_enabled = invite.encryption_enabled;
    if (invite.encryption_enabled) {
        memcpy(cfg.key, invite.key, MESH_KEY_LEN);
    }
    cfg.peer_count = 1;
    memcpy(cfg.peers[0], invite.primary_mac, 6);

    autoJoinListening = false;
    meshEnable(&cfg);
    Serial.printf("[MESH] Auto-joined mesh from %s\n", invite.source_node_id);
}

void meshInit(void) {
    meshMutex = xSemaphoreCreateMutex();
    mbedtls_gcm_init(&gcmCtx);
    memset((void*)&meshCurrentConfig, 0, sizeof(MeshConfig));
    memset((void*)&meshCurrentStatus, 0, sizeof(MeshStatus));

    peerStatusQueue = xQueueCreate(MESH_PEER_STATUS_QUEUE_DEPTH, sizeof(MeshStatusPacket));

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_BT);
    snprintf(localNodeId, MESH_NODE_ID_LEN, "%02X%02X", mac[4], mac[5]);

    // Store STA MAC for invite packets
    esp_read_mac(localStaMac, ESP_MAC_WIFI_STA);

    // Start passive ESP-NOW listener for mesh invites
    // This allows peers to auto-join without phone configuration
    WiFi.mode(WIFI_AP_STA);
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    if (esp_now_init() == ESP_OK) {
        esp_now_register_recv_cb(onEspNowRecv);
        espNowInitialized = true;
        autoJoinListening = true;
        Serial.println("[MESH] Passive listener started (awaiting invite)");
    }

    Serial.printf("[MESH] Initialized, localNodeId=%s\n", localNodeId);
}

void meshEnable(const MeshConfig* cfg) {
    meshDisable();

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

    WiFi.mode(WIFI_AP_STA);
    esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);

    if (esp_now_init() != ESP_OK) {
        Serial.println("[MESH] ESP-NOW init failed");
        return;
    }
    espNowInitialized = true;

    esp_now_register_recv_cb(onEspNowRecv);
    esp_now_register_send_cb(onEspNowSend);

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

    meshEnableTime = millis() / 1000;
    meshDetectionCount = 0;

    Serial.printf("[MESH] Enabled with %d peers\n", cfg->peer_count);
}

void meshDisable(void) {
    if (espNowInitialized) {
        esp_now_unregister_recv_cb();
        esp_now_unregister_send_cb();
        esp_now_deinit();
        espNowInitialized = false;
    }

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

    esp_err_t result = esp_now_send(NULL, encrypted, encLen);

    if (result == ESP_OK) {
        meshDetectionCount++;
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s;
            memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
            s.tx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
            xSemaphoreGive(meshMutex);
        }
    }
}

void meshBroadcastCommand(const MeshCommandPacket* cmd) {
    if (!meshCurrentConfig.enabled) return;

    // Fill source node ID if not already set
    MeshCommandPacket pkt;
    memcpy(&pkt, cmd, sizeof(MeshCommandPacket));
    pkt.pkt_type = MESH_PKT_COMMAND;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);

    uint8_t encrypted[256];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, sizeof(MeshCommandPacket),
                       encrypted, &encLen)) {
        return;
    }

    esp_err_t result = esp_now_send(NULL, encrypted, encLen);
    if (result == ESP_OK) {
        if (xSemaphoreTake(meshMutex, pdMS_TO_TICKS(10)) == pdTRUE) {
            MeshStatus s;
            memcpy(&s, (void*)&meshCurrentStatus, sizeof(MeshStatus));
            s.tx_count++;
            memcpy((void*)&meshCurrentStatus, &s, sizeof(MeshStatus));
            xSemaphoreGive(meshMutex);
        }
        Serial.printf("[MESH] Broadcast cmd: engine=%d cmd=0x%02X\n",
                      pkt.engine_id, pkt.command);
    }
}

void meshBroadcastStatus(void) {
    if (!meshCurrentConfig.enabled) return;

    MeshStatusPacket pkt = {};
    pkt.pkt_type = MESH_PKT_STATUS;
    memcpy(pkt.source_node_id, localNodeId, MESH_NODE_ID_LEN);

    // Build active engine mask from engine registry
    pkt.active_engine_mask = engineGetActiveMask();
    for (uint8_t i = 0; i < ENGINE_COUNT; i++) {
        pkt.engine_states[i] = engineGetState((EngineId)i);
    }

    pkt.detection_count = meshDetectionCount;
    pkt.uptime_sec = (millis() / 1000) - meshEnableTime;
    pkt.free_heap_kb = (int8_t)(ESP.getFreeHeap() / 1024);

    uint8_t encrypted[256];
    size_t encLen = 0;
    if (!encryptPacket((const uint8_t*)&pkt, sizeof(MeshStatusPacket),
                       encrypted, &encLen)) {
        return;
    }

    esp_now_send(NULL, encrypted, encLen);
}

void meshBroadcastInvite(void) {
    if (!meshCurrentConfig.enabled || !espNowInitialized) return;

    MeshInvitePacket invite = {};
    invite.pkt_type = MESH_PKT_INVITE;
    memcpy(invite.source_node_id, localNodeId, MESH_NODE_ID_LEN);
    memcpy(invite.primary_mac, localStaMac, 6);
    invite.encryption_enabled = meshCurrentConfig.encryption_enabled;
    if (meshCurrentConfig.encryption_enabled) {
        memcpy(invite.key, (const void*)meshCurrentConfig.key, MESH_KEY_LEN);
    }
    invite.channel = 1;

    // Invite is sent UNENCRYPTED so passive listeners can receive it
    // Must add broadcast peer temporarily if not already added
    static bool broadcastPeerAdded = false;
    if (!broadcastPeerAdded) {
        esp_now_peer_info_t bcast = {};
        memset(bcast.peer_addr, 0xFF, 6);
        bcast.channel = 0;
        bcast.encrypt = false;
        esp_now_add_peer(&bcast);
        broadcastPeerAdded = true;
    }

    uint8_t bcastAddr[6];
    memset(bcastAddr, 0xFF, 6);
    esp_now_send(bcastAddr, (const uint8_t*)&invite, sizeof(MeshInvitePacket));
    Serial.println("[MESH] Broadcast invite sent");
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

const char* meshGetLocalNodeId(void) {
    return localNodeId;
}
