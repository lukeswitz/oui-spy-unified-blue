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
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif
extern volatile uint32_t g_engRawSeen;
#ifdef __cplusplus
}
#endif
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
#define FW_VERSION     "0.4.0"
#define FW_VERSION_NUM 0x000400

#ifndef OUISPY_BOARD
  #define OUISPY_BOARD "unknown"
#endif

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
    ENGINE_PCAP       = 7,  // bitmask 0x80
    ENGINE_COUNT      = 8
};

#define ENGINE_BITMASK(id) (1 << (id))

static const bool kEngineTargetable[ENGINE_COUNT] = {
    false,
    false,
    false,
    true,
    false,
    true,
    false,
    true,
};

#define CFG_TGT_PREFIX   0xFE
#define CFG_TGT_OVERHEAD 6

static inline bool cfgTgtStrip(const uint8_t** payload, uint8_t* len, const char* self) {
    if (*len < CFG_TGT_OVERHEAD) return true;
    if ((*payload)[0] != CFG_TGT_PREFIX) return true;
    if (memcmp(*payload + 1, self, MESH_NODE_ID_LEN - 1) != 0) return false;
    *payload += CFG_TGT_OVERHEAD;
    *len    -= CFG_TGT_OVERHEAD;
    return true;
}

static inline void bleAddrToMac(const uint8_t* native, uint8_t* out) {
    for (int i = 0; i < 6; i++) out[i] = native[5 - i];
}

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
            uint8_t auth_mode;
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
// Canonical form: lowercase hex only. Map app UUIDs to valid hex.
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
#define CHR_DFU_CONTROL      "00000050-" UUID_BASE
#define CHR_DFU_DATA         "00000051-" UUID_BASE
#define CHR_SYSTEM_CONTROL   "00000052-" UUID_BASE
#define CHR_WIFI_CONFIG      "00000040-" UUID_BASE
#define CHR_IGNORE_LIST      "00000023-" UUID_BASE
#define CHR_NODE_RADIO       "00000024-" UUID_BASE
// PCAP engine
#define CHR_PCAP_CONTROL     "00000160-" UUID_BASE
#define CHR_PCAP_STATS       "00000161-" UUID_BASE
#define CHR_PCAP_DATA        "00000162-" UUID_BASE
#define CHR_DETECTOR_CONFIG  "00000100-" UUID_BASE

// ============================================================================
// PCAP — live capture stats (notified over CHR_PCAP_STATS)
// ============================================================================
// Modes:
//   0 = WIFI radiotap (LINKTYPE_IEEE80211_RADIOTAP=127)
//   1 = BLE LE LL with PHDR (LINKTYPE_BLUETOOTH_LE_LL_WITH_PHDR=256)
#define PCAP_MODE_WIFI 0
#define PCAP_MODE_BLE  1

typedef struct __attribute__((packed)) {
    uint8_t  state;             // 0=idle, 1=capturing, 2=full, 3=error
    uint8_t  mode;              // PCAP_MODE_WIFI / PCAP_MODE_BLE
    uint8_t  current_channel;   // wifi: current hop channel  ble: last seen primary adv chan
    uint8_t  _reserved;
    uint32_t beacon_count;
    uint32_t probe_req_count;
    uint32_t probe_resp_count;
    uint32_t deauth_count;
    uint32_t disassoc_count;
    uint32_t data_count;
    uint32_t ctrl_count;
    uint32_t mgmt_other_count;
    uint32_t ble_adv_count;     // ADV_IND/ADV_NONCONN_IND/ADV_SCAN_IND
    uint32_t ble_scan_count;    // SCAN_REQ/SCAN_RSP
    uint32_t bytes_written;
    uint32_t dropped_frames;
    uint32_t file_size;
    uint32_t uptime_ms;
    uint8_t  auto_enabled;
    uint16_t auto_duration_sec;
    uint8_t  paused_mask;
    uint32_t auto_remaining_ms;
    uint8_t  auto_trigger_src;
    uint8_t  auto_trigger_mac[6];
    uint16_t auto_cooldown_sec;
    uint32_t auto_cooldown_remaining_ms;
    char     source_node_id[MESH_NODE_ID_LEN]; // "" = local; otherwise mesh-relayed
} PcapStats;

