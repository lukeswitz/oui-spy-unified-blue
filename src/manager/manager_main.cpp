#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>
#include "../protocol.h"
#include "../ble_gatt.h"
#include "../mesh_espnow.h"
#include "../wifi_ota_handler.h"
#include "../ignore_list.h"
#include "../engines/detector.h"
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <freertos/task.h>

#ifndef MESH_CH
#define MESH_CH 1
#endif

QueueHandle_t detectionQueue = NULL;
QueueHandle_t engineCmdQueue = NULL;
QueueHandle_t peerStatusQueue = NULL;

volatile GpsData currentGps = {};
volatile bool    gpsValid = false;
volatile bool    hwBuzzerEnabled = false;
volatile uint8_t hwBuzzerVolume = 0;
volatile bool    hwLedEnabled = false;
volatile uint8_t hwNeopixelBrightness = 0;

static void detectionNotifyTask(void*) {
    DetectionEvent evt;
    for (;;) {
        if (xQueueReceive(detectionQueue, &evt, portMAX_DELAY) == pdTRUE) {
            bleGattNotifyDetection(&evt);
#ifdef OUISPY_PCAP_SELFTEST
            Serial.printf("[RELAY] det eng=%u src=%.4s mac=%02x:%02x:%02x:%02x:%02x:%02x -> app(ble=%d)\n",
                evt.engine_id, evt.source_node_id,
                evt.mac[0],evt.mac[1],evt.mac[2],evt.mac[3],evt.mac[4],evt.mac[5],
                bleGattIsConnected() ? 1 : 0);
#endif
        }
    }
}

static void heartbeatTask(void*) {
    uint32_t tick = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        tick++;
        bleGattMaybeResliceWardrive();
        bleGattReconcileEngines();
        if ((tick % 7) == 0 && meshIsEnabled()) {
            uint8_t ib[256];
            size_t in = ignoreListSerialize(ib, sizeof(ib));
            meshBroadcastIgnoreList(ib, in);
        }
        if ((tick % 7) == 3 && meshIsEnabled()) {
            bleGattRebroadcastConfigs();
        }
        if ((tick % 7) == 5 && meshIsEnabled()) {
            uint8_t db[256];
            size_t dn = detectorSerialize(db, sizeof(db));
            meshBroadcastDetectorList(db, dn);
        }
        if (bleGattIsConnected()) {
            bleGattNotifyPcapStats();
            bleGattNotifyMeshStatus();
        }
        if ((tick % 5) == 0) {
            MeshStatus s = meshGetStatus();
            Serial.printf("[MGR] mesh enabled=%u rx=%lu tx=%lu err=%lu | heap=%u | ble=%d\n",
                s.enabled, (unsigned long)s.rx_count, (unsigned long)s.tx_count,
                (unsigned long)s.rx_errors,
                (unsigned)ESP.getFreeHeap(),
                bleGattIsConnected() ? 1 : 0);
        }
    }
}

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println();
    Serial.println("========================================");
    Serial.println("  OUI-SPY MANAGER (WROOM) — BLE+mesh");
    Serial.println("========================================");

    WiFi.persistent(false);
    WiFi.setAutoReconnect(false);
    WiFi.mode(WIFI_AP_STA);
    WiFi.disconnect(false, false);
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    esp_wifi_set_channel(MESH_CH, WIFI_SECOND_CHAN_NONE);

    if (wifiOtaHasPending()) {
        Serial.println("[BOOT] WiFi OTA pending -> OTA-only mode (BLE/mesh off, full heap)");
        wifiOtaRunPendingBlocking();
        Serial.println("[BOOT] WiFi OTA did not complete -> continuing normal boot");
    }

    detectionQueue  = xQueueCreate(64, sizeof(DetectionEvent));
    engineCmdQueue  = xQueueCreate(8,  sizeof(EngineCommand));
    peerStatusQueue = xQueueCreate(MESH_PEER_STATUS_QUEUE_DEPTH, sizeof(MeshStatusPacket));
    if (!detectionQueue || !engineCmdQueue || !peerStatusQueue) {
        Serial.println("[FATAL] queue create FAIL");
        while (1) delay(1000);
    }

    meshInit();
    bleGattInit();
    ignoreListInit();

    {
        MeshConfig cfg = {};
        cfg.enabled = 1;
        cfg.encryption_enabled = 0;
        cfg.peer_count = 0;
        meshEnable(&cfg);
    }

    xTaskCreatePinnedToCore(detectionNotifyTask, "det_notify", 4096, NULL, 2, NULL, 1);
    xTaskCreatePinnedToCore(heartbeatTask,       "hb",         6144, NULL, 1, NULL, 1);

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    Serial.printf("[INIT] MAC %02X:%02X:%02X:%02X:%02X:%02X ch=%d heap=%u\n",
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], MESH_CH, (unsigned)ESP.getFreeHeap());
    Serial.println("[INIT] *** MANAGER READY ***");
}

