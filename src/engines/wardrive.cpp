#include "wardrive.h"
#include "../protocol.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include "../ble_coex.h"

#define MESH_RENDEZVOUS_CH 1
#include "flock_match.h"
#include "flock_auth_cache.h"
#include "dedup_ring.h"
#include "detector.h"
#include "flock_wifi.h"
#include "flock_ble.h"
#include "foxhunter.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <NimBLEDevice.h>

// Flock predicates and OUI live in flock_match.h / flock_oui.h.

// ============================================================================
// State
// ============================================================================

static volatile bool wardriveActive = false;
static unsigned long lastBleScan = 0;
static volatile uint8_t wardriveRadio = 0x03;

static uint8_t channelStart = 1;
static uint8_t channelEnd   = 14;
static unsigned long lastChannelHop = 0;
#ifdef OUISPY_DUAL_BAND
static uint8_t wardrive24Mode = 0;
#endif

#ifdef OUISPY_DUAL_BAND
static const uint8_t k5GhzChannels[] = {
    36, 40, 44, 48, 52, 56, 60, 64,
    100, 104, 108, 112, 116, 120, 124, 128, 132, 136, 140, 144,
    149, 153, 157, 161, 165
};
#endif

static uint16_t priorityDwellMs = 300;
static uint16_t normalDwellMs   = 110;

#ifdef OUISPY_DUAL_BAND
#define WD_MAX_HOPS 48
#else
#define WD_MAX_HOPS 32
#endif
static uint8_t  hopSchedule[WD_MAX_HOPS];
static uint16_t hopDwellMs[WD_MAX_HOPS];
static uint8_t  hopScheduleLen = 1;
static uint8_t  hopIdx = 0;
static uint8_t  currentChannel = 1;

static const uint16_t kAdaptiveMinDwellMs = 80;
static const uint16_t kAdaptiveQuietMs    = 40;
static volatile uint32_t wifiLastNetMs = 0;

#define MESH_RENDEZVOUS_DWELL_MS 40

static bool isPriorityChannel(uint8_t ch) {
    return ch == 1 || ch == 6 || ch == 11 || ch == 44 || ch == 149 || ch == 157;
}

static uint16_t scanDwellForChannel(uint8_t ch) {
    return isPriorityChannel(ch) ? priorityDwellMs : normalDwellMs;
}

