// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#include <stdio.h>
#include "mesh_chan.h"

static int g_fail = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); g_fail++; } } while (0)

static const char kIds[2][MESH_CHAN_ID_LEN] = { {'A','B','1','2',0}, {'C','D','3','4',0} };

static void runAllAcked(uint32_t t0) {
    MeshChanMgr m;
    meshChanMgrInit(&m, 7);
    CHECK(meshChanMgrStart(&m, 1, 6, false, &kIds[0][0], 2, t0) == MCR_OK);
    CHECK(m.epoch == 8);
    MeshChanTick t = meshChanMgrTick(&m, t0);
    CHECK(t.act == MCA_PREPARE);
    CHECK(meshChanMgrTick(&m, t0 + 50).act == MCA_NONE);
    CHECK(meshChanMgrOnAck(&m, kIds[0], 8));
    CHECK(!meshChanMgrOnAck(&m, kIds[0], 8));
    CHECK(!meshChanMgrOnAck(&m, kIds[1], 9));
    CHECK(meshChanMgrTick(&m, t0 + 250).act == MCA_PREPARE);
    CHECK(meshChanMgrOnAck(&m, kIds[1], 8));
    t = meshChanMgrTick(&m, t0 + 300);
    CHECK(t.act == MCA_COMMIT && t.countdownMs == MESH_CHAN_COMMIT_MS);
    CHECK(m.state == MCS_COMMIT);
    CHECK(meshChanMgrTick(&m, t0 + 350).act == MCA_NONE);
    t = meshChanMgrTick(&m, t0 + 450);
    CHECK(t.act == MCA_COMMIT && t.countdownMs == MESH_CHAN_COMMIT_MS - 150);
    t = meshChanMgrTick(&m, t0 + 300 + MESH_CHAN_COMMIT_MS);
    CHECK(t.act == MCA_SWITCH && m.state == MCS_DONE);
    CHECK(meshChanMgrTick(&m, t0 + 400 + MESH_CHAN_COMMIT_MS).act == MCA_NONE);
    uint32_t sw = m.switchMs;
    CHECK(!meshChanMgrMarkFollowed(&m, kIds[0], sw));
    CHECK(!meshChanMgrMarkFollowed(&m, kIds[0], sw - 5));
    CHECK(meshChanMgrMarkFollowed(&m, kIds[0], sw + 5));
    CHECK(!meshChanMgrMarkFollowed(&m, kIds[0], sw + 9));
    CHECK(meshChanMgrFollowed(&m) == 1);
    CHECK(meshChanMgrMarkFollowed(&m, kIds[1], sw + 20));
    CHECK(meshChanMgrFollowed(&m) == 2);
    const char other[MESH_CHAN_ID_LEN] = {'Z','Z','9','9',0};
    CHECK(!meshChanMgrMarkFollowed(&m, other, sw + 20));
}

static void missingAck(void) {
    MeshChanMgr m;
    meshChanMgrInit(&m, 255);
    CHECK(meshChanMgrStart(&m, 3, 4, false, &kIds[0][0], 2, 1000) == MCR_OK);
    CHECK(m.epoch == 1);
    meshChanMgrOnAck(&m, kIds[0], 1);
    int prepares = 0, cancels = 0, commits = 0;
    for (uint32_t t = 1000; t < 1000 + MESH_CHAN_PREPARE_MS + 3000; t += 50) {
        MeshChanTick k = meshChanMgrTick(&m, t);
        if (k.act == MCA_PREPARE) prepares++;
        if (k.act == MCA_CANCEL) cancels++;
        if (k.act == MCA_COMMIT || k.act == MCA_SWITCH) commits++;
    }
    CHECK(prepares > 50);
    CHECK(cancels == MESH_CHAN_CANCEL_SENDS);
    CHECK(commits == 0);
    CHECK(m.state == MCS_FAILED);
    CHECK(!meshChanMgrBusy(&m));
    CHECK(meshChanMgrStart(&m, 3, 4, false, &kIds[0][0], 2, 40000) == MCR_OK);
    CHECK(m.epoch == 2);
}

