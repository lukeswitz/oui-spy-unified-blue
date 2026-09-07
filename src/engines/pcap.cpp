#include "pcap.h"
#include "../protocol.h"
#include "../ble_gatt.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_heap_caps.h>
#ifdef OUISPY_DONGLE
#include "../dongle.h"
#endif

#define PCAP_LT_WIFI         127u
#define PCAP_LT_BLE          256u
#define PCAP_RADIOTAP_LEN    18u
#define PCAP_SNAPLEN         2324u
#ifdef OUISPY_TINYRAM
#define PCAP_BUF_SIZE        (4u * 1024u)
#else
#define PCAP_BUF_SIZE        (16u * 1024u)
#endif
#define BLE_ADV_ACCESS_ADDR  0x8E89BED6u

static volatile bool pcapActive = false;
static volatile uint8_t pcapMode = PCAP_MODE_WIFI;
static uint8_t pcapChanStart = 1;
static uint8_t pcapChanEnd   = 11;
static uint16_t pcapDwellMs  = 250;
static uint8_t pcapHopIdx    = 0;
static uint8_t pcapCurChan   = 1;
#ifdef OUISPY_DUAL_BAND
static const uint8_t kPcap5g[] = {36, 40, 44, 48, 149, 153, 157, 161, 165};
static const uint8_t kPcap5gDfs[] = {52, 56, 60, 64, 100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144};
static uint8_t pcap5gMode = 1;
#define PCAP_MAX_HOPS 48
#else
#define PCAP_MAX_HOPS 32
#endif
static uint8_t pcapHopList[PCAP_MAX_HOPS];
static uint8_t pcapHopListLen = 0;
static bool    pcapRendezvousInSet = false;
static unsigned long pcapLastHop = 0;
static unsigned long pcapStartedAt = 0;
static unsigned long pcapLastStatsNotify = 0;

static volatile uint8_t pcapState = 0;
static volatile bool pcapPaused = false;
static volatile uint32_t pcapStreamedBytes = 0;

static uint8_t* bufA = nullptr;
static uint8_t* bufB = nullptr;
static volatile uint32_t bufSizeA = 0;
static volatile uint32_t bufSizeB = 0;
static volatile bool useA = true;
static portMUX_TYPE pcapBufMux = portMUX_INITIALIZER_UNLOCKED;
static TaskHandle_t pcapSenderHandle = nullptr;

static volatile uint32_t cntBeacon = 0;
static volatile uint32_t cntProbeReq = 0;
static volatile uint32_t cntProbeResp = 0;
static volatile uint32_t cntDeauth = 0;
static volatile uint32_t cntDisassoc = 0;
static volatile uint32_t cntData = 0;
static volatile uint32_t cntCtrl = 0;
static volatile uint32_t cntMgmtOther = 0;
static volatile uint32_t cntBleAdv = 0;
static volatile uint32_t cntBleScan = 0;
static volatile uint32_t cntBytes = 0;
static volatile uint32_t cntDropped = 0;

static NimBLEScan* pPcapScan = nullptr;

static void resetCounters(void) {
    cntBeacon = cntProbeReq = cntProbeResp = 0;
    cntDeauth = cntDisassoc = cntData = cntCtrl = cntMgmtOther = 0;
    cntBleAdv = cntBleScan = cntBytes = cntDropped = 0;
    pcapStreamedBytes = 0;
}

