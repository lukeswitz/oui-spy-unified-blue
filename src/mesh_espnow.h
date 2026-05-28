#ifndef MESH_ESPNOW_H
#define MESH_ESPNOW_H

#include "protocol.h"

void meshInit(void);
void meshEnable(const MeshConfig* cfg);
void meshEnableEx(const MeshConfig* cfg, bool sendInvite);
void meshDisable(void);
void meshSendInvite(void);
void meshBroadcastDetection(const DetectionEvent* evt);
void meshBroadcastCommand(uint8_t command, uint8_t engine_id, const uint8_t* payload, uint8_t payload_len);
bool meshIsEnabled(void);
MeshStatus meshGetStatus(void);

#endif // MESH_ESPNOW_H
