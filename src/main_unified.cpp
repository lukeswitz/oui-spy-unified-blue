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
#include "mesh_espnow.h"
#include "engines/flock_ble.h"
#include "engines/detector.h"
#include "engines/foxhunter.h"
#include "engines/skyspy.h"
#include "engines/flock_wifi.h"
#include "engines/unipwn.h"
#include "engines/wardrive.h"

// ============================================================================
// Global queues and GPS state
// ============================================================================
QueueHandle_t detectionQueue = NULL;
QueueHandle_t engineCmdQueue = NULL;
volatile GpsData currentGps = {};
volatile bool gpsValid = false;

// Hardware config — loaded from NVS at boot, updated live by BLE writes
volatile bool    hwBuzzerEnabled = true;
volatile uint8_t hwBuzzerVolume = 100;       // 0-255 PWM duty cycle
volatile bool    hwLedEnabled = true;
volatile uint8_t hwNeopixelBrightness = 50;

// ============================================================================
// Hardware
// ============================================================================
static void initHardware(void) {
    pinMode(PIN_BUZZER, OUTPUT);
    digitalWrite(PIN_BUZZER, LOW);
    pinMode(PIN_LED, OUTPUT);
    digitalWrite(PIN_LED, HIGH);

    Serial.println("[HW] Pins initialized");
}

// ============================================================================
// Hardware Config — load from NVS at boot
// ============================================================================
static void loadHardwareConfig(void) {
    Preferences p;
    p.begin("ouispy-hw", true);
    hwBuzzerEnabled = p.getBool("buzzer", true);
    hwBuzzerVolume = p.getUChar("bz_vol", 100);
    hwLedEnabled = p.getBool("led", true);
    hwNeopixelBrightness = p.getUChar("neo_brt", 50);
    p.end();
    Serial.printf("[HW] Config: buzzer=%d vol=%d led=%d neo=%d\n",
                  (int)hwBuzzerEnabled, (int)hwBuzzerVolume,
                  (int)hwLedEnabled, (int)hwNeopixelBrightness);
}

// ============================================================================
// Buzzer Feedback — melodic triple-tone on target detection
// ============================================================================

/// Returns true if this engine produces alertable target detections.
/// Whitelist approach: only engines that detect specific targets should chime.
/// Wardrive is passive collection — no beep.
/// Foxhunter has its own proximity beep loop — handled separately.
static bool isAlertableEngine(uint8_t engine_id) {
    switch ((EngineId)engine_id) {
        case ENGINE_DETECTOR:
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
        case ENGINE_SKYSPY:
        case ENGINE_UNIPWN:
            return true;
        case ENGINE_WARDRIVE:
        case ENGINE_FOXHUNTER:
        case ENGINE_COUNT:
        default:
            return false;
    }
}


/// Pleasant ascending three-note chime: E6 → G#6 → B6
static void detectionChime(void) {
    if (!hwBuzzerEnabled || hwBuzzerVolume == 0) return;
    const int notes[] = {1319, 1661, 1976};  // E6, G#6, B6 — major triad
    for (int i = 0; i < 3; i++) {
        ledcSetup(0, notes[i], 8);
        ledcAttachPin(PIN_BUZZER, 0);
        ledcWrite(0, hwBuzzerVolume);
        delay(45);
        ledcWrite(0, 0);
        delay(20);
    }
    ledcDetachPin(PIN_BUZZER);
}

// ============================================================================
// Boot melody — quick ascending chirp to indicate v3 app-controlled mode
// ============================================================================
static void playBootMelody(void) {
    if (!hwBuzzerEnabled) return;

    const int notes[] = {523, 659, 784, 1047};  // C5, E5, G5, C6
    for (int i = 0; i < 4; i++) {
        ledcSetup(0, notes[i], 8);
        ledcAttachPin(PIN_BUZZER, 0);
        ledcWrite(0, hwBuzzerVolume > 0 ? hwBuzzerVolume : 80);
        delay(80);
        ledcWrite(0, 0);
        delay(30);
    }
    ledcDetachPin(PIN_BUZZER);
}

// ============================================================================
// Detection Notification Task (Core 1)
// Drains detectionQueue, deduplicates across engines, sends BLE notifications
// ============================================================================
#define NOTIFY_DEDUP_SIZE 48
#define NOTIFY_DEDUP_COOLDOWN_MS 3000
static struct {
    uint8_t mac[6];
    uint8_t engine_id;
    unsigned long ts;
} notifyDedup[NOTIFY_DEDUP_SIZE];
static int notifyDedupHead = 0;
static int notifyDedupCount = 0;

