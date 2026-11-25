// Copyright (c) 2026 Luke Switzer
#ifndef IEEE802154_FRAME_H
#define IEEE802154_FRAME_H

#include <stdint.h>
#include <string.h>

#define ZB154_FRAME_BEACON 0
#define ZB154_FRAME_DATA   1
#define ZB154_FRAME_ACK    2
#define ZB154_FRAME_CMD    3

#define ZB154_BEACON_NONE   0
#define ZB154_BEACON_ZIGBEE 1
#define ZB154_BEACON_THREAD 2

#define ZB154_ADDR_NONE  0
#define ZB154_ADDR_SHORT 2
#define ZB154_ADDR_EXT   3

#define ZB154_ADV_FIXED 16
#define ZB154_ADV_MAX   31

#define ZB154_FN static inline __attribute__((always_inline))

typedef struct {
    uint8_t  type;
    uint8_t  version;
    uint8_t  secured;
    uint8_t  ackReq;
    uint8_t  hasSeq;
    uint8_t  seq;
    uint8_t  dstMode;
    uint8_t  srcMode;
    uint8_t  hasPan;
    uint16_t pan;
    uint16_t srcShort;
    uint8_t  srcExt[8];
    uint8_t  beaconKind;
    uint8_t  beaconExtPan[8];
    uint8_t  beaconInfo;
    uint8_t  beaconCaps;
    char     netName[17];
} Zb154Frame;

ZB154_FN uint16_t zb154Rd16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }

ZB154_FN void zb154RdExt(const uint8_t* p, uint8_t* out) {
    for (int i = 0; i < 8; i++) out[i] = p[7 - i];
}

ZB154_FN uint16_t zb154Crc16(const uint8_t* data, uint32_t len) {
    uint16_t crc = 0;
    for (uint32_t i = 0; i < len; i++) {
        crc ^= data[i];
        for (int b = 0; b < 8; b++) crc = (crc & 1) ? (uint16_t)((crc >> 1) ^ 0x8408u) : (uint16_t)(crc >> 1);
    }
    return crc;
}

ZB154_FN void zb154ParseBeaconPayload(const uint8_t* p, uint32_t n, Zb154Frame* o) {
    if (n >= 15 && p[0] == 0x00) {
        o->beaconKind = ZB154_BEACON_ZIGBEE;
        o->beaconInfo = p[1];
        o->beaconCaps = (uint8_t)(((p[2] >> 2) & 0x01) | ((p[2] >> 6) & 0x02));
        zb154RdExt(p + 3, o->beaconExtPan);
    } else if (n >= 26 && p[0] == 0x03) {
        o->beaconKind = ZB154_BEACON_THREAD;
        o->beaconInfo = p[1];
        memcpy(o->netName, p + 2, 16);
        o->netName[16] = '\0';
        for (int i = 0; i < 16; i++) {
            if ((uint8_t)o->netName[i] < 0x20 || (uint8_t)o->netName[i] > 0x7E) { o->netName[i] = '\0'; break; }
        }
        memcpy(o->beaconExtPan, p + 18, 8);
    }
}

