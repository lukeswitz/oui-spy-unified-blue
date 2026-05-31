#include "ignore_list.h"
#include <Arduino.h>
#include <Preferences.h>
#include <string.h>
#include <ctype.h>

struct IgnoreSlot {
    uint8_t type;
    uint8_t scope;
    uint8_t len;
    uint8_t value[IGNORE_MAX_VALUE];
};

static IgnoreSlot g_entries[IGNORE_MAX_ENTRIES];
static uint8_t g_count = 0;
static uint32_t g_version = 0;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;

void ignoreListInit(void) {
    // Runtime-only. The app is the single source of truth: it pushes the list
    // on every connect and the manager re-broadcasts it to all nodes, so no
    // per-node copy can diverge. Nothing is persisted. Wipe any list a prior
    // firmware left in NVS (a normal flash does NOT erase NVS).
    Preferences p;
    if (p.begin("ouispy-ign", false)) {
        p.clear();
        p.end();
    }
    portENTER_CRITICAL(&g_mux);
    g_count = 0;
    g_version++;
    portEXIT_CRITICAL(&g_mux);
}

void ignoreListSet(const uint8_t* buf, size_t len) {
    if (!buf || len < 1) {
        portENTER_CRITICAL(&g_mux);
        g_count = 0;
        g_version++;
        portEXIT_CRITICAL(&g_mux);
        Serial.println("[IGNORE] list cleared");
        return;
    }
    IgnoreSlot tmp[IGNORE_MAX_ENTRIES];
    uint8_t cnt = 0;
    size_t i = 0;
    uint8_t declared = buf[i++];
    while (i + 3 <= len && cnt < IGNORE_MAX_ENTRIES) {
        uint8_t type = buf[i++];
        uint8_t scope = buf[i++];
        uint8_t vlen = buf[i++];
        if (vlen == 0 || vlen > IGNORE_MAX_VALUE) break;
        if (i + vlen > len) break;
        tmp[cnt].type = type;
        tmp[cnt].scope = scope;
        tmp[cnt].len = vlen;
        memcpy(tmp[cnt].value, buf + i, vlen);
        i += vlen;
        cnt++;
    }
    bool same;
    portENTER_CRITICAL(&g_mux);
    same = (cnt == g_count) && (memcmp(g_entries, tmp, sizeof(IgnoreSlot) * cnt) == 0);
    if (!same) {
        memcpy(g_entries, tmp, sizeof(IgnoreSlot) * cnt);
        g_count = cnt;
        g_version++;
    }
    portEXIT_CRITICAL(&g_mux);
    if (same) return;
    Serial.printf("[IGNORE] list set: %u entries (declared %u, v%lu)\n",
                  cnt, declared, (unsigned long)g_version);
}

static bool ssidEq(const uint8_t* v, uint8_t vlen, const char* ssid) {
    if (!ssid) return false;
    size_t sl = strnlen(ssid, 32);
    if (sl != vlen) return false;
    return memcmp(v, ssid, vlen) == 0;
}

bool ignoreListMatch(const uint8_t mac[6], const char* ssid, bool isBle) {
    if (g_count == 0) return false;
    bool hit = false;
    portENTER_CRITICAL(&g_mux);
    for (uint8_t i = 0; i < g_count; i++) {
        const IgnoreSlot& e = g_entries[i];
        if (e.scope == IGNORE_SCOPE_WIFI && isBle) continue;
        if (e.scope == IGNORE_SCOPE_BLE && !isBle) continue;
        switch (e.type) {
            case IGNORE_TYPE_MAC:
                if (e.len == 6 && memcmp(e.value, mac, 6) == 0) { hit = true; }
                break;
            case IGNORE_TYPE_OUI:
                if (e.len == 3 && memcmp(e.value, mac, 3) == 0) { hit = true; }
                break;
            case IGNORE_TYPE_SSID:
                if (ssid && ssid[0] && ssidEq(e.value, e.len, ssid)) { hit = true; }
                break;
            default: break;
        }
        if (hit) break;
    }
    portEXIT_CRITICAL(&g_mux);
    return hit;
}

size_t ignoreListSerialize(uint8_t* out, size_t maxLen) {
    if (!out || maxLen < 1) return 0;
    size_t i = 0;
    portENTER_CRITICAL(&g_mux);
    out[i++] = g_count;
    for (uint8_t e = 0; e < g_count; e++) {
        if (i + 3 + g_entries[e].len > maxLen) break;
        out[i++] = g_entries[e].type;
        out[i++] = g_entries[e].scope;
        out[i++] = g_entries[e].len;
        memcpy(out + i, g_entries[e].value, g_entries[e].len);
        i += g_entries[e].len;
    }
    portEXIT_CRITICAL(&g_mux);
    return i;
}

uint8_t ignoreListCount(void) { return g_count; }
uint32_t ignoreListVersion(void) { return g_version; }