static void forced(void) {
    MeshChanMgr m;
    meshChanMgrInit(&m, 0);
    CHECK(meshChanMgrStart(&m, 1, 11, true, &kIds[0][0], 2, 0) == MCR_OK);
    int commits = 0, sw = 0;
    for (uint32_t t = 0; t < MESH_CHAN_PREPARE_MS + MESH_CHAN_COMMIT_MS + 500; t += 50) {
        MeshChanTick k = meshChanMgrTick(&m, t);
        if (k.act == MCA_COMMIT) commits++;
        if (k.act == MCA_SWITCH) sw++;
    }
    CHECK(commits > 10 && sw == 1 && m.state == MCS_DONE);
}

static void guards(void) {
    MeshChanMgr m;
    meshChanMgrInit(&m, 0);
    CHECK(meshChanMgrStart(&m, 1, 0, false, nullptr, 0, 0) == MCR_BAD_CHANNEL);
    CHECK(meshChanMgrStart(&m, 1, 12, false, nullptr, 0, 0) == MCR_BAD_CHANNEL);
    CHECK(meshChanMgrStart(&m, 6, 6, false, nullptr, 0, 0) == MCR_SAME);
    CHECK(meshChanMgrStart(&m, 1, 6, false, nullptr, 0, 0) == MCR_OK);
    CHECK(meshChanMgrStart(&m, 1, 7, false, nullptr, 0, 0) == MCR_BUSY);
    MeshChanTick k = meshChanMgrTick(&m, 0);
    CHECK(k.act == MCA_COMMIT && k.countdownMs == MESH_CHAN_COMMIT_MS);
}

static void lateJoiner(void) {
    MeshChanMgr m;
    meshChanMgrInit(&m, 0);
    meshChanMgrStart(&m, 1, 2, false, &kIds[0][0], 1, 0);
    CHECK(meshChanMgrOnAck(&m, kIds[1], 1));
    CHECK(m.n == 2);
    CHECK(meshChanMgrAcked(&m) == 1);
    meshChanMgrOnAck(&m, kIds[0], 1);
    CHECK(meshChanMgrTick(&m, 10).act == MCA_COMMIT);
}

static void nodeFlow(uint32_t t0) {
    MeshChanNode n;
    meshChanNodeInit(&n);
    uint8_t ch = 0;
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 5, 6, 0, 1, t0) == MCN_REPLY_PREPARED);
    CHECK(meshChanNodePendingCh(&n) == 6);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 5, 6, 0, 1, t0 + 200) == MCN_REPLY_PREPARED);
    CHECK(!meshChanNodeTick(&n, t0 + 20000, &ch));
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 5, 6, 3000, 1, t0 + 21000) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 5, 6, 2850, 1, t0 + 21150) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 5, 6, 2750, 1, t0 + 21300) == MCN_NO_REPLY);
    CHECK(!meshChanNodeTick(&n, t0 + 23999, &ch));
    CHECK(meshChanNodeTick(&n, t0 + 24050, &ch) && ch == 6);
    CHECK(meshChanNodePendingCh(&n) == 0);
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 5, 6, 100, 1, t0 + 24100) == MCN_NO_REPLY);
    CHECK(!meshChanNodeTick(&n, t0 + 25000, &ch));
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 5, 9, 0, 6, t0 + 25000) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 6, 9, 0, 6, t0 + 25000) == MCN_REPLY_PREPARED);
}

