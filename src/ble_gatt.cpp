/**
 * NimBLE GATT Server implementation.
 *
 * Single service with characteristics for:
 * - Device info (READ)
 * - Engine control (READ, WRITE, NOTIFY)
 * - Detection events (NOTIFY)
 * - Device status (READ, NOTIFY)
 * - GPS receive (WRITE)
 * - Hardware config (READ, WRITE)
 * - Alert config (READ, WRITE)
 * - Foxhunter RSSI (NOTIFY)
 */
#include "ble_gatt.h"
#include "engine_registry.h"
#include <Arduino.h>
#include <Preferences.h>
#include <NimBLEDevice.h>

// Forward declarations
static NimBLEServer* pServer = nullptr;
static NimBLECharacteristic* chrDeviceInfo = nullptr;
static NimBLECharacteristic* chrEngineControl = nullptr;
static NimBLECharacteristic* chrDetectionEvents = nullptr;
static NimBLECharacteristic* chrDeviceStatus = nullptr;
static NimBLECharacteristic* chrGpsReceive = nullptr;
static NimBLECharacteristic* chrHardwareConfig = nullptr;
static NimBLECharacteristic* chrAlertConfig = nullptr;
static NimBLECharacteristic* chrFoxhunterRssi = nullptr;
static NimBLECharacteristic* chrFoxhunterConfig = nullptr;
static NimBLECharacteristic* chrUnipwnCommand = nullptr;

static bool phoneConnected = false;

// ============================================================================
// Server Callbacks (NimBLE 1.4 API)
// ============================================================================
class ServerCallbacks : public NimBLEServerCallbacks {
    void onConnect(NimBLEServer* server) override {
        phoneConnected = true;
        Serial.println("[BLE] Phone connected");
    }

    void onDisconnect(NimBLEServer* server) override {
        phoneConnected = false;
        Serial.println("[BLE] Phone disconnected");
        // Restart advertising
        NimBLEDevice::startAdvertising();
        Serial.println("[BLE] Advertising restarted");
    }
};

// ============================================================================
// Engine Control Write Callback (NimBLE 1.4 API)
// ============================================================================
class EngineControlCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 2) return;

        EngineCommand cmd;
        cmd.command = (uint8_t)val[0];
        cmd.engine_id = (uint8_t)val[1];
        cmd.payload_len = 0;

        if (val.length() > 2) {
            cmd.payload_len = (val.length() - 2 > 64) ? 64 : (val.length() - 2);
            memcpy(cmd.payload, val.data() + 2, cmd.payload_len);
        }

        if (engineCmdQueue != NULL) {
            xQueueSend(engineCmdQueue, &cmd, pdMS_TO_TICKS(10));
        }

        Serial.printf("[BLE] Engine command: %s engine %d\n",
                      cmd.command == 0x01 ? "ENABLE" : "DISABLE",
                      cmd.engine_id);
    }

    void onRead(NimBLECharacteristic* chr) override {
        uint8_t buf[8];
        buf[0] = engineGetAvailableMask();
        buf[1] = engineGetActiveMask();
        for (int i = 0; i < ENGINE_COUNT; i++) {
            buf[2 + i] = (uint8_t)engineGetState((EngineId)i);
        }
        chr->setValue(buf, 8);
    }
};

// ============================================================================
// GPS Receive Write Callback
// ============================================================================
class GpsReceiveCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < sizeof(GpsData)) return;

        GpsData gps;
        memcpy(&gps, val.data(), sizeof(GpsData));
        memcpy((void*)&currentGps, &gps, sizeof(GpsData));
        gpsValid = true;
    }
};

// ============================================================================
// Hardware Config Callbacks
// ============================================================================
class HardwareConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 3) return;

        bool buzzer = val[0] != 0;
        bool led = val[1] != 0;
        uint8_t brightness = (uint8_t)val[2];

        Preferences p;
        p.begin("ouispy-hw", false);
        p.putBool("buzzer", buzzer);
        p.putBool("led", led);
        p.putUChar("neo_brt", brightness);
        p.end();

        Serial.printf("[BLE] Hardware config: buzzer=%d led=%d brightness=%d\n",
                      buzzer, led, brightness);
    }

    void onRead(NimBLECharacteristic* chr) override {
        Preferences p;
        p.begin("ouispy-hw", true);
        uint8_t buf[3];
        buf[0] = p.getBool("buzzer", true) ? 1 : 0;
        buf[1] = p.getBool("led", true) ? 1 : 0;
        buf[2] = p.getUChar("neo_brt", 50);
        p.end();
        chr->setValue(buf, 3);
    }
};

