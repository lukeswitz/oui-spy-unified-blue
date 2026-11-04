#include "ota_handler.h"
#include <Arduino.h>
#include <esp_ota_ops.h>
#include <esp_partition.h>
#include <esp_system.h>
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/semphr.h>
#include <esp_heap_caps.h>
#ifdef OUISPY_NIMBLE2
#include <freertos/idf_additions.h>
#endif
#include <mbedtls/ecdsa.h>
#include <mbedtls/md.h>
#include <string.h>
#include "ota_pubkey.h"

#define OTA_TRIAL_MS 60000UL
#define OTA_SIG_LEN 64
#define OTA_SIG_TRAILER_LEN (4 + OTA_SIG_LEN)
#define OTA_SIG_READ_LEN 4096
#define OTA_SIG_YIELD_LEN 65536
#define OTA_SIG_TASK_STACK 8192

extern "C" bool verifyRollbackLater() { return true; }

extern "C" void otaTrialTick(void) {
    static bool done = false;
    if (done || millis() < OTA_TRIAL_MS) return;
    done = true;
    const esp_partition_t* running = esp_ota_get_running_partition();
    esp_ota_img_states_t state;
    if (!running || esp_ota_get_state_partition(running, &state) != ESP_OK) return;
    if (state != ESP_OTA_IMG_PENDING_VERIFY) return;
    esp_err_t err = esp_ota_mark_app_valid_cancel_rollback();
    Serial.printf("[OTA] %s ran %lus: marked valid (%s)\n", running->label,
                  (unsigned long)(OTA_TRIAL_MS / 1000), esp_err_to_name(err));
}

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

const uint8_t OTA_SIG_MAGIC[4] = {'O', 'S', 'G', '1'};

struct OtaSigJob {
    const uint8_t* digest;
    const uint8_t* rs;
    bool valid;
    UBaseType_t stackFree;
    SemaphoreHandle_t done;
};

bool sigDigestValid(const uint8_t digest[32], const uint8_t rs[OTA_SIG_LEN]) {
    mbedtls_ecp_group grp;
    mbedtls_ecp_point q;
    mbedtls_mpi r, s;
    mbedtls_ecp_group_init(&grp);
    mbedtls_ecp_point_init(&q);
    mbedtls_mpi_init(&r);
    mbedtls_mpi_init(&s);
    bool valid = mbedtls_ecp_group_load(&grp, MBEDTLS_ECP_DP_SECP256R1) == 0 &&
                 mbedtls_ecp_point_read_binary(&grp, &q, OTA_SIG_PUBKEY, sizeof(OTA_SIG_PUBKEY)) == 0 &&
                 mbedtls_mpi_read_binary(&r, rs, OTA_SIG_LEN / 2) == 0 &&
                 mbedtls_mpi_read_binary(&s, rs + OTA_SIG_LEN / 2, OTA_SIG_LEN / 2) == 0 &&
                 mbedtls_ecdsa_verify(&grp, digest, 32, &q, &r, &s) == 0;
    mbedtls_mpi_free(&s);
    mbedtls_mpi_free(&r);
    mbedtls_ecp_point_free(&q);
    mbedtls_ecp_group_free(&grp);
    return valid;
}

