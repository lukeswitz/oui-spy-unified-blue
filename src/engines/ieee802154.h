// Copyright (c) 2026 Luke Switzer
#ifndef IEEE802154_H
#define IEEE802154_H

#include <stdint.h>
#include <stdbool.h>

#ifdef OUISPY_DUAL_BAND

#define ZB154_CH_MIN 11
#define ZB154_CH_MAX 26

typedef void (*Zb154RxHandler)(const uint8_t* mac, uint8_t macLen, int8_t rssi, uint8_t lqi, uint8_t channel);

bool zb154Register(Zb154RxHandler handler);
void zb154Unregister(Zb154RxHandler handler);
bool zb154Active(void);
void zb154Tune(uint8_t channel);
void zb154Idle(void);
uint8_t zb154Channel(void);
uint32_t zb154FrameCount(void);

#endif
#endif
