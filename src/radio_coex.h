#pragma once
#include <stdint.h>
#include "esp_wifi.h"

typedef void (*WifiRxParser)(void* buf, wifi_promiscuous_pkt_type_t type);

void wifiCoexRegister(WifiRxParser parser, uint32_t filterMask);
void wifiCoexUnregister(WifiRxParser parser);
bool wifiCoexActive(void);
bool wifiCoexShouldHop(int engineId);

void wifiSnifferApplyPs(void);
