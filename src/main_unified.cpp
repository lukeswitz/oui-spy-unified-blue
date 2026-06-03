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
#include <WiFi.h>
#include <esp_wifi.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>

#include "protocol.h"
#include "engine_registry.h"
#include "ignore_list.h"
#include "ble_gatt.h"
#include "mesh_espnow.h"
#include "wifi_ota_handler.h"
#include "engines/flock_ble.h"
#include "engines/detector.h"
#include "engines/foxhunter.h"
#include "engines/skyspy.h"
#include "engines/flock_wifi.h"
#include "engines/unipwn.h"
#include "engines/wardrive.h"
#include "engines/pcap.h"

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
volatile bool    hwAlertsSuppressed = false;

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

static QueueHandle_t chimeQueue = NULL;

static void chimeTaskFn(void* param) {
    uint8_t req;
    for (;;) {
        if (xQueueReceive(chimeQueue, &req, portMAX_DELAY) == pdTRUE) {
            detectionChime();
        }
    }
}

// Coalesce beeps: one chime per hit, not per detection event. A single device
// often fires multiple alertable detections in a burst (e.g. a Flock cam seen
// on BLE and WiFi = two different MACs the per-MAC dedup can't merge). Gate the
// chime on a short global cooldown so the swarm beeps once.
#define CHIME_DEDUP_MS 1500
static volatile uint32_t lastChimeMs = 0;
static void requestChime(void) {
    if (!chimeQueue) return;
    if (hwAlertsSuppressed) return;
    uint32_t now = millis();
    if (lastChimeMs != 0 && (uint32_t)(now - lastChimeMs) < CHIME_DEDUP_MS) return;
    lastChimeMs = now;
    uint8_t one = 1;
    xQueueSend(chimeQueue, &one, 0);
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
#define NOTIFY_DEDUP_COOLDOWN_MS_DEFAULT 5000
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
    unsigned long cooldown = (unsigned long)engineGetNotifyCooldownMs();
    if (cooldown == 0) cooldown = NOTIFY_DEDUP_COOLDOWN_MS_DEFAULT;
    for (int i = 0; i < notifyDedupCount; i++) {
        if (memcmp(notifyDedup[i].mac, mac, 6) == 0 &&
            engineClass(notifyDedup[i].engine_id) == cls) {
            if (now - notifyDedup[i].ts < cooldown) return true;
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
            bool evtIsBle = (evt.engine_id == ENGINE_FLOCK_BLE ||
                             evt.engine_id == ENGINE_UNIPWN ||
                             evt.channel == 0);
            const char* evtSsid =
                (evt.engine_id == ENGINE_WARDRIVE && !evtIsBle)
                    ? evt.ext.wardrive.ssid : "";
            const char* evtName =
                (evt.engine_id == ENGINE_WARDRIVE)
                    ? (evtIsBle ? evt.ext.wardrive.device_name : evt.ext.wardrive.ssid)
                    : "";
            if (strncmp(evtName, "OUI-SPY", 7) == 0 || meshIsFleetMac(evt.mac)) {
                continue;
            }
            if (ignoreListMatch(evt.mac, evtSsid, evtIsBle)) {
                Serial.printf("[IGNORE-SKIP] eng=%d ble=%d mac=%02X:%02X:%02X:%02X:%02X:%02X ssid='%s'\n",
                              evt.engine_id, evtIsBle ? 1 : 0,
                              evt.mac[0], evt.mac[1], evt.mac[2], evt.mac[3], evt.mac[4], evt.mac[5],
                              evtSsid);
                continue;
            }

            if (evt.engine_id != ENGINE_WARDRIVE &&
                isNotifyDedupCooldown(evt.mac, evt.engine_id)) continue;

            // Audible + visual feedback only for target engines
            if (isAlertableEngine(evt.engine_id)) {
                Serial.printf("[CHIME] engine=%d\n", evt.engine_id);
                requestChime();
                if (hwLedEnabled) {
                    digitalWrite(PIN_LED, LOW);
                }
            }

            // Broadcast to mesh peers (only local detections, not relayed ones)
            if (evt.engine_id == ENGINE_WARDRIVE)
                meshEnqueueWardriveRecord(&evt);
            else
                meshBroadcastDetection(&evt);

            // Send BLE notification
            bleGattNotifyDetection(&evt);

            engineRequestAutoPcap((EngineId)evt.engine_id, evt.channel, evt.mac);

            // LED off after notification sent
            if (hwLedEnabled) {
                digitalWrite(PIN_LED, HIGH);
            }

            // Also print to serial (for debugging / Flask compatibility)
            char macStr[18];
            snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x",
                     evt.mac[0], evt.mac[1], evt.mac[2],
                     evt.mac[3], evt.mac[4], evt.mac[5]);
            if (evt.engine_id == ENGINE_FLOCK_WIFI) {
                Serial.printf("{\"engine\":%d,\"mac\":\"%s\",\"rssi\":%d,\"ch\":%d,\"method\":%d,\"auth\":%d}\n",
                              evt.engine_id, macStr, evt.rssi, evt.channel, evt.method,
                              evt.ext.flock.auth_mode);
            } else {
                Serial.printf("{\"engine\":%d,\"mac\":\"%s\",\"rssi\":%d,\"ch\":%d,\"method\":%d}\n",
                              evt.engine_id, macStr, evt.rssi, evt.channel, evt.method);
            }
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
            bleGattNotifyMeshStatus();
            bleGattNotifyPcapStats();
        }

        // Serial heartbeat
        Serial.printf("[STATUS] engines=0x%02X heap=%d gps=%s id=%s cmdRx=%lu rxWin=%lu slice=%d\n",
                      engineGetActiveMask(),
                      esp_get_free_heap_size(),
                      gpsValid ? "valid" : "none",
                      meshGetLocalNodeId(),
                      (unsigned long)g_meshCmdRx,
                      (unsigned long)g_meshRxWin,
                      meshTimeSlicingActive() ? 1 : 0);

        static bool wasManaged = false;
        if (meshIsEnabled()) {
            if (meshManagerJoined()) {
                wasManaged = true;
            } else if (wasManaged && engineGetActiveMask() != 0) {
                Serial.println("[WATCHDOG] manager lost — self-idle all engines");
                engineDisableAll();
                wasManaged = false;
            } else if (wasManaged) {
                wasManaged = false;
            }
        }
    }
}

