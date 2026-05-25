#include "ota_handler.h"
#include <Arduino.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>
#include <esp_system.h>

#define OP_START  0x01
#define OP_DATA   0x02
#define OP_COMMIT 0x03
#define OP_ABORT  0x04
#define OP_ACK    0x05

namespace {

bool                    g_active = false;
const esp_partition_t*  g_partition = nullptr;
esp_ota_handle_t        g_handle = 0;
uint32_t                g_expectedLength = 0;
uint32_t                g_expectedCrc = 0;
uint32_t                g_bytesReceived = 0;
uint32_t                g_runningCrc = 0xFFFFFFFF;
uint16_t                g_expectedSeq = 0;
uint32_t                g_lastProgressKb = 0;

OtaNotifyFn             g_notifyFn = nullptr;

void notifyStatus(uint16_t seq, uint8_t status) {
    if (!g_notifyFn) return;
    uint8_t buf[4];
    buf[0] = OP_ACK;
    buf[1] = (uint8_t)(seq & 0xFF);
    buf[2] = (uint8_t)((seq >> 8) & 0xFF);
    buf[3] = status;
    g_notifyFn(buf, 4);
}

void crc32Update(const uint8_t* data, size_t len) {
    for (size_t i = 0; i < len; i++) {
        g_runningCrc ^= data[i];
        for (int j = 0; j < 8; j++) {
            if (g_runningCrc & 1) {
                g_runningCrc = (g_runningCrc >> 1) ^ 0xEDB88320;
            } else {
                g_runningCrc >>= 1;
            }
        }
    }
}

void resetState() {
    g_active = false;
    g_partition = nullptr;
    g_handle = 0;
    g_expectedLength = 0;
    g_expectedCrc = 0;
    g_bytesReceived = 0;
    g_runningCrc = 0xFFFFFFFF;
    g_expectedSeq = 0;
    g_lastProgressKb = 0;
}

bool handleStart(const uint8_t* data, size_t len) {
    if (len < 9) return false;
    if (g_active) {
        // Already running — silently abort previous, start new
        if (g_handle) esp_ota_abort(g_handle);
        resetState();
    }

    g_expectedLength  = (uint32_t)data[1]
                      | ((uint32_t)data[2] << 8)
                      | ((uint32_t)data[3] << 16)
                      | ((uint32_t)data[4] << 24);
    g_expectedCrc     = (uint32_t)data[5]
                      | ((uint32_t)data[6] << 8)
                      | ((uint32_t)data[7] << 16)
                      | ((uint32_t)data[8] << 24);

    g_partition = esp_ota_get_next_update_partition(NULL);
    if (!g_partition) {
        Serial.println("[OTA] No update partition available");
        notifyStatus(0, 0x02);
        return false;
    }

    if (g_expectedLength > g_partition->size) {
        Serial.printf("[OTA] Image too large: %u > %u\n",
                      (unsigned)g_expectedLength, (unsigned)g_partition->size);
        notifyStatus(0, 0x02);
        return false;
    }

    Serial.printf("[OTA] START len=%u crc=0x%08X target=%s\n",
                  (unsigned)g_expectedLength, (unsigned)g_expectedCrc,
                  g_partition->label);

    esp_err_t err = esp_ota_begin(g_partition, g_expectedLength, &g_handle);
    if (err != ESP_OK) {
        Serial.printf("[OTA] esp_ota_begin failed: %s\n", esp_err_to_name(err));
        notifyStatus(0, 0x03);
        resetState();
        return false;
    }

    g_active = true;
    g_runningCrc = 0xFFFFFFFF;
    g_bytesReceived = 0;
    g_expectedSeq = 0;
    g_lastProgressKb = 0;
    notifyStatus(0, 0x00);
    return true;
}

bool handleData(const uint8_t* data, size_t len) {
    if (!g_active || len < 3) return false;

    uint16_t seq = (uint16_t)data[1] | ((uint16_t)data[2] << 8);
    const uint8_t* payload = data + 3;
    size_t payloadLen = len - 3;

    if (seq != g_expectedSeq) {
        Serial.printf("[OTA] Seq mismatch: got %u expected %u\n",
                      (unsigned)seq, (unsigned)g_expectedSeq);
        // Tolerate — BLE is reliable per-write. But log it.
    }
    g_expectedSeq = seq + 1;

    if (g_bytesReceived + payloadLen > g_expectedLength) {
        Serial.printf("[OTA] Overflow: would exceed expected length\n");
        esp_ota_abort(g_handle);
        notifyStatus(seq, 0x04);
        resetState();
        return false;
    }

    esp_err_t err = esp_ota_write(g_handle, payload, payloadLen);
    if (err != ESP_OK) {
        Serial.printf("[OTA] esp_ota_write failed: %s\n", esp_err_to_name(err));
        esp_ota_abort(g_handle);
        notifyStatus(seq, 0x04);
        resetState();
        return false;
    }

    crc32Update(payload, payloadLen);
    g_bytesReceived += payloadLen;

    // Throttled progress (every 16 KB)
    uint32_t kb = g_bytesReceived >> 10;
    if (kb >= g_lastProgressKb + 16) {
        g_lastProgressKb = kb;
        notifyStatus((uint16_t)kb, 0x00);
    }
    return true;
}

bool handleCommit() {
    if (!g_active) return false;

    if (g_bytesReceived != g_expectedLength) {
        Serial.printf("[OTA] Length mismatch: got %u expected %u\n",
                      (unsigned)g_bytesReceived, (unsigned)g_expectedLength);
        esp_ota_abort(g_handle);
        notifyStatus(0, 0x05);
        resetState();
        return false;
    }

    uint32_t computedCrc = g_runningCrc ^ 0xFFFFFFFF;
    if (computedCrc != g_expectedCrc) {
        Serial.printf("[OTA] CRC mismatch: got 0x%08X expected 0x%08X\n",
                      (unsigned)computedCrc, (unsigned)g_expectedCrc);
        esp_ota_abort(g_handle);
        notifyStatus(0, 0x05);
        resetState();
        return false;
    }

    esp_err_t err = esp_ota_end(g_handle);
    if (err != ESP_OK) {
        Serial.printf("[OTA] esp_ota_end failed: %s\n", esp_err_to_name(err));
        notifyStatus(0, 0x06);
        resetState();
        return false;
    }

    err = esp_ota_set_boot_partition(g_partition);
    if (err != ESP_OK) {
        Serial.printf("[OTA] esp_ota_set_boot_partition failed: %s\n",
                      esp_err_to_name(err));
        notifyStatus(0, 0x07);
        resetState();
        return false;
    }

    Serial.printf("[OTA] COMMIT OK — rebooting into %s\n", g_partition->label);
    notifyStatus(0, 0xFF);
    resetState();
    delay(500);
    esp_restart();
    return true;
}

void handleAbort() {
    if (g_active && g_handle) {
        esp_ota_abort(g_handle);
    }
    notifyStatus(0, 0x08);
    Serial.println("[OTA] Aborted by host");
    resetState();
}

} // namespace

