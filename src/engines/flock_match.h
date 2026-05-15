#ifndef FLOCK_MATCH_H
#define FLOCK_MATCH_H

#include <stdint.h>
#include <string.h>
#include <Arduino.h>
#include <NimBLEDevice.h>
#include "flock_oui.h"

// ============================================================================
// Shared Flock Safety detection predicates.
// Single source of truth for OUI/name/mfg/UUID/TN-serial/Penguin-decimal logic.
// Used by both standalone flock_ble/flock_wifi engines AND wardrive passenger.
// ============================================================================

static const char* FLOCK_NAME_PATTERNS[] = {
    "FS Ext Battery", "Penguin", "Flock", "Pigvision",
    "FlockCam", "FlockOS", "FS-", "FS_", "flocksafety"
};
static const int FLOCK_NAME_PATTERN_COUNT =
    sizeof(FLOCK_NAME_PATTERNS) / sizeof(FLOCK_NAME_PATTERNS[0]);

// XUNTONG (battery vendor for Flock cams)
static const uint16_t FLOCK_MFG_IDS[] = { 0x09C8 };
static const int FLOCK_MFG_ID_COUNT =
    sizeof(FLOCK_MFG_IDS) / sizeof(FLOCK_MFG_IDS[0]);

// Raven gunshot-detector service UUIDs.
#define RAVEN_DEV_INFO_SVC    "0000180a-0000-1000-8000-00805f9b34fb"
#define RAVEN_GPS_SVC         "00003100-0000-1000-8000-00805f9b34fb"
#define RAVEN_POWER_SVC       "00003200-0000-1000-8000-00805f9b34fb"
#define RAVEN_UPLOAD_SVC      "00003300-0000-1000-8000-00805f9b34fb"
#define RAVEN_CONFIG_SVC      "00003400-0000-1000-8000-00805f9b34fb"
#define RAVEN_ERROR_SVC       "00003500-0000-1000-8000-00805f9b34fb"
#define RAVEN_HRT_SVC         "00001809-0000-1000-8000-00805f9b34fb"
#define RAVEN_OLD_LOC_SVC     "00001819-0000-1000-8000-00805f9b34fb"

// Cached UUID objects to avoid heap alloc / strcasecmp per advert.
struct RavenUuidCache {
    NimBLEUUID dev_info;
    NimBLEUUID gps;
    NimBLEUUID power;
    NimBLEUUID upload;
    NimBLEUUID config;
    NimBLEUUID error;
    NimBLEUUID hrt;
    NimBLEUUID old_loc;
    bool ready;
};

static RavenUuidCache flockRavenCache = {};

static inline void flockMatchInit() {
    if (flockRavenCache.ready) return;
    flockRavenCache.dev_info = NimBLEUUID(RAVEN_DEV_INFO_SVC);
    flockRavenCache.gps      = NimBLEUUID(RAVEN_GPS_SVC);
    flockRavenCache.power    = NimBLEUUID(RAVEN_POWER_SVC);
    flockRavenCache.upload   = NimBLEUUID(RAVEN_UPLOAD_SVC);
    flockRavenCache.config   = NimBLEUUID(RAVEN_CONFIG_SVC);
    flockRavenCache.error    = NimBLEUUID(RAVEN_ERROR_SVC);
    flockRavenCache.hrt      = NimBLEUUID(RAVEN_HRT_SVC);
    flockRavenCache.old_loc  = NimBLEUUID(RAVEN_OLD_LOC_SVC);
    flockRavenCache.ready    = true;
    flockOuiInitBuckets();
}

// ----------------------------------------------------------------------------
// Name match — case-insensitive substring against pattern list.
// Plus post-March-2025 firmware: bare 10-digit decimal name (Penguin drop).
// ----------------------------------------------------------------------------
static inline bool flockMatchNameStr(const char* name) {
    if (!name || !name[0]) return false;
    for (int i = 0; i < FLOCK_NAME_PATTERN_COUNT; i++) {
        if (strcasestr(name, FLOCK_NAME_PATTERNS[i])) return true;
    }
    // 10-digit decimal pattern (Penguin post-March-2025)
    int len = (int)strlen(name);
    if (len == 10) {
        bool allDigit = true;
        for (int i = 0; i < 10; i++) {
            if (name[i] < '0' || name[i] > '9') { allDigit = false; break; }
        }
        if (allDigit) return true;
    }
    return false;
}