ZB154_FN bool zb154ParseMac(const uint8_t* f, uint32_t len, Zb154Frame* o) {
    memset(o, 0, sizeof(*o));
    if (len < 3) return false;
    const uint16_t fcf = zb154Rd16(f);
    o->type = (uint8_t)(fcf & 0x07);
    o->secured = (uint8_t)((fcf >> 3) & 1);
    o->ackReq = (uint8_t)((fcf >> 5) & 1);
    const uint8_t comp = (uint8_t)((fcf >> 6) & 1);
    const uint8_t seqSup = (uint8_t)((fcf >> 8) & 1);
    const uint8_t iePresent = (uint8_t)((fcf >> 9) & 1);
    o->dstMode = (uint8_t)((fcf >> 10) & 3);
    o->version = (uint8_t)((fcf >> 12) & 3);
    o->srcMode = (uint8_t)((fcf >> 14) & 3);
    if (o->type > ZB154_FRAME_CMD || o->dstMode == 1 || o->srcMode == 1) return false;

    uint32_t off = 2;
    if (!(o->version == 2 && seqSup)) {
        o->hasSeq = 1;
        o->seq = f[off++];
    }

    bool dstPan, srcPan;
    if (o->version == 2) {
        if (o->dstMode == 0 && o->srcMode == 0) { dstPan = comp; srcPan = false; }
        else if (o->dstMode != 0 && o->srcMode == 0) { dstPan = !comp; srcPan = false; }
        else if (o->dstMode == 0) { dstPan = false; srcPan = !comp; }
        else if (o->dstMode == ZB154_ADDR_EXT && o->srcMode == ZB154_ADDR_EXT) { dstPan = !comp; srcPan = false; }
        else { dstPan = true; srcPan = !comp; }
    } else {
        dstPan = o->dstMode != 0;
        srcPan = o->srcMode != 0 && !comp;
    }

    uint16_t dstPanId = 0;
    uint8_t haveDstPan = 0;
    if (dstPan) {
        if (off + 2 > len) return false;
        dstPanId = zb154Rd16(f + off);
        off += 2;
        haveDstPan = 1;
    }
    if (o->dstMode == ZB154_ADDR_SHORT) {
        if (off + 2 > len) return false;
        off += 2;
    } else if (o->dstMode == ZB154_ADDR_EXT) {
        if (off + 8 > len) return false;
        off += 8;
    }
    if (srcPan) {
        if (off + 2 > len) return false;
        o->pan = zb154Rd16(f + off);
        o->hasPan = 1;
        off += 2;
    } else if (haveDstPan) {
        o->pan = dstPanId;
        o->hasPan = 1;
    }
    if (o->srcMode == ZB154_ADDR_SHORT) {
        if (off + 2 > len) return false;
        o->srcShort = zb154Rd16(f + off);
        off += 2;
    } else if (o->srcMode == ZB154_ADDR_EXT) {
        if (off + 8 > len) return false;
        zb154RdExt(f + off, o->srcExt);
        off += 8;
    }

    if (o->type == ZB154_FRAME_BEACON && o->version < 2 && !o->secured && !iePresent) {
        if (off + 3 > len) return true;
        off += 2;
        uint8_t gts = f[off++];
        uint32_t gtsN = gts & 0x07;
        if (gtsN) off += 1 + 3 * gtsN;
        if (off + 1 > len) return true;
        uint8_t pend = f[off++];
        off += 2u * (pend & 0x07) + 8u * ((pend >> 4) & 0x07);
        if (off < len) zb154ParseBeaconPayload(f + off, len - off, o);
    }
    return true;
}

ZB154_FN bool zb154SourceKey(const Zb154Frame* o, uint8_t* mac) {
    if (o->srcMode == ZB154_ADDR_EXT) {
        memcpy(mac, o->srcExt + 2, 6);
        return true;
    }
    if (o->srcMode == ZB154_ADDR_SHORT) {
        mac[0] = 0x00;
        mac[1] = 0x00;
        mac[2] = (uint8_t)(o->pan >> 8);
        mac[3] = (uint8_t)(o->pan & 0xFF);
        mac[4] = (uint8_t)(o->srcShort >> 8);
        mac[5] = (uint8_t)(o->srcShort & 0xFF);
        return true;
    }
    return false;
}

ZB154_FN uint8_t zb154PackAdv(const Zb154Frame* o, uint8_t lqi, uint8_t* adv) {
    adv[0] = o->type;
    adv[1] = o->srcMode;
    const uint16_t pan = o->hasPan ? o->pan : 0xFFFFu;
    adv[2] = (uint8_t)(pan & 0xFF);
    adv[3] = (uint8_t)(pan >> 8);
    const uint16_t sh = o->srcMode == ZB154_ADDR_SHORT ? o->srcShort : 0xFFFEu;
    adv[4] = (uint8_t)(sh & 0xFF);
    adv[5] = (uint8_t)(sh >> 8);
    if (o->srcMode == ZB154_ADDR_EXT) memcpy(adv + 6, o->srcExt, 8);
    else memset(adv + 6, 0, 8);
    adv[14] = lqi;
    adv[15] = o->beaconKind;
    uint8_t n = ZB154_ADV_FIXED;
    if (o->beaconKind != ZB154_BEACON_NONE) {
        memcpy(adv + n, o->beaconExtPan, 8);
        n += 8;
        adv[n++] = o->beaconInfo;
        if (o->beaconKind == ZB154_BEACON_ZIGBEE) adv[n++] = o->beaconCaps;
    }
    return n;
}

#endif
