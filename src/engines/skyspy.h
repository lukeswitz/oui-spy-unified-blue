#ifndef ENGINE_SKYSPY_H
#define ENGINE_SKYSPY_H
#include "engine_registry.h"
extern const EngineCallbacks skyspyCallbacks;
#ifdef OUISPY_PORT_SELFTEST
int skyspyPortSelfTest(void);
#endif
#endif
