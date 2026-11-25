// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_BLESNIFF_H
#define ENGINE_BLESNIFF_H

#include "engine_registry.h"
#include "protocol.h"

extern const EngineCallbacks blesniffCallbacks;

bool blesniffActive(void);

// Overwrites the BLE-capture fields of a PcapStats snapshot with BLE Sniff's counters (source flag set).
void blesniffFillStats(PcapStats* out);

#endif
