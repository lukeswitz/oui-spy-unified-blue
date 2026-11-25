// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef MESH_ESPNOW_H
#define MESH_ESPNOW_H

#include "protocol.h"

void meshInit(void);
void meshEnable(const MeshConfig* cfg);
void meshEnableEx(const MeshConfig* cfg, bool sendInvite);
void meshDisable(void);
void meshSendInvite(void);
void meshBroadcastDetection(const DetectionEvent* evt, bool spooled = false);
void meshFlushPendingTxAllChannels(void);
void meshEnqueueWardriveRecord(const DetectionEvent* evt);
#ifdef OUISPY_ROLE_MANAGER
bool meshMgrDrainBatch(void (*emit)(const DetectionEvent*));
#endif
void meshBroadcastCommand(uint8_t command, uint8_t engine_id, const uint8_t* payload, uint8_t payload_len, uint8_t maxRetries = 3);
void meshBroadcastAutoPcapEvent(uint8_t trigger_src, const uint8_t mac[6],
                                uint8_t channel, uint16_t duration_sec,
                                uint8_t paused_mask, uint8_t mode);
void meshForwardNotify(uint8_t kind, const uint8_t* data, size_t len);
void meshForwardPcapRecord(const uint8_t* record, size_t len);
void meshSendHeartbeat(uint8_t active_engines_mask);
bool meshGetLatestAutoPcapEvent(uint32_t max_age_ms, MeshAutoPcapEventPacket* out, uint32_t* age_ms_out);
bool meshIsEnabled(void);
bool meshInMeshWindow(void);
bool meshInRidWindow(void);
bool meshTimeSlicingActive(void);
void meshNoteOnHome(void);
void meshMarkNodesEngine(uint8_t engine, bool on);
bool meshManagerJoined(void);
bool meshMgrPhoneConnected(void);
void meshAddFleetMac(const uint8_t* mac);
bool meshIsFleetMac(const uint8_t* mac);
extern volatile uint32_t g_meshCmdRx;
extern volatile uint32_t g_meshRxWin;
extern volatile uint32_t g_meshRawRx;
extern volatile bool g_meshManagerActive;
void meshResetTxDedup(void);
void meshBroadcastIgnoreList(const uint8_t* data, size_t len);
void meshBroadcastDetectorList(const uint8_t* data, size_t len);
bool meshConsumeNewNodeJoined(void);
void meshBroadcastConfig(uint8_t kind, const uint8_t* data, size_t len);
void meshBroadcastWifiOta(const uint8_t* data, size_t len);
#if defined(OUISPY_AUTOPCAP_SELFTEST) || defined(OUISPY_WATCHDOG_SELFTEST)
void meshDebugForceManager(void);
#endif
const char* meshGetLocalNodeId(void);
MeshStatus meshGetStatus(void);

#define MESH_LIVE_NODES_MAX 16
#define MESH_MANAGER_TTL_MS 45000
#define MESH_NODE_TIMEOUT_MS 45000
struct MeshLiveNode {
    char     id[MESH_NODE_ID_LEN];
    uint32_t last_ms;
    uint8_t  role;
    uint8_t  active_engines;
    uint32_t fw_version;
    uint8_t  board;
    int8_t   temp_c;
    int8_t   rssi;
    uint32_t rssi_ms;
};
size_t meshGetLiveNodes(MeshLiveNode* out, size_t maxOut, uint32_t ttl_ms);
int8_t meshChipTempC(void);
void meshNoteRssi(const uint8_t* mac, int rssi);
#ifndef OUISPY_NIMBLE2
void meshRxTap(void* buf, int type);
#endif

#ifdef OUISPY_ROLE_MANAGER
struct MeshNeighbor {
    uint8_t id[2];
    int8_t  rssi;
};
struct MeshNeighborRow {
    uint8_t      id[2];
    uint8_t      count;
    MeshNeighbor e[MESH_NBR_MAX];
};
size_t meshGetNeighborRows(MeshNeighborRow* out, size_t maxOut);
#endif

#ifdef OUISPY_ROLE_MANAGER
struct MeshNodeDetail {
    char     id[MESH_NODE_ID_LEN];
    uint32_t fw_version;
    uint32_t uptime_s;
    uint32_t rx_ms;
    uint8_t  board;
    uint8_t  filter_macs;
    uint8_t  filter_uuids;
    uint8_t  peer_count;
};
size_t meshGetNodeDetails(MeshNodeDetail* out, size_t maxOut, uint32_t ttl_ms);

struct MeshFilterAck {
    char    id[MESH_NODE_ID_LEN];
    uint8_t status;
    uint8_t macs;
    uint8_t uuids;
};
struct MeshFilterPush {
    uint8_t seq;
    uint8_t macs;
    uint8_t uuids;
    uint8_t expected;
    uint8_t count;
    MeshFilterAck acks[MESH_LIVE_NODES_MAX];
};
void meshStartDetectorPush(const uint8_t* data, size_t len);
bool meshGetFilterPush(MeshFilterPush* out);
#endif

bool meshOtaInitiatorStart(uint32_t size, uint32_t crc, uint32_t fw_version);
bool meshOtaInitiatorRunning(void);
void meshOtaProgress(uint16_t* total, uint16_t* minRecv, uint8_t* nodesDone, uint8_t* nodesSeen);
void meshOtaSetProgressCb(void (*cb)(uint8_t phase, uint8_t pct, uint8_t done, uint8_t seen));

#ifdef OUISPY_NETCOUNT
uint32_t ncUniqueCount(void);
uint32_t ncRxTotalCount(void);
#endif

#ifdef OUISPY_SPOOL_STRESS
extern volatile uint32_t g_spoolStressAwayRx;
#endif

#endif // MESH_ESPNOW_H
