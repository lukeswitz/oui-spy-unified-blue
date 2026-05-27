#ifndef DEDUP_RING_H
#define DEDUP_RING_H

#include <stdint.h>
#include <string.h>
#include <Arduino.h>

template<int SIZE, uint32_t DEFAULT_COOLDOWN_MS>
struct DedupRing {
    struct Entry {
        uint8_t mac[6];
        uint32_t ts;
    } ring[SIZE];
    int head = 0;
    int count = 0;
    uint32_t cooldownMs = DEFAULT_COOLDOWN_MS;

    void setCooldownMs(uint32_t ms) { cooldownMs = ms; }

    bool check(const uint8_t* mac) {
        uint32_t now = millis();
        uint32_t cd = cooldownMs;
        for (int i = 0; i < count; i++) {
            if (memcmp(ring[i].mac, mac, 6) == 0) {
                if (now - ring[i].ts < cd) return true;
                ring[i].ts = now;
                return false;
            }
        }
        int idx;
        if (count < SIZE) {
            idx = count++;
        } else {
            idx = head;
            head = (head + 1) % SIZE;
        }
        memcpy(ring[idx].mac, mac, 6);
        ring[idx].ts = now;
        return false;
    }

    void reset() {
        head = 0;
        count = 0;
    }
};

template<int SIZE, uint32_t DEFAULT_COOLDOWN_MS>
struct DedupRingISR {
    struct Entry {
        uint8_t mac[6];
        uint32_t ts;
    } ring[SIZE];
    int head = 0;
    int count = 0;
    volatile uint32_t cooldownMs = DEFAULT_COOLDOWN_MS;

    void setCooldownMs(uint32_t ms) { cooldownMs = ms; }

    bool IRAM_ATTR check(const uint8_t* mac) {
        uint32_t now = millis();
        uint32_t cd = cooldownMs;
        for (int i = 0; i < count; i++) {
            if (memcmp(ring[i].mac, mac, 6) == 0) {
                if (now - ring[i].ts < cd) return true;
                ring[i].ts = now;
                return false;
            }
        }
        int idx;
        if (count < SIZE) {
            idx = count++;
        } else {
            idx = head;
            head = (head + 1) % SIZE;
        }
        memcpy(ring[idx].mac, mac, 6);
        ring[idx].ts = now;
        return false;
    }

    void reset() {
        head = 0;
        count = 0;
    }
};

#endif
