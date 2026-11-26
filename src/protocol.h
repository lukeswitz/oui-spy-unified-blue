// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

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

// Hardware pins (XIAO ESP32-S3 defaults; per-board override via -DPIN_*)
#ifndef PIN_BUZZER
#define PIN_BUZZER     3
#endif
#ifndef PIN_LED
#define PIN_LED        21    // Onboard LED, active LOW
#endif
#ifndef PIN_NEOPIXEL
#define PIN_NEOPIXEL   4     // WS2812B data
#endif
#ifndef PIN_GPS_RX
#define PIN_GPS_RX     44    // Optional hardware GPS
#endif
#ifndef PIN_GPS_TX
#define PIN_GPS_TX     43
#endif

// Firmware version
#ifndef FW_VERSION
#define FW_VERSION     "0.7.0"
#endif
#ifndef FW_VERSION_NUM
#define FW_VERSION_NUM 0x000700
#endif

#ifndef OUISPY_BOARD
  #define OUISPY_BOARD "unknown"
#endif

enum EngineId : uint8_t {
    ENGINE_DETECTOR   = 0,  // bitmask 0x01
    ENGINE_FLOCK_BLE  = 1,  // bitmask 0x02
    ENGINE_FLOCK_WIFI = 2,  // bitmask 0x04
    ENGINE_FOXHUNTER  = 3,  // bitmask 0x08
    ENGINE_SKYSPY     = 4,  // bitmask 0x10
    ENGINE_UNIPWN     = 5,  // bitmask 0x20
    ENGINE_WARDRIVE   = 6,  // bitmask 0x40
    ENGINE_PCAP       = 7,  // bitmask 0x80
    ENGINE_AXEOFF     = 8,  // ext mask bit 0x01 (mask16 0x100)
    ENGINE_BLESNIFF   = 9,  // ext mask bit 0x02 (mask16 0x200)
    ENGINE_COUNT      = 10
};

// Engines 0-7 keep their 8-bit wire masks; engines 8+ ride in a second "ext" byte appended after them.
#define ENGINE_COUNT_V1 8
#define ENGINE_BITMASK(id) (1 << (id))
#define ENGINE_MASK_LO(m16) ((uint8_t)((m16) & 0xFF))
#define ENGINE_MASK_EXT(m16) ((uint8_t)(((m16) >> 8) & 0xFF))

static const bool kEngineTargetable[ENGINE_COUNT] = {
    false,
    false,
    false,
    true,
    false,
    true,
    false,
    true,
    false,
    true,
};

#define CFG_TGT_PREFIX   0xFE
#define CFG_TGT_OVERHEAD 6

#define NODE_CTL_IDENTIFY 0x20
#define NODE_CTL_LOCATE   0x21
#define NODE_CTL_REBOOT   0x22
#define NODE_CTL_STATUS   0x23
#define NODE_CTL_SETCHAN  0x24
#define NODE_CTL_IDENT_BEEP  0x01
#define NODE_CTL_IDENT_LIGHT 0x02
#define NODE_LOCATE_MAX_MS   1800000UL

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

#define METHOD_OUI_ADDR1       0
#define METHOD_OUI_ADDR2       1
#define METHOD_OUI_ADDR3       2
#define METHOD_SSID            3
#define METHOD_WILDCARD_PROBE  4
#define METHOD_WILDCARD_PROBE_IE_SIG 5

// Flock-BLE methods
#define METHOD_OUI_MATCH       0
#define METHOD_NAME_MATCH      1
#define METHOD_MFG_ID          2
#define METHOD_RAVEN_UUID      3
#define METHOD_GATT_UUID       4
#define METHOD_NORDIC_DFU      5