static void nodeEdges(void) {
    MeshChanNode n;
    meshChanNodeInit(&n);
    uint8_t ch = 0;
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 0, 6, 0, 1, 0) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 1, 0, 0, 1, 0) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 1, 12, 0, 1, 0) == MCN_NO_REPLY);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 1, 1, 0, 1, 0) == MCN_REPLY_ALREADY);
    CHECK(meshChanNodePendingCh(&n) == 0);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 2, 4, 0, 1, 0) == MCN_REPLY_PREPARED);
    CHECK(meshChanNodeOnSet(&n, MCP_CANCEL, 3, 4, 0, 1, 10) == MCN_NO_REPLY);
    CHECK(meshChanNodePendingCh(&n) == 4);
    CHECK(meshChanNodeOnSet(&n, MCP_CANCEL, 2, 4, 0, 1, 10) == MCN_NO_REPLY);
    CHECK(meshChanNodePendingCh(&n) == 0);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 3, 4, 0, 1, 100) == MCN_REPLY_PREPARED);
    CHECK(!meshChanNodeTick(&n, 100 + MESH_CHAN_NODE_TTL_MS - 1, &ch));
    CHECK(meshChanNodePendingCh(&n) == 4);
    CHECK(!meshChanNodeTick(&n, 100 + MESH_CHAN_NODE_TTL_MS, &ch));
    CHECK(meshChanNodePendingCh(&n) == 0);
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 4, 8, 500, 1, 50000) == MCN_NO_REPLY);
    CHECK(meshChanNodePendingCh(&n) == 8);
    CHECK(meshChanNodeTick(&n, 50500, &ch) && ch == 8);
    meshChanNodeInit(&n);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 9, 4, 0, 1, 0) == MCN_REPLY_PREPARED);
    CHECK(meshChanNodeTick(&n, 0, &ch) == false);
    CHECK(meshChanNodeOnSet(&n, MCP_COMMIT, 9, 4, 0, 1, 5) == MCN_NO_REPLY);
    CHECK(meshChanNodeTick(&n, 5, &ch) && ch == 4);
    CHECK(meshChanNodeOnSet(&n, MCP_PREPARE, 9, 5, 0, 4, 5 + MESH_CHAN_STALE_MS) == MCN_REPLY_PREPARED);
}

static void healLogic(void) {
    uint8_t o[16];
    uint8_t n = meshHealOrder(o, 4, 0, false);
    CHECK(n == 11 && o[0] == 4 && o[1] == 1 && o[2] == 2 && o[3] == 3 && o[4] == 5 && o[10] == 11);
    n = meshHealOrder(o, 4, 9, false);
    CHECK(n == 11 && o[0] == 9 && o[1] == 4 && o[2] == 1 && o[9] == 10 && o[10] == 11);
    n = meshHealOrder(o, 4, 4, false);
    CHECK(n == 11 && o[0] == 4);
    n = meshHealOrder(o, 4, 9, true);
    CHECK(n == 1 && o[0] == 9);
    CHECK(meshHealOrder(o, 4, 0, true) == 0);
    CHECK(meshHealOrder(o, 4, 4, true) == 0);
    bool seen[12] = {};
    n = meshHealOrder(o, 7, 2, false);
    for (uint8_t i = 0; i < n; i++) { CHECK(!seen[o[i]]); seen[o[i]] = true; }
    for (uint8_t c = 1; c <= 11; c++) CHECK(seen[c]);
    uint32_t w = MESH_HEAL_FIRST_MS;
    w = meshHealNextWait(w);
    CHECK(w == 240000);
    for (int i = 0; i < 10; i++) w = meshHealNextWait(w);
    CHECK(w == MESH_HEAL_MAX_WAIT_MS);
    CHECK(!meshHealDue(1000 + 119999, 1000, MESH_HEAL_FIRST_MS));
    CHECK(meshHealDue(1000 + 120000, 1000, MESH_HEAL_FIRST_MS));
    CHECK(meshHealDue(10, 0xFFFFFF00u, 100));
    CHECK(!meshHealDue(10, 0xFFFFFF00u, 1000));
}

static void validity(void) {
    CHECK(!meshChanValid(0) && meshChanValid(1) && meshChanValid(11) && !meshChanValid(12) && !meshChanValid(255));
    CHECK(meshChanClamp(0) == 1 && meshChanClamp(0xFF) == 1 && meshChanClamp(6) == 6);
}

int main() {
    runAllAcked(1000);
    runAllAcked(0xFFFFFF00u);
    missingAck();
    forced();
    guards();
    lateJoiner();
    nodeFlow(1000);
    nodeFlow(0xFFFFF000u);
    nodeEdges();
    healLogic();
    validity();
    if (g_fail) { printf("mesh_chan: %d failure(s)\n", g_fail); return 1; }
    printf("mesh_chan: all checks passed\n");
    return 0;
}
