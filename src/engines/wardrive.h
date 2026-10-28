#ifndef WARDRIVE_H
#define WARDRIVE_H

#include "../engine_registry.h"

extern const EngineCallbacks wardriveCallbacks;

uint16_t wardriveGetBleScanDurationMs(void);
uint16_t wardriveGetBleScanIntervalMs(void);
uint8_t  wardriveGetRadio(void);
void     wardriveSetRadioMask(uint8_t mask);
void     wardriveSetDwell(uint16_t pri, uint16_t norm);
uint32_t wardriveGetHopCount(void);
uint32_t wardriveGetMeshSkipCount(void);
#ifdef OUISPY_PORT_SELFTEST
int wardrivePortSelfTest(void);
#endif

#endif // WARDRIVE_H