#define FLOCK_SIG_OUI          0x01
#define FLOCK_SIG_NAME         0x02
#define FLOCK_SIG_SERIAL       0x04
#define FLOCK_SIG_MFG          0x08
#define FLOCK_SIG_TN           0x10
#define FLOCK_SIG_RAVEN_UUID   0x20
#define FLOCK_SIG_GATT         0x40
#define FLOCK_SIG_DFU          0x80
#define FLOCK_SIG_VALIDATED    (FLOCK_SIG_SERIAL | FLOCK_SIG_MFG | FLOCK_SIG_TN)

// Sky Spy methods
#define METHOD_ODID_BLE        0
#define METHOD_ODID_NAN        1
#define METHOD_ODID_BEACON     2
#define METHOD_ODID_VENDOR     3

// Wardrive methods
#define METHOD_WIFI_AP         0
#define METHOD_BLE_ADV         1
#define METHOD_WIFI_CLIENT     2
#define METHOD_802154          3   // channel = 802.15.4 ch 11-26, mac = source key, ssid = Thread name, adv = see engines/ieee802154_frame.h zb154PackAdv

#define WARDRIVE_RADIO_WIFI    0x01
#define WARDRIVE_RADIO_BLE     0x02
#define WARDRIVE_RADIO_802154  0x04

// Detector methods
#define METHOD_DET_BLE_WATCH   0
#define METHOD_DET_WIFI_WATCH  1
#define METHOD_DET_TRACKER     2
#define METHOD_DET_FLIPPER     3
#define METHOD_DET_DEAUTH      4
#define METHOD_DET_PROBE       5
#define METHOD_DET_PWNAGOTCHI  6
#define METHOD_DET_GLASSES     7
#define METHOD_DET_AXON        8
#define METHOD_DET_CAMERA      9
#define METHOD_DET_AMAZON      10
#define METHOD_DET_EVILTWIN    11
#define METHOD_DET_KARMA       12
#define METHOD_DET_MESH        13
#define METHOD_DET_JOINFLOOD   14
#define METHOD_DET_TAGFLOOD    15
#define METHOD_DET_BEACONFLOOD 16
#define METHOD_DET_WEARABLE    17
#define METHOD_DET_VEHICLE     18
#define METHOD_DET_DRONE       19

// Detector rule types: the extension section of a detector list and BLE DetectorConfig op 0x05 [type][len][payload]
#define DET_RULE_NAME_CONTAINS 0x01  // payload: 1-18 printable chars, case-insensitive substring of the BLE name
#define DET_RULE_NAME_PREFIX   0x02  // payload: 1-18 printable chars, case-insensitive start of the BLE name
#define DET_RULE_NAME_PATTERN  0x03  // payload: 1-18 chars, whole name; # hex digit, ? any char, * any run
#define DET_RULE_COMPANY_ID    0x04  // payload: u16 LE company id
#define DET_RULE_COMPANY_DATA  0x05  // payload: u16 LE company id, k data bytes, k mask bytes (1 <= k <= 8)
#define DET_RULE_UUID128       0x06  // payload: 16 bytes in advertisement byte order (reverse of the written form)
#define DET_RULE_WIFI_PROBE    0x07  // payload: 3-6 byte source address prefix of a probe or association request
#define DET_RULE_WIFI_BEACON   0x08  // payload: 3-6 byte source address prefix of a beacon or probe response
#define DET_RULE_PAYLOAD_MAX   18
#define DET_EXT_MAX            32
#define DETCFG_OP_RULE         0x05
#define DETCFG_OP_NODE_FILTER  0x06  // manager only: [0x06][op][target:4, zeros = every node][data]; op is MESH_FOP_*
#define DET_REC_MAC            0x10  // filter edit and report record: payload [prefixLen][prefixLen address bytes]
#define DET_REC_UUID16         0x11  // filter edit and report record: payload u16 LE
// Records in a filter edit and a node's list are [kind][len][payload]; kinds 0x01-0x08 are the DET_RULE_* types.