static void buildHopSchedule(void) {
    hopScheduleLen = 0;
#ifdef OUISPY_DUAL_BAND
    {
        uint8_t ch24[16]; uint8_t ch24n = 0;
        if (wardrive24Mode == 1) {
            const uint8_t p[3] = {1, 6, 11};
            for (uint8_t k = 0; k < 3; k++)
                if (p[k] >= channelStart && p[k] <= channelEnd) ch24[ch24n++] = p[k];
        } else {
            for (uint16_t c = channelStart; c <= channelEnd && ch24n < 16; c++)
                ch24[ch24n++] = (uint8_t)c;
        }
        if (ch24n == 0) ch24[ch24n++] = channelStart;

        const bool en24 = wifiChanEnabled(1);
        const bool en5  = wifiChanEnabled(36);
        if (en24 && en5) {
            uint8_t i24 = 0, i5 = 0;
            while (hopScheduleLen < WD_MAX_HOPS && (i5 < sizeof(k5GhzChannels) || i24 < ch24n)) {
                if (i24 < ch24n) {
                    hopSchedule[hopScheduleLen] = ch24[i24];
                    hopDwellMs[hopScheduleLen] = scanDwellForChannel(ch24[i24]);
                    hopScheduleLen++; i24++;
                }
                for (uint8_t b = 0; b < 2 && i5 < sizeof(k5GhzChannels) && hopScheduleLen < WD_MAX_HOPS; b++) {
                    hopSchedule[hopScheduleLen] = k5GhzChannels[i5];
                    hopDwellMs[hopScheduleLen] = scanDwellForChannel(k5GhzChannels[i5]);
                    hopScheduleLen++; i5++;
                }
            }
        } else if (en24) {
            for (uint8_t k = 0; k < ch24n && hopScheduleLen < WD_MAX_HOPS; k++) {
                hopSchedule[hopScheduleLen] = ch24[k];
                hopDwellMs[hopScheduleLen] = scanDwellForChannel(ch24[k]);
                hopScheduleLen++;
            }
        } else {
            for (uint8_t i = 0; i < sizeof(k5GhzChannels) && hopScheduleLen < WD_MAX_HOPS; i++) {
                hopSchedule[hopScheduleLen] = k5GhzChannels[i];
                hopDwellMs[hopScheduleLen] = scanDwellForChannel(k5GhzChannels[i]);
                hopScheduleLen++;
            }
        }
    }
#else
    for (uint16_t c = channelStart; c <= channelEnd && hopScheduleLen < WD_MAX_HOPS; c++) {
        hopSchedule[hopScheduleLen] = (uint8_t)c;
        hopDwellMs[hopScheduleLen] = scanDwellForChannel((uint8_t)c);
        hopScheduleLen++;
    }
#endif
#ifndef OUISPY_DUAL_BAND
    const uint8_t kPri[3] = {1, 6, 11};
    for (uint8_t i = 0; i < 3 && hopScheduleLen < WD_MAX_HOPS; i++) {
        if (kPri[i] >= channelStart && kPri[i] <= channelEnd && wifiChanEnabled(kPri[i])) {
            hopSchedule[hopScheduleLen] = kPri[i];
            hopDwellMs[hopScheduleLen] = scanDwellForChannel(kPri[i]);
            hopScheduleLen++;
        }
    }
#endif
    // Node mode: ensure the sweep visits the mesh channel (ch1) so ESP-NOW
    // rides the natural dwell instead of a forced scan-pausing park. ch1 is a
    // real, dense channel, so this dwell still logs networks. Skipped in solo
    // (no manager) — full v0.3.9 sweep, no mesh tax.
    if (meshIsEnabled() && meshManagerJoined()) {
        bool hasMeshCh = false;
        for (uint8_t i = 0; i < hopScheduleLen; i++)
            if (hopSchedule[i] == MESH_RENDEZVOUS_CH) { hasMeshCh = true; break; }
        if (!hasMeshCh && hopScheduleLen < WD_MAX_HOPS) {
            hopSchedule[hopScheduleLen] = MESH_RENDEZVOUS_CH;
            hopDwellMs[hopScheduleLen] = scanDwellForChannel(MESH_RENDEZVOUS_CH);
            hopScheduleLen++;
        }
    }
    if (hopScheduleLen == 0) {
        hopSchedule[0] = channelStart;
        hopDwellMs[0] = scanDwellForChannel(channelStart);
        hopScheduleLen = 1;
    }
#ifdef OUISPY_SWEEPLOG
    Serial.printf("[WDSCHED] len=%u:", hopScheduleLen);
    for (uint8_t i = 0; i < hopScheduleLen; i++) Serial.printf(" %u", hopSchedule[i]);
    Serial.println();
#endif
    hopIdx = 0;
    currentChannel = hopSchedule[0];
}

static uint16_t currentSlotDwellMs(void) {
    return hopDwellMs[hopIdx];
}

static uint16_t bleScanDurationMs  = 800;
static uint16_t bleScanIntervalMs  = 3000;

static DedupRing<1024, 5000> wardriveDedup;
static DedupRingISR<1024, 2000> wifiDedup;
static DedupRingISR<64, 5000> isrFlockWifiDedup;

static volatile uint8_t wdFlockBleActive = 0;
static volatile uint8_t wdFlockWifiActive = 0;
static volatile uint8_t wdFoxhunterActive = 0;
static volatile uint8_t wdDetectorActive = 0;

// ============================================================================
// Auth mode mapping from 802.11 RSN/WPA IE to our compact enum
// ============================================================================

// AKM suite selectors (OUI 00-0F-AC):
// 1 = 802.1X (WPA2-Enterprise)
// 2 = PSK (WPA2-Personal)
// 6 = SAE (WPA3-Personal)
// 8 = SAE (WPA3-Personal, FT)
// 12 = SAE-EXT (WPA3-Enterprise 192-bit)
#define AKM_OUI_00   0x00
#define AKM_OUI_0F   0x0F
#define AKM_OUI_AC   0xAC
#define AKM_SUITE_EAP     1
#define AKM_SUITE_PSK     2
#define AKM_SUITE_SAE     8
#define AKM_SUITE_FT_SAE  9
#define AKM_SUITE_SAE_EXT 12

