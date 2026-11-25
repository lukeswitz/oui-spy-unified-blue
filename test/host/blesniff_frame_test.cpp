// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT
#include <cstdio>
#include <cstring>
#include "../../src/engines/blesniff_frame.h"

static int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                             \
        }                                                                           \
    } while (0)

static void filterCases() {
    CHECK(blesniffLlFromHci(0) == BLESNIFF_LL_ADV_IND);
    CHECK(blesniffLlFromHci(1) == BLESNIFF_LL_ADV_DIRECT_IND);
    CHECK(blesniffLlFromHci(2) == BLESNIFF_LL_ADV_SCAN_IND);
    CHECK(blesniffLlFromHci(3) == BLESNIFF_LL_ADV_NONCONN_IND);
    CHECK(blesniffLlFromHci(4) == BLESNIFF_LL_SCAN_RSP);
    CHECK(blesniffLlFromHci(9) == BLESNIFF_LL_ADV_IND);

    CHECK(blesniffPass(BLESNIFF_FT_DEFAULT, 0, 0));
    CHECK(blesniffPass(BLESNIFF_FT_DEFAULT, 4, 1));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADV_IND, 0, 0));
    CHECK(blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADV_IND, 3, 0));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_SCAN_RSP, 4, 0));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_RANDOM, 0, 1));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_RANDOM, 0, 3));
    CHECK(blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_RANDOM, 0, 0));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_PUBLIC, 0, 0));
    CHECK(!blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_PUBLIC, 0, 2));
    CHECK(blesniffPass(BLESNIFF_FT_DEFAULT & ~BLESNIFF_FT_ADDR_PUBLIC, 0, 1));

    CHECK(blesniffClassifyRandom(0x00) == BLESNIFF_ADDR_RANDOM_NRP);
    CHECK(blesniffClassifyRandom(0x7F) == BLESNIFF_ADDR_RANDOM_RPA);
    CHECK(blesniffClassifyRandom(0xC0) == BLESNIFF_ADDR_RANDOM_STATIC);
    CHECK(blesniffClassifyRandom(0x80) == BLESNIFF_ADDR_RANDOM_STATIC);
}

static void frameCases() {
    const uint8_t advA[6] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06};
    const uint8_t adv[3] = {0x02, 0x01, 0x06};
    uint8_t f[BLESNIFF_FRAME_MAX];
    size_t n = blesniffBuildFrame(f, BLESNIFF_LL_ADV_IND, false, advA, nullptr, adv, 3, -60);
    CHECK(n == 10 + 4 + 2 + 6 + 3 + 3);
    CHECK(f[0] == 37);
    CHECK(f[1] == (uint8_t)-60);
    CHECK(f[2] == 0x80);
    const uint8_t aa[4] = {0xD6, 0xBE, 0x89, 0x8E};
    CHECK(std::memcmp(f + 4, aa, 4) == 0);
    CHECK(f[8] == 0x13 && f[9] == 0x0C);
    CHECK(std::memcmp(f + 10, aa, 4) == 0);
    CHECK(f[14] == 0x00);
    CHECK(f[15] == 9);
    CHECK(std::memcmp(f + 16, advA, 6) == 0);
    CHECK(std::memcmp(f + 22, adv, 3) == 0);
    const uint32_t crc = blesniffCrc24(f + 14, 2 + 9);
    CHECK(f[25] == (uint8_t)(crc & 0xFF) && f[26] == (uint8_t)(crc >> 8) && f[27] == (uint8_t)(crc >> 16));

    n = blesniffBuildFrame(f, BLESNIFF_LL_SCAN_RSP, true, advA, nullptr, adv, 3, -70);
    CHECK(f[14] == (0x04 | 0x40));

    const uint8_t tgt[6] = {0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F};
    n = blesniffBuildFrame(f, BLESNIFF_LL_ADV_DIRECT_IND, true, advA, tgt, nullptr, 0, -50);
    CHECK(f[14] == (0x01 | 0x40));
    CHECK(f[15] == 12);
    CHECK(std::memcmp(f + 22, tgt, 6) == 0);
    CHECK(n == 10 + 4 + 2 + 12 + 3);

    uint8_t big[64];
    std::memset(big, 0x5A, sizeof(big));
    n = blesniffBuildFrame(f, BLESNIFF_LL_ADV_IND, false, advA, nullptr, big, 60, -40);
    CHECK(f[15] == 6 + BLESNIFF_MAX_ADV);
    CHECK(n <= BLESNIFF_FRAME_MAX);
}

static void recordCases() {
    uint8_t frame[5] = {1, 2, 3, 4, 5};
    uint8_t rec[BLESNIFF_REC_MAX];
    size_t n = blesniffPackRecord(rec, 3250000u, frame, 5);
    CHECK(n == 24 + 5 + 4);
    uint32_t v;
    std::memcpy(&v, rec + 0, 4); CHECK(v == 0xCAFEBABEu);
    std::memcpy(&v, rec + 4, 4); CHECK(v == 21);
    std::memcpy(&v, rec + 8, 4); CHECK(v == 3);
    std::memcpy(&v, rec + 12, 4); CHECK(v == 250000u);
    std::memcpy(&v, rec + 16, 4); CHECK(v == 5);
    std::memcpy(&v, rec + 20, 4); CHECK(v == 5);
    CHECK(std::memcmp(rec + 24, frame, 5) == 0);
    std::memcpy(&v, rec + 29, 4); CHECK(v == 0xDEADBEEFu);

    uint8_t maxFrame[BLESNIFF_FRAME_MAX] = {0};
    n = blesniffPackRecord(rec, 0, maxFrame, BLESNIFF_FRAME_MAX);
    CHECK(n == BLESNIFF_REC_MAX);
}

int main() {
    filterCases();
    frameCases();
    recordCases();
    if (failures) {
        std::printf("blesniff_frame_test: %d failure(s)\n", failures);
        return 1;
    }
    std::printf("blesniff_frame_test: all checks passed\n");
    return 0;
}
