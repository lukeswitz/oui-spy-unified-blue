// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_FPV_LOGIC_H
#define ENGINE_FPV_LOGIC_H

#include <stddef.h>
#include <stdint.h>
#include <string.h>

namespace fpv {

constexpr uint8_t kBandCount = 6;
constexpr uint8_t kPerBand = 8;
constexpr uint8_t kChannelCount = kBandCount * kPerBand;
constexpr uint8_t kNoChannel = 0xFF;
constexpr uint8_t kNoLevel = 0xFF;
constexpr uint16_t kTuneMinMhz = 5180;
constexpr uint16_t kTuneMaxMhz = 5885;

enum Mode : uint8_t { kModeOff = 0, kModeStop = 1, kModeScan = 2, kModeSweep = 3, kModeHop = 4 };

enum Op : uint8_t {
    kOpEnter = 0x01,
    kOpLeave = 0x02,
    kOpMode = 0x03,
    kOpTune = 0x04,
    kOpStep = 0x05,
    kOpThreshold = 0x06,
};

enum Flag : uint8_t {
    kFlagActive = 0x01,
    kFlagLocked = 0x02,
    kFlagFlagged = 0x04,
    kFlagParked = 0x08,
    kFlagError = 0x10,
};

enum Error : uint8_t {
    kErrNone = 0,
    kErrUnsupported = 1,
    kErrMesh = 2,
    kErrRadio = 3,
    kErrCapture = 4,
    kErrTune = 5,
    kErrNoSignal = 6,
};

constexpr char kBandLetters[kBandCount] = {'A', 'B', 'E', 'F', 'R', 'L'};

constexpr uint16_t kFreqMhz[kChannelCount] = {
    5865, 5845, 5825, 5805, 5785, 5765, 5745, 5725,
    5733, 5752, 5771, 5790, 5809, 5828, 5847, 5866,
    5705, 5685, 5665, 5645, 5885, 5905, 5925, 5945,
    5740, 5760, 5780, 5800, 5820, 5840, 5860, 5880,
    5658, 5695, 5732, 5769, 5806, 5843, 5880, 5917,
    5362, 5399, 5436, 5473, 5510, 5547, 5584, 5621,
};

inline char bandLetter(uint8_t idx) { return kBandLetters[(idx / kPerBand) % kBandCount]; }
inline uint8_t bandNumber(uint8_t idx) { return (uint8_t)(idx % kPerBand + 1); }
inline uint16_t freqMhz(uint8_t idx) { return idx < kChannelCount ? kFreqMhz[idx] : 0; }

inline bool supported(uint8_t idx) {
    return idx < kChannelCount && kFreqMhz[idx] >= kTuneMinMhz && kFreqMhz[idx] <= kTuneMaxMhz;
}

inline uint8_t supportedCount() {
    uint8_t n = 0;
    for (uint8_t i = 0; i < kChannelCount; i++) n += supported(i) ? 1 : 0;
    return n;
}

inline void channelName(uint8_t idx, char out[3]) {
    out[0] = bandLetter(idx);
    out[1] = (char)('0' + bandNumber(idx));
    out[2] = '\0';
}

inline uint8_t stepChannel(uint8_t from, int dir) {
    if (dir == 0) return supported(from) ? from : kNoChannel;
    int step = dir > 0 ? 1 : -1;
    int i = from < kChannelCount ? from : (step > 0 ? kChannelCount - 1 : 0);
    for (int n = 0; n < kChannelCount; n++) {
        i = (i + step + kChannelCount) % kChannelCount;
        if (supported((uint8_t)i)) return (uint8_t)i;
    }
    return kNoChannel;
}

struct Center {
    uint8_t wifiChannel;
    uint16_t mhz;
};

constexpr Center kCenters[] = {
    {132, 5660}, {136, 5680}, {140, 5700}, {144, 5720}, {149, 5745}, {153, 5765},
    {157, 5785}, {161, 5805}, {165, 5825}, {169, 5845}, {173, 5865}, {177, 5885},
};
constexpr size_t kCenterCount = sizeof(kCenters) / sizeof(kCenters[0]);

inline bool planBootstrap(uint16_t mhz, Center* out) {
    if (mhz < kTuneMinMhz || mhz > kTuneMaxMhz) return false;
    size_t best = 0;
    int bestDelta = 0x7fffffff;
    for (size_t i = 0; i < kCenterCount; i++) {
        int d = (int)mhz - (int)kCenters[i].mhz;
        if (d < 0) d = -d;
        if (d < bestDelta) {
            bestDelta = d;
            best = i;
        }
    }
    if (out) *out = kCenters[best];
    return true;
}

constexpr uint8_t kMinPairPower = 8;
constexpr uint8_t kMinCoherence = 40;
constexpr uint8_t kDefaultThreshold = 12;
constexpr uint8_t kFallbackFloor = 8;
constexpr uint8_t kLockAcquire = 3;
constexpr uint8_t kLockLose = 8;
constexpr size_t kMinCapture = 64;

struct Measure {
    bool valid;
    uint8_t level;
    uint8_t coherence;
    uint8_t clipPct;
};

inline int8_t lowNibble(uint8_t b) { return (int8_t)((int8_t)(b << 4) >> 4); }
inline int8_t highNibble(uint8_t b) { return (int8_t)((int8_t)(b & 0xF0) >> 4); }

inline Measure measureIq(const uint8_t* buf, size_t n) {
    Measure m = {false, 0, 0, 0};
    if (!buf || n < kMinCapture) return m;
    bool allSame = true;
    for (size_t i = 1; i < n; i++) {
        if (buf[i] != buf[0]) {
            allSame = false;
            break;
        }
    }
    if (allSame) return m;
    uint32_t sumP = 0;
    uint32_t coherent = 0;
    uint32_t clipped = 0;
    int pi = 0;
    int pq = 0;
    for (size_t i = 0; i < n; i++) {
        int q = lowNibble(buf[i]);
        int in = highNibble(buf[i]);
        int p = in * in + q * q;
        sumP += (uint32_t)p;
        if (in == -8 || in == 7 || q == -8 || q == 7) clipped++;
        if (i > 0 && p >= kMinPairPower) {
            int dot = in * pi + q * pq;
            int cross = q * pi - in * pq;
            if (cross < 0) cross = -cross;
            if (dot > 0 && cross <= dot) coherent++;
        }
        pi = in;
        pq = q;
    }
    uint32_t lvl = (sumP * 2u) / (uint32_t)n;
    m.level = (uint8_t)(lvl > 254u ? 254u : lvl);
    m.coherence = (uint8_t)((coherent * 100u) / (uint32_t)(n - 1));
    m.clipPct = (uint8_t)((clipped * 100u) / (uint32_t)n);
    m.valid = true;
    return m;
}

inline uint8_t smoothLevel(uint8_t previous, uint8_t sample) {
    if (previous == kNoLevel) return sample;
    return (uint8_t)((previous * 3u + sample + 2u) / 4u);
}

inline uint8_t noiseFloor(const uint8_t* levels, size_t count) {
    uint8_t v[kChannelCount];
    size_t n = 0;
    for (size_t i = 0; i < count && n < kChannelCount; i++) {
        if (levels[i] != kNoLevel) v[n++] = levels[i];
    }
    if (n == 0) return kFallbackFloor;
    for (size_t i = 1; i < n; i++) {
        uint8_t key = v[i];
        size_t j = i;
        while (j > 0 && v[j - 1] > key) {
            v[j] = v[j - 1];
            j--;
        }
        v[j] = key;
    }
    return v[n / 4];
}

inline bool isTransmitter(uint8_t level, uint8_t coherence, uint8_t floor, uint8_t threshold) {
    if (level == kNoLevel) return false;
    return (uint16_t)level >= (uint16_t)floor + threshold && coherence >= kMinCoherence;
}

inline uint8_t loudestChannel(const uint8_t* levels, uint8_t floor, uint8_t threshold) {
    uint8_t best = kNoChannel;
    for (uint8_t i = 0; i < kChannelCount; i++) {
        if (!supported(i) || levels[i] == kNoLevel) continue;
        if ((uint16_t)levels[i] < (uint16_t)floor + threshold) continue;
        if (best == kNoChannel || levels[i] > levels[best]) best = i;
    }
    return best;
}

constexpr uint16_t kBleedMhz = 19;

inline uint64_t bleedMask(const uint8_t* levels) {
    uint8_t order[kChannelCount];
    uint8_t n = 0;
    for (uint8_t i = 0; i < kChannelCount; i++)
        if (supported(i) && levels[i] != kNoLevel) order[n++] = i;
    for (uint8_t a = 1; a < n; a++) {
        uint8_t key = order[a];
        uint8_t b = a;
        while (b > 0 && levels[order[b - 1]] < levels[key]) {
            order[b] = order[b - 1];
            b--;
        }
        order[b] = key;
    }
    uint64_t peaks = 0;
    uint64_t bleed = 0;
    for (uint8_t a = 0; a < n; a++) {
        uint8_t i = order[a];
        bool near = false;
        for (uint8_t j = 0; j < kChannelCount && !near; j++) {
            if (!((peaks >> j) & 1u)) continue;
            int d = (int)kFreqMhz[j] - (int)kFreqMhz[i];
            near = (d < 0 ? -d : d) < (int)kBleedMhz;
        }
        if (near) bleed |= (uint64_t)1 << i;
        else peaks |= (uint64_t)1 << i;
    }
    return bleed;
}

struct LockTracker {
    uint8_t hits = 0;
    uint8_t misses = 0;
    bool locked = false;

