#include "wifi_ota_handler.h"
#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <HTTPUpdate.h>
#include <esp_wifi.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>
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
#define K_STA_ENABLED   "sta_en"
#define K_OTA_URL       "ota_url"
#define K_OTA_PEND      "ota_pend"
#define K_OTA_MODE      "ota_mode"
#define K_RELAY_PEND    "relay_pend"
#define K_RELAY_SIZE    "relay_sz"
#define K_RELAY_CRC     "relay_crc"
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
    WiFi.persistent(false);
    WiFi.setAutoReconnect(false);
    esp_wifi_set_storage(WIFI_STORAGE_RAM);
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

extern "C" bool wifiStaIsEnabled(void) {
    Preferences p;
    if (!p.begin(NS, true)) return false;
    bool en = p.getBool(K_STA_ENABLED, false);
    p.end();
    return en;
}

extern "C" bool wifiStaSetEnabled(bool en) {
    Preferences p;
    if (!p.begin(NS, false)) return false;
    p.putBool(K_STA_ENABLED, en);
    p.end();
    Serial.printf("[WIFI] sta_enabled=%d\n", en ? 1 : 0);
    if (!en) wifiStaDisconnect();
    return true;
}

extern "C" bool wifiStaConnect(void) {
    if (!wifiStaIsEnabled()) {
        Serial.println("[WIFI] STA disabled in settings; not connecting");
        return false;
    }
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

extern "C" bool wifiOtaStageToPartition(const char* url, uint32_t* outSize, uint32_t* outCrc) {
    if (!url || url[0] == '\0') return false;
    if (!wifiStaIsConnected() && !wifiStaConnect()) {
        Serial.println("[STAGE] no WiFi"); return false;
    }
    const esp_partition_t* part = esp_ota_get_next_update_partition(NULL);
    if (!part) { Serial.println("[STAGE] no scratch partition"); return false; }

    const size_t SECT = 4096;
    uint8_t* sect = (uint8_t*)malloc(SECT);
    if (!sect) { Serial.println("[STAGE] no heap for stage buffer"); return false; }

    bool secure = (strncmp(url, "https", 5) == 0);
    WiFiClientSecure sclient;
    WiFiClient pclient;
    WiFiClient* client;
    if (secure) { sclient.setInsecure(); sclient.setTimeout(30); client = &sclient; }
    else { pclient.setTimeout(30); client = &pclient; }
    HTTPClient https;
    https.setFollowRedirects(HTTPC_FORCE_FOLLOW_REDIRECTS);
    bool ok = false;
    uint32_t written = 0, crc = 0xFFFFFFFF;

    if (!https.begin(*client, url)) { Serial.println("[STAGE] begin fail"); goto cleanup; }
    {
        int code = https.GET();
        if (code != HTTP_CODE_OK) { Serial.printf("[STAGE] HTTP %d\n", code); goto cleanup; }
        int total = https.getSize();
        if (total <= 0 || (uint32_t)total > (int)part->size) {
            Serial.printf("[STAGE] bad size %d\n", total); goto cleanup;
        }
        uint32_t eraseLen = ((uint32_t)total + 4095u) & ~4095u;
        if (esp_partition_erase_range(part, 0, eraseLen) != ESP_OK) {
            Serial.println("[STAGE] erase fail"); goto cleanup;
        }
        WiFiClient* st = https.getStreamPtr();
        uint32_t sfill = 0, lastLog = 0, t0 = millis();
        uint8_t rd[512];
        bool failed = false;
        while (written + sfill < (uint32_t)total && !failed) {
            if (millis() - t0 > 60000) { Serial.println("[STAGE] timeout"); failed = true; break; }
            size_t avail = st->available();
            if (!avail) { if (!https.connected() && st->available() == 0) break; delay(2); continue; }
            int n = st->readBytes(rd, avail > sizeof(rd) ? sizeof(rd) : avail);
            if (n <= 0) continue;
            t0 = millis();
            for (int i = 0; i < n; i++) {
                sect[sfill++] = rd[i];
                crc ^= rd[i];
                for (int j = 0; j < 8; j++) crc = (crc >> 1) ^ (0xEDB88320u & (uint32_t)(-(int32_t)(crc & 1)));
                if (sfill == SECT) {
                    if (esp_partition_write(part, written, sect, sfill) != ESP_OK) {
                        Serial.println("[STAGE] write fail"); failed = true; break;
                    }
                    written += sfill; sfill = 0;
                    if (written - lastLog >= 65536) { lastLog = written; Serial.printf("[STAGE] %u/%d\n", (unsigned)written, total); }
                }
            }
        }
        if (!failed && sfill > 0) {
            uint32_t wlen = (sfill + 3u) & ~3u;
            for (uint32_t k = sfill; k < wlen; k++) sect[k] = 0xFF;
            if (esp_partition_write(part, written, sect, wlen) != ESP_OK) {
                Serial.println("[STAGE] tail write fail"); failed = true;
            } else {
                written += sfill;
            }
        }
        if (!failed && written == (uint32_t)total) ok = true;
        else if (!failed) Serial.printf("[STAGE] short %u/%d\n", (unsigned)written, total);
    }
cleanup:
    https.end();
    free(sect);
    if (ok) {
        *outSize = written;
        *outCrc = crc ^ 0xFFFFFFFF;
        Serial.printf("[STAGE] done %u bytes crc=0x%08X -> %s\n", (unsigned)written, (unsigned)(*outCrc), part->label);
    }
    return ok;
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

static bool savePending(const char* url, uint8_t mode) {
    if (!url || url[0] == '\0') return false;
    Preferences p;
    if (!p.begin(NS, false)) return false;
    p.putString(K_OTA_URL, url);
    p.putBool(K_OTA_PEND, true);
    p.putUChar(K_OTA_MODE, mode);
    p.end();
    Serial.printf("[WIFI-OTA] pending saved (mode=%u): %s\n", mode, url);
    return true;
}

extern "C" bool wifiOtaSetPending(const char* url) { return savePending(url, 0); }
extern "C" bool wifiOtaSetFleetPending(const char* url) { return savePending(url, 1); }

extern "C" bool wifiOtaHasPending(void) {
    Preferences p;
    if (!p.begin(NS, true)) return false;
    bool pend = p.getBool(K_OTA_PEND, false);
    p.end();
    return pend;
}

extern "C" bool wifiOtaGetRelayPending(uint32_t* size, uint32_t* crc) {
    Preferences p;
    if (!p.begin(NS, false)) return false;
    bool pend = p.getBool(K_RELAY_PEND, false);
    uint32_t sz = p.getULong(K_RELAY_SIZE, 0);
    uint32_t c = p.getULong(K_RELAY_CRC, 0);
    if (pend) p.putBool(K_RELAY_PEND, false);
    p.end();
    if (!pend) return false;
    if (size) *size = sz;
    if (crc) *crc = c;
    return true;
}

extern "C" bool wifiOtaRunPendingBlocking(void) {
    char url[OTA_URL_MAX] = {0};
    uint8_t mode = 0;
    {
        Preferences p;
        if (!p.begin(NS, false)) return false;
        String u = p.getString(K_OTA_URL, "");
        mode = p.getUChar(K_OTA_MODE, 0);
        p.putBool(K_OTA_PEND, false);
        p.remove(K_OTA_URL);
        p.end();
        if (u.length() == 0) return false;
        strncpy(url, u.c_str(), sizeof(url) - 1);
    }

    char ssid[33], pass[65];
    if (!wifiOtaLoadCreds(ssid, sizeof(ssid), pass, sizeof(pass))) {
        Serial.println("[WIFI-OTA] OTA mode: no WiFi creds saved");
        return false;
    }
    Serial.printf("[WIFI-OTA] OTA mode (mode=%u): joining '%s'\n", mode, ssid);
    if (!joinStation(ssid, pass)) {
        Serial.println("[WIFI-OTA] OTA mode: join failed");
        return false;
    }

    if (mode == 1) {
        uint32_t sz = 0, crc = 0;
        if (wifiOtaStageToPartition(url, &sz, &crc)) {
            Preferences p;
            if (p.begin(NS, false)) {
                p.putBool(K_RELAY_PEND, true);
                p.putULong(K_RELAY_SIZE, sz);
                p.putULong(K_RELAY_CRC, crc);
                p.end();
            }
            Serial.printf("[WIFI-OTA] fleet staged %u bytes -> reboot to relay\n", (unsigned)sz);
            delay(300);
            esp_restart();
        }
        Serial.println("[WIFI-OTA] fleet stage failed");
        return false;
    }

    runOta(url);
    return false;
}
