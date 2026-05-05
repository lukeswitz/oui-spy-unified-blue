/**
 * OUI-SPY Unified Firmware — Shared Protocol Definitions
 *
 * All structs, enums, UUIDs, and queue definitions shared between
 * the GATT server, engine registry, and individual engines.
 */
#ifndef PROTOCOL_H
#define PROTOCOL_H

#include <stdint.h>
#include <stdbool.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

// Mesh constants (needed before DetectionEvent)
#define MESH_MAX_PEERS       6
#define MESH_KEY_LEN         32
#define MESH_NONCE_LEN       12
#define MESH_TAG_LEN         16
#define MESH_NODE_ID_LEN     5

// Hardware pins (XIAO ESP32-S3)
#define PIN_BUZZER     3
#define PIN_LED        21    // Onboard LED, active LOW
#define PIN_NEOPIXEL   4     // WS2812B data
#define PIN_GPS_RX     44    // Optional hardware GPS
#define PIN_GPS_TX     43

// Firmware version
#define FW_VERSION     "3.1.0"
#define FW_VERSION_NUM 0x030100

// ============================================================================
// Engine IDs — bitmask-compatible
// ============================================================================
enum EngineId : uint8_t {
    ENGINE_DETECTOR   = 0,  // bitmask 0x01
    ENGINE_FLOCK_BLE  = 1,  // bitmask 0x02
    ENGINE_FLOCK_WIFI = 2,  // bitmask 0x04
    ENGINE_FOXHUNTER  = 3,  // bitmask 0x08
    ENGINE_SKYSPY     = 4,  // bitmask 0x10
    ENGINE_UNIPWN     = 5,  // bitmask 0x20
    ENGINE_WARDRIVE   = 6,  // bitmask 0x40
    ENGINE_COUNT      = 7
};

#define ENGINE_BITMASK(id) (1 << (id))

// ============================================================================
// Engine State
// ============================================================================
enum EngineState : uint8_t {
    ESTATE_DISABLED      = 0,
    ESTATE_IDLE          = 1,
    ESTATE_SCANNING      = 2,
    ESTATE_ACTIVE        = 3,
    ESTATE_ALERTING      = 4,
    // UniPwn-specific
    ESTATE_TARGET_SEL    = 5,
    ESTATE_CONNECTING    = 6,
    ESTATE_EXPLOITING    = 7,
    ESTATE_COMPLETE      = 8
};

// ============================================================================
// Detection Methods
// ============================================================================
// Flock-WiFi methods
#define METHOD_OUI_ADDR1       0
#define METHOD_OUI_ADDR2       1
#define METHOD_OUI_ADDR3       2
#define METHOD_SSID            3
#define METHOD_WILDCARD_PROBE  4

// Flock-BLE methods
#define METHOD_OUI_MATCH       0
#define METHOD_NAME_MATCH      1
#define METHOD_MFG_ID          2
#define METHOD_RAVEN_UUID      3

// Sky Spy methods
#define METHOD_ODID_BLE        0
#define METHOD_ODID_NAN        1
#define METHOD_ODID_BEACON     2

// Wardrive methods
#define METHOD_WIFI_AP         0
#define METHOD_BLE_ADV         1

// ============================================================================
// Detection Event — produced by engines, consumed by GATT notification task
// ============================================================================
typedef struct __attribute__((packed)) {
    uint8_t  engine_id;          // EngineId
    uint8_t  mac[6];             // Device MAC
    int8_t   rssi;               // Signal strength
    uint8_t  channel;            // WiFi channel or 0 for BLE
    uint32_t timestamp_ms;       // millis() at detection
    uint8_t  method;             // Engine-specific detection method
    char     source_node_id[MESH_NODE_ID_LEN]; // Origin node ("" = local)

    // Engine-specific extension (union saves RAM)
    union {
        // Flock-BLE / Flock-WiFi
        struct {
            uint8_t is_raven;
            char    raven_fw[16];
        } flock;

        // Sky Spy ODID
        struct {
            char    uav_id[21];
            char    op_id[21];
            double  drone_lat;
            double  drone_lon;
            int16_t altitude_msl;
            int16_t height_agl;
            int16_t speed;
            int16_t heading;
            double  pilot_lat;
            double  pilot_lon;
        } odid;

        // UniPwn
        struct {
            char    robot_type[8];
            uint8_t exploited;
            char    serial_num[32];
        } unipwn;

        // Detector
        struct {
            char    filter_desc[32];
            uint8_t is_full_mac;
        } detector;

        // Foxhunter (RSSI sent separately via dedicated characteristic)
        struct {
            uint8_t _reserved;
        } foxhunter;

        // Wardrive (WiGLE-style capture)
        struct {
            char    ssid[33];
            uint8_t auth_mode;     // 0=open,1=WEP,2=WPA,3=WPA2,4=WPA_WPA2,5=WPA2_ENT,6=WPA3
            char    device_name[21];
        } wardrive;
    } ext;
} DetectionEvent;