    bool update(bool present) {
        bool before = locked;
        if (present) {
            misses = 0;
            if (hits < 255) hits++;
            if (!locked && hits >= kLockAcquire) locked = true;
        } else {
            hits = 0;
            if (misses < 255) misses++;
            if (locked && misses >= kLockLose) locked = false;
        }
        return locked != before;
    }

    void reset() {
        hits = 0;
        misses = 0;
        locked = false;
    }
};

constexpr uint8_t kStateVersion = 1;
constexpr size_t kStateLen = 124;

struct State {
    uint8_t flags;
    uint8_t mode;
    uint8_t channel;
    uint16_t mhz;
    uint8_t level;
    uint8_t coherence;
    uint8_t floor;
    uint8_t threshold;
    uint8_t flaggedCount;
    uint8_t error;
    uint32_t passes;
    uint64_t supportedMask;
    uint64_t flaggedMask;
    uint8_t levels[kChannelCount];
    uint8_t coh[kChannelCount];
};

inline void putMask48(uint8_t* out, uint64_t m) {
    for (int i = 0; i < 6; i++) out[i] = (uint8_t)(m >> (8 * i));
}

inline uint64_t getMask48(const uint8_t* in) {
    uint64_t m = 0;
    for (int i = 0; i < 6; i++) m |= (uint64_t)in[i] << (8 * i);
    return m;
}

inline uint64_t supportedMask() {
    uint64_t m = 0;
    for (uint8_t i = 0; i < kChannelCount; i++)
        if (supported(i)) m |= (uint64_t)1 << i;
    return m;
}

inline size_t encodeState(const State& s, uint8_t* out, size_t cap) {
    if (!out || cap < kStateLen) return 0;
    out[0] = kStateVersion;
    out[1] = s.flags;
    out[2] = s.mode;
    out[3] = s.channel;
    out[4] = (uint8_t)(s.mhz & 0xFF);
    out[5] = (uint8_t)(s.mhz >> 8);
    out[6] = s.level;
    out[7] = s.coherence;
    out[8] = s.floor;
    out[9] = s.threshold;
    out[10] = s.flaggedCount;
    out[11] = s.error;
    for (int i = 0; i < 4; i++) out[12 + i] = (uint8_t)(s.passes >> (8 * i));
    putMask48(out + 16, s.supportedMask);
    putMask48(out + 22, s.flaggedMask);
    memcpy(out + 28, s.levels, kChannelCount);
    memcpy(out + 76, s.coh, kChannelCount);
    return kStateLen;
}

inline bool decodeState(const uint8_t* in, size_t len, State* s) {
    if (!in || !s || len < kStateLen || in[0] != kStateVersion) return false;
    s->flags = in[1];
    s->mode = in[2];
    s->channel = in[3];
    s->mhz = (uint16_t)(in[4] | (in[5] << 8));
    s->level = in[6];
    s->coherence = in[7];
    s->floor = in[8];
    s->threshold = in[9];
    s->flaggedCount = in[10];
    s->error = in[11];
    s->passes = (uint32_t)in[12] | ((uint32_t)in[13] << 8) | ((uint32_t)in[14] << 16) | ((uint32_t)in[15] << 24);
    s->supportedMask = getMask48(in + 16);
    s->flaggedMask = getMask48(in + 22);
    memcpy(s->levels, in + 28, kChannelCount);
    memcpy(s->coh, in + 76, kChannelCount);
    return true;
}

inline void pseudoMac(uint8_t idx, uint8_t mac[6]) {
    uint16_t f = freqMhz(idx);
    mac[0] = 0x02;
    mac[1] = 'F';
    mac[2] = 'P';
    mac[3] = 'V';
    mac[4] = (uint8_t)(f >> 8);
    mac[5] = (uint8_t)(f & 0xFF);
}

inline int8_t levelToRssi(uint8_t level) {
    uint8_t l = level > 254 ? 254 : level;
    return (int8_t)((int)(l / 2) - 128);
}

inline uint8_t rssiToLevel(int8_t rssi) { return (uint8_t)(((int)rssi + 128) * 2); }

inline void uavId(uint8_t idx, char out[21]) {
    char name[3];
    channelName(idx, name);
    unsigned f = freqMhz(idx);
    out[0] = 'F';
    out[1] = 'P';
    out[2] = 'V';
    out[3] = ' ';
    out[4] = name[0];
    out[5] = name[1];
    out[6] = ' ';
    out[7] = (char)('0' + (f / 1000) % 10);
    out[8] = (char)('0' + (f / 100) % 10);
    out[9] = (char)('0' + (f / 10) % 10);
    out[10] = (char)('0' + f % 10);
    out[11] = '\0';
}

}  // namespace fpv

#endif