static bool IRAM_ATTR appendFrame(const uint8_t* frame, uint32_t flen) {
    if (!pcapActive) return false;

    uint32_t us = (uint32_t)micros();
    uint32_t ts_sec = us / 1000000u;
    uint32_t ts_usec = us - ts_sec * 1000000u;

    uint8_t rec[24];
    uint32_t magic = 0xCAFEBABEu;
    uint32_t recLen = 16u + flen;
    memcpy(rec + 0,  &magic, 4);
    memcpy(rec + 4,  &recLen, 4);
    memcpy(rec + 8,  &ts_sec, 4);
    memcpy(rec + 12, &ts_usec, 4);
    memcpy(rec + 16, &flen, 4);
    memcpy(rec + 20, &flen, 4);
    uint8_t endMarker[4];
    uint32_t emval = 0xDEADBEEFu;
    memcpy(endMarker, &emval, 4);

    portENTER_CRITICAL_ISR(&pcapBufMux);
    if (bufA == nullptr || bufB == nullptr) {
        portEXIT_CRITICAL_ISR(&pcapBufMux);
        return false;
    }
    uint32_t need = 24 + flen + 4;
    if (useA) {
        if (bufSizeA + need > PCAP_BUF_SIZE) {
            if (bufSizeB == 0) {
                useA = false;
                memcpy(bufB + bufSizeB, rec, 24); bufSizeB += 24;
                memcpy(bufB + bufSizeB, frame, flen); bufSizeB += flen;
                memcpy(bufB + bufSizeB, endMarker, 4); bufSizeB += 4;
                portEXIT_CRITICAL_ISR(&pcapBufMux);
                if (pcapSenderHandle) xTaskNotifyGive(pcapSenderHandle);
                return true;
            }
            cntDropped++;
            portEXIT_CRITICAL_ISR(&pcapBufMux);
            return false;
        }
        memcpy(bufA + bufSizeA, rec, 24); bufSizeA += 24;
        memcpy(bufA + bufSizeA, frame, flen); bufSizeA += flen;
        memcpy(bufA + bufSizeA, endMarker, 4); bufSizeA += 4;
    } else {
        if (bufSizeB + need > PCAP_BUF_SIZE) {
            if (bufSizeA == 0) {
                useA = true;
                memcpy(bufA + bufSizeA, rec, 24); bufSizeA += 24;
                memcpy(bufA + bufSizeA, frame, flen); bufSizeA += flen;
                memcpy(bufA + bufSizeA, endMarker, 4); bufSizeA += 4;
                portEXIT_CRITICAL_ISR(&pcapBufMux);
                if (pcapSenderHandle) xTaskNotifyGive(pcapSenderHandle);
                return true;
            }
            cntDropped++;
            portEXIT_CRITICAL_ISR(&pcapBufMux);
            return false;
        }
        memcpy(bufB + bufSizeB, rec, 24); bufSizeB += 24;
        memcpy(bufB + bufSizeB, frame, flen); bufSizeB += flen;
        memcpy(bufB + bufSizeB, endMarker, 4); bufSizeB += 4;
    }
    portEXIT_CRITICAL_ISR(&pcapBufMux);
    return true;
}

static IRAM_ATTR uint16_t wifiChanToFreq(uint8_t ch) {
    if (ch >= 1 && ch <= 13) return (uint16_t)(2407 + ch * 5);
    if (ch == 14) return 2484u;
    return 0u;
}

static IRAM_ATTR uint16_t wifiChanFlags(uint8_t ch) {
    uint16_t flags = 0x0080u;
    uint16_t freq = wifiChanToFreq(ch);
    if (freq >= 2412u && freq <= 2484u) flags |= 0x0040u;
    return flags;
}

static void IRAM_ATTR pcapWifiCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    if (!pcapActive || pcapPaused) return;
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA && type != WIFI_PKT_CTRL) return;
    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    const uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len > 4) len -= 4;
    if (len < 10) return;
    if (len > (int)(PCAP_SNAPLEN - PCAP_RADIOTAP_LEN)) len = PCAP_SNAPLEN - PCAP_RADIOTAP_LEN;

    uint8_t fc0 = p[0];
    uint8_t ft = (fc0 >> 2) & 0x03;
    uint8_t st = (fc0 >> 4) & 0x0F;
    if (ft == 0) {
        switch (st) {
            case 4:  cntProbeReq++; break;
            case 5:  cntProbeResp++; break;
            case 8:  cntBeacon++; break;
            case 10: cntDisassoc++; break;
            case 12: cntDeauth++; break;
            default: cntMgmtOther++; break;
        }
    } else if (ft == 1) cntCtrl++;
    else if (ft == 2) cntData++;

    uint8_t body[PCAP_RADIOTAP_LEN + 2400];
    uint16_t rtlen = PCAP_RADIOTAP_LEN;
    uint16_t freq = wifiChanToFreq(pkt->rx_ctrl.channel);
    uint16_t cflags = wifiChanFlags(pkt->rx_ctrl.channel);
    body[0] = 0;
    body[1] = 0;
    body[2] = (uint8_t)(rtlen & 0xFF);
    body[3] = (uint8_t)(rtlen >> 8);
    body[4] = 0x0A; body[5] = 0; body[6] = 0; body[7] = 0;
    body[8] = 0;
    body[9] = (uint8_t)(pkt->rx_ctrl.rate & 0x1F);
    body[10] = (uint8_t)(freq & 0xFF);
    body[11] = (uint8_t)(freq >> 8);
    body[12] = (uint8_t)(cflags & 0xFF);
    body[13] = (uint8_t)(cflags >> 8);
    body[14] = (uint8_t)pkt->rx_ctrl.rssi;
    body[15] = (uint8_t)-128;
    body[16] = 0;
    body[17] = 0;
    memcpy(body + PCAP_RADIOTAP_LEN, p, len);
    appendFrame(body, (uint32_t)(PCAP_RADIOTAP_LEN + len));
}

