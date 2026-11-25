// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include "../../src/engines/fpv_logic.h"

static int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                             \
        }                                                                           \
    } while (0)

static uint8_t pack(int i, int q) { return (uint8_t)(((i & 0xF) << 4) | (q & 0xF)); }

static void testTable() {
    using namespace fpv;
    CHECK(kChannelCount == 48);
    char nm[3];
    channelName(0, nm);
    CHECK(std::strcmp(nm, "A1") == 0 && freqMhz(0) == 5865);
    channelName(7, nm);
    CHECK(std::strcmp(nm, "A8") == 0 && freqMhz(7) == 5725);
    channelName(8, nm);
    CHECK(std::strcmp(nm, "B1") == 0 && freqMhz(8) == 5733);
    channelName(20, nm);
    CHECK(std::strcmp(nm, "E5") == 0 && freqMhz(20) == 5885);
    channelName(24, nm);
    CHECK(std::strcmp(nm, "F1") == 0 && freqMhz(24) == 5740);
    channelName(36, nm);
    CHECK(std::strcmp(nm, "R5") == 0 && freqMhz(36) == 5806);
    channelName(47, nm);
    CHECK(std::strcmp(nm, "L8") == 0 && freqMhz(47) == 5621);
    CHECK(freqMhz(48) == 0 && !supported(48) && !supported(kNoChannel));
    CHECK(supportedCount() == 44);
    const uint8_t bad[] = {21, 22, 23, 39};
    for (uint8_t i = 0; i < kChannelCount; i++) {
        bool expectBad = false;
        for (uint8_t b : bad) expectBad |= (b == i);
        CHECK(supported(i) == !expectBad);
        if (supported(i)) CHECK(freqMhz(i) >= 5180 && freqMhz(i) <= 5885);
    }
    CHECK(freqMhz(39) == 5917 && freqMhz(21) == 5905 && freqMhz(22) == 5925 && freqMhz(23) == 5945);
    for (uint8_t a = 0; a < kChannelCount; a++)
        for (uint8_t b = a + 1; b < kChannelCount; b++)
            if (kFreqMhz[a] == kFreqMhz[b]) CHECK(kFreqMhz[a] == 5880 || kFreqMhz[a] == 5865);
}

static void testStep() {
    using namespace fpv;
    CHECK(stepChannel(0, 1) == 1);
    CHECK(stepChannel(0, -1) == 47);
    CHECK(stepChannel(47, 1) == 0);
    CHECK(stepChannel(20, 1) == 24);
    CHECK(stepChannel(24, -1) == 20);
    CHECK(stepChannel(38, 1) == 40);
    CHECK(stepChannel(40, -1) == 38);
    CHECK(stepChannel(21, 1) == 24);
    CHECK(stepChannel(21, -1) == 20);
    CHECK(stepChannel(0, 0) == 0);
    CHECK(stepChannel(39, 0) == kNoChannel);
    CHECK(stepChannel(kNoChannel, 1) == 0);
}

static void testBootstrap() {
    using namespace fpv;
    Center c = {};
    CHECK(planBootstrap(5865, &c) && c.wifiChannel == 173 && c.mhz == 5865);
    CHECK(planBootstrap(5885, &c) && c.wifiChannel == 177);
    CHECK(planBootstrap(5362, &c) && c.wifiChannel == 132);
    CHECK(planBootstrap(5733, &c) && c.wifiChannel == 149);
    CHECK(planBootstrap(5180, &c));
    CHECK(!planBootstrap(5179, &c));
    CHECK(!planBootstrap(5886, &c));
    CHECK(!planBootstrap(5917, nullptr));
    for (uint8_t i = 0; i < kChannelCount; i++) CHECK(planBootstrap(freqMhz(i), nullptr) == supported(i));
}

