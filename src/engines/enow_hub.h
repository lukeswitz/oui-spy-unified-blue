#ifndef ENGINE_ENOW_HUB_H
#define ENGINE_ENOW_HUB_H

#include <stdint.h>
#include "../protocol.h"

#define ENOW_HUB_OK            0x00
#define ENOW_HUB_REFUSE_MESH   0x01
#define ENOW_HUB_REFUSE_WIFI   0x02
#define ENOW_HUB_REFUSE_INIT   0x03
#define ENOW_HUB_REFUSE_ARGS   0x04
#define ENOW_HUB_MAX_ALLOW     16

#define ENOW_NODE_PAIRED    0x01
#define ENOW_NODE_ONLINE    0x02
#define ENOW_NODE_ENCRYPTED 0x04

typedef void (*EnowNodeSink)(const uint8_t mac[6], int8_t rssi, uint8_t flags, uint32_t records, const char* name);
typedef void (*EnowFrameSink)(const uint8_t src[6], const uint8_t dst[6], const uint8_t* body, uint16_t captured, uint16_t total);

uint8_t enowHubStart(const char* passphrase, const uint8_t* allow, uint8_t allowCount);
void enowHubStop(void);
void enowHubSetSinks(EnowNodeSink node, EnowFrameSink frame);
bool enowHubPair(const uint8_t mac[6]);
bool enowHubForget(const uint8_t mac[6]);
void enowHubListNodes(void);
void enowHubSetCapture(bool on);
bool enowHubCaptureOn(void);
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
