#include "det_spool.h"
#include <LittleFS.h>
#include <string.h>
#include <esp_heap_caps.h>
#include <Arduino.h>

#if defined(OUISPY_ROLE_MANAGER) && !defined(BOARD_HAS_PSRAM)
#define SPOOL_CAP 120
#else
#define SPOOL_CAP 1000
#endif

#define SPOOL_PATH "/spool.bin"
#define SPOOL_MAGIC 0x4F535031u
#define SPOOL_FLUSH_MS 5000u

typedef struct __attribute__((packed)) {
    DetectionEvent evt;
    uint16_t hit_count;
} SpoolSlot;

typedef struct __attribute__((packed)) {
    uint32_t magic;
    uint16_t count;
    uint16_t dropped;
} SpoolHeader;

static SpoolSlot* s_slots = nullptr;
static uint16_t s_count = 0;
static uint16_t s_dropped = 0;
static uint16_t s_cap = 0;
static bool s_dirty = false;
static bool s_ready = false;
static uint32_t s_lastFlushMs = 0;

bool engineSpoolable(uint8_t engine_id) {
    return engine_id != ENGINE_WARDRIVE && engine_id != ENGINE_PCAP;
}

static int findSlot(uint8_t engine_id, const uint8_t* mac) {
    for (uint16_t i = 0; i < s_count; i++) {
        if (s_slots[i].evt.engine_id == engine_id &&
            memcmp(s_slots[i].evt.mac, mac, 6) == 0) {
            return (int)i;
        }
    }
    return -1;
}

static int oldestSlot() {
    if (s_count == 0) return -1;
    int oldest = 0;
    uint32_t best = s_slots[0].evt.timestamp_ms;
    for (uint16_t i = 1; i < s_count; i++) {
        if (s_slots[i].evt.timestamp_ms < best) {
            best = s_slots[i].evt.timestamp_ms;
            oldest = (int)i;
        }
    }
    return oldest;
}

static void persist() {
    File f = LittleFS.open(SPOOL_PATH, "w");
    if (!f) { s_dirty = false; return; }
    SpoolHeader h = { SPOOL_MAGIC, s_count, s_dropped };
    f.write((const uint8_t*)&h, sizeof(h));
    if (s_count > 0) f.write((const uint8_t*)s_slots, (size_t)s_count * sizeof(SpoolSlot));
    f.close();
    s_dirty = false;
}

void detSpoolInit() {
    if (s_ready) return;
    s_cap = SPOOL_CAP;
    size_t bytes = (size_t)s_cap * sizeof(SpoolSlot);
    if (psramFound()) {
        s_slots = (SpoolSlot*)heap_caps_malloc(bytes, MALLOC_CAP_SPIRAM);
    }
    if (!s_slots) {
        if (s_cap > 300) s_cap = 300;
        bytes = (size_t)s_cap * sizeof(SpoolSlot);
        s_slots = (SpoolSlot*)malloc(bytes);
    }
    if (!s_slots) { s_ready = false; Serial.println("[SPOOL] alloc failed"); return; }

    if (!LittleFS.begin(true)) {
        Serial.println("[SPOOL] LittleFS mount failed, RAM-only");
        s_ready = true;
        return;
    }
    File f = LittleFS.open(SPOOL_PATH, "r");
    if (f) {
        SpoolHeader h;
        if (f.read((uint8_t*)&h, sizeof(h)) == sizeof(h) && h.magic == SPOOL_MAGIC) {
            uint16_t n = h.count;
            if (n > s_cap) n = s_cap;
            size_t got = f.read((uint8_t*)s_slots, (size_t)n * sizeof(SpoolSlot));
            s_count = (uint16_t)(got / sizeof(SpoolSlot));
            s_dropped = h.dropped;
        }
        f.close();
    }
    s_ready = true;
    Serial.printf("[SPOOL] ready cap=%u loaded=%u dropped=%u\n", s_cap, s_count, s_dropped);
}

void detSpoolAppend(const DetectionEvent* evt) {
    if (!s_ready || !s_slots || !evt) return;
    int idx = findSlot(evt->engine_id, evt->mac);
    if (idx >= 0) {
        uint16_t hc = s_slots[idx].hit_count;
        s_slots[idx].evt = *evt;
        s_slots[idx].hit_count = (hc < 0xFFFF) ? (uint16_t)(hc + 1) : hc;
    } else if (s_count < s_cap) {
        s_slots[s_count].evt = *evt;
        s_slots[s_count].hit_count = 1;
        s_count++;
    } else {
        int o = oldestSlot();
        if (o < 0) return;
        s_slots[o].evt = *evt;
        s_slots[o].hit_count = 1;
        if (s_dropped < 0xFFFF) s_dropped++;
    }
    s_dirty = true;
}

uint16_t detSpoolCount() { return s_count; }
uint16_t detSpoolDroppedCount() { return s_dropped; }

bool detSpoolReadSlot(uint16_t i, DetectionEvent* out, uint16_t* hitCount) {
    if (!s_ready || i >= s_count || !out) return false;
    *out = s_slots[i].evt;
    if (hitCount) *hitCount = s_slots[i].hit_count;
    return true;
}

void detSpoolClear() {
    if (s_ready) LittleFS.remove(SPOOL_PATH);
    s_count = 0;
    s_dropped = 0;
    s_dirty = false;
}

void detSpoolFlushIfDirty() {
    if (!s_ready || !s_dirty) return;
    uint32_t now = millis();
    if (now - s_lastFlushMs < SPOOL_FLUSH_MS) return;
    s_lastFlushMs = now;
    persist();
}

#ifdef OUISPY_SPOOL_SELFTEST
void detSpoolSelfTest() {
    detSpoolClear();
    DetectionEvent e;
    memset(&e, 0, sizeof(e));
    e.engine_id = 1;
    for (int i = 0; i < 5; i++) {
        e.mac[5] = (uint8_t)i;
        e.timestamp_ms = (uint32_t)(1000 + i);
        detSpoolAppend(&e);
    }
    e.mac[5] = 2;
    e.timestamp_ms = 9999;
    detSpoolAppend(&e);
    uint16_t hc = 0; DetectionEvent r;
    bool ok = true;
    ok &= (detSpoolCount() == 5);
    for (uint16_t i = 0; i < detSpoolCount(); i++) {
        if (detSpoolReadSlot(i, &r, &hc) && r.mac[5] == 2) ok &= (hc == 2);
    }
    Serial.printf("[SPOOL-TEST] count=%u (want 5) dedup=%s\n",
                  detSpoolCount(), ok ? "PASS" : "FAIL");
    persist();
    s_count = 0; s_ready = false;
    heap_caps_free(s_slots); s_slots = nullptr;
    detSpoolInit();
    Serial.printf("[SPOOL-TEST] reload=%u (want 5) %s\n",
                  detSpoolCount(), detSpoolCount() == 5 ? "PASS" : "FAIL");
}
#endif
