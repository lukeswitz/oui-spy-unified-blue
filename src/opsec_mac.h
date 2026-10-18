#pragma once

#include <Arduino.h>
#include <esp_mac.h>

inline uint8_t g_factoryBtMac[6] = {0};
inline bool g_factoryBtMacSet = false;

inline void opsecRandomizeBaseMac(void) {
    esp_read_mac(g_factoryBtMac, ESP_MAC_BT);
    g_factoryBtMacSet = true;
    uint8_t m[6];
    uint32_t a = esp_random(), b = esp_random();
    m[0] = (uint8_t)((a & 0xFC) | 0x02);
    m[1] = (uint8_t)(a >> 8);
    m[2] = (uint8_t)(a >> 16);
    m[3] = (uint8_t)(a >> 24);
    m[4] = (uint8_t)b;
    m[5] = (uint8_t)((b >> 8) & 0xF0);
    esp_err_t err = esp_base_mac_addr_set(m);
    Serial.printf("[OPSEC] base MAC randomized: %s\n", err == ESP_OK ? "ok" : esp_err_to_name(err));
}

inline void opsecFactoryBtMac(uint8_t out[6]) {
    if (g_factoryBtMacSet) memcpy(out, g_factoryBtMac, 6);
    else esp_read_mac(out, ESP_MAC_BT);
}
