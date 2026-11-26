// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef MESH_CHAN_H
#define MESH_CHAN_H

#include <stdint.h>
#include <string.h>

#define MESH_CH_MIN     1
#define MESH_CH_MAX     11
#define MESH_CH_DEFAULT 1

#define MESH_CHAN_ID_LEN 5
#define MESH_CHAN_ROWS   16

#define MESH_CHAN_PREPARE_MS     15000
#define MESH_CHAN_COMMIT_MS      3000
#define MESH_CHAN_PREPARE_GAP_MS 200
#define MESH_CHAN_COMMIT_GAP_MS  150
#define MESH_CHAN_CANCEL_GAP_MS  200
#define MESH_CHAN_CANCEL_SENDS   5
#define MESH_CHAN_NODE_TTL_MS    30000
#define MESH_CHAN_STALE_MS       60000

#define MESH_HEAL_FIRST_MS         120000
#define MESH_HEAL_MAX_WAIT_MS      900000
#define MESH_HEAL_DWELL_MS         1700
#define MESH_HEAL_QUICK_SILENCE_MS 12000

enum { MCP_PREPARE = 1, MCP_COMMIT = 2, MCP_CANCEL = 3 };
enum { MCS_IDLE = 0, MCS_PREPARE = 1, MCS_COMMIT = 2, MCS_DONE = 3, MCS_FAILED = 4 };
enum { MCA_NONE = 0, MCA_PREPARE, MCA_COMMIT, MCA_CANCEL, MCA_SWITCH };
enum { MCR_OK = 0, MCR_BAD_CHANNEL, MCR_SAME, MCR_BUSY, MCR_MESH_OFF };
enum { MCN_NO_REPLY = 0, MCN_REPLY_PREPARED, MCN_REPLY_ALREADY };

static inline bool meshChanValid(uint8_t ch) { return ch >= MESH_CH_MIN && ch <= MESH_CH_MAX; }
static inline uint8_t meshChanClamp(uint8_t ch) { return meshChanValid(ch) ? ch : MESH_CH_DEFAULT; }
static inline bool meshChanReached(uint32_t now, uint32_t at) { return (int32_t)(now - at) >= 0; }

struct MeshChanRow {
    char    id[MESH_CHAN_ID_LEN];
    uint8_t acked;
    uint8_t followed;
};

struct MeshChanMgr {
    uint8_t     state;
    uint8_t     epoch;
    uint8_t     target;
    uint8_t     force;
    uint8_t     n;
    uint8_t     cancelLeft;
    MeshChanRow rows[MESH_CHAN_ROWS];
    uint32_t    startMs;
    uint32_t    lastTxMs;
    uint32_t    commitAtMs;
    uint32_t    switchMs;
};

struct MeshChanTick {
    uint8_t  act;
    uint16_t countdownMs;
};

static inline void meshChanMgrInit(MeshChanMgr* m, uint8_t seedEpoch) {
    memset(m, 0, sizeof(*m));
    m->epoch = seedEpoch;
}

static inline bool meshChanMgrBusy(const MeshChanMgr* m) {
    return m->state == MCS_PREPARE || m->state == MCS_COMMIT;
}

static inline uint8_t meshChanMgrStart(MeshChanMgr* m, uint8_t current, uint8_t target, bool force,
                                       const char* ids, uint8_t nIds, uint32_t now) {
    if (!meshChanValid(target)) return MCR_BAD_CHANNEL;
    if (meshChanMgrBusy(m)) return MCR_BUSY;
    if (target == current) return MCR_SAME;
    if (nIds > MESH_CHAN_ROWS) nIds = MESH_CHAN_ROWS;
    uint8_t ep = (uint8_t)((m->epoch % 255) + 1);
    memset(m, 0, sizeof(*m));
    m->epoch = ep;
    m->target = target;
    m->force = force ? 1 : 0;
    m->n = nIds;
    for (uint8_t i = 0; i < nIds; i++) memcpy(m->rows[i].id, ids + (size_t)i * MESH_CHAN_ID_LEN, MESH_CHAN_ID_LEN);
    m->state = MCS_PREPARE;
    m->startMs = now;
    m->lastTxMs = now - MESH_CHAN_PREPARE_GAP_MS;
    return MCR_OK;
}

