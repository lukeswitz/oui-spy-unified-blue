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
#include "det_spool.h"
#include "engine_registry.h"
#include "radio_coex.h"
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

#ifdef OUISPY_RGB_DARK
  #define OUISPY_LED_INIT()  neopixelWrite(PIN_NEOPIXEL, 0, 0, 0)
  #define OUISPY_LED_ON()    ((void)0)
  #define OUISPY_LED_OFF()   neopixelWrite(PIN_NEOPIXEL, 0, 0, 0)
#else
  #define OUISPY_LED_INIT()  do { pinMode(PIN_LED, OUTPUT); digitalWrite(PIN_LED, HIGH); } while (0)
  #define OUISPY_LED_ON()    digitalWrite(PIN_LED, LOW)
  #define OUISPY_LED_OFF()   digitalWrite(PIN_LED, HIGH)
#endif

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
    OUISPY_LED_INIT();

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
    bool flockExt = p.getBool("flock_ext", false);
    bool offlScan = p.getBool("offl_scan", false);
    p.end();
    flockSetExtendedOui(flockExt);
    offlineScanEnabledSetFromPref(offlScan);
    detSpoolInit();
#ifdef OUISPY_SPOOL_SELFTEST
    detSpoolSelfTest();
#endif
#ifdef OUISPY_WIGLE_OFFLINE_SELFTEST
    bleGattWigleOfflineSelfTest();
#endif
    Serial.printf("[HW] Config: buzzer=%d vol=%d led=%d neo=%d flock_ext=%d\n",
                  (int)hwBuzzerEnabled, (int)hwBuzzerVolume,
                  (int)hwLedEnabled, (int)hwNeopixelBrightness, (int)flockExt);
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

#define DRONE_DEDUP_SIZE 16
static struct {
    char uavId[21];
    uint8_t method;
    unsigned long ts;
} droneDedup[DRONE_DEDUP_SIZE];
static int droneDedupHead = 0;
static int droneDedupCount = 0;

static bool isDroneDedupCooldown(const char* uavId, uint8_t method) {
    if (uavId == nullptr || uavId[0] == '\0') return false;
    unsigned long now = millis();
    unsigned long cooldown = (unsigned long)engineGetNotifyCooldownMs();
    if (cooldown == 0) cooldown = NOTIFY_DEDUP_COOLDOWN_MS_DEFAULT;
    for (int i = 0; i < droneDedupCount; i++) {
        if (droneDedup[i].method == method &&
            strncmp(droneDedup[i].uavId, uavId, 20) == 0) {
            if (now - droneDedup[i].ts < cooldown) return true;
            droneDedup[i].ts = now;
            return false;
        }
    }
    int idx;
    if (droneDedupCount < DRONE_DEDUP_SIZE) {
        idx = droneDedupCount++;
    } else {
        idx = droneDedupHead;
        droneDedupHead = (droneDedupHead + 1) % DRONE_DEDUP_SIZE;
    }
    strncpy(droneDedup[idx].uavId, uavId, 20);
    droneDedup[idx].uavId[20] = '\0';
    droneDedup[idx].method = method;
    droneDedup[idx].ts = now;
    return false;
}

#ifdef OUISPY_SPOOL_STRESS
volatile bool g_spoolStressFlushPulse = false;
static volatile uint32_t g_spoolStressInjected = 0;
static void spoolStressInjectTask(void* arg) {
    (void)arg;
    uint32_t n = 0;
    for (;;) {
        // ~500 spoolable detections/s through the REAL capture hook.
        // 80% unique (fill+evict), 20% repeats of a hot set (dedup path).
        for (int i = 0; i < 50; i++) {
            DetectionEvent e = {};
            e.engine_id = ENGINE_FLOCK_WIFI;
            e.rssi = -55; e.channel = 6; e.method = 1;
            uint32_t id = (i % 5 == 0) ? (n % 32) : n;   // every 5th = repeat of hot set
            e.mac[0] = 0x02; e.mac[1] = 0xAA;
            e.mac[2] = (uint8_t)(id >> 24); e.mac[3] = (uint8_t)(id >> 16);
            e.mac[4] = (uint8_t)(id >> 8);  e.mac[5] = (uint8_t)id;
            e.timestamp_ms = millis();
            bleGattNotifyDetection(&e);
            g_spoolStressInjected++;
            n++;
        }
        vTaskDelay(pdMS_TO_TICKS(100));
    }
}
#endif