#define SIG_TRACKER    0x01
#define SIG_FLIPPER    0x02
#define SIG_DEAUTH     0x04
#define SIG_PROBE      0x08
#define SIG_PWNAGOTCHI 0x10
#define SIG_GLASSES    0x20
#define SIG_AXON       0x40
#define SIG_CAMERA     0x80
#define SIG_MESH       0x100
#define SIG_BEACONFLOOD 0x200
#define SIG_WEARABLE   0x400
#define SIG_VEHICLE    0x800
#define SIG_DRONE      0x1000
#define SIG_ALL        0x1FFF

#define OUISPY_BLE_PROTO_VERSION 2

#define DET_CONF_NONE      0
#define DET_CONF_SUSPECTED 1
#define DET_CONF_HIGH      2
#define DET_CONF_VERIFIED  3

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
            char    name[32];
            uint8_t sig_mask;
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
            char     self_id[24];
            int16_t  altitude_baro;
            int16_t  vert_speed;
            int16_t  operator_alt;
            uint16_t area_count;
            uint16_t area_radius;
            int16_t  area_ceiling;
            int16_t  area_floor;
            uint16_t loc_timestamp;
            uint8_t  ua_type;
            uint8_t  id_type;
            uint8_t  op_id_type;
            uint8_t  op_location_type;
            uint8_t  classification;
            uint8_t  category_eu;
            uint8_t  class_eu;
            uint8_t  height_type;
            uint8_t  status;
            uint8_t  horiz_acc;
            uint8_t  vert_acc;
            uint8_t  baro_acc;
            uint8_t  speed_acc;
            uint8_t  self_id_type;
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
            uint8_t confidence;
        } detector;

        // Foxhunter (RSSI sent separately via dedicated characteristic)
        struct {
            uint8_t _reserved;
        } foxhunter;

        // Wardrive (WiGLE-style capture)
        struct {
            char    ssid[33];
            uint8_t auth_mode;     // 0=open,1=WEP,2=WPA,3=WPA2,4=WPA_WPA2,5=WPA2_ENT,6=WPA3,7=WPA2_WPA3,8=OWE,9=WPA3_ENT,0xFF=unknown
            char    device_name[21];
            uint8_t adv_len;
            uint8_t adv[62];
            uint8_t ap_bssid[6];
        } wardrive;
    } ext;
} DetectionEvent;

#ifdef __cplusplus
static_assert(sizeof(DetectionEvent) == 163, "DetectionEvent size is part of queue/spool/mesh layout");
#endif

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

typedef struct {
    uint8_t  command;       // 0x01=enable, 0x00=disable, 0x10=config_update, 0x1A=wifi_band
    uint8_t  engine_id;
    uint8_t  payload[64];
    uint8_t  payload_len;
} EngineCommand;

#define ENGINE_CTRL_WIFI_BAND 0x1A

extern QueueHandle_t detectionQueue;   // DetectionEvent, depth 128
extern QueueHandle_t engineCmdQueue;   // EngineCommand, depth 8

extern volatile GpsData currentGps;
extern volatile bool    gpsValid;

extern volatile bool    hwBuzzerEnabled;
extern volatile uint8_t hwBuzzerVolume;      // 0-255 PWM duty cycle
extern volatile bool    hwLedEnabled;
extern volatile uint8_t hwNeopixelBrightness;
extern volatile bool    hwAlertsSuppressed;  // set by phone (inside geofence) / relayed from manager