static void testMeasure() {
    using namespace fpv;
    uint8_t buf[512];
    for (size_t k = 0; k < sizeof(buf); k++) {
        double a = (double)k * 15.0 * M_PI / 180.0;
        buf[k] = pack((int)std::lround(5.0 * std::cos(a)), (int)std::lround(5.0 * std::sin(a)));
    }
    Measure m = measureIq(buf, sizeof(buf));
    CHECK(m.valid && m.coherence >= 95);
    CHECK(m.level >= 44 && m.level <= 56);
    CHECK(m.clipPct == 0);

    uint32_t seed = 12345;
    for (size_t k = 0; k < sizeof(buf); k++) {
        seed = seed * 1664525u + 1013904223u;
        int i = (int)((seed >> 16) % 5) - 2;
        seed = seed * 1664525u + 1013904223u;
        int q = (int)((seed >> 16) % 5) - 2;
        buf[k] = pack(i, q);
    }
    Measure n = measureIq(buf, sizeof(buf));
    CHECK(n.valid && n.level <= 20);
    CHECK(n.coherence < kMinCoherence);

    for (size_t k = 0; k < sizeof(buf); k++) {
        uint32_t r = (uint32_t)k * 2654435761u;
        seed = seed * 1664525u + 1013904223u;
        int sgnI = (r >> 7) & 1 ? 7 : -8;
        int sgnQ = (seed >> 20) & 1 ? 7 : -8;
        buf[k] = pack(sgnI, sgnQ);
    }
    Measure c = measureIq(buf, sizeof(buf));
    CHECK(c.valid && c.clipPct == 100 && c.level >= 200);

    std::memset(buf, 0x00, sizeof(buf));
    CHECK(!measureIq(buf, sizeof(buf)).valid);
    std::memset(buf, 0x5A, sizeof(buf));
    CHECK(!measureIq(buf, sizeof(buf)).valid);
    CHECK(!measureIq(buf, kMinCapture - 1).valid);
    CHECK(!measureIq(nullptr, 512).valid);

    CHECK(lowNibble(0x0F) == -1 && lowNibble(0x07) == 7 && lowNibble(0x08) == -8);
    CHECK(highNibble(0xF0) == -1 && highNibble(0x70) == 7 && highNibble(0x80) == -8);
}

static void testFloorAndFlags() {
    using namespace fpv;
    uint8_t lv[kChannelCount];
    std::memset(lv, kNoLevel, sizeof(lv));
    CHECK(noiseFloor(lv, kChannelCount) == kFallbackFloor);
    for (int i = 0; i < 8; i++) lv[i] = (uint8_t)(10 + i);
    lv[8] = 90;
    lv[9] = 120;
    CHECK(noiseFloor(lv, kChannelCount) == 12);
    lv[0] = lv[1] = lv[2] = 4;
    CHECK(noiseFloor(lv, kChannelCount) == 4);
    uint8_t one[1] = {33};
    CHECK(noiseFloor(one, 1) == 33);

    CHECK(isTransmitter(30, 60, 10, 12));
    CHECK(isTransmitter(22, 40, 10, 12));
    CHECK(!isTransmitter(21, 60, 10, 12));
    CHECK(!isTransmitter(60, 39, 10, 12));
    CHECK(!isTransmitter(kNoLevel, 100, 0, 0));
    CHECK(isTransmitter(254, 100, 250, 4));
    CHECK(!isTransmitter(254, 100, 250, 5));

    CHECK(smoothLevel(kNoLevel, 40) == 40);
    CHECK(smoothLevel(40, 40) == 40);
    CHECK(smoothLevel(0, 100) == 25);
    CHECK(smoothLevel(100, 0) == 75);
}

static void testLock() {
    using namespace fpv;
    LockTracker t;
    CHECK(!t.update(true) && !t.locked);
    CHECK(!t.update(true) && !t.locked);
    CHECK(t.update(true) && t.locked);
    for (int i = 0; i < 7; i++) CHECK(!t.update(false) && t.locked);
    CHECK(!t.update(true) && t.locked);
    for (int i = 0; i < 7; i++) CHECK(!t.update(false) && t.locked);
    CHECK(t.update(false) && !t.locked);
    CHECK(!t.update(false));
    t.update(true);
    t.update(true);
    t.update(false);
    CHECK(!t.update(true) && !t.locked);
    t.reset();
    CHECK(!t.locked && t.hits == 0 && t.misses == 0);
}

static std::string hex(const uint8_t* p, size_t n) {
    static const char* d = "0123456789abcdef";
    std::string s;
    for (size_t i = 0; i < n; i++) {
        s += d[p[i] >> 4];
        s += d[p[i] & 15];
    }
    return s;
}