#ifdef OUISPY_SPOOL_E2E
static void spoolE2EInjectTask(void* arg) {
    (void)arg;
    uint32_t tick = 0;
    for (;;) {
        if (bleGattIsConnected()) { vTaskDelay(pdMS_TO_TICKS(500)); continue; }
        for (int i = 0; i < 8; i++) {
            DetectionEvent e = {};
            e.engine_id = ENGINE_FLOCK_WIFI;
            e.rssi = -50; e.channel = 6; e.method = 1;
            e.mac[0] = 0x02; e.mac[1] = 0xE2; e.mac[2] = 0xE2;
            e.mac[3] = 0x00; e.mac[4] = 0x00; e.mac[5] = (uint8_t)i;
            e.timestamp_ms = millis();
            bleGattNotifyDetection(&e);
        }
        if ((tick++ % 3) == 0) {
            Serial.printf("[SPOOL-E2E] offl=%d spoolCount=%u dropped=%u mgrJoin=%d mgrPhone=%d\n",
                          bleGattOfflineScanEnabled() ? 1 : 0, detSpoolCount(), detSpoolDroppedCount(),
                          meshManagerJoined() ? 1 : 0, meshMgrPhoneConnected() ? 1 : 0);
        }
        vTaskDelay(pdMS_TO_TICKS(1000));
    }
}
#endif

static volatile uint32_t g_ledOffAtMs = 0;

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

            if (evt.engine_id == ENGINE_SKYSPY) {
                if (isDroneDedupCooldown(evt.ext.odid.uav_id, evt.method)) continue;
            } else if (evt.engine_id != ENGINE_WARDRIVE &&
                       isNotifyDedupCooldown(evt.mac, evt.engine_id)) {
                continue;
            }

            // Audible + visual feedback only for target engines
            if (isAlertableEngine(evt.engine_id)) {
                Serial.printf("[CHIME] engine=%d\n", evt.engine_id);
                requestChime();
                if (hwLedEnabled) {
                    g_ledOffAtMs = millis() + 80;
                    OUISPY_LED_ON();
                }
            }

            // Broadcast to mesh peers (only local detections, not relayed ones)
            if (evt.engine_id == ENGINE_WARDRIVE)
                meshEnqueueWardriveRecord(&evt);
            else
                meshBroadcastDetection(&evt);

            // Send BLE notification
            bleGattNotifyDetection(&evt);

            if (evt.source_node_id[0] == '\0')
                engineRequestAutoPcap((EngineId)evt.engine_id, evt.channel, evt.mac);


            // Also print to serial (for debugging / Flask compatibility)
            char macStr[18];
            snprintf(macStr, sizeof(macStr), "%02x:%02x:%02x:%02x:%02x:%02x",
                     evt.mac[0], evt.mac[1], evt.mac[2],
                     evt.mac[3], evt.mac[4], evt.mac[5]);
            // Only emit when the TX buffer has room — a full USB-CDC/UART
            // buffer would block this drain task and back up detectionQueue,
            // causing the WiFi ISR to drop captures.
#ifndef OUISPY_SWEEPLOG
            if (Serial.availableForWrite() >= 96) {
                if (evt.engine_id == ENGINE_FLOCK_WIFI) {
                    Serial.printf("{\"engine\":%d,\"mac\":\"%s\",\"rssi\":%d,\"ch\":%d,\"method\":%d,\"auth\":%d}\n",
                                  evt.engine_id, macStr, evt.rssi, evt.channel, evt.method,
                                  evt.ext.flock.auth_mode);
                } else {
                    Serial.printf("{\"engine\":%d,\"mac\":\"%s\",\"rssi\":%d,\"ch\":%d,\"method\":%d}\n",
                                  evt.engine_id, macStr, evt.rssi, evt.channel, evt.method);
                }
            }