#define MELODY_MAX_NOTES      8
#define MELODY_MAX_ENTRIES    24
#define MELODY_ANY            0xFF
#define MELODY_ENGINE_AXON    0xFE
#define MELODY_AXON_HEARTBEAT 1
#define MELODY_AXON_LOST      2
#define MELODY_OP_SET         0x01
#define MELODY_OP_CLEAR       0x02
#define MELODY_OP_CLEAR_ALL   0x03
#define MELODY_OP_PREVIEW     0x04
#define MELODY_OP_SYNC        0x05
typedef struct __attribute__((packed)) {
    uint8_t engine;
    uint8_t method;
    uint8_t n;
    uint8_t notes[MELODY_MAX_NOTES][3];
} MelodyEntry;
void   melodyInit(void);
void   melodyApply(const uint8_t* data, size_t len);
void   melodyPreview(const uint8_t* data, size_t len);
size_t melodyGetEntryOp(uint8_t idx, uint8_t* out);
uint8_t melodyCount(void);
bool   melodyLookup(uint8_t engine, uint8_t method, uint8_t* n, uint8_t notes[][3]);

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
#define CHR_MELODY           "00000025-" UUID_BASE
// PCAP engine
#define CHR_PCAP_CONTROL     "00000160-" UUID_BASE
#define CHR_PCAP_STATS       "00000161-" UUID_BASE
#define CHR_PCAP_DATA        "00000162-" UUID_BASE
#define CHR_DETECTOR_CONFIG  "00000100-" UUID_BASE

#define SYS_CMD_REBOOT            0x01
#define SYS_CMD_FACTORY_RESET     0x02
#define SYS_CMD_CONFIRM_OTA       0x03
#define SYS_CMD_OTA_VIA_WIFI      0x04
#define SYS_CMD_FLEET_OTA         0x05
#define SYS_CMD_WIFI_DISCONNECT   0x06
#define SYS_CMD_WIFI_WIPE         0x07
#define SYS_OP_FLEET_PROGRESS     0x08
#define SYS_CMD_FLEET_WIFI_OTA    0x0A
#define SYS_CMD_FLUSH_SPOOL       0x0B
#define SYS_CMD_SPOOL_CLEAR       0x0C
#define SYS_CMD_RING_TRACKER      0x0E
#define SYS_CMD_ENOW_HUB          0x0F
#define SYS_OP_ENOW_NODE          0x10
#define SYS_OP_ENOW_FRAME         0x11
#define SYS_CMD_WD_LOG_SEND       0x12
#define SYS_OP_WD_LOG             0x12
#define SYS_CMD_WD_LOG_CLEAR      0x13
#define SYS_CMD_SET_BLE_PIN       0x14
#define SYS_CMD_MESH_FW           0x15
#define SYS_OP_MESH_FW            0x15
#define MESH_FW_SUB_SEND          0x01
#define MESH_FW_SUB_STOP          0x02
#define MESH_FW_SUB_STATUS        0x03
#define MESH_FW_EV_STAGED         0x00
#define MESH_FW_EV_NODE_BEGIN     0x01
#define MESH_FW_EV_NODE_PROGRESS  0x02
#define MESH_FW_EV_NODE_DONE      0x03
#define MESH_FW_EV_NODE_FAIL      0x04
#define MESH_FW_EV_RUN_END        0x05
#define MESH_FW_FAIL_NO_IMAGE     0x01
#define MESH_FW_FAIL_BUSY         0x02
#define MESH_FW_FAIL_NO_ANSWER    0x03
#define MESH_FW_FAIL_REFUSED      0x04
#define MESH_FW_FAIL_STALLED      0x05
#define MESH_FW_FAIL_STOPPED      0x06
#define MESH_FW_FAIL_ARGS         0x07
#define MESH_FW_MAX_TARGETS       8
#define OTA_DFU_FLAG_STAGE_MESH   0x01
#define OTA_DFU_ST_STAGED         0xFE
#define OTA_DFU_ST_STAGE_REFUSED  0x0A
#define WD_LOG_FRAME_HEADER       0x00
#define WD_LOG_FRAME_ROW          0x01
#define WD_LOG_FRAME_END          0x02

#define PCAP_MODE_WIFI 0
#define PCAP_MODE_BLE  1
#define PCAP_MODE_802154 2  // C5 only. beacon_count=beacons, data_count=data, ctrl_count=acks, mgmt_other_count=MAC commands+other

#define PCAP_SRC_PCAP    0  // PcapStats.src: the PCAP engine
#define PCAP_SRC_BLESNIFF 1 // PcapStats.src: the BLE Sniff engine (live advert feed, app writes the file only when asked)