// ============================================================================
// Arduino Setup
// ============================================================================
#ifdef OUISPY_ENGINE_SELFTEST
static const char* selftestEngineName(EngineId id) {
    switch (id) {
        case ENGINE_DETECTOR:   return "DETECTOR";
        case ENGINE_FLOCK_BLE:  return "FLOCK_BLE";
        case ENGINE_FLOCK_WIFI: return "FLOCK_WIFI";
        case ENGINE_FOXHUNTER:  return "FOXHUNTER";
        case ENGINE_SKYSPY:     return "SKYSPY";
        case ENGINE_UNIPWN:     return "UNIPWN";
        case ENGINE_WARDRIVE:   return "WARDRIVE";
        case ENGINE_PCAP:       return "PCAP";
        default:                return "?";
    }
}

static void engineSelftestTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(4000));
#ifdef OUISPY_SELFTEST_MESH_ON
    {
        MeshConfig cfg = {};
        cfg.enabled = 1; cfg.encryption_enabled = 0; cfg.peer_count = 0;
        meshEnable(&cfg);
        Serial.println("[SELFTEST] mesh ENABLED for coexistence test");
        vTaskDelay(pdMS_TO_TICKS(2000));
    }
    Serial.println("[SELFTEST] ===== ENGINE SELF-TEST START (mesh ON, coexist) =====");
#else
    Serial.println("[SELFTEST] ===== ENGINE SELF-TEST START (mesh OFF, local) =====");