#endif
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

#ifdef OUISPY_STATUS_LOG
        Serial.printf("[STATUS] engines=0x%02X heap=%d gps=%s id=%s cmdRx=%lu rxWin=%lu slice=%d\n",
                      engineGetActiveMask(),
                      esp_get_free_heap_size(),
                      gpsValid ? "valid" : "none",
                      meshGetLocalNodeId(),
                      (unsigned long)g_meshCmdRx,
                      (unsigned long)g_meshRxWin,
                      meshTimeSlicingActive() ? 1 : 0);
#endif

        if (g_ledOffAtMs != 0 && (int32_t)(millis() - g_ledOffAtMs) >= 0) {
            OUISPY_LED_OFF();
            g_ledOffAtMs = 0;
        }
        detSpoolFlushIfDirty();
        bleGattSpoolFlushPump();
        bleGattNodeGraceTick();

#ifdef OUISPY_SPOOL_LIVETEST
        Serial.printf("[SPOOL-LIVE] count=%u dropped=%u active=0x%02X rawSeen=%lu\n",
                      detSpoolCount(), detSpoolDroppedCount(), engineGetActiveMask(),
                      (unsigned long)g_engRawSeen);
        {
            DetectionEvent ev; uint16_t hc;
            uint16_t sn = detSpoolCount(); if (sn > 6) sn = 6;
            for (uint16_t i = 0; i < sn; i++) {
                if (detSpoolReadSlot(i, &ev, &hc))
                    Serial.printf("[SPOOL-LIVE]   [%u] eng=%u %02X:%02X:%02X:%02X:%02X:%02X rssi=%d hits=%u\n",
                        i, ev.engine_id, ev.mac[0], ev.mac[1], ev.mac[2], ev.mac[3], ev.mac[4], ev.mac[5],
                        ev.rssi, hc);
            }
        }
#endif

#ifdef OUISPY_SPOOL_STRESS
        {
            static uint32_t lastPulse = 0;
            uint32_t nowMs = millis();
            if (nowMs > 20000 && nowMs - lastPulse > 20000) {
                lastPulse = nowMs;
                g_spoolStressFlushPulse = true;   // fire real spool->mesh flush
                Serial.println("[SPOOL-STRESS] flush pulse armed (mgr-phone-back simulated)");
            }
            Serial.printf("[SPOOL-STRESS] inj=%lu count=%u dropped=%u active=0x%02X heap=%u mgrJoin=%d\n",
                          (unsigned long)g_spoolStressInjected, detSpoolCount(), detSpoolDroppedCount(),
                          engineGetActiveMask(), (unsigned)esp_get_free_heap_size(),
                          meshManagerJoined() ? 1 : 0);
        }
#endif

#ifndef OUISPY_ROLE_MANAGER
        {
            static bool prevMgrPhone = false;
            bool mgrPhone = meshManagerJoined() && meshMgrPhoneConnected();
#ifdef OUISPY_SPOOL_STRESS
            if (g_spoolStressFlushPulse) { mgrPhone = true; g_spoolStressFlushPulse = false; }
#endif
            if (mgrPhone && !prevMgrPhone) {
                uint16_t n = detSpoolCount();
                if (n > 0) {
                    Serial.printf("[SPOOL] mgr phone back — flushing %u to mesh\n", n);
                    DetectionEvent evt;
                    for (uint16_t i = 0; i < n; i++) {
                        if (detSpoolReadSlot(i, &evt, nullptr)) {
                            meshBroadcastDetection(&evt, true);
                            vTaskDelay(pdMS_TO_TICKS(8));
                        }
                    }
                    detSpoolClear();
                    Serial.println("[SPOOL] mesh flush done, spool cleared");
                }
            }
            prevMgrPhone = mgrPhone;
        }
