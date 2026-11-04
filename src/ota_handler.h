#ifndef OTA_HANDLER_H
#define OTA_HANDLER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <esp_partition.h>

#ifdef __cplusplus
extern "C" {
#endif

bool otaSigVerifyPartition(const esp_partition_t* partition, uint32_t totalLen);

void otaInit(void);

// Feed bytes from dfuData WRITE callback. Returns false on framing error.
bool otaOnDataWrite(const uint8_t* data, size_t len);

// Returns true if OTA transfer in progress.
bool otaIsActive(void);

// Set the notify callback used to report progress / status back on dfuControl.
typedef void (*OtaNotifyFn)(const uint8_t* data, size_t len);
void otaSetNotifyCallback(OtaNotifyFn fn);

void otaTrialTick(void);

#ifdef __cplusplus
}
#endif

#endif // OTA_HANDLER_H