// ----------------------------------------------------------------------------
// Mfg ID match. If matched, optionally extract TN-serial (TN<digits>) from
// payload — high-confidence signal. Returns true if mfg ID hits; if tnOut
// non-NULL, copies TN-serial there when found.
// ----------------------------------------------------------------------------
static inline bool flockMatchMfgPayload(const uint8_t* payload, size_t plen,
                                        char* tnOut, size_t tnOutLen) {
    if (tnOut && tnOutLen > 0) tnOut[0] = '\0';
    if (!payload || plen < 2) return false;
    uint16_t code = (uint16_t)payload[0] | ((uint16_t)payload[1] << 8);
    bool hit = false;
    for (int i = 0; i < FLOCK_MFG_ID_COUNT; i++) {
        if (FLOCK_MFG_IDS[i] == code) { hit = true; break; }
    }
    if (!hit) return false;
    if (!tnOut || tnOutLen < 4) return true;
    // Scan rest of payload for ASCII "TN" followed by digits.
    for (size_t i = 2; i + 2 < plen; i++) {
        if (payload[i] == 'T' && payload[i+1] == 'N' &&
            payload[i+2] >= '0' && payload[i+2] <= '9') {
            size_t j = i + 2;
            size_t k = 0;
            tnOut[k++] = 'T';
            tnOut[k++] = 'N';
            while (j < plen && k + 1 < tnOutLen &&
                   payload[j] >= '0' && payload[j] <= '9') {
                tnOut[k++] = (char)payload[j++];
            }
            tnOut[k] = '\0';
            break;
        }
    }
    return true;
}

// ----------------------------------------------------------------------------
// Raven UUID match — uses cached NimBLEUUID. Returns firmware-estimate string
// when matched (raven family only).
// ----------------------------------------------------------------------------
static inline bool flockMatchRavenUuid(NimBLEAdvertisedDevice* dev,
                                       const char** fwOut) {
    if (fwOut) *fwOut = "";
    if (!dev->haveServiceUUID()) return false;
    if (!flockRavenCache.ready) flockMatchInit();
    bool hit = false;
    bool has_new_gps = false, has_old_loc = false, has_power = false;
    int count = dev->getServiceUUIDCount();
    for (int i = 0; i < count; i++) {
        NimBLEUUID u = dev->getServiceUUID(i);
        if (u.equals(flockRavenCache.dev_info) ||
            u.equals(flockRavenCache.upload)   ||
            u.equals(flockRavenCache.config)   ||
            u.equals(flockRavenCache.error)    ||
            u.equals(flockRavenCache.hrt)) {
            hit = true;
        }
        if (u.equals(flockRavenCache.gps))     { hit = true; has_new_gps = true; }
        if (u.equals(flockRavenCache.power))   { hit = true; has_power   = true; }
        if (u.equals(flockRavenCache.old_loc)) { hit = true; has_old_loc = true; }
    }
    if (!hit) return false;
    if (fwOut) {
        if (has_old_loc && !has_new_gps) *fwOut = "1.1.x";
        else if (has_new_gps && !has_power) *fwOut = "1.2.x";
        else if (has_new_gps && has_power)  *fwOut = "1.3.x";
        else                                 *fwOut = "?";
    }
    return true;
}

// ----------------------------------------------------------------------------
// Address-type filter — drop random-resolvable adverts (phones, watches)
// unless they hit one of the deterministic predicates (name/mfg/uuid).
// Public + random-static are kept; flock cams use these.
// ----------------------------------------------------------------------------
static inline bool flockShouldConsiderAddr(NimBLEAdvertisedDevice* dev) {
    uint8_t t = dev->getAddressType();
    // BLE_ADDR_PUBLIC=0, BLE_ADDR_RANDOM=1, BLE_ADDR_PUBLIC_ID=2, BLE_ADDR_RANDOM_ID=3
    // Drop ID (resolvable) types as they are RPA traffic.
    return t == 0 || t == 1;
}

#endif
