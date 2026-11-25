// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
//
// BLE Sniff frame helpers: advert filtering and LINKTYPE_BLUETOOTH_LE_LL_WITH_PHDR (256) record packing.
// Filter bits, PDU numbering and address classes are ported from colonelpanichacks/unified-blue
// raw/blesniff.cpp (MIT).
#pragma once

#include <stdint.h>
#include <stddef.h>
#include <string.h>

#define BLESNIFF_FT_ADV_IND      0x01
#define BLESNIFF_FT_ADV_DIRECT   0x02
#define BLESNIFF_FT_ADV_NONCONN  0x04
#define BLESNIFF_FT_SCAN_RSP     0x08
#define BLESNIFF_FT_ADV_SCAN_IND 0x10
#define BLESNIFF_FT_ADDR_PUBLIC  0x20
#define BLESNIFF_FT_ADDR_RANDOM  0x40
#define BLESNIFF_FT_DEFAULT      0x7F

#define BLESNIFF_LL_ADV_IND         0
#define BLESNIFF_LL_ADV_DIRECT_IND  1
#define BLESNIFF_LL_ADV_NONCONN_IND 2
#define BLESNIFF_LL_SCAN_RSP        4
#define BLESNIFF_LL_ADV_SCAN_IND    6

#define BLESNIFF_ADDR_PUBLIC        0
#define BLESNIFF_ADDR_RANDOM_STATIC 1
#define BLESNIFF_ADDR_RANDOM_NRP    2
#define BLESNIFF_ADDR_RANDOM_RPA    3

#define BLESNIFF_CFG_FILTER 0x01

#define BLESNIFF_MAX_ADV 31
#define BLESNIFF_FRAME_MAX 64
#define BLESNIFF_REC_MAX (24 + BLESNIFF_FRAME_MAX + 4)
#define BLESNIFF_ADV_ACCESS_ADDR 0x8E89BED6u
#define BLESNIFF_PHDR_FLAGS (0x0001 | 0x0002 | 0x0010 | 0x0400 | 0x0800)

// NimBLE HCI advert type (event type from the scan report) -> wire LL PDU type.
static inline uint8_t blesniffLlFromHci(uint8_t hci) {
    switch (hci) {
        case 0: return BLESNIFF_LL_ADV_IND;
        case 1: return BLESNIFF_LL_ADV_DIRECT_IND;
        case 2: return BLESNIFF_LL_ADV_SCAN_IND;
        case 3: return BLESNIFF_LL_ADV_NONCONN_IND;
        case 4: return BLESNIFF_LL_SCAN_RSP;
        default: return BLESNIFF_LL_ADV_IND;
    }
}

static inline uint8_t blesniffTypeBit(uint8_t ll) {
    switch (ll) {
        case BLESNIFF_LL_ADV_IND:         return BLESNIFF_FT_ADV_IND;
        case BLESNIFF_LL_ADV_DIRECT_IND:  return BLESNIFF_FT_ADV_DIRECT;
        case BLESNIFF_LL_ADV_NONCONN_IND: return BLESNIFF_FT_ADV_NONCONN;
        case BLESNIFF_LL_SCAN_RSP:        return BLESNIFF_FT_SCAN_RSP;
        case BLESNIFF_LL_ADV_SCAN_IND:    return BLESNIFF_FT_ADV_SCAN_IND;
        default:                          return 0xFF;
    }
}

// Random address subtype lives in the top two bits of the most significant byte (display order, msb[0]).
static inline uint8_t blesniffClassifyRandom(uint8_t msb) {
    switch ((msb >> 6) & 0x03) {
        case 0:  return BLESNIFF_ADDR_RANDOM_NRP;
        case 1:  return BLESNIFF_ADDR_RANDOM_RPA;
        default: return BLESNIFF_ADDR_RANDOM_STATIC;
    }
}