typedef struct __attribute__((packed)) {
    uint8_t  state;             // 0=idle, 1=capturing, 2=full, 3=error
    uint8_t  mode;              // PCAP_MODE_WIFI / PCAP_MODE_BLE / PCAP_MODE_802154
    uint8_t  current_channel;   // wifi: current hop channel  ble: last seen primary adv chan
    uint8_t  _reserved;         // PCAP_SRC_*
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
#define PCAP_CTRL_PAUSE          0x04  // stop appending frames, keep radio up
#define PCAP_CTRL_RESUME         0x05  // resume appending after a pause
#define PCAP_CTRL_DOWNLOAD       0x10  // begin download via CHR_PCAP_DATA notifies
#define PCAP_CTRL_DOWNLOAD_ABORT 0x11

// PCAP data chunk opcodes (notified on CHR_PCAP_DATA)
#define PCAP_DATA_START          0x01  // [op][len:4 LE][crc32:4 LE]
#define PCAP_DATA_CHUNK          0x02  // [op][seq:2 LE][payload]
#define PCAP_DATA_COMMIT         0x03  // [op]
#define PCAP_DATA_ABORT          0x04  // [op][reason:1]

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
    uint32_t key_failures;
} MeshStatus;

typedef struct __attribute__((packed)) {
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  engine_id;
    uint8_t  mac[6];
    int8_t   rssi;
    uint8_t  channel;
    uint32_t timestamp_ms;
    uint8_t  method;
    uint8_t  ext_data[152];
    uint8_t  ext_len;
} MeshDetectionPacket;

#define DET_FLAG_AWAY 0x80

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
    MESH_PKT_CONFIG          = 0x0B,
    MESH_PKT_DETECTORLIST    = 0x0C,
    MESH_PKT_OTA_BEGIN       = 0x0D,
    MESH_PKT_OTA_DATA        = 0x0E,
    MESH_PKT_OTA_END         = 0x0F,
    MESH_PKT_OTA_ACK         = 0x10,
    MESH_PKT_DETECTION_BATCH = 0x11,
    MESH_PKT_WIFI_OTA        = 0x12,
    MESH_PKT_NODE_INFO       = 0x13,
    MESH_PKT_DETECTION_BATCH_IE = 0x14,
    MESH_PKT_NODE_STATUS     = 0x15,
    MESH_PKT_FILTER_ACK      = 0x16,
    MESH_PKT_OTA_ABORT       = 0x17,
    MESH_PKT_FILTER_OP       = 0x18,
    MESH_PKT_FILTER_RESULT   = 0x19,
    MESH_PKT_FILTER_REPORT   = 0x1A,
    MESH_PKT_ENGINE_EXT      = 0x1B,
    MESH_PKT_CHAN_SET        = 0x1C,
    MESH_PKT_CHAN_ACK        = 0x1D,
};

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_ENGINE_EXT (node -> manager, sent after each heartbeat; older firmware ignores it)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  active_ext;            // engines 8+: bit0 = AXEOFF, bit1 = BLE Sniff
} MeshEngineExtPacket;

#define MESH_CHAN_PREPARE 1
#define MESH_CHAN_COMMIT  2
#define MESH_CHAN_CANCEL  3

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_CHAN_SET (manager -> nodes)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  epoch;                 // nonzero, same for every frame of one change
    uint8_t  phase;                 // MESH_CHAN_*
    uint8_t  channel;               // new mesh channel, 1-11
    uint16_t countdown_ms;          // COMMIT: ms from this frame until the switch
} MeshChanSetPacket;

#define MESH_CHAN_ACK_PREPARED 0
#define MESH_CHAN_ACK_ALREADY  1

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_CHAN_ACK (node -> manager, answers PREPARE)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  epoch;
    uint8_t  channel;
    uint8_t  status;                // MESH_CHAN_ACK_*
} MeshChanAckPacket;