static uint8_t IRAM_ATTR parseAuthFromFrame(const uint8_t* p, int len) {
    // Walk tagged parameters starting after fixed fields
    // Beacon: 24-byte header + 12 bytes fixed (timestamp[8]+interval[2]+capability[2])
    int offset = 36;
    bool hasRSN = false;
    bool hasWPA = false;
    bool hasWPA3 = false;
    bool hasEAP = false;

    while (offset + 2 <= len) {
        uint8_t tagId = p[offset];
        uint8_t tagLen = p[offset + 1];
        if (offset + 2 + tagLen > len) break;

        if (tagId == 48 && tagLen >= 2) {
            // RSN Information Element — parse AKM suite list
            hasRSN = true;
            // RSN IE: version[2] + group_cipher[4] + pairwise_count[2] + pairwise_suites[n*4] + akm_count[2] + akm_suites[n*4]
            int rsnOff = offset + 2;
            int rsnEnd = offset + 2 + tagLen;
            // Skip version (2 bytes)
            rsnOff += 2;
            if (rsnOff + 4 > rsnEnd) goto next_tag;
            // Skip group cipher suite (4 bytes)
            rsnOff += 4;
            if (rsnOff + 2 > rsnEnd) goto next_tag;
            // Pairwise cipher count + suites
            uint16_t pairCount = p[rsnOff] | (p[rsnOff + 1] << 8);
            rsnOff += 2 + pairCount * 4;
            if (rsnOff + 2 > rsnEnd) goto next_tag;
            // AKM suite count + suites
            uint16_t akmCount = p[rsnOff] | (p[rsnOff + 1] << 8);
            rsnOff += 2;
            for (uint16_t i = 0; i < akmCount && rsnOff + 4 <= rsnEnd; i++) {
                // AKM suite: OUI[3] + type[1]
                uint8_t akmType = p[rsnOff + 3];
                if (p[rsnOff] == 0x00 && p[rsnOff + 1] == 0x0F && p[rsnOff + 2] == 0xAC) {
                    if (akmType == 8 || akmType == 9 || akmType == 12) {
                        hasWPA3 = true;
                    }
                    if (akmType == 1 || akmType == 5) {
                        hasEAP = true;
                    }
                }
                rsnOff += 4;
            }
        }

        if (tagId == 221 && tagLen >= 4) {     // Vendor-specific (WPA1)
            if (p[offset+2]==0x00 && p[offset+3]==0x50 &&
                p[offset+4]==0xF2 && p[offset+5]==0x01) {
                hasWPA = true;
            }
        }

        next_tag:
        offset += 2 + tagLen;
    }

    if (hasWPA3)            return 6;  // WPA3
    if (hasEAP && hasRSN)   return 5;  // WPA2_ENT
    if (hasRSN && hasWPA)   return 4;  // WPA_WPA2
    if (hasRSN)             return 3;  // WPA2
    if (hasWPA)             return 2;  // WPA
    if (len >= 36 && (p[34] & 0x10)) return 1;  // WEP (Privacy bit set, no RSN/WPA)
    return 0;                           // Open
}

// ============================================================================
// Check if SSID bytes are all zeroes (hidden network variant: tagLen > 0 but null-filled)
// ============================================================================

static bool IRAM_ATTR isNullSsid(const uint8_t* ssidBytes, uint8_t ssidLen) {
    for (uint8_t i = 0; i < ssidLen; i++) {
        if (ssidBytes[i] != 0) return false;
    }
    return true;
}

// ============================================================================
// Wildcard probe request — stimulates APs to respond immediately on channel hop.
// GhostESP technique: send broadcast probe with empty SSID after each hop.
// APs respond with probe response instead of waiting for next beacon (102.4ms).
// ============================================================================

static const uint8_t wildcardProbeTemplate[] = {
    // Frame control: probe request (type 0, subtype 4)
    0x40, 0x00,
    // Duration
    0x00, 0x00,
    // Destination: broadcast
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    // Source: random (filled at runtime)
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    // BSSID: broadcast
    0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
    // Sequence number
    0x00, 0x00,
    // SSID parameter set: tag 0, length 0 (wildcard)
    0x00, 0x00,
    // Supported rates: 1, 2, 5.5, 11 Mbps
    0x01, 0x04, 0x82, 0x84, 0x8B, 0x96,
};

static void sendWildcardProbe(void) {
    uint8_t probe[sizeof(wildcardProbeTemplate)];
    // Burst of 2 probes with different random source MACs. Single probe
    // can be lost in dense RF — burst gives ~99% AP-response rate without
    // measurable channel cost (~250µs total airtime).
    for (int n = 0; n < 2; n++) {
        memcpy(probe, wildcardProbeTemplate, sizeof(probe));
        probe[10] = 0x02 | (esp_random() & 0xFE);
        for (int i = 11; i < 16; i++) {
            probe[i] = esp_random() & 0xFF;
        }
        // Randomize sequence number too — some APs dedup by seq.
        probe[22] = esp_random() & 0xFF;
        probe[23] = esp_random() & 0xFF;
        esp_wifi_80211_tx(WIFI_IF_STA, probe, sizeof(probe), false);
    }
}

// ============================================================================
// WiFi Promiscuous Callback — wardrive WiFi scanner.
// Beacons/probe-resp for WiGLE collection + foxhunter passive frames.
// Flock-WiFi OUI detection lives in the standalone flock_wifi engine.
// ============================================================================