void loop() {
    delay(50);
#ifdef OUISPY_PCAP_SELFTEST
    static bool stEnabled = false;
    static bool stDisabled = false;
    static char tgt[MESH_NODE_ID_LEN] = {0};
    if (!stEnabled && millis() > 8000) {
        MeshLiveNode ln[8];
        size_t n = meshGetLiveNodes(ln, 8, 30000);
        if (n > 0) {
            stEnabled = true;
            memcpy(tgt, ln[0].id, MESH_NODE_ID_LEN);
            uint8_t cfg[4] = { 0x01, 0x00, 0x01, 0x0B };
            meshBroadcastCommand(0x10, ENGINE_PCAP, cfg, sizeof(cfg));
            delay(120);
            meshBroadcastCommand(0x01, ENGINE_PCAP, (const uint8_t*)tgt, MESH_NODE_ID_LEN);
            Serial.printf("[SELFTEST] ENABLE pcap target=%.4s — watch its [PCAP-RATE]\n", tgt);
        }
    }
    if (stEnabled && !stDisabled && millis() > 40000) {
        stDisabled = true;
        meshBroadcastCommand(0x00, ENGINE_PCAP, nullptr, 0);
        Serial.println("[SELFTEST] DISABLE pcap");
    }
#endif
#ifdef OUISPY_WD_MGR_SELFTEST
    static bool wdOn = false;
    static uint32_t wdLast = 0;
    if (!wdOn && millis() > 8000) {
        MeshLiveNode ln[8];
        size_t n = meshGetLiveNodes(ln, 8, 30000);
        if (n > 0) {
            wdOn = true;
            uint8_t cfg[11] = {0}; cfg[9] = 1; cfg[10] = 11;
            meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, sizeof(cfg));
            delay(120);
            meshBroadcastCommand(0x01, ENGINE_WARDRIVE, nullptr, 0);
            Serial.printf("[WDMGR] wardrive ENABLE -> %u node(s)\n", (unsigned)n);
        }
    }
    if (wdOn && millis() - wdLast > 5000) {
        wdLast = millis();
        uint8_t cfg[11] = {0}; cfg[9] = 1; cfg[10] = 11;
        meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, sizeof(cfg));
        MeshLiveNode ln[8];
        size_t n = meshGetLiveNodes(ln, 8, 30000);
        Serial.printf("[WDMGR] role keepalive (CONFIG only), live=%u heap=%u\n",
                      (unsigned)n, (unsigned)ESP.getFreeHeap());
    }
#endif
#ifdef OUISPY_STOP_SELFTEST
    static bool stOn = false;
    static bool stStopped = false;
    static uint32_t stT0 = 0;
    static uint32_t stReassert = 0;
    if (!stOn && millis() > 8000) {
        MeshLiveNode ln[8];
        size_t n = meshGetLiveNodes(ln, 8, 30000);
        if (n > 0) {
            stOn = true; stT0 = millis();
            mgrDebugSetCommanded((1u << ENGINE_WARDRIVE) | (1u << ENGINE_FLOCK_BLE));
            uint8_t cfg[11] = {0}; cfg[9] = 1; cfg[10] = 11;
            meshBroadcastCommand(0x10, ENGINE_WARDRIVE, cfg, sizeof(cfg));
            delay(120);
            meshBroadcastCommand(0x01, ENGINE_WARDRIVE, nullptr, 0);
            meshBroadcastCommand(0x01, ENGINE_FLOCK_BLE, nullptr, 0);
            Serial.printf("[STOPTEST] ENABLE wardrive+flock_ble (commanded) -> %u nodes; STOP at +22s\n", (unsigned)n);
        }
    }
    if (stOn && !stStopped && (millis() - stT0) > 22000) {
        stStopped = true;
        Serial.println("[STOPTEST] ===== STOP PRESSED ===== clear commanded + DISABLE_ALL + demote");
        mgrDebugSetCommanded(0);
        meshBroadcastCommand(0x0F, 0, nullptr, 0);
        g_meshManagerActive = false;
    }
#endif
}
