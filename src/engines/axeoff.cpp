// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
//
// AXEOFF: passive Axon detector. Signatures, scan windows and WiFi sweep are ported from
// colonelpanichacks/unified-blue raw/axeoff.cpp (MIT). Hits go out as Detector/Axon detections.

#include "axeoff.h"
#include "axeoff_match.h"
#include "dedup_ring.h"
#include "protocol.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>

#define AXEOFF_HOP_MS      200
#define AXEOFF_FIRST_CHAN  11
#define AXEOFF_LAST_CHAN   1
#define AXEOFF_PUSH_GAP_MS 2000

static volatile bool g_scanning = false;
static uint8_t g_chan = AXEOFF_FIRST_CHAN;
static unsigned long g_lastHop = 0;
static DedupRing<8, AXEOFF_PUSH_GAP_MS> g_bleDedup;
static DedupRingISR<8, AXEOFF_PUSH_GAP_MS> g_wifiDedup;
static volatile uint32_t g_hits = 0;

__attribute__((weak)) void axeoffBootChime(void) {}

bool axeoffRunning(void) { return g_scanning; }

static void IRAM_ATTR fillEvent(DetectionEvent* evt, const uint8_t* mac, int8_t rssi, uint8_t channel, uint8_t sig,
                                uint8_t hits, uint16_t svc) {
    memset(evt, 0, sizeof(*evt));
    evt->engine_id = ENGINE_DETECTOR;
    memcpy(evt->mac, mac, 6);
    evt->rssi = rssi;
    evt->channel = channel;
    evt->timestamp_ms = millis();
    evt->method = METHOD_DET_AXON;
    evt->ext.detector.is_full_mac = 1;
    evt->ext.detector.confidence = (axeoffHitCount(hits) >= 2) ? DET_CONF_VERIFIED : DET_CONF_HIGH;
    char* d = evt->ext.detector.filter_desc;
    if (sig == AXEOFF_BLE_SVC && svc) {
        static const char kPrefix[] = "AXEOFF BLE service ";
        memcpy(d, kPrefix, sizeof(kPrefix) - 1);
        for (int i = 0; i < 4; i++) {
            uint8_t n = (svc >> (12 - 4 * i)) & 0x0F;
            d[sizeof(kPrefix) - 1 + i] = (char)(n < 10 ? '0' + n : 'A' + n - 10);
        }
    } else {
        strncpy(d, axeoffSigDesc(sig), sizeof(evt->ext.detector.filter_desc) - 1);
    }
}

class AxeoffBleCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        if (!g_scanning) return;
        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);
#ifdef OUISPY_NIMBLE2_API
        const std::vector<uint8_t>& pl = dev->getPayload();
        const uint8_t* adv = pl.data();
        size_t advLen = pl.size();
#else
        const uint8_t* adv = dev->getPayload();
        size_t advLen = dev->getPayloadLength();
#endif
        uint16_t svc = 0;
        uint8_t hits = axeoffBleMatch(mac, adv, advLen, &svc);
        if (!hits) return;
        if (g_bleDedup.check(mac)) return;
        DetectionEvent evt;
        fillEvent(&evt, mac, (int8_t)dev->getRSSI(), 0, axeoffBleSig(hits), hits, svc);
        g_hits++;
        pushDetection(&evt);
        Serial.printf("[AXEOFF] BLE %02x:%02x:%02x:%02x:%02x:%02x RSSI:%d hits=0x%02X\n",
                      mac[0], mac[1], mac[2], mac[3], mac[4], mac[5], (int)dev->getRSSI(), hits);
    }
};

static AxeoffBleCallbacks g_bleCb;

static void IRAM_ATTR axeoffWifiCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!g_scanning || type != WIFI_PKT_MGMT) return;
    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t src[6];
    uint8_t sig = axeoffWifiMatch(pkt->payload, (int)pkt->rx_ctrl.sig_len, src);
    if (sig == 0xFF) return;
    if (g_wifiDedup.check(src)) return;
    DetectionEvent evt;
    fillEvent(&evt, src, (int8_t)pkt->rx_ctrl.rssi, (uint8_t)pkt->rx_ctrl.channel, sig, 0, 0);
    pushDetectionFromISR(&evt);
}

static void axeoffInit(void) {
    g_bleDedup.reset();
    g_wifiDedup.reset();
    Serial.println("[AXEOFF] Initialized");
}

static void axeoffStart(void) {
    g_scanning = true;
    g_hits = 0;
    g_bleDedup.reset();
    g_wifiDedup.reset();
    if (!meshIsEnabled()) WiFi.mode(WIFI_STA);
    wifiSnifferApplyPs();
    wifiApplyRegdomain();
    wifiCoexRegister(axeoffWifiCb, WIFI_PROMIS_FILTER_MASK_MGMT);
    g_chan = AXEOFF_FIRST_CHAN;
    esp_wifi_set_channel(g_chan, WIFI_SECOND_CHAN_NONE);
    g_lastHop = millis();
    bleCoexRegister(&g_bleCb, false);
    axeoffBootChime();
    Serial.println("[AXEOFF] armed - passive BLE scan + WiFi probe/beacon sweep 11->1");
}

static void axeoffStop(void) {
    g_scanning = false;
    bleCoexUnregister(&g_bleCb);
    wifiCoexUnregister(axeoffWifiCb);
    if (meshIsEnabled() || wifiCoexActive() || wifiRadioExternallyOwned()) {
        WiFi.disconnect(false, false);
        esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    } else {
        WiFi.disconnect(true);
        WiFi.mode(WIFI_OFF);
    }
    Serial.printf("[AXEOFF] Stopped hits=%lu\n", (unsigned long)g_hits);
}

static void axeoffLoop(void) {
    if (!g_scanning) return;
    if (meshIsEnabled() && (meshInMeshWindow() || meshInRidWindow())) return;
    bleCoexEnsureScanning();
    if (!wifiCoexShouldHop(ENGINE_AXEOFF)) return;
    unsigned long now = millis();
    if (now - g_lastHop < AXEOFF_HOP_MS) return;
    int guard = 0;
    do {
        g_chan = (g_chan > AXEOFF_LAST_CHAN) ? g_chan - 1 : AXEOFF_FIRST_CHAN;
    } while (!wifiChanEnabled(g_chan) && ++guard < AXEOFF_FIRST_CHAN);
    esp_wifi_set_channel(g_chan, WIFI_SECOND_CHAN_NONE);
    g_lastHop = now;
    if (meshIsEnabled() && g_chan == 1) meshNoteOnHome();
}

const EngineCallbacks axeoffCallbacks = {
    .init       = axeoffInit,
    .start      = axeoffStart,
    .stop       = axeoffStop,
    .loop       = axeoffLoop,
    .config     = nullptr,
    .applyPrefs = nullptr,
    .name       = "AXEOFF"
};
