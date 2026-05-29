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
void meshBroadcastAutoPcapEvent(uint8_t trigger_src, const uint8_t mac[6],
                                uint8_t channel, uint16_t duration_sec,
                                uint8_t paused_mask);
void meshForwardNotify(uint8_t kind, const uint8_t* data, size_t len);
void meshForwardPcapRecord(const uint8_t* record, size_t len);
void meshSendHeartbeat(uint8_t active_engines_mask);
bool meshGetLatestAutoPcapEvent(uint32_t max_age_ms, MeshAutoPcapEventPacket* out, uint32_t* age_ms_out);
bool meshIsEnabled(void);
const char* meshGetLocalNodeId(void);
MeshStatus meshGetStatus(void);

#define MESH_LIVE_NODES_MAX 16
struct MeshLiveNode {
    char     id[MESH_NODE_ID_LEN];
    uint32_t last_ms;
    uint8_t  role;
    uint8_t  active_engines;
};
size_t meshGetLiveNodes(MeshLiveNode* out, size_t maxOut, uint32_t ttl_ms);

#endif // MESH_ESPNOW_H
