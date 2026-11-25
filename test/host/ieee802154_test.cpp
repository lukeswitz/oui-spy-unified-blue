// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#include <cstdio>
#include <cstring>
#include "../../src/engines/ieee802154_frame.h"

static int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                             \
        }                                                                           \
    } while (0)

static void testCrc() {
    const char* s = "123456789";
    CHECK(zb154Crc16((const uint8_t*)s, 9) == 0x2189);
    CHECK(zb154Crc16((const uint8_t*)s, 0) == 0);
}

static void testZigbeeBeacon() {
    const uint8_t f[] = {
        0x00, 0x80, 0x5A, 0x34, 0x12, 0x00, 0x00, 0xFF, 0xCF, 0x00, 0x00,
        0x00, 0x22, 0x84, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88, 0xFF, 0xFF, 0xFF, 0x00,
    };
    Zb154Frame o;
    CHECK(zb154ParseMac(f, sizeof(f), &o));
    CHECK(o.type == ZB154_FRAME_BEACON);
    CHECK(o.srcMode == ZB154_ADDR_SHORT && o.srcShort == 0x0000);
    CHECK(o.hasPan && o.pan == 0x1234);
    CHECK(o.beaconKind == ZB154_BEACON_ZIGBEE);
    CHECK(o.beaconInfo == 0x22 && o.beaconCaps == 0x03);
    const uint8_t ext[8] = {0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11};
    CHECK(memcmp(o.beaconExtPan, ext, 8) == 0);
    uint8_t mac[6];
    CHECK(zb154SourceKey(&o, mac));
    const uint8_t key[6] = {0x00, 0x00, 0x12, 0x34, 0x00, 0x00};
    CHECK(memcmp(mac, key, 6) == 0);
    uint8_t adv[ZB154_ADV_MAX];
    uint8_t n = zb154PackAdv(&o, 200, adv);
    CHECK(n == 26 && n <= ZB154_ADV_MAX);
    CHECK(adv[0] == 0 && adv[1] == 2 && adv[2] == 0x34 && adv[3] == 0x12 && adv[14] == 200 && adv[15] == 1);
}

static void testDataExtSource() {
    const uint8_t f[] = {
        0x61, 0xC8, 0x07, 0x34, 0x12, 0xFF, 0xFF,
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11, 0x01, 0x02,
    };
    Zb154Frame o;
    CHECK(zb154ParseMac(f, sizeof(f), &o));
    CHECK(o.type == ZB154_FRAME_DATA && o.ackReq && o.hasSeq && o.seq == 7);
    CHECK(o.srcMode == ZB154_ADDR_EXT && o.hasPan && o.pan == 0x1234);
    const uint8_t ext[8] = {0x11, 0x00, 0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA};
    CHECK(memcmp(o.srcExt, ext, 8) == 0);
    uint8_t mac[6];
    CHECK(zb154SourceKey(&o, mac));
    const uint8_t key[6] = {0xFF, 0xEE, 0xDD, 0xCC, 0xBB, 0xAA};
    CHECK(memcmp(mac, key, 6) == 0);
}

static void testNoSource() {
    const uint8_t beaconReq[] = {0x03, 0x08, 0x01, 0xFF, 0xFF, 0xFF, 0xFF, 0x07};
    Zb154Frame o;
    CHECK(zb154ParseMac(beaconReq, sizeof(beaconReq), &o));
    CHECK(o.type == ZB154_FRAME_CMD && o.srcMode == ZB154_ADDR_NONE);
    uint8_t mac[6];
    CHECK(!zb154SourceKey(&o, mac));
    const uint8_t ack[] = {0x02, 0x00, 0x09};
    CHECK(zb154ParseMac(ack, sizeof(ack), &o));
    CHECK(o.type == ZB154_FRAME_ACK && !zb154SourceKey(&o, mac));
}