extern "C" void otaInit(void) {
    resetState();
    const esp_partition_t* running = esp_ota_get_running_partition();
    const esp_partition_t* boot    = esp_ota_get_boot_partition();
    if (running && boot) {
        Serial.printf("[OTA] Running from %s, boot=%s\n",
                      running->label, boot->label);
    }

    // Rollback validation state: if previous OTA boot is pending validation,
    // log it. Companion confirms via SYS_CMD_CONFIRM_OTA after a successful
    // GATT handshake. Until then, a reboot would auto-revert.
    esp_ota_img_states_t state;
    if (running && esp_ota_get_state_partition(running, &state) == ESP_OK) {
        if (state == ESP_OTA_IMG_PENDING_VERIFY) {
            Serial.println("[OTA] Image PENDING_VERIFY — awaiting confirm from app");
        } else if (state == ESP_OTA_IMG_VALID) {
            Serial.println("[OTA] Image VALID");
        }
    }
}

extern "C" bool otaOnDataWrite(const uint8_t* data, size_t len) {
    if (len < 1) return false;
    uint8_t opcode = data[0];
    switch (opcode) {
        case OP_START:  return handleStart(data, len);
        case OP_DATA:   return handleData(data, len);
        case OP_COMMIT: return handleCommit();
        case OP_ABORT:  handleAbort(); return true;
        default:
            Serial.printf("[OTA] Unknown opcode 0x%02X\n", opcode);
            notifyStatus(0, 0x01);
            return false;
    }
}

extern "C" bool otaIsActive(void) {
    return g_active;
}

extern "C" void otaSetNotifyCallback(OtaNotifyFn fn) {
    g_notifyFn = fn;
}
