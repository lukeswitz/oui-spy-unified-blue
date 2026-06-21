#ifdef OUISPY_RID_TARGET
#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include "opendroneid.h"

static ODID_UAS_Data uas;
static uint8_t sendCounter = 0;

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println("[RID-TARGET] Remote-ID drone NAN beacon TX on ch6");

    WiFi.mode(WIFI_MODE_STA);
    esp_wifi_set_promiscuous(true);
    esp_wifi_set_channel(6, WIFI_SECOND_CHAN_NONE);

    memset(&uas, 0, sizeof(uas));
    uas.BasicID[0].UAType = ODID_UATYPE_HELICOPTER_OR_MULTIROTOR;
    uas.BasicID[0].IDType = ODID_IDTYPE_SERIAL_NUMBER;
    strncpy(uas.BasicID[0].UASID, "TESTDRONE1234567890", ODID_ID_SIZE);
    uas.BasicIDValid[0] = 1;
    uas.Location.Status = ODID_STATUS_AIRBORNE;
    uas.Location.Direction = 90.0f;
    uas.Location.SpeedHorizontal = 5.0f;
    uas.Location.Latitude = 39.7392;
    uas.Location.Longitude = -104.9903;
    uas.Location.AltitudeGeo = 100.0f;
    uas.LocationValid = 1;

    Serial.println("[RID-TARGET] UAS_Data built (serial TESTDRONE1234567890)");
}

void loop() {
    uint8_t buf[256];
    char mac[6] = {(char)0x90, (char)0x3a, (char)0xe6, 0x01, 0x02, 0x03};
    int len = odid_wifi_build_message_pack_nan_action_frame(&uas, mac, sendCounter++, buf, sizeof(buf));
    if (len > 0) {
        esp_wifi_80211_tx(WIFI_IF_STA, buf, len, false);
    } else {
        Serial.printf("[RID-TARGET] build failed %d\n", len);
    }
    static uint32_t lastLog = 0;
    if (millis() - lastLog > 5000) {
        lastLog = millis();
        Serial.printf("[RID-TARGET] alive, sent %u frames (len=%d)\n", sendCounter, len);
    }
    delay(300);
}
#endif