static void test2015Addressing() {
    const uint8_t a[] = {
        0x01, 0xE9, 0x34, 0x12, 0xFF, 0xFF, 0x78, 0x56,
        0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF, 0x00, 0x11, 0x99,
    };
    Zb154Frame o;
    CHECK(zb154ParseMac(a, sizeof(a), &o));
    CHECK(o.version == 2 && !o.hasSeq && o.srcMode == ZB154_ADDR_EXT);
    CHECK(o.hasPan && o.pan == 0x5678);
    CHECK(o.srcExt[0] == 0x11 && o.srcExt[7] == 0xAA);

    const uint8_t b[] = {
        0x41, 0xEC, 0x05,
        0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
        0xA1, 0xA2, 0xA3, 0xA4, 0xA5, 0xA6, 0xA7, 0xA8, 0x55,
    };
    CHECK(zb154ParseMac(b, sizeof(b), &o));
    CHECK(o.hasSeq && o.seq == 5 && !o.hasPan);
    CHECK(o.srcMode == ZB154_ADDR_EXT && o.srcExt[0] == 0xA8 && o.srcExt[7] == 0xA1);
}

static void testThreadBeacon() {
    uint8_t f[64];
    size_t n = 0;
    const uint8_t hdr[] = {0x00, 0xC0, 0x01, 0xCD, 0xAB, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0xFF, 0xCF, 0x00, 0x00};
    memcpy(f, hdr, sizeof(hdr));
    n = sizeof(hdr);
    f[n++] = 0x03;
    f[n++] = 0x20;
    char name[16] = {0};
    memcpy(name, "MyThreadNet", 11);
    memcpy(f + n, name, 16);
    n += 16;
    const uint8_t xp[8] = {0xDE, 0xAD, 0xBE, 0xEF, 0x00, 0xCA, 0xFE, 0x01};
    memcpy(f + n, xp, 8);
    n += 8;
    Zb154Frame o;
    CHECK(zb154ParseMac(f, n, &o));
    CHECK(o.beaconKind == ZB154_BEACON_THREAD);
    CHECK(strcmp(o.netName, "MyThreadNet") == 0);
    CHECK(o.beaconInfo == 0x20 && memcmp(o.beaconExtPan, xp, 8) == 0);
    CHECK(o.pan == 0xABCD && o.srcMode == ZB154_ADDR_EXT);
    uint8_t adv[ZB154_ADV_MAX];
    CHECK(zb154PackAdv(&o, 10, adv) == 25);
}

static void testRejects() {
    Zb154Frame o;
    const uint8_t tiny[] = {0x01, 0x08};
    CHECK(!zb154ParseMac(tiny, sizeof(tiny), &o));
    const uint8_t reservedMode[] = {0x01, 0x04, 0x00, 0x00};
    CHECK(!zb154ParseMac(reservedMode, sizeof(reservedMode), &o));
    const uint8_t multipurpose[] = {0x05, 0x00, 0x00, 0x00};
    CHECK(!zb154ParseMac(multipurpose, sizeof(multipurpose), &o));
    const uint8_t truncated[] = {0x61, 0xC8, 0x07, 0x34, 0x12, 0xFF, 0xFF, 0xAA, 0xBB};
    CHECK(!zb154ParseMac(truncated, sizeof(truncated), &o));
    const uint8_t shortBeacon[] = {0x00, 0x80, 0x01, 0x34, 0x12, 0x00, 0x00, 0xFF};
    CHECK(zb154ParseMac(shortBeacon, sizeof(shortBeacon), &o) && o.beaconKind == ZB154_BEACON_NONE);
}

int main() {
    testCrc();
    testZigbeeBeacon();
    testDataExtSource();
    testNoSource();
    test2015Addressing();
    testThreadBeacon();
    testRejects();
    if (failures) {
        std::printf("%d failure(s)\n", failures);
        return 1;
    }
    std::printf("ieee802154: all checks passed\n");
    return 0;
}
