#pragma once

#include <math.h>
#include <stdint.h>
#include <string.h>
#include "opendroneid.h"

struct DroneData {
    uint8_t  mac[6];
    int      rssi;
    uint32_t lastSeen;
    char     uavId[ODID_ID_SIZE + 1];
    char     opId[ODID_ID_SIZE + 1];
    char     selfId[ODID_STR_SIZE + 1];
    double   lat, lon;
    double   pilotLat, pilotLon;
    int16_t  altMsl, heightAgl, speed, heading;
    int16_t  altBaro, vertSpeed, operatorAlt, areaCeiling, areaFloor;
    uint16_t areaCount, areaRadius, locTimestamp;
    uint8_t  uaType, idType, opIdType, opLocType, classification;
    uint8_t  categoryEu, classEu, heightType, status;
    uint8_t  horizAcc, vertAcc, baroAcc, speedAcc, selfIdType;
    uint32_t lastPushed;
    bool     active;
};

static inline int odidBasicIdIndex(const ODID_UAS_Data* u) {
    for (int i = 0; i < ODID_BASIC_ID_MAX_MESSAGES; i++) {
        if (!u->BasicIDValid[i]) continue;
        const ODID_BasicID_data* b = &u->BasicID[i];
        if (b->UAType == ODID_UATYPE_NONE) continue;
        if (b->IDType == ODID_IDTYPE_NONE) continue;
        for (int j = 0; j < ODID_ID_SIZE; j++) {
            uint8_t c = (uint8_t)b->UASID[j];
            if (c >= 0x20 && c <= 0x7E) return i;
        }
    }
    return -1;
}

static inline bool odidIsPlausible(const ODID_UAS_Data* u) {
    return odidBasicIdIndex(u) >= 0;
}

static inline bool odidFromBleAdv(const uint8_t* payload, int len, ODID_UAS_Data* u) {
    if (!payload || len < 6 + (int)sizeof(ODID_BasicID_encoded)) return false;
    if (payload[1] != 0x16 || payload[2] != 0xFA ||
        payload[3] != 0xFF || payload[4] != 0x0D) return false;
    uint8_t* odid = const_cast<uint8_t*>(&payload[6]);
    int odidLen = len - 6;
    memset(u, 0, sizeof(*u));
    if ((odid[0] & 0xF0) == (ODID_MESSAGETYPE_PACKED << 4)) {
        odid_message_process_pack(u, odid, odidLen);
    } else {
        decodeOpenDroneID(u, odid);
    }
    return true;
}

static inline int odidFromBeacon(const uint8_t* payload, int length, ODID_UAS_Data* u) {
    if (payload[0] != 0x80) return -1;
    int offset = 36;
    while (offset + 1 < length) {
        int typ = payload[offset];
        int len = payload[offset + 1];
        if (typ == 0xdd && offset + 4 < length &&
            ((payload[offset+2]==0x90 && payload[offset+3]==0x3a && payload[offset+4]==0xe6) ||
             (payload[offset+2]==0xfa && payload[offset+3]==0x0b && payload[offset+4]==0xbc))) {
            int j = offset + 7;
            if (j >= length) return 0;
            memset(u, 0, sizeof(*u));
            odid_message_process_pack(u, (uint8_t*)&payload[j], length - j);
            return 1;
        }
        offset += 2 + len;
        if (len == 0) break;
    }
    return -1;
}

static inline int16_t odidRound16(float v) {
    return (int16_t)lroundf(v);
}

static inline void applyOdidData(DroneData* d, const ODID_UAS_Data& UAS_data) {
    const int bi = odidBasicIdIndex(&UAS_data);
    if (bi >= 0) {
        strncpy(d->uavId, (char*)UAS_data.BasicID[bi].UASID, ODID_ID_SIZE);
        d->uaType = (uint8_t)UAS_data.BasicID[bi].UAType;
        d->idType = (uint8_t)UAS_data.BasicID[bi].IDType;
    }
    if (UAS_data.LocationValid) {
        d->lat = UAS_data.Location.Latitude;
        d->lon = UAS_data.Location.Longitude;
        d->altMsl = odidRound16(UAS_data.Location.AltitudeGeo);
        d->altBaro = odidRound16(UAS_data.Location.AltitudeBaro);
        d->heightAgl = odidRound16(UAS_data.Location.Height);
        d->speed = odidRound16(UAS_data.Location.SpeedHorizontal);
        d->vertSpeed = odidRound16(UAS_data.Location.SpeedVertical);
        d->heading = odidRound16(UAS_data.Location.Direction);
        d->heightType = (uint8_t)UAS_data.Location.HeightType;
        d->status = (uint8_t)UAS_data.Location.Status;
        d->horizAcc = (uint8_t)UAS_data.Location.HorizAccuracy;
        d->vertAcc = (uint8_t)UAS_data.Location.VertAccuracy;
        d->baroAcc = (uint8_t)UAS_data.Location.BaroAccuracy;
        d->speedAcc = (uint8_t)UAS_data.Location.SpeedAccuracy;
        const float ts = UAS_data.Location.TimeStamp;
        d->locTimestamp = (ts >= 0.0f && ts <= (float)MAX_TIMESTAMP)
                              ? (uint16_t)lroundf(ts * 10.0f)
                              : (uint16_t)INV_TIMESTAMP;
    }
    if (UAS_data.SelfIDValid) {
        strncpy(d->selfId, (char*)UAS_data.SelfID.Desc, ODID_STR_SIZE);
        d->selfIdType = (uint8_t)UAS_data.SelfID.DescType;
    }
    if (UAS_data.SystemValid) {
        d->pilotLat = UAS_data.System.OperatorLatitude;
        d->pilotLon = UAS_data.System.OperatorLongitude;
        d->operatorAlt = odidRound16(UAS_data.System.OperatorAltitudeGeo);
        d->areaCount = UAS_data.System.AreaCount;
        d->areaRadius = UAS_data.System.AreaRadius;
        d->areaCeiling = odidRound16(UAS_data.System.AreaCeiling);
        d->areaFloor = odidRound16(UAS_data.System.AreaFloor);
        d->opLocType = (uint8_t)UAS_data.System.OperatorLocationType;
        d->classification = (uint8_t)UAS_data.System.ClassificationType;
        d->categoryEu = (uint8_t)UAS_data.System.CategoryEU;
        d->classEu = (uint8_t)UAS_data.System.ClassEU;
    }
    if (UAS_data.OperatorIDValid) {
        strncpy(d->opId, (char*)UAS_data.OperatorID.OperatorId, ODID_ID_SIZE);
        d->opIdType = (uint8_t)UAS_data.OperatorID.OperatorIdType;
    }
}
