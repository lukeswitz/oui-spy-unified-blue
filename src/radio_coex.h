#pragma once
#include <stdint.h>
#include "esp_wifi.h"

typedef void (*WifiRxParser)(void* buf, wifi_promiscuous_pkt_type_t type);

void wifiCoexRegister(WifiRxParser parser, uint32_t filterMask);
void wifiCoexUnregister(WifiRxParser parser);
#ifdef OUISPY_NIMBLE2
void c5WifiInitNetif(void);
void c5WifiUp(void);
#endif
bool wifiCoexActive(void);
bool wifiRadioExternallyOwned(void);
bool wifiCoexShouldHop(int engineId);

void wifiSnifferApplyPs(void);

#define WIFI_BAND_24 0x01
#define WIFI_BAND_5  0x02

void    wifiSetBandMask(uint8_t mask);
uint8_t wifiGetBandMask(void);
bool    wifiChanEnabled(uint8_t ch);
void    wifiApplyRegdomain(void);
