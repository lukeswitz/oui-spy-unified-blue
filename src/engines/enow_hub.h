#ifndef ENGINE_ENOW_HUB_H
#define ENGINE_ENOW_HUB_H

#include <stdint.h>
#include "../protocol.h"

#define ENOW_HUB_OK            0x00
#define ENOW_HUB_REFUSE_MESH   0x01
#define ENOW_HUB_REFUSE_WIFI   0x02
#define ENOW_HUB_REFUSE_INIT   0x03
#define ENOW_HUB_REFUSE_ARGS   0x04
#define ENOW_HUB_REFUSE_NOALLOW 0x05
#define ENOW_HUB_MAX_ALLOW     8

uint8_t enowHubStart(const char* passphrase, const uint8_t* allow, uint8_t allowCount);
void enowHubStop(void);
bool enowHubActive(void);
uint8_t enowHubNodeCount(void);
uint32_t enowHubRecordCount(void);
void enowHubTick(void);
bool enowHubBlocksEngine(EngineId id);
bool enowHubSelfTest(void);
#ifdef OUISPY_PORT_SELFTEST
int enowHubPortSelfTest(void);
#endif

#endif
