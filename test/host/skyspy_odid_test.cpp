#include <cstdio>
#include <cstring>
#include "../../src/engines/skyspy_odid.h"
#include "vectors.h"

static int failures = 0;

#define CHECK(cond)                                                                 \
    do {                                                                            \
        if (!(cond)) {                                                              \
            std::printf("FAIL %s:%d %s\n", __FILE__, __LINE__, #cond);              \
            failures++;                                                             \
        }                                                                           \
    } while (0)

static void checkDroneA(const char* via, const ODID_UAS_Data& u) {
    std::printf("-- %s drone A\n", via);
    CHECK(odidBasicIdIndex(&u) == 0);
    DroneData d = {};
    applyOdidData(&d, u);
    CHECK(std::strcmp(d.uavId, "TESTDRONE1234567890") == 0);
    CHECK(d.uaType == ODID_UATYPE_HELICOPTER_OR_MULTIROTOR);
    CHECK(d.idType == ODID_IDTYPE_SERIAL_NUMBER);
    CHECK(d.altMsl == 101);
    CHECK(d.heightAgl == -1000);
    CHECK(d.altBaro == -1000);
    CHECK(d.speed == 6);
    CHECK(d.vertSpeed == 63);
    CHECK(d.heading == 90);
    CHECK(d.locTimestamp == 0xFFFF);
    CHECK(std::strcmp(d.opId, "OPERATOR01") == 0);
    CHECK(std::strcmp(d.selfId, "host test") == 0);
    CHECK(d.lat > 51.47 && d.lat < 51.48);
    CHECK(d.pilotLat > 51.47 && d.pilotLat < 51.48);
    std::printf("   uav=%s alt=%d agl=%d baro=%d spd=%d vspd=%d hdg=%d ts=%u op=%s\n", d.uavId, d.altMsl,
                d.heightAgl, d.altBaro, d.speed, d.vertSpeed, d.heading, d.locTimestamp, d.opId);
}

static void checkDroneB(const char* via, const ODID_UAS_Data& u) {
    std::printf("-- %s drone B (first Basic ID empty, ID in the second)\n", via);
    CHECK(u.BasicIDValid[0] && u.BasicIDValid[1]);
    CHECK(u.BasicID[0].UASID[0] == '\0');
    CHECK(odidBasicIdIndex(&u) == 1);
    CHECK(odidIsPlausible(&u));
    DroneData d = {};
    applyOdidData(&d, u);
    CHECK(std::strcmp(d.uavId, "CAAREG0001") == 0);
    CHECK(d.idType == ODID_IDTYPE_CAA_REGISTRATION_ID);
    CHECK(d.uaType == ODID_UATYPE_HELICOPTER_OR_MULTIROTOR);
    std::printf("   uav=%s basicIdIndex=%d\n", d.uavId, odidBasicIdIndex(&u));
}

static ODID_UAS_Data viaBle(const uint8_t* adv, int len) {
    ODID_UAS_Data u;
    CHECK(odidFromBleAdv(adv, len, &u));
    return u;
}

static ODID_UAS_Data viaBeacon(const uint8_t* frame, int len) {
    ODID_UAS_Data u;
    CHECK(odidFromBeacon(frame, len, &u) == 1);
    return u;
}

static ODID_UAS_Data viaNan(ODID_UAS_Data src) {
    uint8_t buf[1024];
    char mac[6] = {0x02, 0, 0, 0, 0, 0x07};
    int len = odid_wifi_build_message_pack_nan_action_frame(&src, mac, 1, buf, sizeof(buf));
    CHECK(len > 0);
    ODID_UAS_Data u;
    std::memset(&u, 0, sizeof(u));
    char rxMac[6] = {0};
    CHECK(odid_wifi_receive_message_pack_nan_action_frame(&u, rxMac, buf, len) == 0);
    return u;
}

int main() {
    ODID_UAS_Data a = viaBle(BLE_A, sizeof(BLE_A));
    checkDroneA("BLE 4 legacy adv", a);
    checkDroneA("Wi-Fi beacon", viaBeacon(BEACON_A, sizeof(BEACON_A)));
    checkDroneA("Wi-Fi NAN", viaNan(a));

    ODID_UAS_Data b = viaBle(BLE_B, sizeof(BLE_B));
    checkDroneB("BLE 4 legacy adv", b);
    checkDroneB("Wi-Fi beacon", viaBeacon(BEACON_B, sizeof(BEACON_B)));
    checkDroneB("Wi-Fi NAN", viaNan(b));

    std::printf(failures ? "FAILED %d\n" : "ALL PASS\n", failures);
    return failures ? 1 : 0;
}
