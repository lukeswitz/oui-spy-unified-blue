// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
#include <cstdio>
#include <cstring>
#include "../../src/engines/axeoff_match.h"

static int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                             \
        }                                                                           \
    } while (0)

static void mgmtFrame(uint8_t* f, uint8_t fc0, const uint8_t* addr2) {
    std::memset(f, 0, 32);
    f[0] = fc0;
    std::memset(f + 4, 0xFF, 6);
    std::memcpy(f + 10, addr2, 6);
}

static void wifiCases() {
    const uint8_t axon[6] = {0x00, 0x25, 0xDF, 0x11, 0x22, 0x33};
    const uint8_t other[6] = {0x00, 0x25, 0xDE, 0x11, 0x22, 0x33};
    uint8_t f[32], src[6];
    mgmtFrame(f, 0x40, axon);
    CHECK(axeoffWifiMatch(f, 32, src) == AXEOFF_WIFI_PROBE);
    CHECK(std::memcmp(src, axon, 6) == 0);
    mgmtFrame(f, 0x80, axon);
    CHECK(axeoffWifiMatch(f, 32, src) == AXEOFF_WIFI_BEACON);
    mgmtFrame(f, 0x50, axon);
    CHECK(axeoffWifiMatch(f, 32, src) == 0xFF);
    mgmtFrame(f, 0x08, axon);
    CHECK(axeoffWifiMatch(f, 32, src) == 0xFF);
    mgmtFrame(f, 0x40, other);
    CHECK(axeoffWifiMatch(f, 32, src) == 0xFF);
    mgmtFrame(f, 0x40, axon);
    CHECK(axeoffWifiMatch(f, 23, src) == 0xFF);
    CHECK(axeoffWifiMatch(f, 24, nullptr) == AXEOFF_WIFI_PROBE);
}

static void bleCases() {
    const uint8_t plain[6] = {0xAA, 0xBB, 0xCC, 0x01, 0x02, 0x03};
    const uint8_t axonMac[6] = {0x00, 0x25, 0xDF, 0x01, 0x02, 0x03};
    uint16_t svc = 0;

    const uint8_t cid[] = {0x05, 0xFF, 0x4D, 0x03, 0x01, 0x02};
    CHECK(axeoffBleMatch(plain, cid, sizeof(cid), &svc) == AXEOFF_HIT_CID);
    CHECK(axeoffBleSig(AXEOFF_HIT_CID) == AXEOFF_BLE_CID);

    const uint8_t notCid[] = {0x05, 0xFF, 0x4C, 0x00, 0x01, 0x02};
    CHECK(axeoffBleMatch(plain, notCid, sizeof(notCid), &svc) == 0);

    const uint8_t svcFc81[] = {0x03, 0x03, 0x81, 0xFC};
    CHECK(axeoffBleMatch(plain, svcFc81, sizeof(svcFc81), &svc) == AXEOFF_HIT_SVC);
    CHECK(svc == 0xFC81);
    const uint8_t svcFe6b[] = {0x05, 0x02, 0x00, 0x18, 0x6B, 0xFE};
    CHECK(axeoffBleMatch(plain, svcFe6b, sizeof(svcFe6b), &svc) == AXEOFF_HIT_SVC);
    CHECK(svc == 0xFE6B);
    const uint8_t svcFe6c[] = {0x03, 0x03, 0x6C, 0xFE};
    CHECK(axeoffBleMatch(plain, svcFe6c, sizeof(svcFe6c), &svc) == AXEOFF_HIT_SVC);
    CHECK(svc == 0xFE6C);
    const uint8_t svcOther[] = {0x03, 0x03, 0x0F, 0x18};
    CHECK(axeoffBleMatch(plain, svcOther, sizeof(svcOther), &svc) == 0);

    const uint8_t svc32[] = {0x05, 0x05, 0x81, 0xFC, 0x00, 0x00};
    CHECK(axeoffBleMatch(plain, svc32, sizeof(svc32), &svc) == AXEOFF_HIT_SVC);

    uint8_t svc128[18] = {0x11, 0x07};
    svc128[2 + 12] = 0x6C;
    svc128[2 + 13] = 0xFE;
    CHECK(axeoffBleMatch(plain, svc128, sizeof(svc128), &svc) == AXEOFF_HIT_SVC);
    CHECK(svc == 0xFE6C);

    CHECK(axeoffBleMatch(axonMac, nullptr, 0, &svc) == AXEOFF_HIT_MAC);
    CHECK(axeoffBleSig(AXEOFF_HIT_MAC) == AXEOFF_BLE_MAC);

    uint8_t both[sizeof(cid) + sizeof(svcFc81)];
    std::memcpy(both, cid, sizeof(cid));
    std::memcpy(both + sizeof(cid), svcFc81, sizeof(svcFc81));
    uint8_t h = axeoffBleMatch(axonMac, both, sizeof(both), &svc);
    CHECK(h == (AXEOFF_HIT_CID | AXEOFF_HIT_SVC | AXEOFF_HIT_MAC));
    CHECK(axeoffHitCount(h) == 3);
    CHECK(axeoffBleSig(h) == AXEOFF_BLE_CID);
    CHECK(axeoffBleSig(AXEOFF_HIT_SVC | AXEOFF_HIT_MAC) == AXEOFF_BLE_SVC);

    const uint8_t overrun[] = {0x09, 0xFF, 0x4D, 0x03};
    CHECK(axeoffBleMatch(plain, overrun, sizeof(overrun), &svc) == 0);
    const uint8_t zeroLen[] = {0x00, 0x00, 0x05, 0xFF, 0x4D, 0x03, 0x00, 0x00};
    CHECK(axeoffBleMatch(plain, zeroLen, sizeof(zeroLen), &svc) == AXEOFF_HIT_CID);
}

int main() {
    wifiCases();
    bleCases();
    if (failures) {
        std::printf("axeoff_match_test: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("axeoff_match_test: all checks passed\n");
    return 0;
}