// ============================================================================
// GPS Data — received from phone app via BLE
// ============================================================================
typedef struct __attribute__((packed)) {
    double   latitude;
    double   longitude;
    float    altitude;
    float    speed;
    float    heading;
    float    accuracy;
    uint8_t  satellite_count;
    int64_t  timestamp_ms;
} GpsData;

// ============================================================================
// Engine Command — from GATT write to engine task
// ============================================================================
typedef struct {
    uint8_t  command;       // 0x01=enable, 0x00=disable, 0x10=config_update
    uint8_t  engine_id;
    uint8_t  payload[64];
    uint8_t  payload_len;
} EngineCommand;

// ============================================================================
// Queues (extern, created in main.cpp)
// ============================================================================
extern QueueHandle_t detectionQueue;   // DetectionEvent, depth 64
extern QueueHandle_t engineCmdQueue;   // EngineCommand, depth 8

// ============================================================================
// GPS State (extern, updated by BLE write callback)
// ============================================================================
extern volatile GpsData currentGps;
extern volatile bool    gpsValid;

// ============================================================================
// Hardware Config (extern, loaded at boot, updated by BLE write callback)
// ============================================================================
extern volatile bool    hwBuzzerEnabled;
extern volatile uint8_t hwBuzzerVolume;      // 0-255 PWM duty cycle
extern volatile bool    hwLedEnabled;
extern volatile uint8_t hwNeopixelBrightness;

// ============================================================================
// GATT UUIDs
// ============================================================================
// Base UUID matches Flutter app: 0000XXXX-0ui5-4py0-bad0-c010ne1pan1c
// NimBLE needs valid hex — "0ui5" isn't valid hex. Use the app's literal strings.
// flutter_blue_plus Guid accepts arbitrary strings; NimBLE needs valid 128-bit UUIDs.
// Canonical form: lowercase hex only. Map app UUIDs to valid hex.
//
// App uses: 0000XXXX-0ui5-4py0-bad0-c010ne1pan1c  (not valid hex)
// We must use the SAME bytes on both sides.
// flutter_blue_plus Guid() auto-lowercases and parses as string match.
// NimBLE parses as 128-bit UUID from hex string.
// Solution: use valid hex that both sides agree on.
#define UUID_BASE            "0a15-4b70-ba00-c010ae1ba01c"
#define SVC_UUID             "00000001-" UUID_BASE
#define CHR_DEVICE_INFO      "00000001-" UUID_BASE
#define CHR_ENGINE_CONTROL   "00000002-" UUID_BASE
#define CHR_DETECTION_EVENTS "00000010-" UUID_BASE
#define CHR_DEVICE_STATUS    "00000011-" UUID_BASE
#define CHR_GPS_RECEIVE      "00000012-" UUID_BASE
#define CHR_HARDWARE_CONFIG  "00000020-" UUID_BASE
#define CHR_ALERT_CONFIG     "00000021-" UUID_BASE
#define CHR_FOXHUNTER_CONFIG "00000130-" UUID_BASE
#define CHR_FOXHUNTER_RSSI   "00000131-" UUID_BASE
#define CHR_SKYSPY_TELEMETRY "00000140-" UUID_BASE
#define CHR_UNIPWN_DEVICES   "00000150-" UUID_BASE
#define CHR_UNIPWN_COMMAND   "00000151-" UUID_BASE

