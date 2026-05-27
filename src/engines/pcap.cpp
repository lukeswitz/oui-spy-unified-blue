#include "pcap.h"
#include "../protocol.h"
#include "../ble_gatt.h"
#include "../engine_registry.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <esp_heap_caps.h>

#define PCAP_LT_WIFI         127u
#define PCAP_LT_BLE          256u
#define PCAP_RADIOTAP_LEN    18u
#define PCAP_SNAPLEN         2324u
#define PCAP_BUF_SIZE        (16u * 1024u)
#define BLE_ADV_ACCESS_ADDR  0x8E89BED6u

static volatile bool pcapActive = false;
static volatile uint8_t pcapMode = PCAP_MODE_WIFI;
static uint8_t pcapChanStart = 1;
static uint8_t pcapChanEnd   = 11;
static uint16_t pcapDwellMs  = 250;
static uint8_t pcapHopIdx    = 0;
static uint8_t pcapCurChan   = 1;
static unsigned long pcapLastHop = 0;
static unsigned long pcapStartedAt = 0;
static unsigned long pcapLastStatsNotify = 0;

static volatile uint8_t pcapState = 0;
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
    if (!pcapActive) return;
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
        if (!pcapActive) return;
        uint8_t evType = dev->getAdvType();
        if (evType == 4) cntBleScan++;
        else             cntBleAdv++;

        uint8_t advA[6];
        memcpy(advA, dev->getAddress().getNative(), 6);
        uint8_t addrType = dev->getAddressType();
        int8_t  rssi = (int8_t)dev->getRSSI();

        uint8_t* payload = dev->getPayload();
        size_t payLen = dev->getPayloadLength();
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
        pcapStreamedBytes += drainLen;
        cntBytes = pcapStreamedBytes;
    }
}

static void pcapSenderTask(void* /*arg*/) {
    while (true) {
        ulTaskNotifyTake(pdTRUE, pdMS_TO_TICKS(200));
        if (!pcapActive && bufSizeA == 0 && bufSizeB == 0) break;
        drainBuffersOverBle();
    }
    drainBuffersOverBle();
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

static void pcapStart(void) {
    if (pcapActive) return;
    if (!allocBuffers()) {
        Serial.println("[PCAP] buffer alloc failed");
        pcapState = 3;
        engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
        bleGattNotifyPcapStats();
        return;
    }
    bufSizeA = bufSizeB = 0;
    useA = true;
    resetCounters();
    pcapStartedAt = millis();
    pcapLastStatsNotify = 0;
    pcapHopIdx = 0;
    pcapCurChan = pcapChanStart;
    pcapLastHop = millis();
    pcapActive = true;
    pcapState = 1;

    if (xTaskCreatePinnedToCore(pcapSenderTask, "pcap_tx",
                                8192, NULL, 5, &pcapSenderHandle, 1) != pdPASS) {
        Serial.println("[PCAP] task create failed");
        pcapActive = false;
        pcapState = 3;
        freeBuffers();
        engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
        bleGattNotifyPcapStats();
        return;
    }

    if (pcapMode == PCAP_MODE_WIFI) {
        WiFi.mode(WIFI_STA);
        WiFi.disconnect(false, false);
        vTaskDelay(pdMS_TO_TICKS(50));
        wifi_country_t country = { .cc = "JP", .schan = 1, .nchan = 14,
                                    .policy = WIFI_COUNTRY_POLICY_MANUAL };
        esp_wifi_set_country(&country);
        wifi_promiscuous_filter_t f = {
            .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT |
                           WIFI_PROMIS_FILTER_MASK_DATA |
                           WIFI_PROMIS_FILTER_MASK_CTRL
        };
        esp_wifi_set_promiscuous_filter(&f);
        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(pcapWifiCb);
        esp_wifi_set_channel(pcapCurChan, WIFI_SECOND_CHAN_NONE);
    } else {
        pPcapScan = NimBLEDevice::getScan();
        pPcapScan->setAdvertisedDeviceCallbacks(&pcapBleCallbacks, true);
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

    if (pcapMode == PCAP_MODE_WIFI) {
        esp_wifi_set_promiscuous_rx_cb(NULL);
        esp_wifi_set_promiscuous(false);
    } else {
        if (pPcapScan) {
            if (pPcapScan->isScanning()) pPcapScan->stop();
            vTaskDelay(pdMS_TO_TICKS(200));
            pPcapScan->setAdvertisedDeviceCallbacks(nullptr, false);
            pPcapScan->clearResults();
            pPcapScan = nullptr;
        }
    }

    if (pcapSenderHandle) xTaskNotifyGive(pcapSenderHandle);
    for (int i = 0; i < 15 && pcapSenderHandle != nullptr; i++) {
        vTaskDelay(pdMS_TO_TICKS(20));
    }

    freeBuffers();
    if (pcapState != 2) pcapState = 0;
    engineSetState(ENGINE_PCAP, ESTATE_DISABLED);
    bleGattNotifyPcapStats();
    Serial.printf("[PCAP] Stopped bytes=%lu dropped=%lu\n",
                  (unsigned long)cntBytes, (unsigned long)cntDropped);
}

static void pcapLoop(void) {
    unsigned long now = millis();
    if (!pcapActive) {
        if (now - pcapLastStatsNotify >= 1000) {
            pcapLastStatsNotify = now;
            bleGattNotifyPcapStats();
        }
        return;
    }
    if (pcapMode == PCAP_MODE_WIFI) {
        if (now - pcapLastHop >= pcapDwellMs) {
            pcapHopIdx++;
            uint8_t span = (pcapChanEnd - pcapChanStart + 1);
            if (span < 1) span = 1;
            pcapCurChan = pcapChanStart + (pcapHopIdx % span);
            esp_wifi_set_channel(pcapCurChan, WIFI_SECOND_CHAN_NONE);
            pcapLastHop = now;
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
            break;
        case PCAP_CTRL_STOP:  pcapStop(); break;
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
        default: break;
    }
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