// ============================================================================
// Alert Config Callbacks
// ============================================================================
class AlertConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 8) return;

        const uint8_t* data = (const uint8_t*)val.data();
        uint16_t cooldown   = data[0] | (data[1] << 8);
        uint16_t heartbeat  = data[2] | (data[3] << 8);
        uint16_t rediscover = data[4] | (data[5] << 8);
        uint16_t hbActive   = data[6] | (data[7] << 8);

        Preferences p;
        p.begin("ouispy-alert", false);
        p.putUShort("cooldown", cooldown);
        p.putUShort("heartbeat", heartbeat);
        p.putUShort("rediscover", rediscover);
        p.putUShort("hb_active", hbActive);
        p.end();

        Serial.printf("[BLE] Alert config: cool=%d hb=%d redis=%d active=%d\n",
                      cooldown, heartbeat, rediscover, hbActive);
    }

    void onRead(NimBLECharacteristic* chr) override {
        Preferences p;
        p.begin("ouispy-alert", true);
        uint8_t buf[8];
        uint16_t cool = p.getUShort("cooldown", 5000);
        uint16_t hb   = p.getUShort("heartbeat", 30000);
        uint16_t redis = p.getUShort("rediscover", 30000);
        uint16_t active = p.getUShort("hb_active", 3000);
        p.end();

        buf[0] = cool & 0xFF; buf[1] = (cool >> 8) & 0xFF;
        buf[2] = hb & 0xFF;   buf[3] = (hb >> 8) & 0xFF;
        buf[4] = redis & 0xFF; buf[5] = (redis >> 8) & 0xFF;
        buf[6] = active & 0xFF; buf[7] = (active >> 8) & 0xFF;
        chr->setValue(buf, 8);
    }
};

// ============================================================================
// Foxhunter Config Callback — receive target MAC from app
// ============================================================================
extern void foxhunterSetTarget(const uint8_t* mac);

class FoxhunterConfigCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 6) return;
        foxhunterSetTarget((const uint8_t*)val.data());
        Serial.printf("[BLE] Foxhunter target set via app\n");
    }
};

// ============================================================================
// UniPwn Command Callback — receive exploit commands from app
// ============================================================================
class UnipwnCommandCallbacks : public NimBLECharacteristicCallbacks {
    void onWrite(NimBLECharacteristic* chr) override {
        std::string val = chr->getValue();
        if (val.length() < 8) return;
        // Parse: target_mac[6] command_type[1] payload_len[1] payload[N]
        const uint8_t* data = (const uint8_t*)val.data();
        uint8_t cmdType = data[6];
        uint8_t payloadLen = data[7];
        Serial.printf("[BLE] UniPwn command: type=%d target=%02x:%02x:%02x:%02x:%02x:%02x payload=%d bytes\n",
                      cmdType, data[0], data[1], data[2], data[3], data[4], data[5], payloadLen);
        // UniPwn exploitation requires BLE client mode — queued for engine to process
        // Full exploitation chain not implemented in v3 (requires dedicated BLE client task)
    }
};

// ============================================================================
// Static callback instances
// ============================================================================
static ServerCallbacks serverCb;
static FoxhunterConfigCallbacks foxhunterConfigCb;
static UnipwnCommandCallbacks unipwnCommandCb;
static EngineControlCallbacks engineControlCb;
static GpsReceiveCallbacks gpsReceiveCb;
static HardwareConfigCallbacks hwConfigCb;
static AlertConfigCallbacks alertConfigCb;