/// Engine-aware dedup: same MAC from DIFFERENT engine classes passes through.
/// Wardrive (passive collection) and flock/detector (active alerting) are
/// separate classes so a wardrive event never suppresses a flock alert.
static uint8_t engineClass(uint8_t engine_id) {
    switch ((EngineId)engine_id) {
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
            return 1;  // flock class
        case ENGINE_DETECTOR:
        case ENGINE_FOXHUNTER:
        case ENGINE_SKYSPY:
        case ENGINE_UNIPWN:
            return 2;  // target-alert class
        case ENGINE_WARDRIVE:
            return 3;  // passive-collection class
        default:
            return 0;
    }
}

static bool isNotifyDedupCooldown(const uint8_t* mac, uint8_t engine_id) {
    unsigned long now = millis();
    uint8_t cls = engineClass(engine_id);
    for (int i = 0; i < notifyDedupCount; i++) {
        if (memcmp(notifyDedup[i].mac, mac, 6) == 0 &&
            engineClass(notifyDedup[i].engine_id) == cls) {
            if (now - notifyDedup[i].ts < NOTIFY_DEDUP_COOLDOWN_MS) return true;
            notifyDedup[i].ts = now;
            return false;
        }
    }
    int idx;
    if (notifyDedupCount < NOTIFY_DEDUP_SIZE) {
        idx = notifyDedupCount++;
    } else {
        idx = notifyDedupHead;
        notifyDedupHead = (notifyDedupHead + 1) % NOTIFY_DEDUP_SIZE;
    }
    memcpy(notifyDedup[idx].mac, mac, 6);
    notifyDedup[idx].engine_id = engine_id;
    notifyDedup[idx].ts = now;
    return false;
}

static void detectionNotifyTask(void* param) {
    DetectionEvent evt;
    Serial.println("[TASK] Detection notify task started");

    for (;;) {
        if (xQueueReceive(detectionQueue, &evt, portMAX_DELAY) == pdTRUE) {
            if (evt.engine_id != ENGINE_WARDRIVE &&
                isNotifyDedupCooldown(evt.mac, evt.engine_id)) continue;

            // Audible + visual feedback only for target engines
            if (isAlertableEngine(evt.engine_id)) {
                Serial.printf("[CHIME] engine=%d\n", evt.engine_id);
                detectionChime();
                if (hwLedEnabled) {
                    digitalWrite(PIN_LED, LOW);
                }
            }

            // Broadcast to mesh peers (only local detections, not relayed ones)
            meshBroadcastDetection(&evt);

            // Send BLE notification
            bleGattNotifyDetection(&evt);

            // LED off after notification sent
            if (hwLedEnabled) {
                digitalWrite(PIN_LED, HIGH);
            }

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
            if (meshIsEnabled()) {
                bleGattNotifyMeshStatus();
            }
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

    // Load hardware config (buzzer/LED/neopixel) from NVS
    loadHardwareConfig();

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

    // Register all engines
    engineRegister(ENGINE_DETECTOR, &detectorCallbacks);
    engineRegister(ENGINE_FLOCK_BLE, &flockBleCallbacks);
    engineRegister(ENGINE_FLOCK_WIFI, &flockWifiCallbacks);
    engineRegister(ENGINE_FOXHUNTER, &foxhunterCallbacks);
    engineRegister(ENGINE_SKYSPY, &skyspyCallbacks);
    engineRegister(ENGINE_UNIPWN, &unipwnCallbacks);
    engineRegister(ENGINE_WARDRIVE, &wardriveCallbacks);

    // Force all engines disabled at boot — no stale radio state
    engineDisableAll();
    Serial.printf("[INIT] Active mask after boot disable: 0x%02X\n", engineGetActiveMask());

    // Initialize mesh subsystem
    meshInit();

    // Initialize BLE GATT server
    bleGattInit();

    // Create FreeRTOS tasks
    xTaskCreatePinnedToCore(detectionNotifyTask, "det_notify", 4096, NULL, 2, NULL, 1);
    xTaskCreatePinnedToCore(engineCmdTask, "eng_cmd", 4096, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(statusHeartbeatTask, "status_hb", 2048, NULL, 1, NULL, 1);

    Serial.println("[INIT] Tasks created");

    // Boot melody
    playBootMelody();

    // LED blink to confirm boot
    for (int i = 0; i < 3; i++) {
        digitalWrite(PIN_LED, LOW);
        delay(100);
        digitalWrite(PIN_LED, HIGH);
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
