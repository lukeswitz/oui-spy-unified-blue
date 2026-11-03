#pragma once

#include <stdint.h>
#include <esp_attr.h>

#define AUTHC_OPEN        0
#define AUTHC_WEP         1
#define AUTHC_WPA         2
#define AUTHC_WPA2        3
#define AUTHC_WPA_WPA2    4
#define AUTHC_WPA2_EAP    5
#define AUTHC_WPA3_SAE    6
#define AUTHC_WPA2_WPA3   7
#define AUTHC_OWE         8
#define AUTHC_WPA3_EAP    9

static inline uint8_t IRAM_ATTR wifiAuthFromMgmt(const uint8_t* p, int len) {
    int offset = 36;
    bool hasRSN = false, hasWPA = false;
    bool psk = false, sae = false, eap = false, suiteB = false, owe = false;

    while (offset + 2 <= len) {
        uint8_t tagId = p[offset];
        uint8_t tagLen = p[offset + 1];
        if (offset + 2 + tagLen > len) break;
        if (tagId == 48 && tagLen >= 2) {
            hasRSN = true;
            int off = offset + 4;
            int end = offset + 2 + tagLen;
            if (off + 6 <= end) {
                off += 4;
                uint16_t pairCount = p[off] | (p[off + 1] << 8);
                off += 2 + pairCount * 4;
                if (off + 2 <= end) {
                    uint16_t akmCount = p[off] | (p[off + 1] << 8);
                    off += 2;
                    for (uint16_t i = 0; i < akmCount && off + 4 <= end; i++, off += 4) {
                        if (p[off] != 0x00 || p[off + 1] != 0x0F || p[off + 2] != 0xAC) continue;
                        switch (p[off + 3]) {
                            case 1: case 3: case 5: eap = true; break;
                            case 11: case 12: case 13: suiteB = true; break;
                            case 2: case 4: case 6: case 19: case 20: psk = true; break;
                            case 8: case 9: case 24: case 25: sae = true; break;
                            case 18: owe = true; break;
                            default: break;
                        }
                    }
                }
            }
        } else if (tagId == 221 && tagLen >= 4 &&
                   p[offset + 2] == 0x00 && p[offset + 3] == 0x50 &&
                   p[offset + 4] == 0xF2 && p[offset + 5] == 0x01) {
            hasWPA = true;
        }
        offset += 2 + tagLen;
    }

    if (suiteB)          return AUTHC_WPA3_EAP;
    if (eap && hasRSN)   return AUTHC_WPA2_EAP;
    if (sae && psk)      return AUTHC_WPA2_WPA3;
    if (sae)             return AUTHC_WPA3_SAE;
    if (owe)             return AUTHC_OWE;
    if (hasRSN && hasWPA) return AUTHC_WPA_WPA2;
    if (hasRSN)          return AUTHC_WPA2;
    if (hasWPA)          return AUTHC_WPA;
    if (len >= 36 && (p[34] & 0x10)) return AUTHC_WEP;
    return AUTHC_OPEN;
}
