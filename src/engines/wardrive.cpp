#include "wardrive.h"
#include "../protocol.h"
#include "flock_match.h"
#include "dedup_ring.h"
#include "detector.h"
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

// Channel hopping — interleaved schedule, per-channel adaptive dwell.
// Default range 1-11 covers US ISM (~99% of APs). JP/EU 12-14 via config.
static uint8_t channelStart = 1;
static uint8_t channelEnd   = 11;
static unsigned long lastChannelHop = 0;

// Per-channel dwell base. Priority 200ms = catches ~2 beacons (beacon
// interval typ 102.4ms). Normal 110ms = covers one full beacon period.
static uint16_t priorityDwellMs = 200;
static uint16_t normalDwellMs   = 110;

// Adaptive dwell per ch (1..14 → index 0..13).
static uint16_t timePerChannel[14] = {
    200, 110, 110, 110, 110, 200, 110, 110, 110, 110, 200, 110, 110, 110
};
static volatile uint8_t beaconsThisHop = 0;

// Interleaved hop schedule. Priority channels (1/6/11 within range) are
// inserted before every non-priority channel so they get revisited every
// (numPriority + 1) hops instead of once per linear sweep.
// Worst case range 1-14: 3 pri * (11 non-pri + 1 tail) = ~48 slots → 64 cap.
static uint8_t hopSchedule[64];
static uint8_t hopScheduleLen = 1;
static uint8_t hopIdx = 0;
static uint8_t currentChannel = 1;

static void buildHopSchedule(void) {
    hopScheduleLen = 0;
    uint8_t priChans[3];
    uint8_t numPri = 0;
    const uint8_t kPri[3] = {1, 6, 11};
    for (uint8_t i = 0; i < 3; i++) {
        if (kPri[i] >= channelStart && kPri[i] <= channelEnd) {
            priChans[numPri++] = kPri[i];
        }
    }
    bool hasNonPri = false;
    for (uint16_t c = channelStart; c <= channelEnd; c++) {
        if (c == 1 || c == 6 || c == 11) continue;
        for (uint8_t i = 0; i < numPri && hopScheduleLen < 64; i++) {
            hopSchedule[hopScheduleLen++] = priChans[i];
        }
        if (hopScheduleLen < 64) hopSchedule[hopScheduleLen++] = (uint8_t)c;
        hasNonPri = true;
    }
    // Tail priority pass — ensures last slot is priority for revisit symmetry.
    if (numPri > 0) {
        for (uint8_t i = 0; i < numPri && hopScheduleLen < 64; i++) {
            hopSchedule[hopScheduleLen++] = priChans[i];
        }
    }
    if (hopScheduleLen == 0) {
        hopSchedule[0] = channelStart;
        hopScheduleLen = 1;
    }
    if (!hasNonPri) {
        // All-priority range (e.g. 1-1, 6-6). Already filled with tail pass.
    }
    hopIdx = 0;
    currentChannel = hopSchedule[0];
}

// BLE scan timing — conservative 
// 800ms scan every 3000ms = ~27% BLE duty
static uint16_t bleScanDurationMs  = 800;
static uint16_t bleScanIntervalMs  = 3000;

// Dedup rings
static DedupRing<512, 10000> wardriveDedup;
// ISR WiFi beacon dedup — separate ring to avoid contention with BLE callback.
static DedupRingISR<512, 10000> wifiDedup;
// Smaller dedup for Flock-WiFi hits inside ISR (independent cooldown).
static DedupRingISR<64, 5000> isrFlockWifiDedup;

// Cached engine active states — avoids function calls per frame in ISR
static volatile uint8_t wdFlockBleActive = 0;
static volatile uint8_t wdFlockWifiActive = 0;
static volatile uint8_t wdFoxhunterActive = 0;
static volatile uint8_t wdDetectorActive = 0;

static bool isPriorityChannel(uint8_t ch) {
    return ch == 1 || ch == 6 || ch == 11;
}

