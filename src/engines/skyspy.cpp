/**
 * Sky Spy Engine — FAA Remote ID / Open Drone ID detection.
 * BLE scan for ODID advertisements + WiFi promiscuous for NAN/Beacon frames.
 * Ported from raw/skyspy.cpp.
 */
#include "skyspy.h"
#include "protocol.h"
#include "../mesh_espnow.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include "opendroneid.h"
#include "odid_wifi.h"

#define MAX_UAVS 32

static ODID_UAS_Data UAS_data;

struct DroneData {
    uint8_t  mac[6];
    int      rssi;
    uint32_t lastSeen;
    char     uavId[ODID_ID_SIZE + 1];
    char     opId[ODID_ID_SIZE + 1];
    double   lat, lon;
    double   pilotLat, pilotLon;
    int16_t  altMsl, heightAgl, speed, heading;
    bool     active;
};

static DroneData drones[MAX_UAVS];
static NimBLEScan* bleScan = nullptr;
static bool scanning = false;
static unsigned long lastScanStart = 0;

static DroneData* findOrAllocDrone(uint8_t* mac) {
    for (int i = 0; i < MAX_UAVS; i++) {
        if (drones[i].active && memcmp(drones[i].mac, mac, 6) == 0)
            return &drones[i];
    }
    for (int i = 0; i < MAX_UAVS; i++) {
        if (!drones[i].active) return &drones[i];
    }
    return &drones[0]; // Overwrite oldest
}

static void pushDroneDetection(DroneData* d, uint8_t method) {
    DetectionEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.engine_id = ENGINE_SKYSPY;
    memcpy(evt.mac, d->mac, 6);
    evt.rssi = d->rssi;
    evt.channel = 0;
    evt.timestamp_ms = millis();
    evt.method = method;

    strncpy(evt.ext.odid.uav_id, d->uavId, 20);
    strncpy(evt.ext.odid.op_id, d->opId, 20);
    evt.ext.odid.drone_lat = d->lat;
    evt.ext.odid.drone_lon = d->lon;
    evt.ext.odid.altitude_msl = d->altMsl;
    evt.ext.odid.height_agl = d->heightAgl;
    evt.ext.odid.speed = d->speed;
    evt.ext.odid.heading = d->heading;
    evt.ext.odid.pilot_lat = d->pilotLat;
    evt.ext.odid.pilot_lon = d->pilotLon;

    pushDetection(&evt);
}

static void applyOdidData(DroneData* d) {
    if (UAS_data.BasicIDValid[0])
        strncpy(d->uavId, (char*)UAS_data.BasicID[0].UASID, ODID_ID_SIZE);
    if (UAS_data.LocationValid) {
        d->lat = UAS_data.Location.Latitude;
        d->lon = UAS_data.Location.Longitude;
        d->altMsl = (int16_t)UAS_data.Location.AltitudeGeo;
        d->heightAgl = (int16_t)UAS_data.Location.Height;
        d->speed = (int16_t)UAS_data.Location.SpeedHorizontal;
        d->heading = (int16_t)UAS_data.Location.Direction;
    }
    if (UAS_data.SystemValid) {
        d->pilotLat = UAS_data.System.OperatorLatitude;
        d->pilotLon = UAS_data.System.OperatorLongitude;
    }
    if (UAS_data.OperatorIDValid)
        strncpy(d->opId, (char*)UAS_data.OperatorID.OperatorId, ODID_ID_SIZE);
}

// ============================================================================
// BLE Callback — ODID advertisements
// ============================================================================

class SkySkyBLECallback : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        int len = dev->getPayloadLength();
        uint8_t* payload = dev->getPayload();
        if (!payload || len < 6 + (int)sizeof(ODID_BasicID_encoded)) return;

        // ODID BLE signature: 0x16 0xFA 0xFF 0x0D
        if (payload[1] != 0x16 || payload[2] != 0xFA ||
            payload[3] != 0xFF || payload[4] != 0x0D) return;

        uint8_t* odid = &payload[6];
        int odidLen = len - 6;

        memset(&UAS_data, 0, sizeof(UAS_data));
        if ((odid[0] & 0xF0) == (ODID_MESSAGETYPE_PACKED << 4)) {
            odid_message_process_pack(&UAS_data, odid, odidLen);
        } else {
            decodeOpenDroneID(&UAS_data, odid);
        }

        bool useful = UAS_data.BasicIDValid[0] || UAS_data.LocationValid ||
                      UAS_data.SystemValid || UAS_data.OperatorIDValid;
        if (!useful) return;

        const uint8_t* native = dev->getAddress().getNative();
        if (!native) return;
        uint8_t mac[6];
        bleAddrToMac(native, mac);

        DroneData* d = findOrAllocDrone(mac);
        if (!d->active) {
            memset(d, 0, sizeof(*d));
            memcpy(d->mac, mac, 6);
            d->active = true;
        }
        d->lastSeen = millis();
        d->rssi = dev->getRSSI();
        applyOdidData(d);

        pushDroneDetection(d, METHOD_ODID_BLE);

        Serial.printf("[SKYSPY] BLE drone: %s RSSI:%d alt:%dm\n",
                      d->uavId, d->rssi, d->altMsl);
    }
};

