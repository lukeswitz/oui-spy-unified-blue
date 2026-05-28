#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>
#include "../protocol.h"
#include "../ble_gatt.h"
#include "../mesh_espnow.h"
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
        }
    }
}

static void heartbeatTask(void*) {
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        MeshStatus s = meshGetStatus();
        Serial.printf("[MGR] mesh enabled=%u rx=%lu tx=%lu err=%lu | heap=%u | ble=%d\n",
            s.enabled, (unsigned long)s.rx_count, (unsigned long)s.tx_count,
            (unsigned long)s.rx_errors,
            (unsigned)ESP.getFreeHeap(),
            bleGattIsConnected() ? 1 : 0);
        bleGattNotifyMeshStatus();
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

    detectionQueue  = xQueueCreate(64, sizeof(DetectionEvent));
    engineCmdQueue  = xQueueCreate(8,  sizeof(EngineCommand));
    peerStatusQueue = xQueueCreate(MESH_PEER_STATUS_QUEUE_DEPTH, sizeof(MeshStatusPacket));
    if (!detectionQueue || !engineCmdQueue || !peerStatusQueue) {
        Serial.println("[FATAL] queue create FAIL");
        while (1) delay(1000);
    }

    meshInit();
    bleGattInit();

    {
        MeshConfig cfg = {};
        cfg.enabled = 1;
        cfg.encryption_enabled = 0;
        cfg.peer_count = 0;
        meshEnable(&cfg);
    }

    xTaskCreatePinnedToCore(detectionNotifyTask, "det_notify", 4096, NULL, 2, NULL, 1);
    xTaskCreatePinnedToCore(heartbeatTask,       "hb",         2048, NULL, 1, NULL, 1);

    uint8_t mac[6];
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    Serial.printf("[INIT] MAC %02X:%02X:%02X:%02X:%02X:%02X ch=%d heap=%u\n",
        mac[0],mac[1],mac[2],mac[3],mac[4],mac[5], MESH_CH, (unsigned)ESP.getFreeHeap());
    Serial.println("[INIT] *** MANAGER READY ***");
}

void loop() {
    delay(50);
}
