/**
 * Shared Flock Safety OUI table — used by flock_wifi, flock_ble, and wardrive
 * engines to identify Flock Safety devices by MAC prefix.
 *
 * Byte-compiled for fast IRAM matching. Covers both BLE ext-battery
 * and WiFi camera OUIs.
 */
#ifndef FLOCK_OUI_H
#define FLOCK_OUI_H

#include <stdint.h>
#include <string.h>

static const uint8_t FLOCK_OUI_TABLE[][3] = {
    // FS Ext Battery (BLE)
    {0x58,0x8e,0x81}, {0xcc,0xcc,0xcc}, {0xec,0x1b,0xbd}, {0x90,0x35,0xea},
    {0x04,0x0d,0x84}, {0xf0,0x82,0xc0}, {0x1c,0x34,0xf1}, {0x38,0x5b,0x44},
    {0x94,0x34,0x69}, {0xb4,0xe3,0xf9},
    // Flock WiFi cameras
    {0x70,0xc9,0x4e}, {0x3c,0x91,0x80}, {0xd8,0xf3,0xbc}, {0x80,0x30,0x49},
    {0x14,0x5a,0xfc}, {0x74,0x4c,0xa1}, {0x08,0x3a,0x88}, {0x9c,0x2f,0x9d},
    {0x94,0x08,0x53}, {0xe4,0xaa,0xea},
};
static const int FLOCK_OUI_COUNT = sizeof(FLOCK_OUI_TABLE) / sizeof(FLOCK_OUI_TABLE[0]);

/**
 * Check if a 6-byte MAC matches any known Flock Safety OUI.
 * Skips locally administered (randomized) MACs.
 */
static inline bool flockMatchOui(const uint8_t* mac) {
    if (mac[0] & 0x02) return false;  // randomized MAC
    for (int i = 0; i < FLOCK_OUI_COUNT; i++) {
        if (mac[0] == FLOCK_OUI_TABLE[i][0] &&
            mac[1] == FLOCK_OUI_TABLE[i][1] &&
            mac[2] == FLOCK_OUI_TABLE[i][2]) return true;
    }
    return false;
}

/**
 * IRAM-safe variant for use in ISR callbacks (promiscuous WiFi sniffer).
 */
static inline bool IRAM_ATTR flockMatchOuiISR(const uint8_t* mac) {
    if (mac[0] & 0x02) return false;
    for (int i = 0; i < FLOCK_OUI_COUNT; i++) {
        if (mac[0] == FLOCK_OUI_TABLE[i][0] &&
            mac[1] == FLOCK_OUI_TABLE[i][1] &&
            mac[2] == FLOCK_OUI_TABLE[i][2]) return true;
    }
    return false;
}

#endif // FLOCK_OUI_H
