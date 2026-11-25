// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
//
// BLE Sniff: passive capture of every BLE advert (duplicates kept) as LE LL pcap records on the PCAP data
// stream, ported from colonelpanichacks/unified-blue raw/blesniff.cpp (MIT). The app shows the live advert
// table and writes the .pcap; nothing is stored on the board.

#include "blesniff.h"
#include "blesniff_frame.h"
#include "../protocol.h"
#include "../ble_gatt.h"
#include "../ble_coex.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include <Arduino.h>
#include <Preferences.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_heap_caps.h>

#ifdef OUISPY_TINYRAM
#define BLESNIFF_BUF_SIZE (4u * 1024u)
#else
#define BLESNIFF_BUF_SIZE (8u * 1024u)
#endif

static volatile bool g_active = false;
static uint8_t g_ftMask = BLESNIFF_FT_DEFAULT;
static unsigned long g_startedAt = 0;
static unsigned long g_lastStats = 0;

static uint8_t* g_bufA = nullptr;
static uint8_t* g_bufB = nullptr;
static volatile uint32_t g_sizeA = 0;
static volatile uint32_t g_sizeB = 0;
static volatile bool g_useA = true;
static portMUX_TYPE g_mux = portMUX_INITIALIZER_UNLOCKED;
static TaskHandle_t g_sender = nullptr;

static volatile uint32_t g_cntAdv = 0;
static volatile uint32_t g_cntRsp = 0;
static volatile uint32_t g_cntBytes = 0;
static volatile uint32_t g_cntDropped = 0;

static bool appendRecord(const uint8_t* rec, uint32_t len) {
    portENTER_CRITICAL(&g_mux);
    if (!g_bufA || !g_bufB) {
        portEXIT_CRITICAL(&g_mux);
        return false;
    }
    uint8_t* cur = g_useA ? g_bufA : g_bufB;
    volatile uint32_t* curSize = g_useA ? &g_sizeA : &g_sizeB;
    if (*curSize + len > BLESNIFF_BUF_SIZE) {
        volatile uint32_t* otherSize = g_useA ? &g_sizeB : &g_sizeA;
        if (*otherSize != 0) {
            g_cntDropped++;
            portEXIT_CRITICAL(&g_mux);
            if (g_sender) xTaskNotifyGive(g_sender);
            return false;
        }
        g_useA = !g_useA;
        cur = g_useA ? g_bufA : g_bufB;
        curSize = g_useA ? &g_sizeA : &g_sizeB;
        memcpy(cur + *curSize, rec, len);
        *curSize += len;
        portEXIT_CRITICAL(&g_mux);
        if (g_sender) xTaskNotifyGive(g_sender);
        return true;
    }
    memcpy(cur + *curSize, rec, len);
    *curSize += len;
    portEXIT_CRITICAL(&g_mux);
    return true;
}

static void emitFrame(uint8_t ll, bool txRandom, const uint8_t* advA, const uint8_t* targetA,
                      const uint8_t* adv, uint8_t advLen, int8_t rssi) {
    uint8_t frame[BLESNIFF_FRAME_MAX];
    uint8_t rec[BLESNIFF_REC_MAX];
    size_t fl = blesniffBuildFrame(frame, ll, txRandom, advA, targetA, adv, advLen, rssi);
    size_t rl = blesniffPackRecord(rec, (uint32_t)micros(), frame, (uint32_t)fl);
    appendRecord(rec, (uint32_t)rl);
}

class BlesniffCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        if (!g_active) return;
        uint8_t hci = dev->getAdvType();
        uint8_t rawAt = dev->getAddressType();
        if (!blesniffPass(g_ftMask, hci, rawAt)) return;

        uint8_t advA[6];
        memcpy(advA, dev->getAddress().getNative(), 6);
        bool txRandom = (rawAt == 1 || rawAt == 3);
        int8_t rssi = (int8_t)dev->getRSSI();
#ifdef OUISPY_NIMBLE2_API
        const std::vector<uint8_t>& pl = dev->getPayload();
        const uint8_t* payload = pl.data();
        size_t payLen = pl.size();