#endif
    const EngineId order[] = {
        ENGINE_DETECTOR, ENGINE_FLOCK_BLE, ENGINE_FLOCK_WIFI, ENGINE_FOXHUNTER,
        ENGINE_SKYSPY, ENGINE_UNIPWN, ENGINE_WARDRIVE, ENGINE_PCAP
    };
    for (size_t k = 0; k < sizeof(order) / sizeof(order[0]); k++) {
        EngineId id = order[k];
        const char* nm = selftestEngineName(id);
        bool passive = (id == ENGINE_FLOCK_BLE || id == ENGINE_FLOCK_WIFI);
        if (passive) engineEnable(ENGINE_WARDRIVE);

        Serial.printf("[SELFTEST] --- %s (id=%d): enabling%s ---\n",
                      nm, id, passive ? " (+WARDRIVE scan host)" : "");
        bool en = engineEnable(id);
        vTaskDelay(pdMS_TO_TICKS(400));
        bool started = (engineGetActiveMask() & ENGINE_BITMASK(id)) != 0;

        uint32_t seen0 = g_engRawSeen;
        uint32_t t0 = millis();
        while (millis() - t0 < 8000) {
            vTaskDelay(pdMS_TO_TICKS(200));
        }
        uint32_t activity = g_engRawSeen - seen0;
        if (id == ENGINE_PCAP) {
            PcapStats ps1; pcapGetStats(&ps1);
            uint32_t frames = ps1.beacon_count + ps1.probe_req_count + ps1.probe_resp_count
                            + ps1.data_count + ps1.ctrl_count + ps1.mgmt_other_count
                            + ps1.deauth_count + ps1.disassoc_count
                            + ps1.ble_adv_count + ps1.ble_scan_count;
            activity = frames;
            Serial.printf("[SELFTEST] %s frames=%lu bytes_written=%lu dropped=%lu\n",
                nm, (unsigned long)frames, (unsigned long)ps1.bytes_written,
                (unsigned long)ps1.dropped_frames);
        }

        bool dis = engineDisable(id);
        if (passive) engineDisable(ENGINE_WARDRIVE);
        vTaskDelay(pdMS_TO_TICKS(600));
        bool stopped = (engineGetActiveMask() & ENGINE_BITMASK(id)) == 0;

        const char* verdict;
        if (!en || !started)      verdict = "FAIL-ENABLE";
        else if (!dis || !stopped) verdict = "FAIL-STOP";
        else if (activity == 0)    verdict = "ENABLE+STOP-OK-NO-ACTIVITY";
        else                       verdict = "PASS";
        Serial.printf("[SELFTEST] RESULT %s: start=%d stop=%d activity=%lu => %s\n",
            nm, started, stopped, (unsigned long)activity, verdict);
        Serial.printf("[SELFTEST] mask now=0x%02X heap=%lu\n",
            engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());
        vTaskDelay(pdMS_TO_TICKS(1500));
    }
    Serial.println("[SELFTEST] ===== ENGINE SELF-TEST DONE =====");
    vTaskDelete(NULL);
}
#endif

#ifdef OUISPY_AUTOPCAP_SELFTEST
static void autoPcapSelftestTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(6000));
    uint32_t t0 = millis();
    while (millis() - t0 < 30000) {
        if (meshManagerJoined() &&
            (engineGetActiveMask() & ENGINE_BITMASK(ENGINE_WARDRIVE))) break;
        vTaskDelay(pdMS_TO_TICKS(250));
    }
    Serial.printf("[APTEST] ready mgrJoined=%d slicing=%d window=%d mask=0x%02X heap=%lu\n",
        meshManagerJoined() ? 1 : 0, meshTimeSlicingActive() ? 1 : 0,
        meshInMeshWindow() ? 1 : 0, engineGetActiveMask(),
        (unsigned long)esp_get_free_heap_size());

    engineSetAutoPcap(true);
    for (int round = 0; round < 3; round++) {
        Serial.printf("[APTEST] === ROUND %d: inject FLOCK_WIFI x3 (autoPcap=%d slicing=%d) ===\n",
            round, engineAutoPcapEnabled() ? 1 : 0, meshTimeSlicingActive() ? 1 : 0);
        for (int n = 0; n < 3; n++) {
            DetectionEvent evt = {};
            evt.engine_id = ENGINE_FLOCK_WIFI;
            uint8_t fmac[6] = {0xDE,0xAD,0xBE,0xEF,(uint8_t)round,(uint8_t)(0x01 + n)};
            memcpy(evt.mac, fmac, 6);
            evt.rssi = -40; evt.channel = (uint8_t)(6 + n); evt.method = 0;
            pushDetection(&evt);
        }
        for (int i = 0; i < 44; i++) {
            vTaskDelay(pdMS_TO_TICKS(500));
            PcapStats ps; pcapGetStats(&ps);
            uint32_t frames = ps.beacon_count + ps.probe_req_count + ps.probe_resp_count
                            + ps.data_count + ps.ctrl_count + ps.mgmt_other_count;
            uint8_t m = engineGetActiveMask();
            bool pcapOn = (m & ENGINE_BITMASK(ENGINE_PCAP)) != 0;
            Serial.printf("[APTEST] r%d t=%.1fs slice=%d win=%d mask=0x%02X PCAP=%d frames=%lu heap=%lu\n",
                round, i * 0.5, meshTimeSlicingActive() ? 1 : 0, meshInMeshWindow() ? 1 : 0,
                m, pcapOn ? 1 : 0, (unsigned long)frames,
                (unsigned long)esp_get_free_heap_size());
        }
    }
    Serial.println("[APTEST] DONE — survived auto-pcap+mesh-forward under load");
    vTaskDelete(NULL);
}
#endif