// ============================================================================
// Mesh Configuration
// ============================================================================
typedef struct __attribute__((packed)) {
    uint8_t enabled;
    uint8_t encryption_enabled;
    uint8_t key[MESH_KEY_LEN];
    uint8_t peer_count;
    uint8_t peers[MESH_MAX_PEERS][6];
} MeshConfig;

typedef struct __attribute__((packed)) {
    uint8_t enabled;
    uint8_t peer_count;
    uint8_t connected_peers;
    uint32_t rx_count;
    uint32_t tx_count;
    uint32_t rx_errors;
} MeshStatus;

typedef struct __attribute__((packed)) {
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  engine_id;
    uint8_t  mac[6];
    int8_t   rssi;
    uint8_t  channel;
    uint32_t timestamp_ms;
    uint8_t  method;
    uint8_t  ext_data[96];
    uint8_t  ext_len;
} MeshDetectionPacket;

// ============================================================================
// Mesh Packet Types — discriminator for ESP-NOW payloads
// ============================================================================
enum MeshPacketType : uint8_t {
    MESH_PKT_DETECTION = 0x01,
    MESH_PKT_COMMAND   = 0x02,
    MESH_PKT_STATUS    = 0x03,
    MESH_PKT_INVITE    = 0x04,
};

// Command relay: primary node -> peers (via ESP-NOW)
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_COMMAND
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  command;               // 0x01=enable, 0x00=disable, 0x0F=disable_all, 0x10=config
    uint8_t  engine_id;
    uint8_t  payload[32];
    uint8_t  payload_len;
} MeshCommandPacket;

// Status heartbeat: each node -> all peers (every 5s)
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_STATUS
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  active_engine_mask;    // Bitmask: bit N = engine N active
    uint8_t  engine_states[ENGINE_COUNT];
    uint32_t detection_count;       // Total since mesh enabled
    uint32_t uptime_sec;            // Seconds since mesh enabled
    int8_t   free_heap_kb;          // ESP.getFreeHeap() / 1024
} MeshStatusPacket;

// Mesh invite: primary -> broadcast (unencrypted, recruits peers)
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_INVITE
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  primary_mac[6];        // Primary node's WiFi STA MAC
    uint8_t  encryption_enabled;
    uint8_t  key[MESH_KEY_LEN];     // Encryption key (plaintext in invite)
    uint8_t  channel;               // ESP-NOW channel
} MeshInvitePacket;

// ============================================================================
// GATT UUIDs — Mesh
// ============================================================================
#define CHR_MESH_CONFIG      "00000060-" UUID_BASE
#define CHR_MESH_STATUS      "00000061-" UUID_BASE
#define CHR_ORCHESTRATION    "00000070-" UUID_BASE

// ============================================================================
// Mesh globals (extern, managed by mesh_espnow.cpp)
// ============================================================================
extern volatile MeshConfig meshCurrentConfig;
extern volatile MeshStatus meshCurrentStatus;

// Ring buffer for peer status notifications (forwarded to BLE)
#define MESH_PEER_STATUS_QUEUE_DEPTH 4
extern QueueHandle_t peerStatusQueue;  // MeshStatusPacket, depth 4

// ============================================================================
// Helper: push detection onto queue (ISR-safe variant available)
// ============================================================================
static inline bool pushDetection(const DetectionEvent* evt) {
    if (detectionQueue == NULL) return false;
    return xQueueSend(detectionQueue, evt, pdMS_TO_TICKS(10)) == pdTRUE;
}

/// Stamp a DetectionEvent with current GPS from phone app.
static inline void stampGps(DetectionEvent* evt) {
    (void)evt; // GPS fields not in DetectionEvent struct — stamped by app side
}

static inline bool pushDetectionFromISR(const DetectionEvent* evt) {
    if (detectionQueue == NULL) return false;
    BaseType_t wake = pdFALSE;
    bool ok = xQueueSendFromISR(detectionQueue, evt, &wake) == pdTRUE;
    if (wake) portYIELD_FROM_ISR();
    return ok;
}

#endif // PROTOCOL_H
