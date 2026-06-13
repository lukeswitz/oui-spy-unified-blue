#ifndef ENGINE_FLOCK_WIFI_H
#define ENGINE_FLOCK_WIFI_H
#include "engine_registry.h"
extern const EngineCallbacks flockWifiCallbacks;
void flockWifiSetRadioGate(bool on);
void flockWifiHostSuspend(bool suspend);
void flockSetExtendedOui(bool en);
bool flockGetExtendedOui(void);
#endif