#else
        const uint8_t* payload = dev->getPayload();
        size_t payLen = dev->getPayloadLength();
#endif
        size_t advLen = dev->getAdvLength();
        if (advLen > payLen) advLen = payLen;
        size_t scanLen = payLen - advLen;

        bool hasTarget = (hci == 1) && dev->haveTargetAddress();
        uint8_t targetA[6];
        if (hasTarget) memcpy(targetA, dev->getTargetAddress(0).getNative(), 6);

        uint8_t ll = blesniffLlFromHci(hci);
        emitFrame(ll, txRandom, advA, hasTarget ? targetA : nullptr, payload, (uint8_t)advLen, rssi);
        if (hci == 4) g_cntRsp++; else g_cntAdv++;

        if (scanLen > 0 && hci != 4 && (g_ftMask & BLESNIFF_FT_SCAN_RSP)) {
            emitFrame(BLESNIFF_LL_SCAN_RSP, txRandom, advA, nullptr, payload + advLen, (uint8_t)scanLen, rssi);
            g_cntRsp++;
        }
    }
};

static BlesniffCallbacks g_cb;

static void drainBuffers(void) {
    uint8_t* buf = nullptr;
    uint32_t len = 0;
    portENTER_CRITICAL(&g_mux);
    if (g_useA && g_sizeB > 0) {
        buf = g_bufB; len = g_sizeB; g_sizeB = 0;
    } else if (!g_useA && g_sizeA > 0) {
        buf = g_bufA; len = g_sizeA; g_sizeA = 0;
    } else if (g_useA && g_sizeA > 0) {
        buf = g_bufA; len = g_sizeA; g_sizeA = 0; g_useA = false;
    } else if (!g_useA && g_sizeB > 0) {
        buf = g_bufB; len = g_sizeB; g_sizeB = 0; g_useA = true;
    }
    portEXIT_CRITICAL(&g_mux);
    if (buf && len) {
        bleGattStreamPcapBytes(buf, len);
        g_cntBytes += len;
    }
}

static void freeBuffers(void) {
    uint8_t* a;
    uint8_t* b;
    portENTER_CRITICAL(&g_mux);
    a = g_bufA; g_bufA = nullptr;
    b = g_bufB; g_bufB = nullptr;
    g_sizeA = g_sizeB = 0;
    g_useA = true;
    portEXIT_CRITICAL(&g_mux);
    if (a) free(a);
    if (b) free(b);
}

static void senderTask(void*) {
    while (true) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(100));
        if (!g_active && g_sizeA == 0 && g_sizeB == 0) break;
        drainBuffers();
    }
    freeBuffers();
    g_sender = nullptr;
    vTaskDelete(NULL);
}

static bool allocBuffers(void) {
    uint32_t caps = MALLOC_CAP_8BIT;
#ifdef BOARD_HAS_PSRAM
    caps |= MALLOC_CAP_SPIRAM;
#endif
    g_bufA = (uint8_t*)heap_caps_malloc(BLESNIFF_BUF_SIZE, caps);
    g_bufB = (uint8_t*)heap_caps_malloc(BLESNIFF_BUF_SIZE, caps);
    if (!g_bufA) g_bufA = (uint8_t*)malloc(BLESNIFF_BUF_SIZE);
    if (!g_bufB) g_bufB = (uint8_t*)malloc(BLESNIFF_BUF_SIZE);
    if (g_bufA && g_bufB) return true;
    if (g_bufA) { free(g_bufA); g_bufA = nullptr; }
    if (g_bufB) { free(g_bufB); g_bufB = nullptr; }
    return false;
}

static void blesniffInit(void) {
    Preferences p;
    p.begin("blesniff", true);
    g_ftMask = p.getUChar("ftmask", BLESNIFF_FT_DEFAULT);
    p.end();
    if (g_ftMask == 0) g_ftMask = BLESNIFF_FT_DEFAULT;
    Serial.printf("[BLESNIFF] Initialized ftmask=0x%02X\n", g_ftMask);
}

