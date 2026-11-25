// Copyright (c) 2026 Luke Switzer
#ifndef ENGINE_FLOCK_BLE_H
#define ENGINE_FLOCK_BLE_H

#include "engine_registry.h"

extern const EngineCallbacks flockBleCallbacks;
void flockBleSetRadioGate(bool on);
void flockBleHostSuspend(bool suspend);

#endif
