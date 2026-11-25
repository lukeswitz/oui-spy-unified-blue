// Copyright (c) 2026 Luke Switzer
#include "ieee802154.h"

#ifdef OUISPY_DUAL_BAND
#include <Arduino.h>
#include <esp_attr.h>
#include <esp_ieee802154.h>
#include <esp_coexist.h>

#define ZB154_MAX_HANDLERS 2

static Zb154RxHandler g_handlers[ZB154_MAX_HANDLERS];
static volatile int g_count = 0;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;
static bool g_enabled = false;
static volatile bool g_rxOn = false;
static volatile uint8_t g_channel = ZB154_CH_MIN;
static volatile uint32_t g_frames = 0;

static void IRAM_ATTR zb154RxDone(uint8_t* frame, esp_ieee802154_frame_info_t* info) {
    g_frames++;
    const uint8_t len = frame[0];
    if (len >= 4 && len <= 127) {
        Zb154RxHandler local[ZB154_MAX_HANDLERS];
        portENTER_CRITICAL_ISR(&g_mux);
        const int n = g_count;
        for (int i = 0; i < n; i++) local[i] = g_handlers[i];
        portEXIT_CRITICAL_ISR(&g_mux);
        for (int i = 0; i < n; i++) {
            if (local[i]) local[i](frame + 1, (uint8_t)(len - 2), info->rssi, info->lqi, info->channel);
        }
    }
    esp_ieee802154_receive_handle_done(frame);
}

static bool zb154Enable(void) {
    if (g_enabled) return true;
    esp_ieee802154_event_cb_list_t cbs = {};
    cbs.rx_done_cb = zb154RxDone;
    esp_err_t rc = esp_ieee802154_event_callback_list_register(cbs);
    if (rc != ESP_OK) {
        Serial.printf("[ZB154] callback register failed rc=0x%x\n", (int)rc);
        return false;
    }
    rc = esp_ieee802154_enable();
    if (rc != ESP_OK) {
        esp_ieee802154_event_callback_list_unregister();
        Serial.printf("[ZB154] enable failed rc=0x%x\n", (int)rc);
        return false;
    }
    esp_ieee802154_set_promiscuous(true);
    esp_ieee802154_set_coordinator(false);
    esp_ieee802154_set_rx_when_idle(true);
    esp_coex_wifi_i154_enable();
    g_enabled = true;
    Serial.println("[ZB154] receive-only driver up (promiscuous, no ack, no tx)");
    return true;
}

static void zb154Disable(void) {
    if (!g_enabled) return;
    esp_ieee802154_sleep();
    g_rxOn = false;
    esp_ieee802154_disable();
    esp_ieee802154_event_callback_list_unregister();
    g_enabled = false;
    Serial.printf("[ZB154] driver down frames=%lu\n", (unsigned long)g_frames);
}

bool zb154Register(Zb154RxHandler handler) {
    if (!handler) return false;
    if (!zb154Enable()) return false;
    portENTER_CRITICAL(&g_mux);
    bool found = false;
    for (int i = 0; i < g_count; i++) {
        if (g_handlers[i] == handler) { found = true; break; }
    }
    if (!found && g_count < ZB154_MAX_HANDLERS) g_handlers[g_count++] = handler;
    portEXIT_CRITICAL(&g_mux);
    return true;
}

void zb154Unregister(Zb154RxHandler handler) {
    if (!handler) return;
    bool empty = false;
    portENTER_CRITICAL(&g_mux);
    for (int i = 0; i < g_count; i++) {
        if (g_handlers[i] == handler) {
            for (int j = i; j < g_count - 1; j++) g_handlers[j] = g_handlers[j + 1];
            g_count--;
            g_handlers[g_count] = nullptr;
            break;
        }
    }
    empty = (g_count == 0);
    portEXIT_CRITICAL(&g_mux);
    if (empty) zb154Disable();
}

bool zb154Active(void) { return g_enabled && g_count > 0; }

void zb154Tune(uint8_t channel) {
    if (!g_enabled) return;
    if (channel < ZB154_CH_MIN) channel = ZB154_CH_MIN;
    if (channel > ZB154_CH_MAX) channel = ZB154_CH_MAX;
    esp_ieee802154_set_channel(channel);
    esp_ieee802154_receive();
    g_channel = channel;
    g_rxOn = true;
}

void zb154Idle(void) {
    if (!g_enabled || !g_rxOn) return;
    esp_ieee802154_sleep();
    g_rxOn = false;
}

uint8_t zb154Channel(void) { return g_channel; }
uint32_t zb154FrameCount(void) { return g_frames; }

#endif