static inline uint8_t meshChanMgrAcked(const MeshChanMgr* m) {
    uint8_t c = 0;
    for (uint8_t i = 0; i < m->n; i++) if (m->rows[i].acked) c++;
    return c;
}

static inline uint8_t meshChanMgrFollowed(const MeshChanMgr* m) {
    uint8_t c = 0;
    for (uint8_t i = 0; i < m->n; i++) if (m->rows[i].followed) c++;
    return c;
}

static inline MeshChanTick meshChanMgrTick(MeshChanMgr* m, uint32_t now) {
    MeshChanTick t = { MCA_NONE, 0 };
    if (m->state == MCS_PREPARE) {
        if (meshChanMgrAcked(m) == m->n) {
            m->state = MCS_COMMIT;
        } else if ((uint32_t)(now - m->startMs) >= MESH_CHAN_PREPARE_MS) {
            if (m->force) {
                m->state = MCS_COMMIT;
            } else {
                m->state = MCS_FAILED;
                m->cancelLeft = MESH_CHAN_CANCEL_SENDS;
                m->lastTxMs = now - MESH_CHAN_CANCEL_GAP_MS;
            }
        } else if ((uint32_t)(now - m->lastTxMs) >= MESH_CHAN_PREPARE_GAP_MS) {
            m->lastTxMs = now;
            t.act = MCA_PREPARE;
            return t;
        } else {
            return t;
        }
        if (m->state == MCS_COMMIT) {
            m->commitAtMs = now + MESH_CHAN_COMMIT_MS;
            m->lastTxMs = now - MESH_CHAN_COMMIT_GAP_MS;
        }
    }
    if (m->state == MCS_COMMIT) {
        if (meshChanReached(now, m->commitAtMs)) {
            m->state = MCS_DONE;
            m->switchMs = now;
            t.act = MCA_SWITCH;
        } else if ((uint32_t)(now - m->lastTxMs) >= MESH_CHAN_COMMIT_GAP_MS) {
            m->lastTxMs = now;
            uint32_t left = m->commitAtMs - now;
            t.act = MCA_COMMIT;
            t.countdownMs = left > 0xFFFF ? 0xFFFF : (uint16_t)left;
        }
        return t;
    }
    if (m->state == MCS_FAILED && m->cancelLeft > 0 &&
        (uint32_t)(now - m->lastTxMs) >= MESH_CHAN_CANCEL_GAP_MS) {
        m->lastTxMs = now;
        m->cancelLeft--;
        t.act = MCA_CANCEL;
    }
    return t;
}

static inline bool meshChanMgrOnAck(MeshChanMgr* m, const char* id, uint8_t epoch) {
    if (!meshChanMgrBusy(m) || epoch != m->epoch) return false;
    for (uint8_t i = 0; i < m->n; i++) {
        if (memcmp(m->rows[i].id, id, MESH_CHAN_ID_LEN) == 0) {
            bool fresh = !m->rows[i].acked;
            m->rows[i].acked = 1;
            return fresh;
        }
    }
    if (m->n >= MESH_CHAN_ROWS) return false;
    memcpy(m->rows[m->n].id, id, MESH_CHAN_ID_LEN);
    m->rows[m->n].acked = 1;
    m->rows[m->n].followed = 0;
    m->n++;
    return true;
}

static inline bool meshChanMgrMarkFollowed(MeshChanMgr* m, const char* id, uint32_t heardMs) {
    if (m->state != MCS_DONE) return false;
    if ((int32_t)(heardMs - m->switchMs) <= 0) return false;
    for (uint8_t i = 0; i < m->n; i++) {
        if (memcmp(m->rows[i].id, id, MESH_CHAN_ID_LEN) == 0) {
            bool fresh = !m->rows[i].followed;
            m->rows[i].followed = 1;
            return fresh;
        }
    }
    return false;
}