static void IRAM_ATTR wardriveWifiCb(void* buf, wifi_promiscuous_pkt_type_t type) {
    g_engRawSeen++;
    if (!wardriveActive) return;

    // MGMT (beacons/probe-resp for WiGLE) + DATA (foxhunter target frames).
    // CTRL frames excluded at filter mask; this is belt-and-suspenders.
    if (type != WIFI_PKT_MGMT && type != WIFI_PKT_DATA) return;

    wifi_promiscuous_pkt_t* pkt = (wifi_promiscuous_pkt_t*)buf;
    uint8_t* p = pkt->payload;
    int len = pkt->rx_ctrl.sig_len;
    if (len < 24) return;

    uint8_t frameType = (p[0] >> 2) & 0x03;
    uint8_t frameSubtype = (p[0] >> 4) & 0x0F;

    const uint8_t* addr1 = &p[4];
    const uint8_t* addr2 = &p[10];
    const uint8_t* addr3 = &p[16];

    // ----- Flock-WiFi OUI fast-path (any frame type) -----
    // Cheap: bucket-indexed OUI table, ISR-safe dedup, no allocs.
    if (wdFlockWifiActive && pkt->rx_ctrl.rssi >= FLOCK_RSSI_MIN) {
        uint8_t fMethod = 0xFF;
        const uint8_t* fMac = NULL;
        if (flockMatchOuiISR(addr2)) {
            fMethod = METHOD_OUI_ADDR2;
            fMac = addr2;
            // Probe-request with wildcard SSID is a strong cam signal.
            if (frameType == 0 && frameSubtype == 4) {
                int bodyOff = 24;
                int bodyLen = len - bodyOff;
                if (bodyLen > 0) {
                    int r = isWildcardProbeIE(p + bodyOff, bodyLen);
                    if (r == -1 && bodyLen > 4) {
                        r = isWildcardProbeIE(p + bodyOff, bodyLen - 4);
                    }
                    if (r == 1) fMethod = METHOD_WILDCARD_PROBE;
                }
            }
        } else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
            fMethod = METHOD_OUI_ADDR1;
            fMac = addr1;
        }
        if (fMac) {
            if (frameType == 0 && (frameSubtype == 8 || frameSubtype == 5)) {
                uint8_t a = parseAuthFromFrame(p, len);
                if (a > 0) flockAuthCacheSet(fMac, a);
            }
            if (!isrFlockWifiDedup.check(fMac)) {
                DetectionEvent fEvt = {};
                fEvt.engine_id = ENGINE_FLOCK_WIFI;
                memcpy(fEvt.mac, fMac, 6);
                fEvt.rssi = pkt->rx_ctrl.rssi;
                fEvt.channel = pkt->rx_ctrl.channel;
                fEvt.timestamp_ms = millis();
                fEvt.method = fMethod;
                fEvt.ext.flock.auth_mode = flockAuthCacheGet(fMac);
                fEvt.ext.flock.sig_mask = FLOCK_SIG_OUI;
                pushDetectionFromISR(&fEvt);
            }
        }
    }

    if (wdDetectorActive) {
        detectorCheckWifiSignaturesISR(p, len, pkt->rx_ctrl.rssi, pkt->rx_ctrl.channel);
        detectorCheckWifiDeviceISR(addr2, pkt->rx_ctrl.rssi, pkt->rx_ctrl.channel);
        if (!(addr1[0] & 0x01)) {
            detectorCheckWifiDeviceISR(addr1, pkt->rx_ctrl.rssi, pkt->rx_ctrl.channel);
        }
        if (frameType == 0) {
            detectorCheckWifiDeviceISR(addr3, pkt->rx_ctrl.rssi, pkt->rx_ctrl.channel);
        }
    }

    // Beacons / probe-resp only beyond this point
    if (frameType != 0 || (frameSubtype != 8 && frameSubtype != 5)) {
        // Foxhunter still wants any frame from a target. Cheap when inactive.
        if (wdFoxhunterActive) {
            foxhunterCheckWifiDeviceISR(addr1, addr2, addr3,
                                         pkt->rx_ctrl.rssi,
                                         pkt->rx_ctrl.channel);
        }
        return;
    }

    // Foxhunter check on the beacon/probe-resp frame too
    if (wdFoxhunterActive) {
        foxhunterCheckWifiDeviceISR(addr1, addr2, addr3,
                                     pkt->rx_ctrl.rssi,
                                     pkt->rx_ctrl.channel);
    }

    {
        if (wifiDedup.check(addr3)) return;
        wifiLastNetMs = millis();

        int tagOffset = 36;
        char ssid[33] = {0};
        if (tagOffset + 2 <= len) {
            uint8_t tagId = p[tagOffset];
            uint8_t tagLen = p[tagOffset + 1];
            if (tagId == 0 && tagLen > 0 && tagLen <= 32 && tagOffset + 2 + tagLen <= len) {
                if (!isNullSsid(&p[tagOffset + 2], tagLen)) {
                    memcpy(ssid, &p[tagOffset + 2], tagLen);
                    ssid[tagLen] = '\0';
                }
            }
        }

        uint8_t authMode = parseAuthFromFrame(p, len);

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, addr3, 6);
        evt.rssi = pkt->rx_ctrl.rssi;
        evt.channel = pkt->rx_ctrl.channel;
        evt.timestamp_ms = millis();
        evt.method = METHOD_WIFI_AP;
        memcpy(evt.ext.wardrive.ssid, ssid, 33);
        evt.ext.wardrive.auth_mode = authMode;
        pushDetectionFromISR(&evt);
    }
}

