#include "flock_wifi.h"
#include "protocol.h"
#include "flock_oui.h"
#include "dedup_ring.h"
#include "../engine_registry.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <string.h>

// Flock Wi-Fi cams known to operate on standard ISM channels only.
static const uint8_t channels[] = {1, 6, 11};
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 350;

static volatile bool scanning = false;

// 64-slot dedup ring (bumped from 16: phones flood OUI matches).
static DedupRingISR<64, 5000> wifiDedup;

// Wildcard probe template (broadcast PROBE_REQ, empty SSID).
// Elicits PROBE_RESP from APs immediately on channel hop, faster than
// waiting for beacon interval (~102.4 ms).
static const uint8_t wildcardProbeTpl[] = {
    0x40, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    0x00, 0x00,
    0x00, 0x00,
    0x01, 0x04, 0x82, 0x84, 0x8B, 0x96,
};

static void sendWildcardProbe() {
    uint8_t probe[sizeof(wildcardProbeTpl)];
    memcpy(probe, wildcardProbeTpl, sizeof(probe));
    probe[10] = 0x02 | (esp_random() & 0xFE);
    for (int i = 11; i < 16; i++) probe[i] = esp_random() & 0xFF;
    esp_wifi_80211_tx(WIFI_IF_STA, probe, sizeof(probe), false);
}

static void IRAM_ATTR wifiSnifferCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!scanning) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    uint8_t frameType = (p[0] >> 2) & 0x03;
    uint8_t frameSubtype = (p[0] >> 4) & 0x0F;

    const uint8_t* addr1 = &p[4];
    const uint8_t* addr2 = &p[10];
    const uint8_t* addr3 = &p[16];

    uint8_t method = 0xFF;
    const uint8_t* matchMac = NULL;

    if (flockMatchOuiISR(addr2)) {
        method = METHOD_OUI_ADDR2;
        matchMac = addr2;
        if (frameType == 0 && frameSubtype == 4) {
            int bodyOff = 24;
            int bodyLen = len - bodyOff;
            const uint8_t* body = p + bodyOff;
            int r = (bodyLen > 0) ? isWildcardProbeIE(body, bodyLen) : -1;
            if (r == -1 && bodyLen > 4) r = isWildcardProbeIE(body, bodyLen - 4);
            if (r == 1) method = METHOD_WILDCARD_PROBE;
        }
    } else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
        method = METHOD_OUI_ADDR1;
        matchMac = addr1;
    } else if (frameType == 0 && flockMatchOuiISR(addr3)) {
        method = METHOD_OUI_ADDR3;
        matchMac = addr3;
    }

    if (method == 0xFF || !matchMac) return;
    if (wifiDedup.check(matchMac)) return;

    DetectionEvent evt = {};
    evt.engine_id = ENGINE_FLOCK_WIFI;
    memcpy(evt.mac, matchMac, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = method;
    pushDetectionFromISR(&evt);
}

static void flockWifiInit(void) {
    wifiDedup.reset();
    channelIdx = 0;
    flockOuiInitBuckets();
    Serial.println("[FLOCK-WIFI] Initialized");
}

static void flockWifiStart(void) {
    scanning = true;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) {
        Serial.println("[FLOCK-WIFI] Started (passive — wardrive handles WiFi scan)");
        return;
    }
    WiFi.mode(WIFI_STA);
    wifi_promiscuous_filter_t filter = {
        .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT |
                       WIFI_PROMIS_FILTER_MASK_DATA
    };
    esp_wifi_set_promiscuous_filter(&filter);
    esp_wifi_set_promiscuous(true);
    esp_wifi_set_promiscuous_rx_cb(wifiSnifferCb);
    esp_wifi_set_channel(channels[0], WIFI_SECOND_CHAN_NONE);
    lastChannelHop = millis();
    sendWildcardProbe();
    Serial.println("[FLOCK-WIFI] Started (promiscuous ch1/6/11, wildcard probe)");
}

static void flockWifiStop(void) {
    scanning = false;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) {
        Serial.println("[FLOCK-WIFI] Stopped (was passive)");
        return;
    }
    esp_wifi_set_promiscuous_rx_cb(NULL);
    esp_wifi_set_promiscuous(false);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    Serial.println("[FLOCK-WIFI] Stopped");
}

static void flockWifiLoop(void) {
    if (!scanning) return;
    if (engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED) return;
    if (millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % 3;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
        sendWildcardProbe();
    }
}

const EngineCallbacks flockWifiCallbacks = {
    .init   = flockWifiInit,
    .start  = flockWifiStart,
    .stop   = flockWifiStop,
    .loop   = flockWifiLoop,
    .config = NULL,
    .name   = "Flock-WiFi"
};
