#ifndef MESH_ESPNOW_H
#define MESH_ESPNOW_H

#include "protocol.h"

void meshInit(void);
void meshEnable(const MeshConfig* cfg);
void meshDisable(void);
void meshBroadcastDetection(const DetectionEvent* evt);
bool meshIsEnabled(void);
MeshStatus meshGetStatus(void);

#endif // MESH_ESPNOW_H