// ============================================================================
// BLE — timed scans via callback. NimBLE 1.4 API.
// ============================================================================

static NimBLEScan* pWardriveScan = nullptr;

class WardriveAdvCallbacks : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* dev) override {
        g_engRawSeen++;
        if (!wardriveActive) return;

        uint8_t mac[6];
        bleAddrToMac(dev->getAddress().getNative(), mac);
        if (wdDetectorActive) detectorCheckBleSignatures(dev, mac, dev->getRSSI());
        if (wardriveDedup.check(mac)) return;

        int rssi = dev->getRSSI();
        uint32_t now = millis();
        std::string name = dev->getName();

        // Flock predicates (only when engine active). Uses shared
        // flock_match.h — cached NimBLEUUID, no heap allocs in hot path.
        if (wdFlockBleActive && flockShouldConsiderAddr(dev)) {
            bool isFlock = false;
            uint8_t flockMethod = 0;
            bool isRaven = false;
            const char* ravenFw = "";
            char tnSerial[20] = {0};
            uint8_t sigMask = 0;

            if (dev->haveManufacturerData()) {
                std::string md = dev->getManufacturerData();
                if (flockMatchMfgPayload((const uint8_t*)md.data(), md.size(),
                                         tnSerial, sizeof(tnSerial))) {
                    sigMask |= FLOCK_SIG_MFG;
                    if (tnSerial[0]) sigMask |= FLOCK_SIG_TN;
                }
            }
            if (flockMatchOui(mac)) sigMask |= FLOCK_SIG_OUI;
            if (name.length() > 0) {
                if (flockMatchNameStr(name.c_str()))        sigMask |= FLOCK_SIG_NAME;
                if (flockMatchBareSerialName(name.c_str())) sigMask |= FLOCK_SIG_SERIAL;
            }

            if (sigMask & FLOCK_SIG_NAME) {
                isFlock = true;
                flockMethod = METHOD_NAME_MATCH;
            } else if ((sigMask & FLOCK_SIG_VALIDATED) == FLOCK_SIG_VALIDATED) {
                isFlock = true;
                flockMethod = METHOD_NAME_MATCH;
            }
            if (!isFlock && flockMatchRavenUuid(dev, &ravenFw)) {
                isFlock = true;
                flockMethod = METHOD_RAVEN_UUID;
                isRaven = true;
                sigMask |= FLOCK_SIG_RAVEN_UUID;
            }

            if (isFlock) {
                DetectionEvent fEvt = {};
                fEvt.engine_id = ENGINE_FLOCK_BLE;
                memcpy(fEvt.mac, mac, 6);
                fEvt.rssi = rssi;
                fEvt.timestamp_ms = now;
                fEvt.method = flockMethod;
                fEvt.ext.flock.is_raven = isRaven ? 1 : 0;
                if (isRaven) {
                    strncpy(fEvt.ext.flock.raven_fw, ravenFw,
                            sizeof(fEvt.ext.flock.raven_fw) - 1);
                } else if (tnSerial[0]) {
                    strncpy(fEvt.ext.flock.raven_fw, tnSerial,
                            sizeof(fEvt.ext.flock.raven_fw) - 1);
                }
                if (!name.empty()) {
                    strncpy(fEvt.ext.flock.name, name.c_str(),
                            sizeof(fEvt.ext.flock.name) - 1);
                }
                fEvt.ext.flock.sig_mask = sigMask;
                pushDetection(&fEvt);
            }
        }

