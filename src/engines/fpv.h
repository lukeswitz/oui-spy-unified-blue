// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_FPV_H
#define ENGINE_FPV_H

#include <stddef.h>
#include <stdint.h>
#include <sdkconfig.h>
#include "../protocol.h"

#if CONFIG_IDF_TARGET_ESP32C5 && !defined(OUISPY_ROLE_MANAGER) && !defined(OUISPY_DONGLE)
#define OUISPY_FPV 1
#endif

#ifdef OUISPY_FPV
void fpvInit(void);
bool fpvActive(void);
bool fpvBlocksEngine(EngineId id);
void fpvCommand(const uint8_t* data, size_t len);
void fpvAbort(void);
size_t fpvPackState(uint8_t* buf, size_t cap);
#else
static inline void fpvInit(void) {}
static inline bool fpvActive(void) { return false; }
static inline bool fpvBlocksEngine(EngineId) { return false; }
static inline void fpvAbort(void) {}
#endif

#endif
