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
bool detSpoolStorageOk();

typedef struct __attribute__((packed)) {
    uint8_t  mac[6];
    int8_t   rssi;
    uint8_t  channel;
    uint8_t  auth_mode;
    uint8_t  is_ble;
    char     name[33];
    int32_t  lat_e7;
    int32_t  lon_e7;
    int16_t  altitude_m;
    uint16_t accuracy_dm;
    uint32_t utc_epoch;
} WdLogRecord;

bool wdLogAppend(const DetectionEvent* evt, uint32_t utcEpoch);
uint32_t wdLogCount();
uint32_t wdLogDropped();
bool wdLogRead(uint32_t index, WdLogRecord* out);
void wdLogClear();

#ifdef OUISPY_SPOOL_SELFTEST
void detSpoolSelfTest();
#endif
#ifdef OUISPY_PORT_SELFTEST
int detSpoolPortSelfTest();
#endif