#endif

        static bool wasManaged = false;
        if (meshIsEnabled()) {
            if (meshManagerJoined()) {
                wasManaged = true;
            } else if (wasManaged && engineGetActiveMask() != 0) {
                if (!bleGattOfflineScanEnabled() && !bleGattIsConnected()) {
                    Serial.println("[WATCHDOG] manager lost — self-idle all engines");
                    engineDisableAll();
                }
                wasManaged = false;
            } else if (wasManaged) {
                wasManaged = false;
            }
        }
    }
}

#ifdef OUISPY_ENGINE_DIAG
volatile uint32_t g_diagDetCount[ENGINE_COUNT] = {0};

static const char* diagEngName(int id) {
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

static void engineDiagTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(3000));

    for (;;) {
        bleGattDebugForcePhone(true);
        for (int i = 0; i < ENGINE_COUNT; i++) g_diagDetCount[i] = 0;
        uint32_t lh = wardriveGetHopCount();
        engineEnable(ENGINE_WARDRIVE);
        engineEnable(ENGINE_FLOCK_WIFI);
        engineEnable(ENGINE_FLOCK_BLE);
        engineEnable(ENGINE_SKYSPY);
        engineEnable(ENGINE_DETECTOR);
        Serial.println("\n[MULTI] enabled W+FW+FB+SKY+DET together (direct node, no manager)");
        uint32_t lraw = g_engRawSeen;
        int ridSeen = 0;
        for (int t = 0; t < 12; t++) {
            for (int s = 0; s < 25; s++) {
                if (meshInRidWindow()) ridSeen++;
                vTaskDelay(pdMS_TO_TICKS(100));
            }
            uint32_t h = wardriveGetHopCount();
            uint32_t raw = g_engRawSeen;
            uint8_t ch = 0; wifi_second_chan_t s2; esp_wifi_get_channel(&ch, &s2);
            Serial.printf("[MULTI] t+%2lus ch=%2u hop+=%lu raw+=%lu ridWin=%d det[W=%lu FW=%lu SKY=%lu DET=%lu]\n",
                (unsigned long)((t + 1) * 25 / 10), ch, (unsigned long)(h - lh), (unsigned long)(raw - lraw),
                ridSeen,
                (unsigned long)g_diagDetCount[ENGINE_WARDRIVE], (unsigned long)g_diagDetCount[ENGINE_FLOCK_WIFI],
                (unsigned long)g_diagDetCount[ENGINE_SKYSPY], (unsigned long)g_diagDetCount[ENGINE_DETECTOR]);
            lh = h; lraw = raw; ridSeen = 0;
        }
        engineDisableAll();
        vTaskDelay(pdMS_TO_TICKS(2000));
    }

    for (int phase = 0; phase < 2; phase++) {
        bool phone = (phase == 1);
        bleGattDebugForcePhone(phone);
        for (int i = 0; i < ENGINE_COUNT; i++) g_diagDetCount[i] = 0;
        uint32_t lastHop = wardriveGetHopCount();
        engineEnable(ENGINE_WARDRIVE);
        Serial.printf("\n[DIAG] ==== A/B WARDRIVE phoneOwned=%d mgrJoined=%d ====\n",
            phone ? 1 : 0, meshManagerJoined() ? 1 : 0);
        uint32_t t0 = millis();
        while (millis() - t0 < 16000) {
            vTaskDelay(pdMS_TO_TICKS(2000));
            uint32_t hop = wardriveGetHopCount();
            uint8_t ch = 0; wifi_second_chan_t s2; esp_wifi_get_channel(&ch, &s2);
            Serial.printf("[DIAG] AB phoneOwned=%d t+%2lus ch=%2u hop+=%lu W=%lu st=%d\n",
                phone ? 1 : 0, (unsigned long)((millis() - t0) / 1000), ch,
                (unsigned long)(hop - lastHop),
                (unsigned long)g_diagDetCount[ENGINE_WARDRIVE],
                (int)engineGetState(ENGINE_WARDRIVE));
            lastHop = hop;
        }
        engineDisable(ENGINE_WARDRIVE);
        vTaskDelay(pdMS_TO_TICKS(1500));
    }

    bleGattDebugForcePhone(true);
    const EngineId order[] = {
        ENGINE_WARDRIVE, ENGINE_DETECTOR, ENGINE_FLOCK_BLE, ENGINE_FLOCK_WIFI,
        ENGINE_SKYSPY, ENGINE_FOXHUNTER, ENGINE_UNIPWN, ENGINE_PCAP,
    };
    const uint32_t kRunMs = 20000;
    for (;;) {
        for (size_t k = 0; k < sizeof(order) / sizeof(order[0]); k++) {
            EngineId e = order[k];
            for (int i = 0; i < ENGINE_COUNT; i++) g_diagDetCount[i] = 0;
            uint32_t lastHop = wardriveGetHopCount();
            uint32_t lastSkip = wardriveGetMeshSkipCount();
            bool ok = engineEnable(e);
            MeshStatus ms = meshGetStatus();
            MeshLiveNode lv[MESH_LIVE_NODES_MAX];
            size_t lc = meshGetLiveNodes(lv, MESH_LIVE_NODES_MAX, MESH_NODE_TIMEOUT_MS);
            Serial.printf("\n[DIAG] ==== ENABLE %s ok=%d mesh_en=%d mgrJoined=%d sliceActive=%d rx=%lu tx=%lu live=%u self=%s ====\n",
                diagEngName(e), ok ? 1 : 0, meshIsEnabled() ? 1 : 0,
                meshManagerJoined() ? 1 : 0, meshTimeSlicingActive() ? 1 : 0,
                (unsigned long)ms.rx_count, (unsigned long)ms.tx_count,
                (unsigned)lc, meshGetLocalNodeId());
            for (size_t li = 0; li < lc; li++)
                Serial.printf("[DIAG]    live[%u] id=%.4s role=%u eng=0x%02x age=%lums\n",
                    (unsigned)li, lv[li].id, lv[li].role, lv[li].active_engines,
                    (unsigned long)(millis() - lv[li].last_ms));
            uint32_t t0 = millis();
            while (millis() - t0 < kRunMs) {
                vTaskDelay(pdMS_TO_TICKS(2000));
                uint8_t ch = 0; wifi_second_chan_t s2;
                esp_wifi_get_channel(&ch, &s2);
                uint32_t hop = wardriveGetHopCount();
                uint32_t skip = wardriveGetMeshSkipCount();
                Serial.printf("[DIAG] %s t+%2lus ch=%2u hop+=%lu meshskip+=%lu inWin=%d "
                    "det[D=%lu FB=%lu FW=%lu SKY=%lu W=%lu PCAP=%lu] heap=%u st=%d\n",
                    diagEngName(e), (unsigned long)((millis() - t0) / 1000), ch,
                    (unsigned long)(hop - lastHop), (unsigned long)(skip - lastSkip),
                    meshInMeshWindow() ? 1 : 0,
                    (unsigned long)g_diagDetCount[ENGINE_DETECTOR],
                    (unsigned long)g_diagDetCount[ENGINE_FLOCK_BLE],
                    (unsigned long)g_diagDetCount[ENGINE_FLOCK_WIFI],
                    (unsigned long)g_diagDetCount[ENGINE_SKYSPY],
                    (unsigned long)g_diagDetCount[ENGINE_WARDRIVE],
                    (unsigned long)g_diagDetCount[ENGINE_PCAP],
                    (unsigned)esp_get_free_heap_size(), (int)engineGetState(e));
                lastHop = hop; lastSkip = skip;
            }
            engineDisable(e);
            Serial.printf("[DIAG] ==== DISABLE %s ====\n", diagEngName(e));
            vTaskDelay(pdMS_TO_TICKS(1500));
        }
    }
}
#endif

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

