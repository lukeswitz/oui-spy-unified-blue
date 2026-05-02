/**
 * OUI-SPY Unified Firmware v3.0 — App-Controlled Architecture
 *
 * No boot selector. No WiFi APs. No web dashboards.
 * BLE GATT is the sole control interface.
 * All engines compiled in, activated by phone app at runtime.
 *
 * Core 0: WiFi engine task (Flock-WiFi or Sky Spy promiscuous)
 * Core 1: BLE GATT server + BLE engine tasks + detection notification
 */
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>

#include "protocol.h"
#include "engine_registry.h"
#include "ble_gatt.h"
#include "engines/flock_ble.h"

// ============================================================================
// Global queues and GPS state
// ============================================================================
QueueHandle_t detectionQueue = NULL;
QueueHandle_t engineCmdQueue = NULL;
volatile GpsData currentGps = {};
volatile bool gpsValid = false;

// ============================================================================
// Hardware
// ============================================================================
static void initHardware(void) {
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);
    pinMode(PIN_LED, OUTPUT);
    digitalWrite(PIN_LED, HIGH);  // LED off (active LOW on XIAO)

    Serial.println("[HW] Pins initialized");
}

// ============================================================================
// Boot melody — quick ascending chirp to indicate v3 app-controlled mode
// ============================================================================
static void playBootMelody(void) {
    Preferences bzP;
    bzP.begin("ouispy-hw", true);
    bool buzzerOn = bzP.getBool("buzzer", true);
    bzP.end();
    if (!buzzerOn) return;

    const int notes[] = {523, 659, 784, 1047};  // C5, E5, G5, C6
    for (int i = 0; i < 4; i++) {
        ledcSetup(0, notes[i], 8);
        ledcAttachPin(PIN_BUZZER, 0);
        ledcWrite(0, 80);
        delay(80);
        ledcWrite(0, 0);
        delay(30);
    }
    ledcDetachPin(PIN_BUZZER);
}

// ============================================================================
// Detection Notification Task (Core 1)
// Drains detectionQueue, sends BLE notifications to phone
// ============================================================================
static void detectionNotifyTask(void* param) {
    DetectionEvent evt;
    Serial.println("[TASK] Detection notify task started");

    for (;;) {
        if (xQueueReceive(detectionQueue, &evt, portMAX_DELAY) == pdTRUE) {
            // Send BLE notification
            bleGattNotifyDetection(&evt);

            // Also print to serial (for debugging / Flask compatibility)
            char macStr[18];
            snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x",
                     evt.mac[0], evt.mac[1], evt.mac[2],
                     evt.mac[3], evt.mac[4], evt.mac[5]);
            Serial.printf("{\"engine\":%d,\"mac\":\"%s\",\"rssi\":%d,\"ch\":%d,\"method\":%d}\n",
                          evt.engine_id, macStr, evt.rssi, evt.channel, evt.method);
        }
    }
}

// ============================================================================
// Engine Command Task (Core 1)
// Processes enable/disable commands from BLE
// ============================================================================
static void engineCmdTask(void* param) {
    EngineCommand cmd;
    Serial.println("[TASK] Engine command task started");

    for (;;) {
        if (xQueueReceive(engineCmdQueue, &cmd, portMAX_DELAY) == pdTRUE) {
            engineProcessCommand(&cmd);
            // Notify phone of state change
            bleGattNotifyEngineState();
        }
    }
}

// ============================================================================
// Status Heartbeat Task (Core 1)
// Periodic device status updates to phone
// ============================================================================
static void statusHeartbeatTask(void* param) {
    Serial.println("[TASK] Status heartbeat task started");

    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(5000));  // Every 5 seconds

        if (bleGattIsConnected()) {
            bleGattNotifyEngineState();
        }

        // Serial heartbeat
        Serial.printf("[STATUS] engines=0x%02X heap=%d gps=%s\n",
                      engineGetActiveMask(),
                      esp_get_free_heap_size(),
                      gpsValid ? "valid" : "none");
    }
}

// ============================================================================
// Arduino Setup
// ============================================================================
void setup() {
    Serial.begin(115200);
    delay(200);

    Serial.println("\n========================================");
    Serial.println("  OUI-SPY v3.0 — App-Controlled Mode");
    Serial.println("  No boot selector. BLE GATT only.");
    Serial.println("========================================\n");

    // Initialize hardware
    initHardware();

    // Create FreeRTOS queues
    detectionQueue = xQueueCreate(64, sizeof(DetectionEvent));
    engineCmdQueue = xQueueCreate(8, sizeof(EngineCommand));

    if (detectionQueue == NULL || engineCmdQueue == NULL) {
        Serial.println("[FATAL] Queue creation failed!");
        while (1) delay(1000);
    }
    Serial.println("[INIT] Queues created (det=64, cmd=8)");

    // Initialize engine registry
    engineRegistryInit();

    // Register engines
    engineRegister(ENGINE_FLOCK_BLE, &flockBleCallbacks);

    // Initialize BLE GATT server
    bleGattInit();

    // Auto-enable Flock-BLE on boot (no app needed to test)
    engineEnable(ENGINE_FLOCK_BLE);

    // Create FreeRTOS tasks
    xTaskCreatePinnedToCore(detectionNotifyTask, "det_notify", 4096, NULL, 2, NULL, 1);
    xTaskCreatePinnedToCore(engineCmdTask, "eng_cmd", 4096, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(statusHeartbeatTask, "status_hb", 2048, NULL, 1, NULL, 1);

    Serial.println("[INIT] Tasks created");

    // Boot melody
    playBootMelody();

    // LED blink to confirm boot
    for (int i = 0; i < 3; i++) {
        digitalWrite(PIN_LED, LOW);   // ON
        delay(100);
        digitalWrite(PIN_LED, HIGH);  // OFF
        delay(100);
    }

    Serial.println("\n[INIT] *** OUI-SPY READY ***");
    Serial.println("[INIT] Waiting for phone connection via BLE...");
    Serial.printf("[INIT] Free heap: %d bytes\n", esp_get_free_heap_size());
}

// ============================================================================
// Arduino Loop
// ============================================================================
void loop() {
    // Run all active engine loops
    engineLoopAll();

    // Small yield to prevent watchdog
    delay(1);
}
