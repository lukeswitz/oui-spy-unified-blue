// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_AXEOFF_H
#define ENGINE_AXEOFF_H

#include "engine_registry.h"

extern const EngineCallbacks axeoffCallbacks;

// Plays AXEOFF's boot jingle on the buzzer. Weak no-op here; main_unified.cpp provides the real one.
void axeoffBootChime(void);

// True while the AXEOFF engine is the only Axon source, so the presence timeout can follow upstream's 8 s.
bool axeoffRunning(void);

#endif