#ifdef OUISPY_RADIOWATCH
static void radioWatchTask(void* arg) {
    (void)arg;
    uint32_t prev = 0;
    for (;;) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        uint32_t now = g_engRawSeen;
        uint32_t d = now - prev;
        prev = now;
        uint8_t m = engineGetActiveMask();
        bool scan = false;
        NimBLEScan* s = NimBLEDevice::getScan();
        if (s) scan = s->isScanning();
        Serial.printf("[RW] mask=0x%02X raw+=%lu wifiCoex=%d bleScan=%d heap=%lu\n",
                      m, (unsigned long)d, wifiCoexActive() ? 1 : 0,
                      scan ? 1 : 0, (unsigned long)esp_get_free_heap_size());
    }
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

#ifdef OUISPY_COEX_STRESS
static void coexEn(EngineId id) {
    EngineCommand ec = {};
    ec.command = 0x01; ec.engine_id = id; ec.payload_len = 0;
    xQueueSend(engineCmdQueue, &ec, portMAX_DELAY);
}
static void coexDis(EngineId id) {
    EngineCommand ec = {};
    ec.command = 0x00; ec.engine_id = id; ec.payload_len = 0;
    xQueueSend(engineCmdQueue, &ec, portMAX_DELAY);
}
static void coexStressTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(5000));
    Serial.println("[STRESS] ===== A: 5 BLE engines concurrent (no wardrive) =====");
    coexEn(ENGINE_FLOCK_BLE); coexEn(ENGINE_SKYSPY); coexEn(ENGINE_UNIPWN);
    coexEn(ENGINE_DETECTOR); coexEn(ENGINE_FOXHUNTER);
    uint32_t b = g_engRawSeen;
    for (int i = 0; i < 15; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        Serial.printf("[STRESS] A t=%ds mask=0x%02X seen=%lu heap=%lu\n",
            i + 1, engineGetActiveMask(), (unsigned long)(g_engRawSeen - b),
            (unsigned long)esp_get_free_heap_size());
    }
    coexDis(ENGINE_FLOCK_BLE); coexDis(ENGINE_SKYSPY); coexDis(ENGINE_UNIPWN);
    coexDis(ENGINE_DETECTOR); coexDis(ENGINE_FOXHUNTER);
    vTaskDelay(pdMS_TO_TICKS(2500));
    Serial.printf("[STRESS] A done mask=0x%02X heap=%lu\n",
        engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());

    Serial.println("[STRESS] ===== B: wardrive host + flock + detector + skyspy =====");
    coexEn(ENGINE_WARDRIVE); coexEn(ENGINE_FLOCK_WIFI); coexEn(ENGINE_FLOCK_BLE);
    coexEn(ENGINE_DETECTOR); coexEn(ENGINE_SKYSPY);
    b = g_engRawSeen;
    for (int i = 0; i < 12; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        Serial.printf("[STRESS] B t=%ds mask=0x%02X seen=%lu heap=%lu\n",
            i + 1, engineGetActiveMask(), (unsigned long)(g_engRawSeen - b),
            (unsigned long)esp_get_free_heap_size());
    }
    coexDis(ENGINE_WARDRIVE); coexDis(ENGINE_FLOCK_WIFI); coexDis(ENGINE_FLOCK_BLE);
    coexDis(ENGINE_DETECTOR); coexDis(ENGINE_SKYSPY);
    vTaskDelay(pdMS_TO_TICKS(2500));
    Serial.printf("[STRESS] B done mask=0x%02X heap=%lu\n",
        engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());

    Serial.println("[STRESS] ===== C: rapid enable/disable churn x25 =====");
    for (int i = 0; i < 25; i++) {
        coexEn(ENGINE_SKYSPY); coexEn(ENGINE_FLOCK_BLE); coexEn(ENGINE_DETECTOR);
        coexEn(ENGINE_FLOCK_WIFI);
        vTaskDelay(pdMS_TO_TICKS(120));
        coexDis(ENGINE_SKYSPY); coexDis(ENGINE_FLOCK_BLE); coexDis(ENGINE_DETECTOR);
        coexDis(ENGINE_FLOCK_WIFI);
        vTaskDelay(pdMS_TO_TICKS(120));
    }
    vTaskDelay(pdMS_TO_TICKS(2500));
    Serial.printf("[STRESS] C done mask=0x%02X heap=%lu\n",
        engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());

    Serial.println("[STRESS] ===== D: reverse order (flockWifi then wardrive) — no double =====");
    coexEn(ENGINE_FLOCK_WIFI);
    vTaskDelay(pdMS_TO_TICKS(3000));
    Serial.println("[STRESS] D flockWifi up; now starting wardrive (must suspend flock)");
    coexEn(ENGINE_WARDRIVE);
    vTaskDelay(pdMS_TO_TICKS(4000));
    Serial.printf("[STRESS] D mask=0x%02X (wardrive must host; flock cb suspended)\n",
        engineGetActiveMask());
    coexEn(ENGINE_SKYSPY);
    vTaskDelay(pdMS_TO_TICKS(3000));
    Serial.printf("[STRESS] D +skyspy mask=0x%02X heap=%lu\n",
        engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());
    coexDis(ENGINE_WARDRIVE);
    vTaskDelay(pdMS_TO_TICKS(3000));
    Serial.printf("[STRESS] D wardrive off — flock must resume; mask=0x%02X\n",
        engineGetActiveMask());
    coexDis(ENGINE_FLOCK_WIFI); coexDis(ENGINE_SKYSPY);
    vTaskDelay(pdMS_TO_TICKS(2500));

    Serial.println("[STRESS] ===== E: flockWifi + detector (no wardrive) channel arbiter =====");
    coexEn(ENGINE_FLOCK_WIFI); coexEn(ENGINE_DETECTOR);
    uint32_t e0 = g_engRawSeen;
    for (int i = 0; i < 10; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        Serial.printf("[STRESS] E t=%ds mask=0x%02X seen=%lu heap=%lu\n",
            i + 1, engineGetActiveMask(), (unsigned long)(g_engRawSeen - e0),
            (unsigned long)esp_get_free_heap_size());
    }
    coexDis(ENGINE_FLOCK_WIFI); coexDis(ENGINE_DETECTOR);
    vTaskDelay(pdMS_TO_TICKS(2500));
    Serial.printf("[STRESS] E done mask=0x%02X heap=%lu\n",
        engineGetActiveMask(), (unsigned long)esp_get_free_heap_size());

    Serial.println("[STRESS] ===== ALL DONE — no crash =====");
    vTaskDelete(NULL);
}
#endif

