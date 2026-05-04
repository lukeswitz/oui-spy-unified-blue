#ifndef MESH_ESPNOW_H
#define MESH_ESPNOW_H

#include "protocol.h"

void meshInit(void);
void meshEnable(const MeshConfig* cfg);
void meshDisable(void);
void meshBroadcastDetection(const DetectionEvent* evt);
void meshBroadcastCommand(const MeshCommandPacket* cmd);
void meshBroadcastStatus(void);
void meshBroadcastInvite(void);
void meshProcessPendingInvite(void);
bool meshIsEnabled(void);
MeshStatus meshGetStatus(void);
const char* meshGetLocalNodeId(void);

#endif // MESH_ESPNOW_H