static uint8_t mapPduType(uint8_t advType) {
    switch (advType) {
        case 0: return 0;
        case 1: return 1;
        case 2: return 6;
        case 3: return 2;
        case 4: return 4;
        default: return 0;
    }
}

static inline uint8_t addrIsRandom(uint8_t at) {
    return (at == 1 || at == 3) ? 1 : 0;
}

static constexpr uint16_t BLE_PHDR_FLAGS = 0x0001 | 0x0002 | 0x0010 | 0x0400 | 0x0800;

static uint32_t bleCrc24(const uint8_t* data, size_t len, uint32_t init = 0x555555u) {
    uint32_t crc = init;
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

static void emitBleFrame(uint8_t pduType, uint8_t addrType,
                         const uint8_t* advA, const uint8_t* targetA,
                         const uint8_t* advData, uint8_t advDataLen, int8_t rssi) {
    if (advDataLen > 31) advDataLen = 31;
    const uint8_t targetLen = (targetA != nullptr) ? 6 : 0;
    const uint8_t payloadLen = 6 + targetLen + advDataLen;

    uint8_t body[64];
    size_t off = 0;
    body[off++] = 37;
    body[off++] = (uint8_t)rssi;
    body[off++] = (uint8_t)-128;
    body[off++] = 0;
    uint32_t aa = BLE_ADV_ACCESS_ADDR;
    memcpy(body + off, &aa, 4); off += 4;
    uint16_t flags = BLE_PHDR_FLAGS;
    memcpy(body + off, &flags, 2); off += 2;
    memcpy(body + off, &aa, 4); off += 4;
    size_t pduStart = off;
    uint8_t txAdd = addrIsRandom(addrType);
    body[off++] = (pduType & 0x0F) | (txAdd << 6);
    body[off++] = payloadLen;
    memcpy(body + off, advA, 6); off += 6;
    if (targetLen)  { memcpy(body + off, targetA, 6); off += 6; }
    if (advDataLen) { memcpy(body + off, advData, advDataLen); off += advDataLen; }
    uint32_t crc = bleCrc24(body + pduStart, 2u + (size_t)payloadLen);
    body[off++] = (uint8_t)(crc & 0xFF);
    body[off++] = (uint8_t)((crc >> 8) & 0xFF);
    body[off++] = (uint8_t)((crc >> 16) & 0xFF);
    appendFrame(body, (uint32_t)off);
}

class PcapBleCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        if (!pcapActive || pcapPaused) return;
        uint8_t evType = dev->getAdvType();
        if (evType == 4) cntBleScan++;
        else             cntBleAdv++;

        uint8_t advA[6];
        memcpy(advA, dev->getAddress().getNative(), 6);
        uint8_t addrType = dev->getAddressType();
        int8_t  rssi = (int8_t)dev->getRSSI();

#ifdef OUISPY_NIMBLE2
        const std::vector<uint8_t>& _pl = dev->getPayload();
        const uint8_t* payload = _pl.data();
        size_t payLen = _pl.size();
#else
        uint8_t* payload = dev->getPayload();
        size_t payLen = dev->getPayloadLength();
#endif
        uint8_t advLen = dev->getAdvLength();
        if (advLen > payLen) advLen = payLen;
        uint8_t scanLen = (uint8_t)((payLen > advLen) ? (payLen - advLen) : 0);

        bool hasTarget = (evType == 1) && dev->haveTargetAddress();
        uint8_t targetA[6];
        if (hasTarget) memcpy(targetA, dev->getTargetAddress(0).getNative(), 6);

        emitBleFrame(mapPduType(evType), addrType, advA,
                     hasTarget ? targetA : nullptr,
                     payload, advLen, rssi);

        if (scanLen > 0 && evType != 4) {
            emitBleFrame(4, addrType, advA, nullptr,
                         payload + advLen, scanLen, rssi);
            cntBleScan++;
        }
    }
};
static PcapBleCallbacks pcapBleCallbacks;