// PCAP control opcodes (write to CHR_PCAP_CONTROL)
#define PCAP_CTRL_START          0x01  // payload: channel_start[1] channel_end[1] radio_mask[1]
#define PCAP_CTRL_STOP           0x02
#define PCAP_CTRL_CLEAR          0x03  // delete on-flash capture file
#define PCAP_CTRL_DOWNLOAD       0x10  // begin download via CHR_PCAP_DATA notifies
#define PCAP_CTRL_DOWNLOAD_ABORT 0x11

// PCAP data chunk opcodes (notified on CHR_PCAP_DATA)
#define PCAP_DATA_START          0x01  // [op][len:4 LE][crc32:4 LE]
#define PCAP_DATA_CHUNK          0x02  // [op][seq:2 LE][payload]
#define PCAP_DATA_COMMIT         0x03  // [op]
#define PCAP_DATA_ABORT          0x04  // [op][reason:1]

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
    MESH_PKT_DETECTION       = 0x01,
    MESH_PKT_COMMAND         = 0x02,
    MESH_PKT_STATUS          = 0x03,
    MESH_PKT_INVITE          = 0x04,
    MESH_PKT_ACK             = 0x06,
    MESH_PKT_AUTOPCAP_EVENT  = 0x07,
    MESH_PKT_RAW_NOTIFY      = 0x08,
    MESH_PKT_HEARTBEAT       = 0x09,
    MESH_PKT_IGNORELIST      = 0x0A,
};

#define MESH_IGNORELIST_MAX 220
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  len;
    uint8_t  data[MESH_IGNORELIST_MAX];
} MeshIgnoreListPacket;

#define MESH_ROLE_NODE     0
#define MESH_ROLE_MANAGER  1

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint32_t uptime_s;
    uint32_t free_heap;
    uint8_t  role;
    uint8_t  active_engines_mask;
} MeshHeartbeatPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  trigger_src;
    uint8_t  trigger_mac[6];
    uint8_t  channel;
    uint16_t duration_sec;
    uint8_t  paused_mask;
} MeshAutoPcapEventPacket;

// Raw BLE notification forwarded over mesh. Node fills payload + kind,
// MGR routes to matching BLE characteristic and notifies phone.
enum MeshRawNotifyKind : uint8_t {
    RAW_NOTIFY_PCAP_DATA         = 0x01,
    RAW_NOTIFY_PCAP_STATS        = 0x02,
    RAW_NOTIFY_FOXHUNTER_RSSI    = 0x03,
    RAW_NOTIFY_SKYSPY_TELEMETRY  = 0x04,
    RAW_NOTIFY_UNIPWN_DEVICES    = 0x05,
};

#define MESH_RAW_PAYLOAD_MAX 200
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_RAW_NOTIFY
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  kind;                  // MeshRawNotifyKind
    uint16_t seq;                   // monotonic per (node,kind) for ordering
    uint8_t  payload_len;
    uint8_t  payload[MESH_RAW_PAYLOAD_MAX];
} MeshRawNotifyPacket;

// Command relay: primary node -> peers (via ESP-NOW)
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_COMMAND
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  command;               // 0x01=enable, 0x00=disable, 0x0F=disable_all, 0x10=config
    uint8_t  engine_id;
    uint8_t  payload[32];
    uint8_t  payload_len;
    uint8_t  seq;                   // monotonic per-MGR; ACK matches on this
} MeshCommandPacket;

// ACK from a node back to manager when a command is executed.
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_ACK
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  ack_seq;
    uint8_t  ack_cmd;
    uint8_t  ack_engine_id;
    uint8_t  reserved[2];
} MeshAckPacket;

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

#endif