#ifdef OUISPY_WATCHDOG_SELFTEST
static void watchdogSelftestTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(6000));
    meshDebugForceManager();
    vTaskDelay(pdMS_TO_TICKS(300));
    {
        EngineCommand ec = {};
        ec.command = 0x01;
        ec.engine_id = ENGINE_WARDRIVE;
        ec.payload_len = 0;
        xQueueSend(engineCmdQueue, &ec, portMAX_DELAY);
    }
    vTaskDelay(pdMS_TO_TICKS(500));
    Serial.printf("[WDTEST] forced manager + wardrive ENABLE (mask=0x%02X); NOT refreshing manager -> "
                  "watchdog must self-idle in ~%lus\n",
                  engineGetActiveMask(), (unsigned long)(MESH_MANAGER_TTL_MS / 1000));
    for (int i = 0; i < 12; i++) {
        vTaskDelay(pdMS_TO_TICKS(5000));
        Serial.printf("[WDTEST] t=%ds mgrJoined=%d mask=0x%02X\n",
                      (i + 1) * 5, meshManagerJoined() ? 1 : 0, engineGetActiveMask());
    }
    Serial.println("[WDTEST] DONE");
    vTaskDelete(NULL);
}
#endif

void setup() {
    Serial.begin(115200);
    delay(200);

    Serial.println("\n========================================");
    Serial.println("  OUI-SPY v3.0 — App-Controlled Mode");
    Serial.println("  No boot selector. BLE GATT only.");
    Serial.println("========================================\n");

    WiFi.persistent(false);
    WiFi.setAutoReconnect(false);
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(true, true);
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    WiFi.mode(WIFI_OFF);

    if (wifiOtaHasPending()) {
        Serial.println("[BOOT] WiFi OTA pending -> OTA-only mode (BLE/mesh/engines skipped, full heap)");
        wifiOtaRunPendingBlocking();
        Serial.println("[BOOT] WiFi OTA did not complete -> continuing normal boot");
    }

    initHardware();

    // Load hardware config (buzzer/LED/neopixel) from NVS
    loadHardwareConfig();
    ignoreListInit();

    // Create FreeRTOS queues
    detectionQueue = xQueueCreate(64, sizeof(DetectionEvent));
    engineCmdQueue = xQueueCreate(8, sizeof(EngineCommand));
    chimeQueue = xQueueCreate(1, sizeof(uint8_t));

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
    engineRegister(ENGINE_PCAP, &pcapCallbacks);

    // Force all engines disabled at boot — no stale radio state
    engineDisableAll();
    Serial.printf("[INIT] Active mask after boot disable: 0x%02X\n", engineGetActiveMask());

    // Initialize mesh subsystem
    meshInit();

    bleGattInit();

    Serial.println("[INIT] WiFi STA reserved for OTA mode only — mesh stays on ch1");

    // Create FreeRTOS tasks
    xTaskCreatePinnedToCore(detectionNotifyTask, "det_notify", 4096, NULL, 2, NULL, 1);
    xTaskCreatePinnedToCore(engineCmdTask, "eng_cmd", 4096, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(statusHeartbeatTask, "status_hb", 6144, NULL, 1, NULL, 1);
    xTaskCreatePinnedToCore(chimeTaskFn, "chime", 2048, NULL, 1, NULL, 1);

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

#ifndef OUISPY_ENGINE_SELFTEST
    {
        MeshConfig cfg = {};
        cfg.enabled = 1;
        cfg.encryption_enabled = 0;
        cfg.peer_count = 0;
        meshEnable(&cfg);
        Serial.println("[INIT] mesh auto-enabled (plaintext broadcast, manager-controlled)");
    }
#ifdef OUISPY_AUTOPCAP_SELFTEST
    xTaskCreatePinnedToCore(autoPcapSelftestTask, "aptest", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] AUTO-PCAP SELFTEST armed");
#endif
#ifdef OUISPY_WATCHDOG_SELFTEST
    xTaskCreatePinnedToCore(watchdogSelftestTask, "wdtest", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] WATCHDOG SELFTEST armed");
#endif
#else
    xTaskCreatePinnedToCore(engineSelftestTask, "selftest", 8192, NULL, 1, NULL, 1);
    Serial.println("[INIT] ENGINE SELF-TEST mode (mesh disabled)");
#endif

    Serial.println("\n[INIT] *** OUI-SPY READY ***");
    Serial.println("[INIT] Waiting for phone connection via BLE OR mesh command...");
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