static void pcapBleOnComplete(NimBLEScanResults results) {
    if (pPcapScan && pcapActive) pPcapScan->clearResults();
}

static void drainBuffersOverBle(void) {
    uint8_t* drainBuf = nullptr;
    uint32_t drainLen = 0;
    portENTER_CRITICAL(&pcapBufMux);
    if (useA && bufSizeB > 0) {
        drainBuf = bufB; drainLen = bufSizeB; bufSizeB = 0;
    } else if (!useA && bufSizeA > 0) {
        drainBuf = bufA; drainLen = bufSizeA; bufSizeA = 0;
    } else if (bufSizeA > 0 && useA) {
        drainBuf = bufA; drainLen = bufSizeA; bufSizeA = 0; useA = false;
    } else if (bufSizeB > 0 && !useA) {
        drainBuf = bufB; drainLen = bufSizeB; bufSizeB = 0; useA = true;
    }
    portEXIT_CRITICAL(&pcapBufMux);
    if (drainBuf && drainLen) {
        bleGattStreamPcapBytes(drainBuf, drainLen);
#ifdef OUISPY_DONGLE
        donglePcapWriteFramed(drainBuf, drainLen);
#endif
        pcapStreamedBytes += drainLen;
        cntBytes = pcapStreamedBytes;
    }
}

static void freeBuffers(void);

static void pcapSenderTask(void* /*arg*/) {
    while (true) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(200));
        if (!pcapActive && bufSizeA == 0 && bufSizeB == 0) break;
        drainBuffersOverBle();
    }
    drainBuffersOverBle();
#ifdef OUISPY_DONGLE
    donglePcapClose();
