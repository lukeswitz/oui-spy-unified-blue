#include "wifi_ota_handler.h"
#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <esp_wifi.h>
#include <esp_ota_ops.h>
#include <esp_system.h>
#include <esp_log.h>
#include <esp_sntp.h>
#include <time.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>

#define NS              "ouispy-wifi"
#define K_SSID          "ssid"
#define K_PASS          "pass"
#define JOIN_TIMEOUT_MS 20000
#define SNTP_WAIT_MS    15000
#define OP_NOTIFY       0x06
#define OTA_TASK_STACK  16384
#define OTA_URL_MAX     512

namespace {

WifiOtaNotifyFn g_notifyFn = nullptr;
volatile bool   g_staConnected = false;
char            g_staSsid[33] = {0};
uint32_t        g_staIp = 0;
bool            g_sntpStarted = false;

TaskHandle_t    g_otaTask = nullptr;
SemaphoreHandle_t g_otaLock = nullptr;
char            g_otaUrl[OTA_URL_MAX] = {0};

void notify(WifiOtaStatus status, uint32_t progress) {
    if (!g_notifyFn) return;
    uint8_t buf[6];
    buf[0] = OP_NOTIFY;
    buf[1] = (uint8_t)status;
    buf[2] = (uint8_t)(progress & 0xFF);
    buf[3] = (uint8_t)((progress >> 8) & 0xFF);
    buf[4] = (uint8_t)((progress >> 16) & 0xFF);
    buf[5] = (uint8_t)((progress >> 24) & 0xFF);
    g_notifyFn(buf, 6);
}

void wifiEvent(WiFiEvent_t event, WiFiEventInfo_t info) {
    switch (event) {
        case ARDUINO_EVENT_WIFI_STA_GOT_IP:
            g_staConnected = true;
            g_staIp = (uint32_t)WiFi.localIP();
            Serial.printf("[WIFI] STA up IP=%s RSSI=%d\n",
                          WiFi.localIP().toString().c_str(), WiFi.RSSI());
            break;
        case ARDUINO_EVENT_WIFI_STA_DISCONNECTED:
            if (g_staConnected) Serial.println("[WIFI] STA dropped, reconnecting");
            g_staConnected = false;
            g_staIp = 0;
            WiFi.reconnect();
            break;
        default:
            break;
    }
}

void startSntpOnce(void) {
    if (g_sntpStarted) return;
    g_sntpStarted = true;
    sntp_setoperatingmode(SNTP_OPMODE_POLL);
    sntp_setservername(0, (char*)"pool.ntp.org");
    sntp_setservername(1, (char*)"time.google.com");
    sntp_init();
    Serial.println("[WIFI] SNTP started");
}

bool waitForTime(uint32_t timeoutMs) {
    uint32_t start = millis();
    time_t now = 0;
    while (millis() - start < timeoutMs) {
        time(&now);
        if (now > 1700000000) {
            struct tm tmInfo;
            gmtime_r(&now, &tmInfo);
            Serial.printf("[WIFI] Time %04d-%02d-%02d %02d:%02d:%02d UTC\n",
                          tmInfo.tm_year + 1900, tmInfo.tm_mon + 1, tmInfo.tm_mday,
                          tmInfo.tm_hour, tmInfo.tm_min, tmInfo.tm_sec);
            return true;
        }
        delay(200);
    }
    Serial.println("[WIFI] SNTP timeout");
    return false;
}

bool joinStation(const char* ssid, const char* pass) {
    Serial.printf("[WIFI] begin('%s')\n", ssid);
    WiFi.onEvent(wifiEvent);
    WiFi.mode(WIFI_STA);
    WiFi.begin(ssid, pass);
    uint32_t start = millis();
    while (WiFi.status() != WL_CONNECTED) {
        if (millis() - start > JOIN_TIMEOUT_MS) {
            Serial.printf("[WIFI] join timeout status=%d\n", WiFi.status());
            return false;
        }
        delay(250);
    }
    strncpy(g_staSsid, ssid, sizeof(g_staSsid) - 1);
    g_staSsid[sizeof(g_staSsid) - 1] = '\0';
    g_staConnected = true;
    g_staIp = (uint32_t)WiFi.localIP();
    Serial.printf("[WIFI] joined IP=%s RSSI=%d\n",
                  WiFi.localIP().toString().c_str(), WiFi.RSSI());
    esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
    startSntpOnce();
    return true;
}

void onProgress(int sent, int total) {
    static uint32_t lastNotify = 0;
    if ((uint32_t)sent - lastNotify > 16384 || sent == total) {
        Serial.printf("[WIFI-OTA] %d/%d\n", sent, total);
        notify(WIFI_OTA_DOWNLOADING, (uint32_t)sent);
        lastNotify = sent;
    }
}

bool runOta(const char* url) {
    if (!wifiStaIsConnected()) {
        notify(WIFI_OTA_CONNECTING, 0);
        if (!wifiStaConnect()) {
            notify(WIFI_OTA_ERR_CONNECT, 0);
            return false;
        }
    }
    notify(WIFI_OTA_CONNECTED, 0);

    startSntpOnce();
    waitForTime(SNTP_WAIT_MS);

    Serial.printf("[WIFI-OTA] download %s\n", url);
    notify(WIFI_OTA_DOWNLOADING, 0);

    WiFiClientSecure client;
    client.setInsecure();
    client.setTimeout(30);

    httpUpdate.rebootOnUpdate(false);
    httpUpdate.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
    httpUpdate.onProgress(onProgress);

    t_httpUpdate_return ret = httpUpdate.update(client, url);
    switch (ret) {
        case HTTP_UPDATE_FAILED:
            Serial.printf("[WIFI-OTA] FAILED %d: %s\n",
                          httpUpdate.getLastError(),
                          httpUpdate.getLastErrorString().c_str());
            notify(WIFI_OTA_ERR_HTTP, 0);
            return false;
        case HTTP_UPDATE_NO_UPDATES:
            Serial.println("[WIFI-OTA] no update returned");
            notify(WIFI_OTA_ERR_HTTP, 0);
            return false;
        case HTTP_UPDATE_OK:
            Serial.println("[WIFI-OTA] OK, rebooting into new image");
            notify(WIFI_OTA_REBOOTING, 0);
            delay(500);
            esp_restart();
            return true;
    }
    return false;
}

void otaTaskLoop(void* arg) {
    (void)arg;
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        char url[OTA_URL_MAX];
        xSemaphoreTake(g_otaLock, portMAX_DELAY);
        strncpy(url, g_otaUrl, sizeof(url) - 1);
        url[sizeof(url) - 1] = '\0';
        xSemaphoreGive(g_otaLock);
        if (url[0] == '\0') continue;
        runOta(url);
    }
}