static const char* kGolden =
    "0103030499163c520a0c020004030201ffff1fff7fff10020000000000050a0f14191e23282d32373c41464b50555a5f64"
    "ffffff787d82878c91969ba0a5aaafb4b9beff00050a0f14191e2300070e151c232a31383f464d545b62040b12192027"
    "000000434a51585f01080f161d242b323940004e555c63050c131a";

static fpv::State goldenState() {
    using namespace fpv;
    State s = {};
    s.flags = kFlagActive | kFlagLocked;
    s.mode = kModeSweep;
    s.channel = 4;
    s.mhz = 5785;
    s.level = 60;
    s.coherence = 82;
    s.floor = 10;
    s.threshold = 12;
    s.flaggedCount = 2;
    s.error = 0;
    s.passes = 0x01020304u;
    s.supportedMask = supportedMask();
    s.flaggedMask = ((uint64_t)1 << 4) | ((uint64_t)1 << 9);
    for (uint8_t i = 0; i < kChannelCount; i++) {
        s.levels[i] = supported(i) ? (uint8_t)((i * 5) % 200) : kNoLevel;
        s.coh[i] = supported(i) ? (uint8_t)((i * 7) % 101) : 0;
    }
    return s;
}

static void testPacket() {
    using namespace fpv;
    State s = goldenState();
    uint8_t buf[kStateLen];
    CHECK(encodeState(s, buf, sizeof(buf)) == kStateLen);
    CHECK(encodeState(s, buf, kStateLen - 1) == 0);
    CHECK(kStateLen == 124);
    CHECK(buf[0] == 1 && buf[1] == 0x03 && buf[2] == 3 && buf[3] == 4);
    CHECK(buf[4] == 0x99 && buf[5] == 0x16);
    CHECK(buf[12] == 0x04 && buf[15] == 0x01);
    CHECK(getMask48(buf + 16) == supportedMask());
    CHECK(supportedMask() == 0xFF7FFF1FFFFFull);

    State d = {};
    CHECK(decodeState(buf, sizeof(buf), &d));
    CHECK(d.flags == s.flags && d.mode == s.mode && d.channel == s.channel && d.mhz == s.mhz);
    CHECK(d.level == s.level && d.coherence == s.coherence && d.floor == s.floor);
    CHECK(d.threshold == s.threshold && d.flaggedCount == s.flaggedCount && d.error == s.error);
    CHECK(d.passes == s.passes && d.supportedMask == s.supportedMask && d.flaggedMask == s.flaggedMask);
    CHECK(std::memcmp(d.levels, s.levels, kChannelCount) == 0 && std::memcmp(d.coh, s.coh, kChannelCount) == 0);

    buf[0] = 2;
    CHECK(!decodeState(buf, sizeof(buf), &d));
    buf[0] = 1;
    CHECK(!decodeState(buf, kStateLen - 1, &d));
    CHECK(!decodeState(nullptr, kStateLen, &d));

    encodeState(s, buf, sizeof(buf));
    std::string got = hex(buf, kStateLen);
    if (std::getenv("FPV_PRINT_GOLDEN")) std::printf("GOLDEN %s\n", got.c_str());
    CHECK(got == kGolden);
    CHECK(got.size() == 248);
}

static void testIdentity() {
    using namespace fpv;
    uint8_t mac[6];
    pseudoMac(0, mac);
    CHECK(mac[0] == 0x02 && mac[1] == 'F' && mac[2] == 'P' && mac[3] == 'V');
    CHECK(mac[4] == 0x16 && mac[5] == 0xE9);
    pseudoMac(47, mac);
    CHECK(mac[4] == 0x15 && mac[5] == 0xF5);
    char id[21];
    uavId(0, id);
    CHECK(std::strcmp(id, "FPV A1 5865") == 0);
    uavId(47, id);
    CHECK(std::strcmp(id, "FPV L8 5621") == 0);
    CHECK(levelToRssi(0) == -128 && levelToRssi(254) == -1 && levelToRssi(255) == -1);
    for (int l = 0; l <= 254; l += 2) CHECK(rssiToLevel(levelToRssi((uint8_t)l)) == l);
}

int main() {
    testTable();
    testStep();
    testBootstrap();
    testMeasure();
    testFloorAndFlags();
    testLock();
    testPacket();
    testIdentity();
    if (failures == 0) std::printf("fpv_logic: all checks passed\n");
    return failures == 0 ? 0 : 1;
}