// ============================================================================
// Init
// ============================================================================
void bleGattInit(void) {
    Serial.println("[BLE] Initializing NimBLE...");

    NimBLEDevice::init("OUI-SPY");
    NimBLEDevice::setPower(ESP_PWR_LVL_P9);
    NimBLEDevice::setMTU(512);

    pServer = NimBLEDevice::createServer();
    pServer->setCallbacks(&serverCb);

    NimBLEService* svc = pServer->createService(SVC_UUID);

    // -- Device Info (READ) --
    chrDeviceInfo = svc->createCharacteristic(
        CHR_DEVICE_INFO,
        NIMBLE_PROPERTY::READ
    );
    {
        char info[64];
        int len = snprintf(info, sizeof(info), "%s", FW_VERSION);
        len++; // null terminator
        uint8_t mac[6];
        esp_read_mac(mac, ESP_MAC_BT);
        len += snprintf(info + len, sizeof(info) - len, "OUISPY-%02X%02X",
                        mac[4], mac[5]);
        chrDeviceInfo->setValue((uint8_t*)info, len + 1);
    }

    // -- Engine Control (READ, WRITE, NOTIFY) --
    chrEngineControl = svc->createCharacteristic(
        CHR_ENGINE_CONTROL,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
    );
    chrEngineControl->setCallbacks(&engineControlCb);

    // -- Detection Events (NOTIFY) --
    chrDetectionEvents = svc->createCharacteristic(
        CHR_DETECTION_EVENTS,
        NIMBLE_PROPERTY::NOTIFY
    );

    // -- Device Status (READ, NOTIFY) --
    chrDeviceStatus = svc->createCharacteristic(
        CHR_DEVICE_STATUS,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY
    );

    // -- GPS Receive (WRITE, WRITE_NR) --
    chrGpsReceive = svc->createCharacteristic(
        CHR_GPS_RECEIVE,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::WRITE_NR
    );
    chrGpsReceive->setCallbacks(&gpsReceiveCb);

    // -- Hardware Config (READ, WRITE) --
    chrHardwareConfig = svc->createCharacteristic(
        CHR_HARDWARE_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrHardwareConfig->setCallbacks(&hwConfigCb);

    // -- Alert Config (READ, WRITE) --
    chrAlertConfig = svc->createCharacteristic(
        CHR_ALERT_CONFIG,
        NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE
    );
    chrAlertConfig->setCallbacks(&alertConfigCb);

    // -- Foxhunter Config (WRITE) --
    chrFoxhunterConfig = svc->createCharacteristic(
        CHR_FOXHUNTER_CONFIG,
        NIMBLE_PROPERTY::WRITE
    );
    chrFoxhunterConfig->setCallbacks(&foxhunterConfigCb);

    // -- Foxhunter RSSI (NOTIFY) --
    chrFoxhunterRssi = svc->createCharacteristic(
        CHR_FOXHUNTER_RSSI,
        NIMBLE_PROPERTY::NOTIFY
    );

    // -- UniPwn Command (WRITE, NOTIFY) --
    chrUnipwnCommand = svc->createCharacteristic(
        CHR_UNIPWN_COMMAND,
        NIMBLE_PROPERTY::WRITE | NIMBLE_PROPERTY::NOTIFY
    );
    chrUnipwnCommand->setCallbacks(&unipwnCommandCb);

    svc->start();

    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    adv->addServiceUUID(SVC_UUID);
    adv->setScanResponse(true);
    adv->start();

    Serial.println("[BLE] GATT server started, advertising as OUI-SPY");
}

// ============================================================================
// Notifications
// ============================================================================
void bleGattNotifyDetection(const DetectionEvent* evt) {
    if (!phoneConnected || chrDetectionEvents == nullptr) return;

    uint8_t buf[128];
    size_t len = 14;

    // Common header: engine_id[1] mac[6] rssi[1] channel[1] ts_ms[4] method[1]
    buf[0] = evt->engine_id;
    memcpy(buf + 1, evt->mac, 6);
    buf[7] = (uint8_t)evt->rssi;
    buf[8] = evt->channel;
    memcpy(buf + 9, &evt->timestamp_ms, 4);
    buf[13] = evt->method;

    // Engine-specific extension
    switch ((EngineId)evt->engine_id) {
        case ENGINE_FLOCK_BLE:
        case ENGINE_FLOCK_WIFI:
            buf[14] = evt->ext.flock.is_raven;
            memcpy(buf + 15, evt->ext.flock.raven_fw, 16);
            len = 31;
            break;

        case ENGINE_SKYSPY:
            memcpy(buf + 14, evt->ext.odid.uav_id, 21);
            memcpy(buf + 35, evt->ext.odid.op_id, 21);
            memcpy(buf + 56, &evt->ext.odid.drone_lat, 8);
            memcpy(buf + 64, &evt->ext.odid.drone_lon, 8);
            memcpy(buf + 72, &evt->ext.odid.altitude_msl, 2);
            memcpy(buf + 74, &evt->ext.odid.height_agl, 2);
            memcpy(buf + 76, &evt->ext.odid.speed, 2);
            memcpy(buf + 78, &evt->ext.odid.heading, 2);
            memcpy(buf + 80, &evt->ext.odid.pilot_lat, 8);
            memcpy(buf + 88, &evt->ext.odid.pilot_lon, 8);
            len = 96;
            break;

        case ENGINE_UNIPWN:
            memcpy(buf + 14, evt->ext.unipwn.robot_type, 8);
            buf[22] = evt->ext.unipwn.exploited;
            len = 23;
            break;

        case ENGINE_DETECTOR:
            buf[14] = evt->ext.detector.is_full_mac;
            memcpy(buf + 15, evt->ext.detector.filter_desc, 32);
            len = 47;
            break;

        default:
            break;
    }

    chrDetectionEvents->setValue(buf, len);
    chrDetectionEvents->notify();
}

void bleGattNotifyFoxhunterRssi(int8_t rssi, uint16_t intervalMs) {
    if (!phoneConnected || chrFoxhunterRssi == nullptr) return;

    uint8_t buf[3];
    buf[0] = (uint8_t)rssi;
    buf[1] = intervalMs & 0xFF;
    buf[2] = (intervalMs >> 8) & 0xFF;

    chrFoxhunterRssi->setValue(buf, 3);
    chrFoxhunterRssi->notify();
}

void bleGattNotifyEngineState(void) {
    if (!phoneConnected || chrEngineControl == nullptr) return;

    uint8_t buf[8];
    buf[0] = engineGetAvailableMask();
    buf[1] = engineGetActiveMask();
    for (int i = 0; i < ENGINE_COUNT; i++) {
        buf[2 + i] = (uint8_t)engineGetState((EngineId)i);
    }
    chrEngineControl->setValue(buf, 8);
    chrEngineControl->notify();
}

bool bleGattIsConnected(void) {
    return phoneConnected;
}
