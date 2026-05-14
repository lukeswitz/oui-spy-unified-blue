#ifndef FLOCK_OUI_H
#define FLOCK_OUI_H

#include <stdint.h>
#include <string.h>

static const uint8_t FLOCK_OUI_TABLE[][3] = {
    {0x00,0xf4,0x8d},
    {0x04,0x0d,0x84},
    {0x08,0x3a,0x88},
    {0x14,0x5a,0xfc},
    {0x14,0xb5,0xcd},
    {0x1c,0x34,0xf1},
    {0x24,0xb2,0xb9},
    {0x38,0x5b,0x44},
    {0x3c,0x71,0xbf},
    {0x3c,0x91,0x80},
    {0x48,0x27,0xea},
    {0x58,0x00,0xe3},
    {0x58,0x8e,0x81},
    {0x5c,0x93,0xa2},
    {0x64,0x6e,0x69},
    {0x70,0x08,0x94},
    {0x70,0xc9,0x4e},
    {0x74,0x4c,0xa1},
    {0x80,0x30,0x49},
    {0x82,0x6b,0xf2},
    {0x90,0x35,0xea},
    {0x94,0x08,0x53},
    {0x94,0x2a,0x6f},
    {0x94,0x34,0x69},
    {0x9c,0x2f,0x9d},
    {0xa4,0xcf,0x12},
    {0xb4,0x1e,0x52},
    {0xb4,0xe3,0xf9},
    {0xb8,0x1e,0xa4},
    {0xb8,0x35,0x32},
    {0xc0,0x35,0x32},
    {0xd0,0x39,0x57},
    {0xd4,0x11,0xd6},
    {0xd8,0xf3,0xbc},
    {0xe0,0x0a,0xf6},
    {0xe0,0x4f,0x43},
    {0xe4,0xaa,0xea},
    {0xe8,0xd0,0xfc},
    {0xec,0x1b,0xbd},
    {0xf0,0x82,0xc0},
    {0xf4,0x6a,0xdd},
    {0xf4,0xe2,0xc6},
};
static const int FLOCK_OUI_COUNT = sizeof(FLOCK_OUI_TABLE) / sizeof(FLOCK_OUI_TABLE[0]);

struct FlockOuiBucket {
    uint8_t start;
    uint8_t count;
};

static FlockOuiBucket flockOuiBuckets[256];
static bool flockOuiBucketsReady = false;

static inline void flockOuiInitBuckets() {
    if (flockOuiBucketsReady) return;
    memset(flockOuiBuckets, 0, sizeof(flockOuiBuckets));
    for (int i = 0; i < FLOCK_OUI_COUNT; i++) {
        uint8_t b = FLOCK_OUI_TABLE[i][0];
        if (flockOuiBuckets[b].count == 0) {
            flockOuiBuckets[b].start = (uint8_t)i;
        }
        flockOuiBuckets[b].count++;
    }
    flockOuiBucketsReady = true;
}

static inline bool flockMatchOui(const uint8_t* mac) {
    if (mac[0] & 0x02) return false;
    if (!flockOuiBucketsReady) flockOuiInitBuckets();
    const FlockOuiBucket& b = flockOuiBuckets[mac[0]];
    for (int i = b.start; i < b.start + b.count; i++) {
        if (mac[1] == FLOCK_OUI_TABLE[i][1] &&
            mac[2] == FLOCK_OUI_TABLE[i][2]) return true;
    }
    return false;
}

static inline bool IRAM_ATTR flockMatchOuiISR(const uint8_t* mac) {
    if (mac[0] & 0x02) return false;
    if (!flockOuiBucketsReady) return false;
    const FlockOuiBucket& b = flockOuiBuckets[mac[0]];
    for (int i = b.start; i < b.start + b.count; i++) {
        if (mac[1] == FLOCK_OUI_TABLE[i][1] &&
            mac[2] == FLOCK_OUI_TABLE[i][2]) return true;
    }
    return false;
}

static inline int IRAM_ATTR isWildcardProbeIE(const uint8_t* body, int len) {
    if (!body || len < 2) return -1;
    while (len >= 2) {
        uint8_t id   = body[0];
        uint8_t elen = body[1];
        if ((int)elen + 2 > len) break;
        if (id == 0) return (elen == 0) ? 1 : 0;
        body += elen + 2;
        len  -= elen + 2;
    }
    return -1;
}

#endif
