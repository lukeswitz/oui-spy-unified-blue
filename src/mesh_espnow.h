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
bool meshInMeshWindow(void);
bool meshTimeSlicingActive(void);
void meshNoteOnHome(void);
void meshMarkNodesEngine(uint8_t engine, bool on);
bool meshManagerJoined(void);
void meshAddFleetMac(const uint8_t* mac);
bool meshIsFleetMac(const uint8_t* mac);
extern volatile uint32_t g_meshCmdRx;
extern volatile uint32_t g_meshRxWin;
extern volatile bool g_meshManagerActive;
void meshResetTxDedup(void);
void meshBroadcastIgnoreList(const uint8_t* data, size_t len);
void meshBroadcastDetectorList(const uint8_t* data, size_t len);
void meshBroadcastConfig(uint8_t kind, const uint8_t* data, size_t len);
#if defined(OUISPY_AUTOPCAP_SELFTEST) || defined(OUISPY_WATCHDOG_SELFTEST)
void meshDebugForceManager(void);
#endif
const char* meshGetLocalNodeId(void);
MeshStatus meshGetStatus(void);

#define MESH_LIVE_NODES_MAX 16
#define MESH_MANAGER_TTL_MS 20000
#define MESH_NODE_TIMEOUT_MS 45000
struct MeshLiveNode {
    char     id[MESH_NODE_ID_LEN];
    uint32_t last_ms;
    uint8_t  role;
    uint8_t  active_engines;
};
size_t meshGetLiveNodes(MeshLiveNode* out, size_t maxOut, uint32_t ttl_ms);

bool meshOtaInitiatorStart(uint32_t size, uint32_t crc, uint32_t fw_version);
bool meshOtaInitiatorRunning(void);
void meshOtaProgress(uint16_t* total, uint16_t* minRecv, uint8_t* nodesDone, uint8_t* nodesSeen);
void meshOtaSetProgressCb(void (*cb)(uint8_t phase, uint8_t pct, uint8_t done, uint8_t seen));

#endif // MESH_ESPNOW_H