#ifdef OUISPY_SKYSPY_MESH_TEST
static void skyspyMeshTestEnable(uint8_t eng) {
    EngineCommand ec = {};
    ec.command = 0x01; ec.engine_id = eng; ec.payload_len = 0;
    xQueueSend(engineCmdQueue, &ec, portMAX_DELAY);
}
static void skyspyMeshTestTask(void* arg) {
    (void)arg;
    vTaskDelay(pdMS_TO_TICKS(8000));
    skyspyMeshTestEnable(ENGINE_WARDRIVE);
    vTaskDelay(pdMS_TO_TICKS(500));
    skyspyMeshTestEnable(ENGINE_SKYSPY);
    Serial.println("[SKYTEST] wardrive+skyspy enabled — ch6 RID-window test");
    uint32_t base = g_engRawSeen;
    for (int i = 0; i < 90; i++) {
        vTaskDelay(pdMS_TO_TICKS(1000));
        if (i % 5 == 4) { skyspyMeshTestEnable(ENGINE_WARDRIVE); skyspyMeshTestEnable(ENGINE_SKYSPY); }
        uint8_t ch = 0; wifi_second_chan_t sc;
        esp_wifi_get_channel(&ch, &sc);
        Serial.printf("[SKYTEST] t=%ds ch=%u mask=0x%02X ridWin=%d ridSeen=%lu\n",
                      i + 1, ch, engineGetActiveMask(),
                      meshInRidWindow() ? 1 : 0, (unsigned long)(g_engRawSeen - base));
    }
    Serial.println("[SKYTEST] DONE");
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
    Serial.printf("[VERSION] OUI-SPY FW=%s (0x%06X)\n", FW_VERSION, FW_VERSION_NUM);

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

    wifiStaSetEnabled(false);

    initHardware();

    // Load hardware config (buzzer/LED/neopixel) from NVS
    loadHardwareConfig();
    ignoreListInit();

    // Create FreeRTOS queues
    detectionQueue = xQueueCreate(128, sizeof(DetectionEvent));
    engineCmdQueue = xQueueCreate(8, sizeof(EngineCommand));
    chimeQueue = xQueueCreate(1, sizeof(uint8_t));

    if (detectionQueue == NULL || engineCmdQueue == NULL || chimeQueue == NULL) {
        Serial.println("[FATAL] Queue creation failed!");
        while (1) delay(1000);
    }
    Serial.println("[INIT] Queues created (det=128, cmd=8)");

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
        OUISPY_LED_ON();
        delay(100);
        OUISPY_LED_OFF();
        delay(100);
    }

