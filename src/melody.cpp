#include <Arduino.h>
#include <Preferences.h>
#include "protocol.h"

static MelodyEntry melTable[MELODY_MAX_ENTRIES];
static uint8_t melCount = 0;
static portMUX_TYPE melMux = portMUX_INITIALIZER_UNLOCKED;

static void melodySave(void) {
    MelodyEntry copy[MELODY_MAX_ENTRIES];
    portENTER_CRITICAL(&melMux);
    uint8_t n = melCount;
    memcpy(copy, melTable, sizeof(MelodyEntry) * n);
    portEXIT_CRITICAL(&melMux);
    Preferences p;
    p.begin("ouispy-mel", false);
    if (n) p.putBytes("tbl", copy, sizeof(MelodyEntry) * n);
    p.putUChar("n", n);
    p.end();
}

void melodyInit(void) {
    Preferences p;
    p.begin("ouispy-mel", true);
    uint8_t n = p.getUChar("n", 0);
    if (n > MELODY_MAX_ENTRIES) n = 0;
    size_t got = n ? p.getBytes("tbl", melTable, sizeof(MelodyEntry) * n) : 0;
    p.end();
    melCount = (got == sizeof(MelodyEntry) * n) ? n : 0;
    for (uint8_t i = 0; i < melCount; i++)
        if (melTable[i].n > MELODY_MAX_NOTES) melTable[i].n = MELODY_MAX_NOTES;
    Serial.printf("[MELODY] %u assignments\n", (unsigned)melCount);
}

static int melFind(uint8_t engine, uint8_t method) {
    for (uint8_t i = 0; i < melCount; i++)
        if (melTable[i].engine == engine && melTable[i].method == method) return i;
    return -1;
}

void melodyApply(const uint8_t* d, size_t len) {
    if (len < 1) return;
    uint8_t op = d[0];
    bool changed = false;
    if (op == MELODY_OP_SET && len >= 4) {
        uint8_t n = d[3] > MELODY_MAX_NOTES ? MELODY_MAX_NOTES : d[3];
        if (len < 4 + (size_t)n * 3) n = (uint8_t)((len - 4) / 3);
        portENTER_CRITICAL(&melMux);
        int i = melFind(d[1], d[2]);
        bool added = false;
        if (i < 0 && melCount < MELODY_MAX_ENTRIES) { i = melCount++; added = true; }
        if (i >= 0) {
            changed = added || melTable[i].engine != d[1] || melTable[i].method != d[2] ||
                      melTable[i].n != n || memcmp(melTable[i].notes, d + 4, (size_t)n * 3) != 0;
            melTable[i].engine = d[1];
            melTable[i].method = d[2];
            melTable[i].n = n;
            memcpy(melTable[i].notes, d + 4, (size_t)n * 3);
        }
        portEXIT_CRITICAL(&melMux);
    } else if (op == MELODY_OP_SYNC && len >= 6) {
        uint8_t idx = d[1], total = d[2];
        uint8_t n = d[5] > MELODY_MAX_NOTES ? MELODY_MAX_NOTES : d[5];
        if (len < 6 + (size_t)n * 3) n = (uint8_t)((len - 6) / 3);
        if (idx < total && total <= MELODY_MAX_ENTRIES) {
            portENTER_CRITICAL(&melMux);
            changed = melCount != total || melTable[idx].engine != d[3] ||
                      melTable[idx].method != d[4] || melTable[idx].n != n ||
                      memcmp(melTable[idx].notes, d + 6, (size_t)n * 3) != 0;
            melTable[idx].engine = d[3];
            melTable[idx].method = d[4];
            melTable[idx].n = n;
            memcpy(melTable[idx].notes, d + 6, (size_t)n * 3);
            melCount = total;
            portEXIT_CRITICAL(&melMux);
        }
    } else if (op == MELODY_OP_CLEAR && len >= 3) {
        portENTER_CRITICAL(&melMux);
        int i = melFind(d[1], d[2]);
        if (i >= 0) { melTable[i] = melTable[--melCount]; changed = true; }
        portEXIT_CRITICAL(&melMux);
    } else if (op == MELODY_OP_CLEAR_ALL) {
        portENTER_CRITICAL(&melMux);
        changed = melCount != 0;
        melCount = 0;
        portEXIT_CRITICAL(&melMux);
    }
    if (changed) melodySave();
}

size_t melodyGetEntryOp(uint8_t idx, uint8_t* out) {
    size_t len = 0;
    portENTER_CRITICAL(&melMux);
    if (idx < melCount) {
        const MelodyEntry& e = melTable[idx];
        out[0] = MELODY_OP_SYNC; out[1] = idx; out[2] = melCount;
        out[3] = e.engine; out[4] = e.method; out[5] = e.n;
        memcpy(out + 6, e.notes, (size_t)e.n * 3);
        len = 6 + (size_t)e.n * 3;
    }
    portEXIT_CRITICAL(&melMux);
    return len;
}

uint8_t melodyCount(void) { return melCount; }

bool melodyLookup(uint8_t engine, uint8_t method, uint8_t* n, uint8_t notes[][3]) {
    bool found = false;
    portENTER_CRITICAL(&melMux);
    int i = melFind(engine, method);
    if (i < 0) i = melFind(engine, MELODY_ANY);
    if (i < 0 && engine < ENGINE_COUNT) i = melFind(MELODY_ANY, MELODY_ANY);
    if (i >= 0) {
        *n = melTable[i].n;
        memcpy(notes, melTable[i].notes, (size_t)melTable[i].n * 3);
        found = true;
    }
    portEXIT_CRITICAL(&melMux);
    return found;
}