        DetectionEvent evt = {};
        evt.engine_id = ENGINE_WARDRIVE;
        memcpy(evt.mac, mac, 6);
        evt.rssi = rssi;
        evt.timestamp_ms = now;
        evt.method = METHOD_BLE_ADV;
        strncpy(evt.ext.wardrive.device_name, name.c_str(), 20);
        pushDetection(&evt);

        // Dispatch to other active engines that went passive
        if (wdDetectorActive) {
            detectorCheckBleDevice(mac, evt.rssi);
            detectorCheckBleUuid(dev, mac, evt.rssi);
        }
        if (wdFoxhunterActive) {
            foxhunterCheckBleDevice(mac, evt.rssi);
        }
    }
};

static void wardriveBleOnComplete(NimBLEScanResults results) {
    if (pWardriveScan && wardriveActive) {
        pWardriveScan->clearResults();
    }
}

static WardriveAdvCallbacks wardriveBleCallbacks;

// ============================================================================
// Lifecycle
// ============================================================================

static void wardriveInit(void) {
    wardriveDedup.reset();
    wifiDedup.reset();
    isrFlockWifiDedup.reset();
    flockMatchInit();
    Serial.println("[WARDRIVE] Initialized");
}

static void wardriveStart(void) {
    wardriveActive = true;
    lastBleScan = 0;
    wardriveDedup.reset();
    wifiDedup.reset();
    isrFlockWifiDedup.reset();
    meshResetTxDedup();
    uint32_t relog = engineGetRediscoverMs();
    wardriveDedup.setCooldownMs(relog);
    wifiDedup.setCooldownMs(relog);
    isrFlockWifiDedup.setCooldownMs(relog);
    wdFlockBleActive = (engineGetState(ENGINE_FLOCK_BLE) != ESTATE_DISABLED) ? 1 : 0;
    wdFlockWifiActive = (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED) ? 1 : 0;
    wdFoxhunterActive = (engineGetState(ENGINE_FOXHUNTER) != ESTATE_DISABLED) ? 1 : 0;
    wdDetectorActive = (engineGetState(ENGINE_DETECTOR) != ESTATE_DISABLED) ? 1 : 0;
    buildHopSchedule();
    lastChannelHop = millis();

    if (wardriveRadio & 0x01) {
        if (!meshIsEnabled()) {
            WiFi.mode(WIFI_STA);
            WiFi.disconnect(false, false);
            vTaskDelay(pdMS_TO_TICKS(50));
        }

        wifiApplyRegdomain();

        wifi_promiscuous_filter_t ctrl_filter = {
            .filter_mask = 0
        };
        esp_wifi_set_promiscuous_ctrl_filter(&ctrl_filter);

        wifiSnifferApplyPs();
        wifiCoexRegister(wardriveWifiCb,
                         WIFI_PROMIS_FILTER_MASK_MGMT | WIFI_PROMIS_FILTER_MASK_DATA);
        esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);

        sendWildcardProbe();
    }

    // BLE scanner
    if (wardriveRadio & 0x02) {
        pWardriveScan = NimBLEDevice::getScan();
        bleCoexRegister(&wardriveBleCallbacks, true);
        pWardriveScan->setActiveScan(true);
        pWardriveScan->setInterval(100);
        pWardriveScan->setWindow(99);
    }

    engineSetState(ENGINE_WARDRIVE, ESTATE_SCANNING);
    flockWifiHostSuspend(true);
    flockBleHostSuspend(true);
    detectorHostSuspend(true);
    Serial.printf("[WARDRIVE] Started (radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d)\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
}

static void wardriveStop(void) {
    Serial.println("[WARDRIVE] Stopping...");
    wardriveActive = false;
    vTaskDelay(pdMS_TO_TICKS(50));

    if (pWardriveScan != nullptr) {
        bleCoexUnregister(&wardriveBleCallbacks);
        if (pWardriveScan->isScanning()) pWardriveScan->stop();
#ifdef OUISPY_NIMBLE2
        vTaskDelay(pdMS_TO_TICKS(100));
#else
        vTaskDelay(pdMS_TO_TICKS(200));
#endif
        pWardriveScan->clearResults();
        pWardriveScan = nullptr;
    }

    wifiCoexUnregister(wardriveWifiCb);
#ifdef OUISPY_NIMBLE2
    vTaskDelay(pdMS_TO_TICKS(40));
#else
    vTaskDelay(pdMS_TO_TICKS(100));
#endif
    if (meshIsEnabled() || wifiCoexActive() || wifiRadioExternallyOwned()) {
        WiFi.disconnect(false, false);
        esp_wifi_set_channel(1, WIFI_SECOND_CHAN_NONE);
    } else {
        WiFi.disconnect(true, true);
    }

    engineSetState(ENGINE_WARDRIVE, ESTATE_DISABLED);
    flockWifiHostSuspend(false);
    flockBleHostSuspend(false);
    detectorHostSuspend(false);
    Serial.println("[WARDRIVE] Stopped");
}