void ensureOtaTask(void) {
    if (g_otaTask) return;
    g_otaLock = xSemaphoreCreateMutex();
    xTaskCreatePinnedToCore(otaTaskLoop, "wifi_ota", OTA_TASK_STACK, NULL, 5, &g_otaTask, 1);
}

} // namespace

extern "C" void wifiOtaSetNotifyCallback(WifiOtaNotifyFn fn) {
    g_notifyFn = fn;
}

extern "C" bool wifiOtaSaveCreds(const char* ssid, const char* pass) {
    if (!ssid || ssid[0] == '\0') return false;
    Preferences p;
    if (!p.begin(NS, false)) return false;
    p.putString(K_SSID, ssid);
    p.putString(K_PASS, pass ? pass : "");
    p.end();
    Serial.printf("[WIFI] saved '%s'\n", ssid);
    return true;
}

extern "C" bool wifiOtaLoadCreds(char* ssidOut, size_t ssidLen,
                                  char* passOut, size_t passLen) {
    Preferences p;
    if (!p.begin(NS, true)) return false;
    String ssid = p.getString(K_SSID, "");
    String pass = p.getString(K_PASS, "");
    p.end();
    if (ssid.length() == 0) return false;
    strncpy(ssidOut, ssid.c_str(), ssidLen - 1);
    ssidOut[ssidLen - 1] = '\0';
    strncpy(passOut, pass.c_str(), passLen - 1);
    passOut[passLen - 1] = '\0';
    return true;
}

extern "C" bool wifiOtaWipeCreds(void) {
    Preferences p;
    if (!p.begin(NS, false)) return false;
    p.remove(K_SSID);
    p.remove(K_PASS);
    p.end();
    Serial.println("[WIFI] creds wiped");
    return true;
}

extern "C" void wifiStaDisconnect(void) {
    if (g_staConnected || WiFi.status() == WL_CONNECTED) {
        Serial.println("[WIFI] STA disconnect");
        WiFi.disconnect(true, true);
        WiFi.mode(WIFI_OFF);
        g_staConnected = false;
        g_staIp = 0;
        g_staSsid[0] = '\0';
    }
}

extern "C" bool wifiStaConnect(void) {
    char ssid[33], pass[65];
    if (!wifiOtaLoadCreds(ssid, sizeof(ssid), pass, sizeof(pass))) return false;
    if (g_staConnected && strcmp(ssid, g_staSsid) == 0) return true;
    bool ok = joinStation(ssid, pass);
    if (ok) ensureOtaTask();
    return ok;
}

extern "C" bool wifiStaIsConnected(void) {
    return g_staConnected && WiFi.status() == WL_CONNECTED;
}

extern "C" void wifiStaGetSsid(char* out, size_t outLen) {
    if (!out || outLen == 0) return;
    strncpy(out, g_staSsid, outLen - 1);
    out[outLen - 1] = '\0';
}

extern "C" uint32_t wifiStaGetIp(void) {
    return g_staIp;
}

extern "C" int8_t wifiStaGetRssi(void) {
    return g_staConnected ? (int8_t)WiFi.RSSI() : 0;
}

extern "C" bool wifiOtaDispatch(const char* url) {
    if (!url || url[0] == '\0') return false;
    ensureOtaTask();
    if (!g_otaTask) return false;
    xSemaphoreTake(g_otaLock, portMAX_DELAY);
    strncpy(g_otaUrl, url, sizeof(g_otaUrl) - 1);
    g_otaUrl[sizeof(g_otaUrl) - 1] = '\0';
    xSemaphoreGive(g_otaLock);
    xTaskNotifyGive(g_otaTask);
    return true;
}