#define MESH_FILTER_ACCEPTED           0
#define MESH_FILTER_REFUSED_NO_ENGINE  1
#define MESH_FILTER_REFUSED_DENIED     2
#define MESH_FILTER_REFUSED_FULL       3
#define MESH_FILTER_REFUSED_UNSUPPORTED 4   // every row needs a radio the node has turned off
#define MESH_FILTER_REFUSED_INVALID    5

#define MESH_FOP_ADD    1   // data: records to add
#define MESH_FOP_DEL    2   // data: records to remove
#define MESH_FOP_CLEAR  3   // data: none
#define MESH_FOP_PRESET 4   // data: preset id (see engines/detector_presets.h)
#define MESH_FOP_GET    5   // data: none; the node answers with a result and then its list in report pages
#define MESH_FILTEROP_MAX      100
#define MESH_FILTERREPORT_MAX  100
#define SYS_OP_NODE_FILTERS    0x16  // manager -> phone notify: [0x16][id:2][op seq][page][pages][records]

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_FILTER_OP (manager -> nodes)
    char     source_node_id[MESH_NODE_ID_LEN];
    char     target_node_id[MESH_NODE_ID_LEN];  // first byte 0 = every node
    uint8_t  op;                    // MESH_FOP_*
    uint8_t  seq;                   // nonzero; answers carry it back
    uint8_t  len;
    uint8_t  data[MESH_FILTEROP_MAX];
} MeshFilterOpPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_FILTER_RESULT (node -> manager, answers MESH_PKT_FILTER_OP)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  op_seq;
    uint8_t  status;                // MESH_FILTER_*
    uint8_t  filter_macs;
    uint8_t  filter_uuids;
    uint8_t  filter_rules;
    uint8_t  changed;               // rows added, removed or cleared
    uint8_t  skipped;               // rows it could not match or hold
} MeshFilterResultPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_FILTER_REPORT (node -> manager, one page of a node's list after MESH_FOP_GET)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  op_seq;
    uint8_t  page;
    uint8_t  pages;
    uint8_t  len;
    uint8_t  data[MESH_FILTERREPORT_MAX];
} MeshFilterReportPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_FILTER_ACK (node -> manager, answers a detector-list push)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  push_seq;              // trailer byte of the DETECTORLIST packet being answered
    uint8_t  status;                // MESH_FILTER_*
    uint8_t  filter_macs;           // MAC/OUI filters the node holds after applying
    uint8_t  filter_uuids;          // service-UUID filters the node holds after applying
} MeshFilterAckPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  board;
    int8_t   temp_c;
} MeshNodeInfoPacket;

// MESH_PKT_NODE_INFO may carry a neighbor table after temp_c: [count:1] then count x [id:2 binary, rssi:1].
#define MESH_NBR_MAX 12
#define MESH_NBR_ENTRY 3
#define MESH_RSSI_UNKNOWN ((int8_t)-128)

static inline bool meshIdToBytes(const char* id, uint8_t out[2]) {
    for (int i = 0; i < 2; i++) {
        int v = 0;
        for (int j = 0; j < 2; j++) {
            char c = id[i * 2 + j];
            int d = (c >= '0' && c <= '9') ? c - '0'
                  : (c >= 'A' && c <= 'F') ? c - 'A' + 10
                  : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
            if (d < 0) return false;
            v = (v << 4) | d;
        }
        out[i] = (uint8_t)v;
    }
    return true;
}

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_NODE_STATUS (node -> manager, answers NODE_CTL_STATUS)
    char     source_node_id[MESH_NODE_ID_LEN];
    uint32_t fw_version;
    uint32_t uptime_s;
    uint8_t  board;
    uint8_t  filter_macs;           // detector MAC/OUI filters held
    uint8_t  filter_uuids;          // detector service-UUID filters held
    uint8_t  peer_count;            // mesh peers this node currently hears
    uint8_t  reply_seq;             // seq of the request this answers
} MeshNodeStatusPacket;

#define OUISPY_TEMP_UNKNOWN ((int8_t)-128)