struct MeshChanNode {
    uint8_t  pendEpoch;
    uint8_t  pendCh;
    uint8_t  haveApply;
    uint8_t  haveLast;
    uint8_t  lastEpoch;
    uint32_t preparedMs;
    uint32_t applyAtMs;
    uint32_t lastApplyMs;
};

static inline void meshChanNodeInit(MeshChanNode* n) { memset(n, 0, sizeof(*n)); }

static inline uint8_t meshChanNodePendingCh(const MeshChanNode* n) {
    return n->pendEpoch ? n->pendCh : 0;
}

static inline uint8_t meshChanNodeOnSet(MeshChanNode* n, uint8_t phase, uint8_t epoch, uint8_t ch,
                                        uint16_t countdownMs, uint8_t current, uint32_t now) {
    if (epoch == 0) return MCN_NO_REPLY;
    if (phase == MCP_CANCEL) {
        if (n->pendEpoch == epoch) { n->pendEpoch = 0; n->pendCh = 0; n->haveApply = 0; }
        return MCN_NO_REPLY;
    }
    if (!meshChanValid(ch)) return MCN_NO_REPLY;
    if (n->haveLast && epoch == n->lastEpoch && (uint32_t)(now - n->lastApplyMs) < MESH_CHAN_STALE_MS)
        return MCN_NO_REPLY;
    if (phase == MCP_PREPARE) {
        if (ch == current) return MCN_REPLY_ALREADY;
        if (n->pendEpoch != epoch) { n->pendEpoch = epoch; n->haveApply = 0; }
        n->pendCh = ch;
        n->preparedMs = now;
        return MCN_REPLY_PREPARED;
    }
    if (phase == MCP_COMMIT) {
        if (ch == current) return MCN_NO_REPLY;
        if (n->pendEpoch != epoch) { n->pendEpoch = epoch; n->haveApply = 0; }
        n->pendCh = ch;
        uint32_t at = now + countdownMs;
        if (!n->haveApply || (int32_t)(at - n->applyAtMs) < 0) n->applyAtMs = at;
        n->haveApply = 1;
        n->preparedMs = now;
    }
    return MCN_NO_REPLY;
}

static inline bool meshChanNodeTick(MeshChanNode* n, uint32_t now, uint8_t* chOut) {
    if (!n->pendEpoch) return false;
    if (n->haveApply) {
        if (!meshChanReached(now, n->applyAtMs)) return false;
        *chOut = n->pendCh;
        n->lastEpoch = n->pendEpoch;
        n->lastApplyMs = now;
        n->haveLast = 1;
        n->pendEpoch = 0;
        n->pendCh = 0;
        n->haveApply = 0;
        return true;
    }
    if ((uint32_t)(now - n->preparedMs) >= MESH_CHAN_NODE_TTL_MS) {
        n->pendEpoch = 0;
        n->pendCh = 0;
    }
    return false;
}

static inline uint8_t meshHealOrder(uint8_t* out, uint8_t current, uint8_t hint, bool quick) {
    uint8_t len = 0;
    bool seen[MESH_CH_MAX + 1] = {};
    if (meshChanValid(hint) && hint != current) { out[len++] = hint; seen[hint] = true; }
    if (quick) return len;
    if (meshChanValid(current) && !seen[current]) { out[len++] = current; seen[current] = true; }
    for (uint8_t c = MESH_CH_MIN; c <= MESH_CH_MAX; c++)
        if (!seen[c]) out[len++] = c;
    return len;
}

static inline uint32_t meshHealNextWait(uint32_t waitMs) {
    uint32_t w = waitMs * 2;
    return w > MESH_HEAL_MAX_WAIT_MS ? MESH_HEAL_MAX_WAIT_MS : w;
}

static inline bool meshHealDue(uint32_t now, uint32_t refMs, uint32_t waitMs) {
    return meshChanReached(now, refMs + waitMs);
}

#endif