#ifndef OUISPY_ENGINE_SELFTEST
#ifndef OUISPY_COEX_STRESS
    {
        MeshConfig cfg = {};
        cfg.enabled = 1;
        cfg.encryption_enabled = 0;
        cfg.peer_count = 0;
        meshEnable(&cfg);
        Serial.println("[INIT] mesh auto-enabled (plaintext broadcast, manager-controlled)");
    }
#endif
#ifdef OUISPY_SPOOL_LIVETEST
    meshDisable();
    offlineScanEnabledSetFromPref(true);
    delay(800);
    engineEnable(ENGINE_FLOCK_WIFI);
    Serial.println("[SPOOL-LIVE] standalone flock-WIFI spool test: mesh OFF, offline ON, no phone, flock-WIFI armed");
#endif
#ifdef OUISPY_SPOOL_STRESS
    offlineScanEnabledSetFromPref(true);
    xTaskCreatePinnedToCore(spoolStressInjectTask, "spoolstress", 4096, NULL, 1, NULL, 1);
    Serial.println("[SPOOL-STRESS] node: offline ON, mesh auto, injecting ~500 spoolable det/s; 20s flush-to-mesh pulse");
#endif
#ifdef OUISPY_SPOOL_E2E
    offlineScanEnabledSetFromPref(true);
    xTaskCreatePinnedToCore(spoolE2EInjectTask, "spoole2e", 4096, NULL, 1, NULL, 1);
    Serial.println("[SPOOL-E2E] node: offline forced ON, injecting 8 fixed flock det/s via real capture hook");