static volatile uint32_t g_wdHopCount = 0;
static volatile uint32_t g_wdMeshSkip = 0;
uint32_t wardriveGetHopCount(void) { return g_wdHopCount; }
uint32_t wardriveGetMeshSkipCount(void) { return g_wdMeshSkip; }

static void wardriveLoop(void) {
#ifdef OUISPY_SWEEPLOG
    {
        static uint32_t lastDiag = 0;
        uint32_t nowd = millis();
        if (nowd - lastDiag >= 2000) {
            lastDiag = nowd;
            uint8_t pri = 0;
            wifi_second_chan_t sec = WIFI_SECOND_CHAN_NONE;
            esp_wifi_get_channel(&pri, &sec);
            Serial.printf("[WDDIAG] active=%d radio=0x%02X ch=%u schedLen=%u meshEn=%d meshWin=%d ridWin=%d mgrJoined=%d skip=%lu hops=%lu\n",
                          wardriveActive ? 1 : 0, wardriveRadio, pri, hopScheduleLen,
                          meshIsEnabled() ? 1 : 0, meshInMeshWindow() ? 1 : 0,
                          meshInRidWindow() ? 1 : 0, meshManagerJoined() ? 1 : 0,
                          (unsigned long)g_wdMeshSkip, (unsigned long)g_wdHopCount);
        }
    }
#endif
    if (meshManagerJoined() && (meshInMeshWindow() || meshInRidWindow())) { g_wdMeshSkip++; return; }
    if (!wardriveActive) return;
    unsigned long now = millis();

    wdFlockBleActive   = (engineGetState(ENGINE_FLOCK_BLE)  != ESTATE_DISABLED) ? 1 : 0;
    wdFlockWifiActive  = (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED) ? 1 : 0;
    wdFoxhunterActive  = (engineGetState(ENGINE_FOXHUNTER)  != ESTATE_DISABLED) ? 1 : 0;
    wdDetectorActive   = (engineGetState(ENGINE_DETECTOR)   != ESTATE_DISABLED) ? 1 : 0;

    if (wardriveRadio & 0x01) {
        uint16_t maxDwell = currentSlotDwellMs();
        uint16_t minDwell = maxDwell < kAdaptiveMinDwellMs ? maxDwell : kAdaptiveMinDwellMs;
        uint32_t elapsed = now - lastChannelHop;
#ifdef OUISPY_ADAPTIVE_DWELL
        bool due = (elapsed >= maxDwell) ||
                   (elapsed >= minDwell && (uint32_t)(now - wifiLastNetMs) >= kAdaptiveQuietMs);
#else
        (void)minDwell;
        bool due = (elapsed >= maxDwell);
#endif
        if (due && wifiCoexShouldHop(ENGINE_WARDRIVE)) {
#ifdef OUISPY_SWEEPLOG
            Serial.printf("[HOP] ch=%u dwelt=%lums\n", currentChannel, (unsigned long)elapsed);
#endif
            g_wdHopCount++;
            hopIdx++;
            if (hopIdx >= hopScheduleLen) hopIdx = 0;
#ifdef OUISPY_SWEEPLOG
            if (hopIdx == 0) {
                static uint32_t g_lastSweepMs = 0;
                Serial.printf("[SWEEP] ms=%lu len=%u\n",
                              (unsigned long)(now - g_lastSweepMs), hopScheduleLen);
                g_lastSweepMs = now;
            }
#endif
            currentChannel = hopSchedule[hopIdx];
            esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
            lastChannelHop = now;
            wifiLastNetMs = now;
            sendWildcardProbe();
            if (meshIsEnabled() && currentChannel == MESH_RENDEZVOUS_CH) meshNoteOnHome();
        }
    }

    if (wardriveRadio & 0x02) {
        if (pWardriveScan != nullptr) {
            if (now - lastBleScan >= bleScanIntervalMs && !pWardriveScan->isScanning()) {
                lastBleScan = now;
                pWardriveScan->start(0, wardriveBleOnComplete, false);
#ifdef OUISPY_SWEEPLOG
                Serial.printf("[BLEDUTY] ON  t=%lu (dur=%u int=%u)\n",
                              (unsigned long)now, bleScanDurationMs, bleScanIntervalMs);
#endif
            } else if (pWardriveScan->isScanning() && (now - lastBleScan >= bleScanDurationMs)) {
                pWardriveScan->stop();
#ifdef OUISPY_SWEEPLOG
                Serial.printf("[BLEDUTY] OFF t=%lu (on for %lums)\n",
                              (unsigned long)now, (unsigned long)(now - lastBleScan));
#endif
            }
        }
    }
}

