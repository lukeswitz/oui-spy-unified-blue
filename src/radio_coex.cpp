#include "radio_coex.h"
#include "engine_registry.h"
#include "protocol.h"
#include <Arduino.h>
#include "esp_bt.h"

void wifiSnifferApplyPs(void) {
    if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
        esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    } else {
        esp_wifi_set_ps(WIFI_PS_NONE);
    }
}

#define WIFI_COEX_MAX 8

static WifiRxParser g_parsers[WIFI_COEX_MAX];
static uint32_t g_filters[WIFI_COEX_MAX];
static volatile int g_count = 0;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

static void IRAM_ATTR wifiCoexDispatch(void* buf, wifi_promiscuous_pkt_type_t type) {
    int n = g_count;
    for (int i = 0; i < n; i++) {
        WifiRxParser p = g_parsers[i];
        if (p) p(buf, type);
    }
}

static void wifiCoexApplyFilter(void) {
    uint32_t mask = 0;
    portENTER_CRITICAL(&g_mux);
    for (int i = 0; i < g_count; i++) mask |= g_filters[i];
    portEXIT_CRITICAL(&g_mux);
    if (mask == 0) mask = WIFI_PROMIS_FILTER_MASK_MGMT;
    wifi_promiscuous_filter_t f = {};
    f.filter_mask = mask;
    esp_wifi_set_promiscuous_filter(&f);
}

void wifiCoexRegister(WifiRxParser parser, uint32_t filterMask) {
    if (!parser) return;
    bool first = false;
    portENTER_CRITICAL(&g_mux);
    bool found = false;
    for (int i = 0; i < g_count; i++) {
        if (g_parsers[i] == parser) { g_filters[i] = filterMask; found = true; break; }
    }
    if (!found && g_count < WIFI_COEX_MAX) {
        g_parsers[g_count] = parser;
        g_filters[g_count] = filterMask;
        g_count++;
    }
    first = (g_count == 1);
    portEXIT_CRITICAL(&g_mux);

    wifiCoexApplyFilter();
    if (first) {
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wifiCoexDispatch);
    }
    Serial.printf("[COEX] wifi register (count=%d)\n", g_count);
}

void wifiCoexUnregister(WifiRxParser parser) {
    if (!parser) return;
    bool empty = false;
    portENTER_CRITICAL(&g_mux);
    for (int i = 0; i < g_count; i++) {
        if (g_parsers[i] == parser) {
            for (int j = i; j < g_count - 1; j++) {
                g_parsers[j] = g_parsers[j + 1];
                g_filters[j] = g_filters[j + 1];
            }
            g_count--;
            g_parsers[g_count] = nullptr;
            g_filters[g_count] = 0;
            break;
        }
    }
    empty = (g_count == 0);
    portEXIT_CRITICAL(&g_mux);

    if (empty) {
        esp_wifi_set_promiscuous_rx_cb(NULL);
        esp_wifi_set_promiscuous(false);
    } else {
        wifiCoexApplyFilter();
    }
    Serial.printf("[COEX] wifi unregister (count=%d)\n", g_count);
}

bool wifiCoexActive(void) {
    return g_count > 0;
}

bool wifiCoexShouldHop(int engineId) {
    uint8_t mask = engineGetActiveMask();
    static const int prio[] = {
        ENGINE_FOXHUNTER, ENGINE_WARDRIVE, ENGINE_PCAP,
        ENGINE_DETECTOR, ENGINE_FLOCK_WIFI
    };
    for (unsigned i = 0; i < sizeof(prio) / sizeof(prio[0]); i++) {
        if (mask & ENGINE_BITMASK(prio[i])) return prio[i] == engineId;
    }
    return true;
}
