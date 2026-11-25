// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
//
// Axon signature matchers for the AXEOFF engine. Signatures and match order are ported from
// colonelpanichacks/unified-blue raw/axeoff.cpp (MIT).
#pragma once

#include <stdint.h>
#include <stddef.h>
#if __has_include(<esp_attr.h>)
#include <esp_attr.h>
#endif
#ifndef IRAM_ATTR
#define IRAM_ATTR
#endif

#define AXEOFF_CID 0x034D

static const uint8_t kAxeoffOui[3] = {0x00, 0x25, 0xDF};
static const uint16_t kAxeoffSvcs[] = {0xFC81, 0xFE6B, 0xFE6C};
#define AXEOFF_SVC_COUNT (sizeof(kAxeoffSvcs) / sizeof(kAxeoffSvcs[0]))

enum AxeoffSig : uint8_t {
    AXEOFF_BLE_CID = 0,
    AXEOFF_BLE_SVC,
    AXEOFF_BLE_MAC,
    AXEOFF_WIFI_PROBE,
    AXEOFF_WIFI_BEACON,
    AXEOFF_SIG_COUNT
};

#define AXEOFF_HIT_CID 0x01
#define AXEOFF_HIT_SVC 0x02
#define AXEOFF_HIT_MAC 0x04

static inline const char* IRAM_ATTR axeoffSigDesc(uint8_t sig) {
    switch (sig) {
        case AXEOFF_BLE_CID:     return "AXEOFF BLE CID 034D";
        case AXEOFF_BLE_SVC:     return "AXEOFF BLE service UUID";
        case AXEOFF_BLE_MAC:     return "AXEOFF BLE OUI 00:25:DF";
        case AXEOFF_WIFI_PROBE:  return "AXEOFF WiFi probe 0025DF";
        case AXEOFF_WIFI_BEACON: return "AXEOFF WiFi beacon 0025DF";
        default:                 return "AXEOFF";
    }
}

static inline bool IRAM_ATTR axeoffOuiMatch(const uint8_t* mac) {
    return mac[0] == kAxeoffOui[0] && mac[1] == kAxeoffOui[1] && mac[2] == kAxeoffOui[2];
}

static inline bool axeoffSvcMatch(uint16_t u16, uint16_t* matched) {
    for (size_t i = 0; i < AXEOFF_SVC_COUNT; i++) {
        if (kAxeoffSvcs[i] == u16) {
            if (matched) *matched = u16;
            return true;
        }
    }
    return false;
}

// Walks the advert's AD structures. Returns a mask of AXEOFF_HIT_* and the matched service UUID (0 if none).
// mac is in display order (most significant byte first).
static inline uint8_t axeoffBleMatch(const uint8_t* mac, const uint8_t* adv, size_t len, uint16_t* svcOut) {
    uint8_t hits = 0;
    uint16_t svc = 0;
    size_t i = 0;
    while (i < len) {
        uint8_t l = adv[i];
        if (l == 0) { i++; continue; }
        if (i + 1 + l > len) break;
        uint8_t type = adv[i + 1];
        const uint8_t* d = adv + i + 2;
        uint8_t dl = (uint8_t)(l - 1);
        if (type == 0xFF && dl >= 2) {
            if (d[0] == (AXEOFF_CID & 0xFF) && d[1] == (AXEOFF_CID >> 8)) hits |= AXEOFF_HIT_CID;
        } else if (type == 0x02 || type == 0x03) {
            for (uint8_t k = 0; k + 1 < dl; k += 2) {
                if (axeoffSvcMatch((uint16_t)(d[k] | (d[k + 1] << 8)), &svc)) hits |= AXEOFF_HIT_SVC;
            }
        } else if (type == 0x04 || type == 0x05) {
            for (uint8_t k = 0; k + 3 < dl; k += 4) {
                if (axeoffSvcMatch((uint16_t)(d[k] | (d[k + 1] << 8)), &svc)) hits |= AXEOFF_HIT_SVC;
            }
        } else if (type == 0x06 || type == 0x07) {
            for (uint8_t k = 0; k + 15 < dl; k += 16) {
                if (axeoffSvcMatch((uint16_t)(d[k + 12] | (d[k + 13] << 8)), &svc)) hits |= AXEOFF_HIT_SVC;
            }
        }
        i += 1 + l;
    }
    if (axeoffOuiMatch(mac)) hits |= AXEOFF_HIT_MAC;
    if (svcOut) *svcOut = svc;
    return hits;
}

// Upstream priority: manufacturer CID, then service UUID, then MAC prefix.
static inline uint8_t axeoffBleSig(uint8_t hits) {
    if (hits & AXEOFF_HIT_CID) return AXEOFF_BLE_CID;
    if (hits & AXEOFF_HIT_SVC) return AXEOFF_BLE_SVC;
    return AXEOFF_BLE_MAC;
}

static inline uint8_t IRAM_ATTR axeoffHitCount(uint8_t hits) {
    return (uint8_t)(((hits & AXEOFF_HIT_CID) ? 1 : 0) + ((hits & AXEOFF_HIT_SVC) ? 1 : 0) +
                     ((hits & AXEOFF_HIT_MAC) ? 1 : 0));
}

// 802.11 management frame (header at p, len bytes incl. no FCS requirement): probe request or beacon whose
// transmitter (addr2) carries the Axon OUI. Returns AXEOFF_WIFI_PROBE / AXEOFF_WIFI_BEACON or 0xFF.
static inline uint8_t IRAM_ATTR axeoffWifiMatch(const uint8_t* p, int len, uint8_t* srcOut) {
    if (len < 24) return 0xFF;
    uint8_t ftype = (p[0] >> 2) & 0x03;
    uint8_t subtype = (p[0] >> 4) & 0x0F;
    if (ftype != 0) return 0xFF;
    if (subtype != 0x04 && subtype != 0x08) return 0xFF;
    const uint8_t* addr2 = p + 10;
    if (!axeoffOuiMatch(addr2)) return 0xFF;
    if (srcOut) for (int i = 0; i < 6; i++) srcOut[i] = addr2[i];
    return subtype == 0x04 ? AXEOFF_WIFI_PROBE : AXEOFF_WIFI_BEACON;
}