static const char* const kOuispyBoards[] = {
    "", "xiao_s3", "s3_devkitc", "xiao_c5", "tdongle_s3", "tdongle_c5",
    "stickc", "stickc_plus", "stickc_plus2", "xiao_c3", "wroom",
};

static inline uint8_t ouispyBoardCode(void) {
    for (uint8_t i = 1; i < sizeof(kOuispyBoards) / sizeof(kOuispyBoards[0]); i++)
        if (strcmp(kOuispyBoards[i], OUISPY_BOARD) == 0) return i;
    return 0;
}

#define MESH_DET_REC_NAME_MAX  32
#define MESH_DET_REC_IE_MAX    30
#define MESH_DET_REC_ADV_MAX   31
#define MESH_DET_BATCH_BUDGET  215
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;                          // MESH_PKT_DETECTION_BATCH
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  count;
    uint8_t  data[MESH_DET_BATCH_BUDGET];
} MeshDetectionBatchPacket;

#define MESH_IGNORELIST_MAX 220
// MESH_PKT_DETECTORLIST may carry one extra byte after data[len]: a nonzero push_seq asks nodes to answer with MeshFilterAckPacket.
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  len;
    uint8_t  data[MESH_IGNORELIST_MAX];
} MeshIgnoreListPacket;

// Device-wide config relay: manager -> all nodes (node mode overrides per-node).
#define MESH_CFG_KIND_HW    1   // hardware: buzzer/led/neopixel
#define MESH_CFG_KIND_ALERT 2   // alert timing: cooldown/heartbeat/rediscover
#define MESH_CFG_KIND_AUTOPCAP 3
#define MESH_CFG_KIND_FOXHUNTER 4
#define MESH_CFG_KIND_ENGINE 5
#define MESH_CFG_KIND_SIGMASK 6
#define MESH_CFG_KIND_WIFIBAND 7   // data[0] = WIFI_BAND_* mask (bit0=2.4, bit1=5)
#define MESH_CFG_KIND_MELODY 8
// MESH_CFG_KIND_ENGINE data: [mask lo][ver lo][ver hi] and, from this build on, [mask ext] (engines 8+); older nodes ignore the 4th byte.
#define MESH_CONFIG_MAX     32
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;          // MESH_PKT_CONFIG
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  cfg_kind;          // MESH_CFG_KIND_*
    uint8_t  len;
    uint8_t  data[MESH_CONFIG_MAX];
} MeshConfigPacket;

#define MESH_WIFIOTA_MAX 220
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;          // MESH_PKT_WIFI_OTA
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  len;
    uint8_t  data[MESH_WIFIOTA_MAX];
} MeshWifiOtaPacket;

#define MESH_ROLE_NODE     0
#define MESH_ROLE_MANAGER  1

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint32_t uptime_s;
    uint32_t free_heap;
    uint8_t  role;
    uint8_t  active_engines_mask;
    uint8_t  alerts_suppressed;
    uint32_t fw_version;
    uint8_t  phone_connected;
} MeshHeartbeatPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;
    char     source_node_id[MESH_NODE_ID_LEN];
    uint8_t  trigger_src;
    uint8_t  trigger_mac[6];
    uint8_t  channel;
    uint16_t duration_sec;
    uint8_t  paused_mask;
    uint8_t  mode;
} MeshAutoPcapEventPacket;

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

#define MESH_OTA_CHUNK_MAX 192   // payload bytes/chunk (plaintext+GCM fits ESP-NOW 250B)

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_OTA_BEGIN
    char     source_node_id[MESH_NODE_ID_LEN];  // manager id
    uint32_t total_size;           // node image bytes
    uint32_t crc32;                // CRC32 (IEEE) of full image
    uint32_t fw_version_num;       // target version (heartbeat confirm)
    uint16_t total_chunks;
} MeshOtaBeginPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_OTA_DATA
    char     source_node_id[MESH_NODE_ID_LEN];  // manager id
    uint16_t seq;                  // chunk index 0..total_chunks-1
    uint8_t  len;                  // payload bytes this chunk
    uint8_t  payload[MESH_OTA_CHUNK_MAX];
} MeshOtaDataPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_OTA_END
    char     source_node_id[MESH_NODE_ID_LEN];  // manager id
    uint32_t crc32;
} MeshOtaEndPacket;

