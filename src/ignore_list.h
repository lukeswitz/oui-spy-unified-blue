#pragma once
#include <stdint.h>
#include <stddef.h>

// Wire format (matches companion IgnoreListState serialization):
//   [count:1] then count entries, each: [type:1][scope:1][len:1][value:len]
//   type:  0=SSID (utf8), 1=MAC (6 raw bytes), 2=OUI (3 raw bytes)
//   scope: 0=both, 1=wifi-only, 2=ble-only
#define IGNORE_TYPE_SSID 0
#define IGNORE_TYPE_MAC  1
#define IGNORE_TYPE_OUI  2
#define IGNORE_SCOPE_BOTH 0
#define IGNORE_SCOPE_WIFI 1
#define IGNORE_SCOPE_BLE  2

#define IGNORE_MAX_ENTRIES 48
#define IGNORE_MAX_VALUE   33

void ignoreListInit(void);
void ignoreListSet(const uint8_t* buf, size_t len);
bool ignoreListMatch(const uint8_t mac[6], const char* ssid, bool isBle);
size_t ignoreListSerialize(uint8_t* out, size_t maxLen);
uint8_t ignoreListCount(void);
uint32_t ignoreListVersion(void);
