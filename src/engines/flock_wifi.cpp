/**
 * Flock-WiFi Engine — WiFi promiscuous mode sniffer for Flock Safety cameras.
 * Matches OUI on addr1/addr2/addr3, SSID keywords, and wildcard probes.
 * Ported from standalone flock-you WiFi sniffer logic.
 */
#include "flock_wifi.h"
#include "protocol.h"
#include "flock_oui.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <string.h>

// Channel hopping
static const uint8_t channels[] = {1, 6, 11};
static int channelIdx = 0;
static unsigned long lastChannelHop = 0;
static const unsigned long DWELL_MS = 350;

static volatile bool scanning = false;

// Dedup ring
#define WIFI_DEDUP_SIZE 16
#define WIFI_DEDUP_COOLDOWN_MS 5000
static struct { uint8_t mac[6]; unsigned long ts; } wifiDedup[WIFI_DEDUP_SIZE];
static int wifiDedupCount = 0;

// ============================================================================
// IRAM helpers
// ============================================================================

// matchOui now provided by flock_oui.h as flockMatchOuiISR()

static bool IRAM_ATTR isDedupCooldownISR(const uint8_t* mac) {
    uint32_t now = millis();
    for (int i = 0; i < wifiDedupCount; i++) {
        if (memcmp(wifiDedup[i].mac, mac, 6) == 0) {
            if (now - wifiDedup[i].ts < WIFI_DEDUP_COOLDOWN_MS) return true;
            wifiDedup[i].ts = now;
            return false;
        }
    }
    static int wifiDedupHead = 0;
    int idx;
    if (wifiDedupCount < WIFI_DEDUP_SIZE) {
        idx = wifiDedupCount++;
    } else {
        idx = wifiDedupHead;
        wifiDedupHead = (wifiDedupHead + 1) % WIFI_DEDUP_SIZE;
    }
    memcpy(wifiDedup[idx].mac, mac, 6);
    wifiDedup[idx].ts = now;
    return false;
}

// ============================================================================
// WiFi Promiscuous Callback (ISR context — no malloc, no Serial)
// ============================================================================

static void IRAM_ATTR wifiSnifferCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!scanning) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    uint8_t frameType = (p[0] >> 2) & 0x03;
    uint8_t frameSubtype = (p[0] >> 4) & 0x0F;

    const uint8_t* addr1 = &p[4];   // destination
    const uint8_t* addr2 = &p[10];  // source/transmitter
    const uint8_t* addr3 = &p[16];  // BSSID

    uint8_t method = 0xFF;
    const uint8_t* matchMac = NULL;

    // Check addr2 (transmitter) — highest confidence
    if (flockMatchOuiISR(addr2)) {
        method = METHOD_OUI_ADDR2;
        matchMac = addr2;

        // Wildcard probe check: probe request (type=0 subtype=4) with empty SSID
        if (frameType == 0 && frameSubtype == 4 && len > 25) {
            uint8_t ssidLen = p[25]; // SSID IE length
            if (ssidLen == 0) {
                method = METHOD_WILDCARD_PROBE;
            }
        }
    }
    // Check addr1 (destination) — skip multicast
    else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
        method = METHOD_OUI_ADDR1;
        matchMac = addr1;
    }
    // Check addr3 (BSSID) — management frames only
    else if (frameType == 0 && flockMatchOuiISR(addr3)) {
        method = METHOD_OUI_ADDR3;
        matchMac = addr3;
    }

    if (method == 0xFF || !matchMac) return;
    if (isDedupCooldownISR(matchMac)) return;

    DetectionEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.engine_id = ENGINE_FLOCK_WIFI;
    memcpy(evt.mac, matchMac, 6);
    evt.rssi = pkt->rx_ctrl.rssi;
    evt.channel = pkt->rx_ctrl.channel;
    evt.timestamp_ms = millis();
    evt.method = method;

    pushDetectionFromISR(&evt);
}

// ============================================================================
// Lifecycle
// ============================================================================

static void flockWifiInit(void) {
    wifiDedupCount = 0;
    channelIdx = 0;
    Serial.println("[FLOCK-WIFI] Initialized");
}

static void flockWifiStart(void) {
    WiFi.mode(WIFI_STA);
    esp_wifi_set_promiscuous(true);
    esp_wifi_set_promiscuous_rx_cb(wifiSnifferCb);
    esp_wifi_set_channel(channels[0], WIFI_SECOND_CHAN_NONE);
    lastChannelHop = millis();
    scanning = true;
    Serial.println("[FLOCK-WIFI] Started (promiscuous ch1/6/11)");
}

static void flockWifiStop(void) {
    scanning = false;  // volatile — ISR callback checks this
    esp_wifi_set_promiscuous_rx_cb(NULL);
    esp_wifi_set_promiscuous(false);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);
    Serial.println("[FLOCK-WIFI] Stopped");
}

static void flockWifiLoop(void) {
    if (!scanning) return;

    // Channel hop
    if (millis() - lastChannelHop >= DWELL_MS) {
        channelIdx = (channelIdx + 1) % 3;
        esp_wifi_set_channel(channels[channelIdx], WIFI_SECOND_CHAN_NONE);
        lastChannelHop = millis();
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