bool sigPartitionHash(const esp_partition_t* part, uint32_t totalLen, uint8_t digest[32],
                      uint8_t trailer[OTA_SIG_TRAILER_LEN]) {
    if (!part || totalLen <= OTA_SIG_TRAILER_LEN || totalLen > part->size) {
        Serial.printf("[OTA-SIG] refused: length %u\n", (unsigned)totalLen);
        return false;
    }
    const uint32_t imageLen = totalLen - OTA_SIG_TRAILER_LEN;
    if (esp_partition_read(part, imageLen, trailer, OTA_SIG_TRAILER_LEN) != ESP_OK) {
        Serial.println("[OTA-SIG] refused: trailer read failed");
        return false;
    }
    if (memcmp(trailer, OTA_SIG_MAGIC, sizeof(OTA_SIG_MAGIC)) != 0) {
        Serial.println("[OTA-SIG] refused: image is not signed");
        return false;
    }
    uint8_t* buf = (uint8_t*)malloc(OTA_SIG_READ_LEN);
    if (!buf) {
        Serial.println("[OTA-SIG] refused: no heap for read buffer");
        return false;
    }
    mbedtls_md_context_t sha;
    mbedtls_md_init(&sha);
    bool readOk = mbedtls_md_setup(&sha, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 0) == 0 &&
                  mbedtls_md_starts(&sha) == 0;
    uint32_t off = 0, sinceYield = 0;
    while (readOk && off < imageLen) {
        uint32_t n = imageLen - off;
        if (n > OTA_SIG_READ_LEN) n = OTA_SIG_READ_LEN;
        readOk = esp_partition_read(part, off, buf, n) == ESP_OK &&
                 mbedtls_md_update(&sha, buf, n) == 0;
        off += n;
        sinceYield += n;
        if (sinceYield >= OTA_SIG_YIELD_LEN) {
            sinceYield = 0;
            vTaskDelay(1);
        }
    }
    if (readOk) readOk = mbedtls_md_finish(&sha, digest) == 0;
    mbedtls_md_free(&sha);
    free(buf);
    if (!readOk) {
        Serial.println("[OTA-SIG] refused: hash failed");
        return false;
    }
    return true;
}

void sigTask(void* arg) {
    OtaSigJob* job = (OtaSigJob*)arg;
    job->valid = sigDigestValid(job->digest, job->rs);
    job->stackFree = uxTaskGetStackHighWaterMark(NULL);
    xSemaphoreGive(job->done);
#ifdef OUISPY_NIMBLE2
    vTaskDelay(portMAX_DELAY);
#else
    vTaskDelete(NULL);
#endif
}

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

    if (!otaSigVerifyPartition(g_partition, g_expectedLength)) {
        notifyStatus(0, 0x09);
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

extern "C" bool otaSigVerifyPartition(const esp_partition_t* partition, uint32_t totalLen) {
    uint32_t t0 = millis();
    uint8_t digest[32];
    uint8_t trailer[OTA_SIG_TRAILER_LEN];
    if (!sigPartitionHash(partition, totalLen, digest, trailer)) return false;
    OtaSigJob job = {digest, trailer + sizeof(OTA_SIG_MAGIC), false, 0, xSemaphoreCreateBinary()};
    if (!job.done) {
        Serial.println("[OTA-SIG] refused: no heap for semaphore");
        return false;
    }
#ifdef OUISPY_NIMBLE2
    TaskHandle_t task = NULL;
    BaseType_t rc = xTaskCreateWithCaps(sigTask, "ota_sig", OTA_SIG_TASK_STACK, &job,
                                        uxTaskPriorityGet(NULL), &task, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
#else
    BaseType_t rc = xTaskCreate(sigTask, "ota_sig", OTA_SIG_TASK_STACK, &job,
                                uxTaskPriorityGet(NULL), NULL);
#endif
    if (rc != pdPASS) {
        Serial.printf("[OTA-SIG] refused: no heap for task, internal largest=%u\n",
                      (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
        vSemaphoreDelete(job.done);
        return false;
    }
    xSemaphoreTake(job.done, portMAX_DELAY);
#ifdef OUISPY_NIMBLE2
    vTaskDeleteWithCaps(task);
#endif
    vSemaphoreDelete(job.done);
    Serial.printf("[OTA-SIG] %s len=%u %ums stack_free=%u internal_free=%u\n", job.valid ? "valid" : "bad signature",
                  (unsigned)totalLen, (unsigned)(millis() - t0), (unsigned)job.stackFree,
                  (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
    return job.valid;
}

extern "C" void otaInit(void) {
    resetState();
    const esp_partition_t* running = esp_ota_get_running_partition();
    const esp_partition_t* boot    = esp_ota_get_boot_partition();
    if (running && boot) {
        Serial.printf("[OTA] Running from %s, boot=%s\n",
                      running->label, boot->label);
    }

    esp_ota_img_states_t state;
    if (running && esp_ota_get_state_partition(running, &state) == ESP_OK) {
        if (state == ESP_OTA_IMG_PENDING_VERIFY) {
            Serial.println("[OTA] Image PENDING_VERIFY: marked valid after 60 s up or on app confirm");
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
