// Copyright (c) 2026 Luke Switzer
#pragma once
#include <stdint.h>
#include <stddef.h>

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