// node -> manager: progress + resume request
#define MESH_OTA_ST_READY     0
#define MESH_OTA_ST_RECEIVING 1
#define MESH_OTA_ST_RESUME    2   // next_needed_seq points at first gap
#define MESH_OTA_ST_DONE      3
#define MESH_OTA_ST_ERR       0x80
typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_OTA_ACK
    char     source_node_id[MESH_NODE_ID_LEN];  // node id
    uint8_t  status;               // MESH_OTA_ST_*
    uint16_t next_needed_seq;      // first missing chunk (resume)
    uint16_t recv_count;           // chunks written so far (progress)
} MeshOtaAckPacket;

typedef struct __attribute__((packed)) {
    MeshOtaBeginPacket begin;       // pkt_type MESH_PKT_OTA_BEGIN; only target_node_id accepts it
    char     target_node_id[MESH_NODE_ID_LEN];
} MeshOtaTargetBeginPacket;

typedef struct __attribute__((packed)) {
    uint8_t  pkt_type;              // MESH_PKT_OTA_ABORT (manager -> node)
    char     source_node_id[MESH_NODE_ID_LEN];  // manager id
    char     target_node_id[MESH_NODE_ID_LEN];  // node that drops its transfer and restarts
} MeshOtaAbortPacket;

#define CHR_MESH_CONFIG      "00000060-" UUID_BASE
#define CHR_MESH_STATUS      "00000061-" UUID_BASE
#define CHR_ORCHESTRATION    "00000070-" UUID_BASE

extern volatile MeshConfig meshCurrentConfig;
extern volatile MeshStatus meshCurrentStatus;

// Ring buffer for peer status notifications (forwarded to BLE)
#define MESH_PEER_STATUS_QUEUE_DEPTH 4
extern QueueHandle_t peerStatusQueue;  // MeshStatusPacket, depth 4

#if defined(OUISPY_ENGINE_DIAG) || defined(OUISPY_ENGINE_MATRIX)
extern volatile uint32_t g_diagDetCount[ENGINE_COUNT];
#endif

extern uint16_t g_detQueueDepth;

static inline uint16_t detqIsrReserve(void) { return (uint16_t)(g_detQueueDepth * 3 / 16); }

static inline bool pushDetection(const DetectionEvent* evt) {
    if (detectionQueue == NULL) return false;
#if defined(OUISPY_ENGINE_DIAG) || defined(OUISPY_ENGINE_MATRIX)
    if (evt && evt->engine_id < ENGINE_COUNT) g_diagDetCount[evt->engine_id]++;
#endif
#ifndef OUISPY_ROLE_MANAGER
    if (uxQueueSpacesAvailable(detectionQueue) <= detqIsrReserve()) return false;
#endif
    return xQueueSend(detectionQueue, evt, pdMS_TO_TICKS(2)) == pdTRUE;
}

/// Stamp a DetectionEvent with current GPS from phone app.
static inline void stampGps(DetectionEvent* evt) {
    (void)evt; // GPS fields not in DetectionEvent struct — stamped by app side
}

static inline bool pushDetectionFromISR(const DetectionEvent* evt) {
    if (detectionQueue == NULL) return false;
#if defined(OUISPY_ENGINE_DIAG) || defined(OUISPY_ENGINE_MATRIX)
    if (evt && evt->engine_id < ENGINE_COUNT) g_diagDetCount[evt->engine_id]++;
#endif
    BaseType_t wake = pdFALSE;
    bool ok = xQueueSendFromISR(detectionQueue, evt, &wake) == pdTRUE;
    if (wake) portYIELD_FROM_ISR();
    return ok;
}

#endif