static SkySkyBLECallback bleCb;

// ============================================================================
// WiFi Promiscuous Callback — NAN + Beacon ODID frames
// ============================================================================

static void IRAM_ATTR wifiCallback(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (type != WIFI_PKT_MGMT) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* payload = pkt->payload;
    int length = pkt->rx_ctrl.sig_len;

    // NAN Action Frame
    static const uint8_t nanDest[6] = {0x51, 0x6f, 0x9a, 0x01, 0x00, 0x00};
    if (memcmp(nanDest, &payload[4], 6) == 0) {
        char nanMac[6] = {0};
        if (odid_wifi_receive_message_pack_nan_action_frame(&UAS_data, nanMac, payload, length) == 0) {
            DroneData* d = findOrAllocDrone(&payload[10]);
            if (!d->active) {
                memset(d, 0, sizeof(*d));
                memcpy(d->mac, &payload[10], 6);
                d->active = true;
            }
            d->rssi = pkt->rx_ctrl.rssi;
            d->lastSeen = millis();
            applyOdidData(d);
            pushDroneDetection(d, METHOD_ODID_NAN);
        }
        return;
    }

    // Beacon frame with vendor-specific ODID element
    if (payload[0] == 0x80) {
        int offset = 36;
        while (offset < length) {
            int typ = payload[offset];
            int len = payload[offset + 1];
            if (typ == 0xdd && offset + 4 < length &&
                ((payload[offset+2]==0x90 && payload[offset+3]==0x3a && payload[offset+4]==0xe6) ||
                 (payload[offset+2]==0xfa && payload[offset+3]==0x0b && payload[offset+4]==0xbc))) {
                int j = offset + 7;
                if (j < length) {
                    memset(&UAS_data, 0, sizeof(UAS_data));
                    odid_message_process_pack(&UAS_data, &payload[j], length - j);

                    DroneData* d = findOrAllocDrone(&payload[10]);
                    if (!d->active) {
                        memset(d, 0, sizeof(*d));
                        memcpy(d->mac, &payload[10], 6);
                        d->active = true;
                    }
                    d->rssi = pkt->rx_ctrl.rssi;
                    d->lastSeen = millis();
                    applyOdidData(d);
                    pushDroneDetection(d, METHOD_ODID_BEACON);
                }
                return;
            }
            offset += 2 + len;
            if (len == 0) break;
        }
    }
}

// ============================================================================
// Lifecycle
// ============================================================================

static void skyspyInit(void) {
    memset(drones, 0, sizeof(drones));
    bleScan = NimBLEDevice::getScan();
    bleScan->setAdvertisedDeviceCallbacks(&bleCb, true);
    bleScan->setActiveScan(true);
    bleScan->setInterval(100);
    bleScan->setWindow(99);
    Serial.println("[SKYSPY] Initialized");
}

static void skyspyStart(void) {
    if (!meshIsEnabled()) {
        WiFi.mode(WIFI_STA);
    }
    // MGMT only — ODID (NAN/Beacon) travels in mgmt frames; DATA/CTRL would
    // bury the callback in irrelevant traffic and miss drone beacons.
    wifi_promiscuous_filter_t filter = {
        .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT
    };
    esp_wifi_set_promiscuous_filter(&filter);
    esp_wifi_set_promiscuous(true);
    esp_wifi_set_promiscuous_rx_cb(wifiCallback);
    esp_wifi_set_channel(6, WIFI_SECOND_CHAN_NONE);

    scanning = true;
    lastScanStart = 0;
    Serial.println("[SKYSPY] Started (BLE + WiFi ch6)");
}

static void skyspyStop(void) {
    if (bleScan && bleScan->isScanning()) bleScan->stop();
    esp_wifi_set_promiscuous(false);
    if (meshIsEnabled()) {
        esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    }
    scanning = false;
    Serial.println("[SKYSPY] Stopped");
}

static void skyspyLoop(void) {
    if (!scanning || !bleScan) return;

    // BLE scan cycle
    if (millis() - lastScanStart >= 1500) {
        if (!bleScan->isScanning()) {
            bleScan->start(1, false);
            lastScanStart = millis();
        }
    }

    // Expire old drones (30s timeout)
    for (int i = 0; i < MAX_UAVS; i++) {
        if (drones[i].active && millis() - drones[i].lastSeen > 30000) {
            drones[i].active = false;
        }
    }
}

const EngineCallbacks skyspyCallbacks = {
    .init   = skyspyInit,
    .start  = skyspyStart,
    .stop   = skyspyStop,
    .loop   = skyspyLoop,
    .config = NULL,
    .name   = "Sky Spy"
};
