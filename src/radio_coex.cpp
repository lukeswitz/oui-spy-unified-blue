#include "radio_coex.h"
#include "engine_registry.h"
#include "protocol.h"
#include "wifi_ota_handler.h"
#include <Arduino.h>
#include "esp_bt.h"
#ifdef OUISPY_NIMBLE2
#include <WiFi.h>
#include <esp_event.h>
#include <esp_netif.h>
#include <nvs_flash.h>

static bool g_c5WifiUp = false;
static bool g_c5WifiInited = false;
void c5WifiInitNetif(void) {
    esp_netif_init();
    esp_err_t le = esp_event_loop_create_default();
    if (le != ESP_OK && le != ESP_ERR_INVALID_STATE) {
        Serial.printf("[COEX] event loop rc=0x%x\n", (int)le);
    }
    nvs_flash_init();
}
void c5WifiPrepare(void) {
    if (g_c5WifiInited) return;
    size_t dma = heap_caps_get_free_size(MALLOC_CAP_DMA);
    wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
    cfg.nvs_enable = 0;
    esp_err_t irc = esp_wifi_init(&cfg);
    if (irc != ESP_OK) {
        Serial.printf("[COEX] C5 WiFi init FAILED dma=%u init=0x%x\n", (unsigned)dma, (int)irc);
        return;
    }
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
    esp_wifi_set_mode(WIFI_MODE_STA);
    g_c5WifiInited = true;
    Serial.printf("[COEX] C5 WiFi ready dma=%u init=0x%x\n", (unsigned)dma, (int)irc);
}
void c5WifiUp(void) {
    if (g_c5WifiUp) return;
    c5WifiPrepare();
    if (!g_c5WifiInited) return;
    size_t dma = heap_caps_get_free_size(MALLOC_CAP_DMA);
    esp_err_t src = esp_wifi_start();
    if (src != ESP_OK) {
        Serial.printf("[COEX] C5 WiFi start FAILED dma=%u start=0x%x\n", (unsigned)dma, (int)src);
        return;
    }
    wifiSnifferApplyPs();
    g_c5WifiUp = true;
    Serial.printf("[COEX] C5 WiFi up dma=%u\n", (unsigned)dma);
}
static void __attribute__((unused)) c5WifiDown(void) {
    if (!g_c5WifiUp) return;
    esp_wifi_stop();
    esp_wifi_deinit();
    g_c5WifiUp = false;
    Serial.println("[COEX] C5 WiFi down");
}
#endif

void wifiSnifferApplyPs(void) {
    if (esp_bt_controller_get_status() == ESP_BT_CONTROLLER_STATUS_ENABLED) {
        esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    } else {
        esp_wifi_set_ps(WIFI_PS_NONE);
    }
}

static uint8_t g_wifiBandMask = WIFI_BAND_24 | WIFI_BAND_5;

void wifiSetBandMask(uint8_t mask) {
    mask &= (WIFI_BAND_24 | WIFI_BAND_5);
    if (mask == 0) mask = WIFI_BAND_24;
    g_wifiBandMask = mask;
}

uint8_t wifiGetBandMask(void) { return g_wifiBandMask; }

bool wifiChanEnabled(uint8_t ch) {
#ifdef OUISPY_DUAL_BAND
    return (ch <= 14) ? (g_wifiBandMask & WIFI_BAND_24) != 0
                      : (g_wifiBandMask & WIFI_BAND_5) != 0;
#else
    return ch <= 14;
#endif
}

void wifiApplyRegdomain(void) {
#ifdef OUISPY_DUAL_BAND
    if (g_wifiBandMask & WIFI_BAND_5) {
        wifi_country_t c = { .cc = "US", .schan = 1, .nchan = 11,
                             .max_tx_power = 20, .policy = WIFI_COUNTRY_POLICY_MANUAL };
        esp_wifi_set_country(&c);
        return;
    }
#endif
    wifi_country_t c = { .cc = "JP", .schan = 1, .nchan = 14,
                         .policy = WIFI_COUNTRY_POLICY_MANUAL };
    esp_wifi_set_country(&c);
}

#define WIFI_COEX_MAX 8

static WifiRxParser g_parsers[WIFI_COEX_MAX];
static uint32_t g_filters[WIFI_COEX_MAX];
static volatile int g_count = 0;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

static void IRAM_ATTR wifiCoexDispatch(void* buf, wifi_promiscuous_pkt_type_t type) {
    WifiRxParser local[WIFI_COEX_MAX];
    portENTER_CRITICAL_ISR(&g_mux);
    int n = g_count;
    for (int i = 0; i < n; i++) local[i] = g_parsers[i];
    portEXIT_CRITICAL_ISR(&g_mux);
    for (int i = 0; i < n; i++) {
        if (local[i]) local[i](buf, type);
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

    if (first) {
#ifdef OUISPY_NIMBLE2
        c5WifiUp();
#endif
        wifiStaReleaseForScan();
        wifiCoexApplyFilter();
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wifiCoexDispatch);
    } else {
        wifiCoexApplyFilter();
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

bool wifiRadioExternallyOwned(void) {
#ifdef OUISPY_DONGLE
    return true;
#else
    return false;
#endif
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