static uint16_t dwellForChannel(uint8_t ch) {
    if (ch >= 1 && ch <= 14) return timePerChannel[ch - 1];
    return isPriorityChannel(ch) ? priorityDwellMs : normalDwellMs;
}

// Adaptive: adjust dwell based on beacon count (like Atomgps_wigler).
// Floor kept tight to keep cycle fast; ceiling capped so dense channels
// don't starve other channels.
static void updateAdaptiveDwell(uint8_t ch, uint8_t beaconCount) {
    if (ch < 1 || ch > 14) return;
    const uint16_t minDwell = 80;
    const uint16_t maxDwell = 300;
    const uint16_t step = 30;

    if (beaconCount >= 5) {
        timePerChannel[ch - 1] = min((int)(timePerChannel[ch - 1] + step), (int)maxDwell);
    } else if (beaconCount <= 1) {
        uint16_t floor = isPriorityChannel(ch) ? 150 : minDwell;
        timePerChannel[ch - 1] = max((int)(timePerChannel[ch - 1] - step), (int)floor);
    }
}

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
    if (wdFlockWifiActive) {
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
                    if (r == 1) fMethod = METHOD_WILDCARD_PROBE;
                }
            }
        } else if (!(addr1[0] & 0x01) && flockMatchOuiISR(addr1)) {
            fMethod = METHOD_OUI_ADDR1;
            fMac = addr1;
        } else if (frameType == 0 && flockMatchOuiISR(addr3)) {
            fMethod = METHOD_OUI_ADDR3;
            fMac = addr3;
        }
        if (fMac && !isrFlockWifiDedup.check(fMac)) {
            DetectionEvent fEvt = {};
            fEvt.engine_id = ENGINE_FLOCK_WIFI;
            memcpy(fEvt.mac, fMac, 6);
            fEvt.rssi = pkt->rx_ctrl.rssi;
            fEvt.channel = pkt->rx_ctrl.channel;
            fEvt.timestamp_ms = millis();
            fEvt.method = fMethod;
            pushDetectionFromISR(&fEvt);
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

    // Beacon / Probe Response → wardrive AP capture (WiGLE data)
    {
        if (wifiDedup.check(addr3)) return;

        int tagOffset = 36;
        char ssid[33] = {0};
        if (tagOffset + 2 <= len) {
            uint8_t tagId = p[tagOffset];
            uint8_t tagLen = p[tagOffset + 1];
            if (tagId == 0 && tagLen > 0 && tagLen <= 32 && tagOffset + 2 + tagLen <= len) {
                // Check for null-filled SSID (hidden network variant:
                // some APs broadcast tagLen=32 with all 0x00 bytes)
                if (!isNullSsid(&p[tagOffset + 2], tagLen)) {
                    memcpy(ssid, &p[tagOffset + 2], tagLen);
                    ssid[tagLen] = '\0';
                }
                // hidden network
            }
            // tagLen == 0: standard hidden network — ssid stays empty
        }

        uint8_t authMode = parseAuthFromFrame(p, len);
        beaconsThisHop++;

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
        if (!wardriveActive) return;

        uint8_t mac[6];
        memcpy(mac, dev->getAddress().getNative(), 6);
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

            if (flockMatchOui(mac)) {
                isFlock = true;
                flockMethod = METHOD_OUI_MATCH;
            }
            if (!isFlock && name.length() > 0 && flockMatchNameStr(name.c_str())) {
                isFlock = true;
                flockMethod = METHOD_NAME_MATCH;
            }
            if (!isFlock && dev->haveManufacturerData()) {
                std::string md = dev->getManufacturerData();
                if (flockMatchMfgPayload((const uint8_t*)md.data(), md.size(),
                                         tnSerial, sizeof(tnSerial))) {
                    isFlock = true;
                    flockMethod = METHOD_MFG_ID;
                }
            }
            if (!isFlock && flockMatchRavenUuid(dev, &ravenFw)) {
                isFlock = true;
                flockMethod = METHOD_RAVEN_UUID;
                isRaven = true;
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
    wdFlockBleActive = (engineGetState(ENGINE_FLOCK_BLE) != ESTATE_DISABLED) ? 1 : 0;
    // Wardrive owns the WiFi radio. If user enabled Flock-WiFi, run flock
    // OUI matching from inside this ISR — registry enforces WiFi mutex so
    // flock_wifi standalone won't conflict.
    wdFlockWifiActive = (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED) ? 1 : 0;
    wdFoxhunterActive = (engineGetState(ENGINE_FOXHUNTER) != ESTATE_DISABLED) ? 1 : 0;
    wdDetectorActive = (engineGetState(ENGINE_DETECTOR) != ESTATE_DISABLED) ? 1 : 0;
    buildHopSchedule();
    lastChannelHop = millis();
    beaconsThisHop = 0;

    // Reset adaptive dwell to base values
    for (int i = 0; i < 14; i++) {
        timePerChannel[i] = isPriorityChannel(i + 1) ? priorityDwellMs : normalDwellMs;
    }

    // WiFi: pure promiscuous mode — catches beacons (SSID/auth), flock
    // cameras, foxhunter targets. All in one callback, no WiFi.scanNetworks().
    if (wardriveRadio & 0x01) {
        WiFi.mode(WIFI_STA);
        WiFi.disconnect();

        // Set country to allow channels 1-14 (manual policy = user controls range)
        wifi_country_t country = {
            .cc = "JP",     // JP allows widest range (1-14)
            .schan = 1,
            .nchan = 14,
            .policy = WIFI_COUNTRY_POLICY_MANUAL
        };
        esp_wifi_set_country(&country);

        wifi_promiscuous_filter_t filter = {
            .filter_mask = WIFI_PROMIS_FILTER_MASK_MGMT |
                           WIFI_PROMIS_FILTER_MASK_DATA
        };
        esp_wifi_set_promiscuous_filter(&filter);

        esp_wifi_set_promiscuous(true);
        esp_wifi_set_promiscuous_rx_cb(wardriveWifiCb);
        esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);

        // Send wildcard probe on first channel to stimulate immediate AP responses
        sendWildcardProbe();
    }

    // BLE scanner
    if (wardriveRadio & 0x02) {
        pWardriveScan = NimBLEDevice::getScan();
        pWardriveScan->setAdvertisedDeviceCallbacks(&wardriveBleCallbacks, true);
        pWardriveScan->setActiveScan(true);
        // 97/97 ms: prime, avoids aliasing with 100/152.5 ms BLE adv periods.
        // interval == window per Espressif coex FAQ (max RF residency, no
        // wasted gaps inside BLE TDM slot).
        pWardriveScan->setInterval(100);
        pWardriveScan->setWindow(99);
    }

    engineSetState(ENGINE_WARDRIVE, ESTATE_SCANNING);
    Serial.printf("[WARDRIVE] Started (radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d)\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
}

static void wardriveStop(void) {
    Serial.println("[WARDRIVE] Stopping...");
    wardriveActive = false;

    // Stop BLE
    if (pWardriveScan != nullptr) {
        if (pWardriveScan->isScanning()) pWardriveScan->stop();
        vTaskDelay(pdMS_TO_TICKS(200));
        pWardriveScan->setAdvertisedDeviceCallbacks(nullptr, false);
        pWardriveScan->clearResults();
        pWardriveScan = nullptr;
    }

    // Stop WiFi promiscuous
    esp_wifi_set_promiscuous_rx_cb(NULL);
    esp_wifi_set_promiscuous(false);
    WiFi.disconnect(true);
    WiFi.mode(WIFI_OFF);

    engineSetState(ENGINE_WARDRIVE, ESTATE_DISABLED);
    Serial.println("[WARDRIVE] Stopped");
}

static void wardriveLoop(void) {
    if (!wardriveActive) return;
    unsigned long now = millis();

    wdFlockBleActive   = (engineGetState(ENGINE_FLOCK_BLE)  != ESTATE_DISABLED) ? 1 : 0;
    wdFlockWifiActive  = (engineGetState(ENGINE_FLOCK_WIFI) != ESTATE_DISABLED) ? 1 : 0;
    wdFoxhunterActive  = (engineGetState(ENGINE_FOXHUNTER)  != ESTATE_DISABLED) ? 1 : 0;
    wdDetectorActive   = (engineGetState(ENGINE_DETECTOR)   != ESTATE_DISABLED) ? 1 : 0;

    // WiFi: interleaved hop schedule, adaptive per-channel dwell.
    if (wardriveRadio & 0x01) {
        uint16_t dwell = dwellForChannel(currentChannel);
        if (now - lastChannelHop >= dwell) {
            updateAdaptiveDwell(currentChannel, beaconsThisHop);
            beaconsThisHop = 0;

            hopIdx++;
            if (hopIdx >= hopScheduleLen) hopIdx = 0;
            currentChannel = hopSchedule[hopIdx];
            esp_wifi_set_channel(currentChannel, WIFI_SECOND_CHAN_NONE);
            lastChannelHop = now;

            sendWildcardProbe();
        }
    }

    if (wardriveRadio & 0x02) {
        if (pWardriveScan != nullptr) {
            if (now - lastBleScan >= bleScanIntervalMs && !pWardriveScan->isScanning()) {
                lastBleScan = now;
                pWardriveScan->start(0, wardriveBleOnComplete, false);
            } else if (pWardriveScan->isScanning() && (now - lastBleScan >= bleScanDurationMs)) {
                pWardriveScan->stop();
            }
        }
    }
}

static void wardriveConfig(const uint8_t* payload, uint8_t len) {
    if (len < 1) return;
    uint8_t newRadio = payload[0] & 0x03;
    if (newRadio == 0) newRadio = 0x03;
    wardriveRadio = newRadio;

    if (len >= 5) {
        // bytes[1:2] = priority dwell (was wifiScanInterval)
        // bytes[3:4] = normal dwell (was wifiDwellPerCh)
        priorityDwellMs = payload[1] | (payload[2] << 8);
        normalDwellMs   = payload[3] | (payload[4] << 8);
        if (priorityDwellMs < 50) priorityDwellMs = 50;
        if (normalDwellMs < 50) normalDwellMs = 50;
    }
    if (len >= 9) {
        bleScanDurationMs = payload[5] | (payload[6] << 8);
        bleScanIntervalMs = payload[7] | (payload[8] << 8);
        if (bleScanDurationMs < 100) bleScanDurationMs = 100;
        if (bleScanIntervalMs < bleScanDurationMs + 100) bleScanIntervalMs = bleScanDurationMs + 100;
    }
    if (len >= 11) {
        uint8_t cs = payload[9];
        uint8_t ce = payload[10];
        if (cs >= 1 && cs <= 14) channelStart = cs;
        if (ce >= channelStart && ce <= 14) channelEnd = ce;
    }
    // Reset adaptive dwell and rebuild hop schedule for new range/dwell.
    for (int i = 0; i < 14; i++) {
        timePerChannel[i] = isPriorityChannel(i + 1) ? priorityDwellMs : normalDwellMs;
    }
    buildHopSchedule();

    Serial.printf("[WARDRIVE] Config: radio=0x%02X ch=%d-%d pri=%dms norm=%dms ble=%d/%d\n",
        wardriveRadio, channelStart, channelEnd,
        priorityDwellMs, normalDwellMs,
        bleScanDurationMs, bleScanIntervalMs);
}

uint16_t wardriveGetBleScanDurationMs(void) { return bleScanDurationMs; }
uint16_t wardriveGetBleScanIntervalMs(void) { return bleScanIntervalMs; }

const EngineCallbacks wardriveCallbacks = {
    .init   = wardriveInit,
    .start  = wardriveStart,
    .stop   = wardriveStop,
    .loop   = wardriveLoop,
    .config = wardriveConfig,
    .name   = "Wardrive",
};