static void wardriveConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    const char* self = meshGetLocalNodeId();
    if (!cfgTgtStrip(&payload, &len, self)) {
        Serial.printf("[WARDRIVE] cfg target mismatch self=%s — ignored\n", self);
        return;
    }
    if (len < 1) return;
    uint8_t  prevStart = channelStart, prevEnd = channelEnd;
    uint16_t prevPri = priorityDwellMs, prevNorm = normalDwellMs;
    uint8_t  prevRadio = wardriveRadio;
#ifdef OUISPY_DUAL_BAND
    uint8_t  prev24Mode = wardrive24Mode;
#endif

    uint8_t newRadio = payload[0] & 0x03;
    if (newRadio == 0) newRadio = 0x03;
    wardriveRadio = newRadio;

    if (len >= 5) {
        priorityDwellMs = payload[1] | (payload[2] << 8);
        normalDwellMs   = payload[3] | (payload[4] << 8);
        if (priorityDwellMs < 50) priorityDwellMs = 50;
        if (normalDwellMs < 50) normalDwellMs = 50;
    }
    if (len >= 9) {
        bleScanDurationMs = payload[5] | (payload[6] << 8);
        bleScanIntervalMs = payload[7] | (payload[8] << 8);
        if (bleScanDurationMs < 100) bleScanDurationMs = 100;
        uint32_t minInterval = (uint32_t)bleScanDurationMs + 100;
        if (minInterval > 0xFFFF) minInterval = 0xFFFF;
        if (bleScanIntervalMs < minInterval) bleScanIntervalMs = (uint16_t)minInterval;
    }
    if (len >= 11) {
        uint8_t cs = payload[9];
        uint8_t ce = payload[10];
        if (cs >= 1 && cs <= 14 && ce >= cs && ce <= 14) {
            channelStart = cs;
            channelEnd = ce;
        }
    }
#ifdef OUISPY_DUAL_BAND
    if (len >= 12) wardrive24Mode = payload[11] & 0x01;
#endif

    if (wardriveActive && newRadio != prevRadio) {
        Serial.printf("[WARDRIVE] radio change 0x%02X->0x%02X while running — restart\n",
                      prevRadio, newRadio);
        wardriveStop();
        wardriveStart();
        return;
    }

    bool scheduleChanged = (channelStart != prevStart) || (channelEnd != prevEnd) ||
                           (priorityDwellMs != prevPri) || (normalDwellMs != prevNorm);
#ifdef OUISPY_DUAL_BAND
    scheduleChanged = scheduleChanged || (wardrive24Mode != prev24Mode);
#endif
    if (scheduleChanged || !wardriveActive) {
        buildHopSchedule();
    } else {
        return;
    }

    Serial.printf("[WARDRIVE] Config: radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
#ifdef OUISPY_DUAL_BAND
    Serial.printf("[WARDRIVE] 2.4 mode=%s\n", wardrive24Mode ? "1/6/11" : "all");
#endif
}

uint16_t wardriveGetBleScanDurationMs(void) { return bleScanDurationMs; }
uint16_t wardriveGetBleScanIntervalMs(void) { return bleScanIntervalMs; }
uint8_t  wardriveGetRadio(void) { return wardriveRadio; }

void wardriveSetDwell(uint16_t pri, uint16_t norm) {
    priorityDwellMs = pri < 50 ? 50 : pri;
    normalDwellMs = norm < 50 ? 50 : norm;
}

void wardriveSetRadioMask(uint8_t mask) {
    uint8_t m = mask & 0x03;
    if (m == 0) m = 0x03;
    if (m == wardriveRadio) return;
    uint8_t prev = wardriveRadio;
    wardriveRadio = m;
    Serial.printf("[WARDRIVE] local radio mask 0x%02X->0x%02X\n", prev, m);
    if (wardriveActive) { wardriveStop(); wardriveStart(); }
}

static void wardriveApplyPrefs(void) {
    uint32_t relog = engineGetRediscoverMs();
    wardriveDedup.setCooldownMs(relog);
    wifiDedup.setCooldownMs(relog);
    isrFlockWifiDedup.setCooldownMs(relog);
}

const EngineCallbacks wardriveCallbacks = {
    .init       = wardriveInit,
    .start      = wardriveStart,
    .stop       = wardriveStop,
    .loop       = wardriveLoop,
    .config     = wardriveConfig,
    .applyPrefs = wardriveApplyPrefs,
    .name       = "Wardrive",
};