#endif
#ifdef OUISPY_AUTOPCAP_SELFTEST
    xTaskCreatePinnedToCore(autoPcapSelftestTask, "aptest", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] AUTO-PCAP SELFTEST armed");
#endif
#ifdef OUISPY_RADIOWATCH
    xTaskCreatePinnedToCore(radioWatchTask, "radiowatch", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] RADIO WATCH armed");
#endif
#ifdef OUISPY_WATCHDOG_SELFTEST
    xTaskCreatePinnedToCore(watchdogSelftestTask, "wdtest", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] WATCHDOG SELFTEST armed");
#endif
#ifdef OUISPY_COEX_STRESS
    xTaskCreatePinnedToCore(coexStressTask, "coexstress", 6144, NULL, 1, NULL, 1);
    Serial.println("[INIT] COEX STRESS armed");
#endif
#ifdef OUISPY_SKYSPY_MESH_TEST
    xTaskCreatePinnedToCore(skyspyMeshTestTask, "skytest", 4096, NULL, 1, NULL, 1);
    Serial.println("[INIT] SKYSPY MESH TEST armed (real manager)");
#endif
#ifdef OUISPY_SPOOL_E2E
    bleGattSpoolE2EStart();
    Serial.println("[INIT] SPOOL E2E armed (standalone node: engines + spool-while-away + flush)");
#endif
#ifdef OUISPY_ENGINE_DIAG
    xTaskCreatePinnedToCore(engineDiagTask, "engdiag", 6144, NULL, 1, NULL, 1);
    Serial.println("[INIT] ENGINE DIAG armed (cycles all engines, mesh auto-enabled — standalone repro)");
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