#endif
    freeBuffers();
    Serial.printf("[PCAP] sender exit stackHeadroom=%u internalFree=%u\n",
                  (unsigned)uxTaskGetStackHighWaterMark(NULL),
                  (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
    pcapSenderHandle = nullptr;
    vTaskDelete(NULL);
}

static bool allocBuffers(void) {
    if (bufA && bufB) return true;
    uint32_t caps = MALLOC_CAP_8BIT;
#ifdef BOARD_HAS_PSRAM
    caps |= MALLOC_CAP_SPIRAM;
#endif
    bufA = (uint8_t*)heap_caps_malloc(PCAP_BUF_SIZE, caps);
    bufB = (uint8_t*)heap_caps_malloc(PCAP_BUF_SIZE, caps);
    if (!bufA) bufA = (uint8_t*)malloc(PCAP_BUF_SIZE);
    if (!bufB) bufB = (uint8_t*)malloc(PCAP_BUF_SIZE);
    return bufA != nullptr && bufB != nullptr;
}

static void freeBuffers(void) {
    uint8_t* a = nullptr;
    uint8_t* b = nullptr;
    portENTER_CRITICAL(&pcapBufMux);
    a = bufA; bufA = nullptr;
    b = bufB; bufB = nullptr;
    bufSizeA = bufSizeB = 0;
    useA = true;
    portEXIT_CRITICAL(&pcapBufMux);
    if (a) free(a);
    if (b) free(b);
}

static void pcapInit(void) {
    resetCounters();
    Serial.println("[PCAP] Initialized");
}

static void pcapBuildHopList(void) {
    pcapHopListLen = 0;
    pcapRendezvousInSet = false;
    for (uint8_t c = pcapChanStart; c <= pcapChanEnd && pcapHopListLen < PCAP_MAX_HOPS; c++) {
        if (!wifiChanEnabled(c)) continue;
        if (c == 1) pcapRendezvousInSet = true;
        pcapHopList[pcapHopListLen++] = c;
    }
#ifdef OUISPY_DUAL_BAND
    if (!engineAutoPcapPending() && pcap5gMode >= 1) {
        for (uint8_t i = 0; i < sizeof(kPcap5g) && pcapHopListLen < PCAP_MAX_HOPS; i++) {
            if (wifiChanEnabled(kPcap5g[i])) pcapHopList[pcapHopListLen++] = kPcap5g[i];
        }
        if (pcap5gMode >= 2) {
            for (uint8_t i = 0; i < sizeof(kPcap5gDfs) && pcapHopListLen < PCAP_MAX_HOPS; i++) {
                if (wifiChanEnabled(kPcap5gDfs[i])) pcapHopList[pcapHopListLen++] = kPcap5gDfs[i];
            }
        }
    }
#endif
    if (pcapHopListLen == 0) { pcapHopList[0] = pcapChanStart; pcapHopListLen = 1; }
}

static void pcapStart(void) {
    if (pcapActive) return;
    if (!allocBuffers()) {
        Serial.println("[PCAP] buffer alloc failed");
        pcapState = 3;
        engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
        bleGattNotifyPcapStats();
        return;
    }
    Serial.printf("[PCAP] buffers ok (2x%u) internalFree=%u largest=%u\n",
                  (unsigned)PCAP_BUF_SIZE,
                  (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
                  (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
    bufSizeA = bufSizeB = 0;
    useA = true;
    resetCounters();
    pcapStartedAt = millis();
    pcapLastStatsNotify = 0;
    pcapHopIdx = 0;
    pcapBuildHopList();
    pcapCurChan = pcapHopList[0];
    pcapLastHop = millis();
    pcapActive = true;
    pcapPaused = false;
    pcapState = 1;

#ifdef OUISPY_TINYRAM
    const uint32_t pcapTxStack = 4096;
#else
    const uint32_t pcapTxStack = 8192;
#endif
    if (xTaskCreatePinnedToCore(pcapSenderTask, "pcap_tx",
                                pcapTxStack, NULL, 5, &pcapSenderHandle, 1) != pdPASS) {
        Serial.printf("[PCAP] task create failed (stack=%u internalFree=%u largest=%u)\n",
                      (unsigned)pcapTxStack,
                      (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL),
                      (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL));
        pcapActive = false;
        pcapState = 3;
        freeBuffers();
        engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
        bleGattNotifyPcapStats();
        return;
    }

#ifdef OUISPY_DONGLE
    donglePcapOpen(pcapMode == PCAP_MODE_BLE ? PCAP_LT_BLE : PCAP_LT_WIFI);
#endif

    if (pcapMode == PCAP_MODE_WIFI) {
        bool meshOn = meshIsEnabled();
        if (!meshOn) {
            WiFi.mode(WIFI_STA);
            WiFi.disconnect(false, false);
            vTaskDelay(pdMS_TO_TICKS(50));
        }
        wifiApplyRegdomain();
        wifiSnifferApplyPs();
        wifiCoexRegister(pcapWifiCb,
                         WIFI_PROMIS_FILTER_MASK_MGMT | WIFI_PROMIS_FILTER_MASK_DATA |
                         WIFI_PROMIS_FILTER_MASK_CTRL);
        esp_wifi_set_channel(pcapCurChan, WIFI_SECOND_CHAN_NONE);
        Serial.printf("[PCAP] WiFi promisc on, ch=%u, mesh=%d\n",
                      pcapCurChan, meshOn ? 1 : 0);
    } else {
        pPcapScan = NimBLEDevice::getScan();
        bleCoexRegister(&pcapBleCallbacks, true);
        pPcapScan->setActiveScan(true);
        pPcapScan->setInterval(160);
        pPcapScan->setWindow(159);
        pPcapScan->start(0, pcapBleOnComplete, false);
    }

    engineSetState(ENGINE_PCAP, ESTATE_SCANNING);
    bleGattNotifyPcapStats();
    Serial.printf("[PCAP] Started mode=%s ch=%d-%d\n",
                  pcapMode == PCAP_MODE_BLE ? "BLE" : "WIFI",
                  pcapChanStart, pcapChanEnd);
}

static void pcapStop(void) {
    if (!pcapActive && pcapState != 1 && pcapState != 2) {
        engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
        return;
    }
    pcapActive = false;
    pcapPaused = false;

    if (pcapMode == PCAP_MODE_WIFI) {
        wifiCoexUnregister(pcapWifiCb);
    } else {
        bleCoexUnregister(&pcapBleCallbacks);
        NimBLEScan* localScan = pPcapScan;
        pPcapScan = nullptr;
        if (localScan) {
            if (localScan->isScanning()) localScan->stop();
            vTaskDelay(pdMS_TO_TICKS(200));
            localScan->clearResults();
        }
    }

    if (meshIsEnabled()) {
        esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    }

    if (pcapSenderHandle) {
        xTaskNotifyGive(pcapSenderHandle);
        for (int i = 0; i < 100 && pcapSenderHandle != nullptr; i++) {
            vTaskDelay(pdMS_TO_TICKS(20));
        }
    } else {
        freeBuffers();
    }
    if (pcapState != 2) pcapState = 0;
    engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
    bleGattNotifyPcapStats();
    Serial.printf("[PCAP] Stopped bytes=%lu dropped=%lu\n",
                  (unsigned long)cntBytes, (unsigned long)cntDropped);
}

#ifndef PCAP_MAX_BYTES
#define PCAP_MAX_BYTES (10u * 1024u * 1024u)
#endif

uint32_t pcapCapturedBytes(void) { return pcapStreamedBytes; }

static void pcapLoop(void) {
    if (meshIsEnabled() && meshInMeshWindow()) return;
    unsigned long now = millis();
    if (pcapActive && pcapStreamedBytes >= PCAP_MAX_BYTES) {
        Serial.printf("[PCAP] size cap %u bytes reached — stopping\n",
                      (unsigned)PCAP_MAX_BYTES);
        engineDisable(ENGINE_PCAP);
        return;
    }
    if (!pcapActive) {
        if (now - pcapLastStatsNotify >= 1000) {
            pcapLastStatsNotify = now;
            bleGattNotifyPcapStats();
        }
        return;
    }
#ifdef OUISPY_PCAP_SELFTEST
    {
        static unsigned long lastRate = 0;
        static uint32_t lastB = 0, lastBy = 0;
        if (now - lastRate >= 2000) {
            Serial.printf("[PCAP-RATE] beacons=%lu (+%lu/2s) probeResp=%lu data=%lu bytes=%lu (+%lu/2s)\n",
                (unsigned long)cntBeacon, (unsigned long)(cntBeacon - lastB),
                (unsigned long)cntProbeResp, (unsigned long)cntData,
                (unsigned long)cntBytes, (unsigned long)(cntBytes - lastBy));
            lastB = cntBeacon; lastBy = cntBytes; lastRate = now;
        }
    }
#endif
    if (pcapMode == PCAP_MODE_WIFI) {
        if (wifiCoexShouldHop(ENGINE_PCAP) && now - pcapLastHop >= pcapDwellMs) {
            const bool meshOn = meshIsEnabled();
            const bool rendezvousNow = (pcapCurChan == 1);
            if (meshOn && !pcapRendezvousInSet && !rendezvousNow) {
                pcapCurChan = 1;
            } else {
                pcapHopIdx++;
                if (pcapHopIdx >= pcapHopListLen) pcapHopIdx = 0;
                pcapCurChan = pcapHopList[pcapHopIdx];
            }
            esp_wifi_set_channel(pcapCurChan, WIFI_SECOND_CHAN_NONE);
            pcapLastHop = now;
            if (meshOn && pcapCurChan == 1) meshNoteOnHome();
        }
    }
    if (pcapSenderHandle && (bufSizeA + bufSizeB) > (PCAP_BUF_SIZE / 4)) {
        xTaskNotifyGive(pcapSenderHandle);
    }
    if (now - pcapLastStatsNotify >= 500) {
        pcapLastStatsNotify = now;
        bleGattNotifyPcapStats();
    }
}

static void pcapPause(void) {
    if (!pcapActive || pcapPaused) return;
    pcapPaused = true;
    pcapState = 4;
    Serial.println("[PCAP] Paused");
    bleGattNotifyPcapStats();
}

static void pcapResume(void) {
    if (!pcapActive || !pcapPaused) return;
    pcapPaused = false;
    pcapState = 1;
    Serial.println("[PCAP] Resumed");
    bleGattNotifyPcapStats();
}

static void pcapConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    uint8_t op = payload[0];
    switch (op) {
        case PCAP_CTRL_START:
            if (len >= 2) {
                pcapMode = (payload[1] == PCAP_MODE_BLE) ? PCAP_MODE_BLE : PCAP_MODE_WIFI;
            }
            if (len >= 4) {
                uint8_t cs = payload[2];
                uint8_t ce = payload[3];
                if (cs >= 1 && cs <= 14) pcapChanStart = cs;
                if (ce >= pcapChanStart && ce <= 14) pcapChanEnd = ce;
            }
#ifdef OUISPY_DUAL_BAND
            if (len >= 6) pcap5gMode = payload[5] & 0x03;
#endif
            break;
        case PCAP_CTRL_STOP:   pcapStop(); break;
        case PCAP_CTRL_PAUSE:  pcapPause(); break;
        case PCAP_CTRL_RESUME: pcapResume(); break;
        case 0x10:
            if (len >= 2) engineSetAutoPcap(payload[1] != 0);
            bleGattNotifyPcapStats();
            break;
        case 0x11:
            if (len >= 3) {
                uint16_t s = payload[1] | (payload[2] << 8);
                engineSetAutoPcapDuration(s);
            }
            bleGattNotifyPcapStats();
            break;
        case 0x12:
            if (len >= 3) {
                uint16_t s = payload[1] | (payload[2] << 8);
                engineSetAutoPcapCooldown(s);
            }
            bleGattNotifyPcapStats();
            break;
        default: break;
    }
}

uint8_t pcapActiveMode(void) {
    return pcapActive ? pcapMode : 0xFF;
}

void pcapGetStats(PcapStats* out) {
    if (!out) return;
    out->state            = pcapState;
    out->mode             = pcapMode;
    out->current_channel  = pcapCurChan;
    out->_reserved        = 0;
    out->beacon_count     = cntBeacon;
    out->probe_req_count  = cntProbeReq;
    out->probe_resp_count = cntProbeResp;
    out->deauth_count     = cntDeauth;
    out->disassoc_count   = cntDisassoc;
    out->data_count       = cntData;
    out->ctrl_count       = cntCtrl;
    out->mgmt_other_count = cntMgmtOther;
    out->ble_adv_count    = cntBleAdv;
    out->ble_scan_count   = cntBleScan;
    out->bytes_written    = cntBytes;
    out->dropped_frames   = cntDropped;
    out->file_size        = pcapStreamedBytes;
    out->uptime_ms        = pcapActive ? (uint32_t)(millis() - pcapStartedAt) : 0u;
    out->auto_enabled     = engineAutoPcapEnabled() ? 1 : 0;
    out->auto_duration_sec = engineGetAutoPcapDuration();
    out->paused_mask      = engineGetAutoPcapPausedMask();
    out->auto_remaining_ms = engineGetAutoPcapRemainingMs();
    out->auto_trigger_src = engineGetAutoPcapTriggerSrc();
    const uint8_t* tm = engineGetAutoPcapTriggerMac();
    if (tm) memcpy(out->auto_trigger_mac, tm, 6);
    else memset(out->auto_trigger_mac, 0, 6);
    out->auto_cooldown_sec = engineGetAutoPcapCooldown();
    out->auto_cooldown_remaining_ms = engineGetAutoPcapCooldownRemainingMs();

    if (!pcapActive && out->auto_trigger_src == 0xFF) {
        MeshAutoPcapEventPacket ev;
        uint32_t age = 0;
        uint32_t maxAgeMs = (uint32_t)out->auto_duration_sec * 1000U + 2000U;
        if (maxAgeMs < 12000U) maxAgeMs = 12000U;
        if (meshGetLatestAutoPcapEvent(maxAgeMs, &ev, &age)) {
            out->auto_trigger_src = ev.trigger_src;
            memcpy(out->auto_trigger_mac, ev.trigger_mac, 6);
            out->paused_mask = ev.paused_mask;
            out->current_channel = ev.channel;
            out->mode = ev.mode;
            uint32_t totalMs = (uint32_t)ev.duration_sec * 1000U;
            out->auto_remaining_ms = (age < totalMs) ? (totalMs - age) : 0u;
            out->auto_duration_sec = ev.duration_sec;
            out->state = (out->auto_remaining_ms > 0) ? 1 : out->state;
            memcpy(out->source_node_id, ev.source_node_id, MESH_NODE_ID_LEN);
        } else {
            memset(out->source_node_id, 0, MESH_NODE_ID_LEN);
        }
    } else {
        memset(out->source_node_id, 0, MESH_NODE_ID_LEN);
    }
}

bool pcapBeginDownload(uint32_t*, uint32_t*) { return false; }
size_t pcapReadDownloadChunk(uint8_t*, size_t) { return 0; }
void pcapAbortDownload(void) {}
void pcapClearCapture(void) { resetCounters(); pcapState = 0; }

const EngineCallbacks pcapCallbacks = {
    .init   = pcapInit,
    .start  = pcapStart,
    .stop   = pcapStop,
    .loop   = pcapLoop,
    .config = pcapConfig,
    .name   = "PCAP",
};