// rawAddrType is the NimBLE address type: 0/2 public, 1/3 random. Returns false when the filter drops the advert.
static inline bool blesniffPass(uint8_t ftMask, uint8_t hciType, uint8_t rawAddrType) {
    uint8_t bit = blesniffTypeBit(blesniffLlFromHci(hciType));
    if (bit != 0xFF && (ftMask & bit) == 0) return false;
    if (rawAddrType == 0 || rawAddrType == 2) return (ftMask & BLESNIFF_FT_ADDR_PUBLIC) != 0;
    if (rawAddrType == 1 || rawAddrType == 3) return (ftMask & BLESNIFF_FT_ADDR_RANDOM) != 0;
    return true;
}

static inline uint32_t blesniffCrc24(const uint8_t* data, size_t len) {
    uint32_t crc = 0x555555u;
    for (size_t i = 0; i < len; i++) {
        uint8_t b = data[i];
        for (int j = 0; j < 8; j++) {
            uint32_t fb = ((b >> j) & 1u) ^ (crc & 1u);
            crc >>= 1;
            if (fb) crc ^= 0xDA6000u;
        }
    }
    return crc & 0xFFFFFFu;
}

// advA is the advertiser address as NimBLE stores it (least significant byte first). Returns the frame length.
static inline size_t blesniffBuildFrame(uint8_t* out, uint8_t ll, bool txRandom, const uint8_t* advA,
                                        const uint8_t* targetA, const uint8_t* adv, uint8_t advLen, int8_t rssi) {
    if (advLen > BLESNIFF_MAX_ADV) advLen = BLESNIFF_MAX_ADV;
    const uint8_t targetLen = targetA ? 6 : 0;
    const uint8_t payloadLen = (uint8_t)(6 + targetLen + advLen);
    size_t off = 0;
    out[off++] = 37;
    out[off++] = (uint8_t)rssi;
    out[off++] = (uint8_t)-128;
    out[off++] = 0;
    uint32_t aa = BLESNIFF_ADV_ACCESS_ADDR;
    memcpy(out + off, &aa, 4); off += 4;
    uint16_t flags = BLESNIFF_PHDR_FLAGS;
    memcpy(out + off, &flags, 2); off += 2;
    memcpy(out + off, &aa, 4); off += 4;
    size_t pduStart = off;
    out[off++] = (uint8_t)((ll & 0x0F) | (txRandom ? 0x40 : 0));
    out[off++] = payloadLen;
    memcpy(out + off, advA, 6); off += 6;
    if (targetLen) { memcpy(out + off, targetA, 6); off += 6; }
    if (advLen) { memcpy(out + off, adv, advLen); off += advLen; }
    uint32_t crc = blesniffCrc24(out + pduStart, 2u + (size_t)payloadLen);
    out[off++] = (uint8_t)(crc & 0xFF);
    out[off++] = (uint8_t)((crc >> 8) & 0xFF);
    out[off++] = (uint8_t)((crc >> 16) & 0xFF);
    return off;
}

// One record of the PCAP data stream: [0xCAFEBABE][recLen][ts_sec][ts_usec][incl][orig][frame][0xDEADBEEF].
static inline size_t blesniffPackRecord(uint8_t* out, uint32_t tsUs, const uint8_t* frame, uint32_t flen) {
    uint32_t sec = tsUs / 1000000u;
    uint32_t usec = tsUs - sec * 1000000u;
    uint32_t magic = 0xCAFEBABEu, recLen = 16u + flen, endMark = 0xDEADBEEFu;
    memcpy(out + 0, &magic, 4);
    memcpy(out + 4, &recLen, 4);
    memcpy(out + 8, &sec, 4);
    memcpy(out + 12, &usec, 4);
    memcpy(out + 16, &flen, 4);
    memcpy(out + 20, &flen, 4);
    memcpy(out + 24, frame, flen);
    memcpy(out + 24 + flen, &endMark, 4);
    return 24u + flen + 4u;
}