static void blesniffStart(void) {
    if (g_active) return;
    if (!allocBuffers()) {
        Serial.println("[BLESNIFF] buffer alloc failed");
        engineSetState(ENGINE_BLESNIFF, ESTATE_DISABLED);
        return;
    }
    g_cntAdv = g_cntRsp = g_cntBytes = g_cntDropped = 0;
    g_startedAt = millis();
    g_lastStats = 0;
    g_active = true;
#ifdef OUISPY_TINYRAM
    const uint32_t stack = 4096;
#else
    const uint32_t stack = 6144;
#endif
    if (xTaskCreatePinnedToCore(senderTask, "bsn_tx", stack, NULL, 5, &g_sender, 1) != pdPASS) {
        Serial.println("[BLESNIFF] sender task create failed");
        g_active = false;
        freeBuffers();
        engineSetState(ENGINE_BLESNIFF, ESTATE_DISABLED);
        return;
    }
    bleCoexRegister(&g_cb, false);
    Serial.printf("[BLESNIFF] Started ftmask=0x%02X buf=2x%u\n", g_ftMask, (unsigned)BLESNIFF_BUF_SIZE);
    bleGattNotifyPcapStats();
}

static void blesniffStop(void) {
    if (!g_active) {
        engineSetState(ENGINE_BLESNIFF, ESTATE_DISABLED);
        return;
    }
    g_active = false;
    bleCoexUnregister(&g_cb);
    if (g_sender) {
        xTaskNotifyGive(g_sender);
        for (int i = 0; i < 100 && g_sender != nullptr; i++) vTaskDelay(pdMS_TO_TICKS(20));
    } else {
        freeBuffers();
    }
    engineSetState(ENGINE_BLESNIFF, ESTATE_DISABLED);
    bleGattNotifyPcapStats();
    Serial.printf("[BLESNIFF] Stopped adv=%lu rsp=%lu dropped=%lu bytes=%lu\n", (unsigned long)g_cntAdv,
                  (unsigned long)g_cntRsp, (unsigned long)g_cntDropped, (unsigned long)g_cntBytes);
}

static void blesniffLoop(void) {
    if (!g_active) return;
    if (meshIsEnabled() && meshInMeshWindow()) return;
    bleCoexEnsureScanning();
    unsigned long now = millis();
    if (g_sender && (g_sizeA + g_sizeB) > (BLESNIFF_BUF_SIZE / 4)) xTaskNotifyGive(g_sender);
    if (now - g_lastStats >= 500) {
        g_lastStats = now;
        bleGattNotifyPcapStats();
    }
}

static void blesniffConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    if (!cfgTgtStrip(&payload, &len, meshGetLocalNodeId())) return;
    if (len < 2 || payload[0] != BLESNIFF_CFG_FILTER) return;
    uint8_t m = (uint8_t)(payload[1] & 0x7F);
    g_ftMask = m ? m : BLESNIFF_FT_DEFAULT;
    Preferences p;
    p.begin("blesniff", false);
    p.putUChar("ftmask", g_ftMask);
    p.end();
    Serial.printf("[BLESNIFF] ftmask -> 0x%02X\n", g_ftMask);
}

bool blesniffActive(void) { return g_active; }

void blesniffFillStats(PcapStats* out) {
    if (!out || !g_active) return;
    out->state = 1;
    out->mode = PCAP_MODE_BLE;
    out->_reserved = PCAP_SRC_BLESNIFF;
    out->ble_adv_count = g_cntAdv;
    out->ble_scan_count = g_cntRsp;
    out->bytes_written = g_cntBytes;
    out->file_size = g_cntBytes;
    out->dropped_frames = g_cntDropped;
    out->uptime_ms = (uint32_t)(millis() - g_startedAt);
}

const EngineCallbacks blesniffCallbacks = {
    .init       = blesniffInit,
    .start      = blesniffStart,
    .stop       = blesniffStop,
    .loop       = blesniffLoop,
    .config     = blesniffConfig,
    .applyPrefs = nullptr,
    .name       = "BLE-Sniff"
};
