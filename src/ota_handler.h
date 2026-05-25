/**
 * OTA Handler — streaming firmware update over BLE.
 *
 * Wire protocol matches companion/lib/core/ble/chunked_transfer.dart:
 *   START:  opcode(0x01)[1] + total_length[4] + crc32[4]   = 9 bytes
 *   DATA:   opcode(0x02)[1] + seq_num[2] + payload[N]      = 3+N bytes
 *   COMMIT: opcode(0x03)[1]                                = 1 byte
 *   ABORT:  opcode(0x04)[1]                                = 1 byte
 *   ACK:    opcode(0x05)[1] + seq_num[2] + status[1]       = 4 bytes (notify)
 *
 * Streaming: chunks fed directly to esp_ota_write() — no full-image buffer
 * (firmware can be larger than free heap). CRC32 (IEEE 802.3) computed
 * incrementally and verified at COMMIT before esp_ota_set_boot_partition().
 *
 * Status codes (notify on dfuControl):
 *   0x00 = OK / progress (seq_num = bytes received >> 10 = KB count)
 *   0x01 = bad opcode
 *   0x02 = no OTA partition
 *   0x03 = esp_ota_begin failed
 *   0x04 = esp_ota_write failed
 *   0x05 = CRC mismatch
 *   0x06 = esp_ota_end failed
 *   0x07 = esp_ota_set_boot_partition failed
 *   0x08 = aborted by host
 *   0xFF = COMMIT OK — device will reboot in 500ms
 */
#ifndef OTA_HANDLER_H
#define OTA_HANDLER_H

#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

void otaInit(void);

// Feed bytes from dfuData WRITE callback. Returns false on framing error.
bool otaOnDataWrite(const uint8_t* data, size_t len);

// Returns true if OTA transfer in progress.
bool otaIsActive(void);

// Set the notify callback used to report progress / status back on dfuControl.
typedef void (*OtaNotifyFn)(const uint8_t* data, size_t len);
void otaSetNotifyCallback(OtaNotifyFn fn);

#ifdef __cplusplus
}
#endif

#endif // OTA_HANDLER_H
