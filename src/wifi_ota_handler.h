#ifndef WIFI_OTA_HANDLER_H
#define WIFI_OTA_HANDLER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    WIFI_OTA_IDLE          = 0,
    WIFI_OTA_CONNECTING    = 1,
    WIFI_OTA_CONNECTED     = 2,
    WIFI_OTA_DOWNLOADING   = 3,
    WIFI_OTA_REBOOTING     = 4,
    WIFI_OTA_ERR_NO_CREDS  = 0x80,
    WIFI_OTA_ERR_CONNECT   = 0x81,
    WIFI_OTA_ERR_HTTP      = 0x82,
    WIFI_OTA_ERR_VALIDATE  = 0x83,
    WIFI_OTA_ERR_WRITE     = 0x84,
} WifiOtaStatus;

typedef void (*WifiOtaNotifyFn)(const uint8_t* data, size_t len);
void wifiOtaSetNotifyCallback(WifiOtaNotifyFn fn);

bool wifiOtaSaveCreds(const char* ssid, const char* pass);
bool wifiOtaLoadCreds(char* ssidOut, size_t ssidLen, char* passOut, size_t passLen);
bool wifiOtaWipeCreds(void);
void wifiStaDisconnect(void);
void wifiStaReleaseForScan(void);

bool wifiStaConnect(void);
void wifiStaConnectAsync(void);
bool wifiStaIsConnected(void);
bool wifiStaIsEnabled(void);
bool wifiStaSetEnabled(bool enabled);
void wifiStaGetSsid(char* out, size_t outLen);
uint32_t wifiStaGetIp(void);
int8_t wifiStaGetRssi(void);

bool wifiOtaDispatch(const char* url);

bool wifiOtaSetPending(const char* url);
bool wifiOtaHasPending(void);
bool wifiOtaRunPendingBlocking(void);
bool wifiOtaStageToPartition(const char* url, uint32_t* outSize, uint32_t* outCrc);
bool wifiOtaSetFleetPending(const char* url);
bool wifiOtaGetRelayPending(uint32_t* size, uint32_t* crc);

#ifdef __cplusplus
}
#endif

#endif
