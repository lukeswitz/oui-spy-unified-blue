#ifndef FLOCK_AUTH_CACHE_H
#define FLOCK_AUTH_CACHE_H

#include <stdint.h>
#include <string.h>
#include <Arduino.h>

#define FLOCK_AUTH_CACHE_SIZE 32

struct FlockAuthEntry {
    uint8_t mac[6];
    uint8_t auth;
    uint32_t ts;
};

static FlockAuthEntry flockAuthCache[FLOCK_AUTH_CACHE_SIZE];
static int flockAuthHead = 0;

static inline void IRAM_ATTR flockAuthCacheSet(const uint8_t* mac, uint8_t auth) {
    if (auth == 0) return;
    uint32_t now = millis();
    for (int i = 0; i < FLOCK_AUTH_CACHE_SIZE; i++) {
        if (memcmp(flockAuthCache[i].mac, mac, 6) == 0) {
            flockAuthCache[i].auth = auth;
            flockAuthCache[i].ts = now;
            return;
        }
    }
    int idx = flockAuthHead;
    flockAuthHead = (flockAuthHead + 1) % FLOCK_AUTH_CACHE_SIZE;
    memcpy(flockAuthCache[idx].mac, mac, 6);
    flockAuthCache[idx].auth = auth;
    flockAuthCache[idx].ts = now;
}

static inline uint8_t IRAM_ATTR flockAuthCacheGet(const uint8_t* mac) {
    for (int i = 0; i < FLOCK_AUTH_CACHE_SIZE; i++) {
        if (memcmp(flockAuthCache[i].mac, mac, 6) == 0) {
            return flockAuthCache[i].auth;
        }
    }
    return 0;
}

#endif
