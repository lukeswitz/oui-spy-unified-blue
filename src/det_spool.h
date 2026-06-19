#pragma once
#include <stdint.h>
#include "protocol.h"

void detSpoolInit();
void detSpoolAppend(const DetectionEvent* evt);
uint16_t detSpoolCount();
bool detSpoolReadSlot(uint16_t i, DetectionEvent* out, uint16_t* hitCount);
void detSpoolClear();
uint16_t detSpoolDroppedCount();
bool engineSpoolable(uint8_t engine_id);
void detSpoolFlushIfDirty();

#ifdef OUISPY_SPOOL_SELFTEST
void detSpoolSelfTest();
#endif
