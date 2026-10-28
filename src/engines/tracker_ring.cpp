#include "tracker_ring.h"
#include "../ble_coex.h"
#include <Arduino.h>
#include <NimBLEDevice.h>
#ifdef OUISPY_NIMBLE2
#include <freertos/idf_additions.h>
#endif

struct RingProto {
    const char* svc;
    const char* chr;
    uint8_t cmd[3];
    uint8_t cmdLen;
};

static const RingProto RING_PROTOS[] = {
    { "15190001-12f4-c226-88ed-2ac5579f2a85", "8e0c0001-1d68-fb92-bf61-48377421680e", {0x00, 0x03, 0x00}, 2 },
    { "fd44",                                 "4f860003-943b-49ef-bed4-2f730304427a", {0x01, 0x00, 0x03}, 3 },
    { "7dfc9000-7d1c-4951-86aa-8d9728f8d66c", "7dfc9001-7d1c-4951-86aa-8d9728f8d66c", {0xAF, 0x00, 0x00}, 1 },
};

struct RingJob {
    uint8_t mac[6];
    uint8_t addrType;
    TrackerRingDoneFn done;
};

static volatile bool s_busy = false;
static RingJob s_job;

static TaskHandle_t s_task = nullptr;

static void ringRun(const RingJob& job) {
    uint8_t status = TRACKER_RING_NO_CONNECT;
    uint8_t proto = 0xFF;
    bleCoexPauseForMesh();
    NimBLEClient* c = NimBLEDevice::createClient();
    if (c) {
        c->setConnectTimeout(6000);
        NimBLEAddress addr(job.mac, job.addrType);
        if (c->connect(addr)) {
            status = TRACKER_RING_NO_SERVICE;
            for (uint8_t i = 0; i < sizeof(RING_PROTOS) / sizeof(RING_PROTOS[0]); i++) {
                NimBLERemoteService* s = c->getService(NimBLEUUID(RING_PROTOS[i].svc));
                if (!s) continue;
                NimBLERemoteCharacteristic* ch = s->getCharacteristic(NimBLEUUID(RING_PROTOS[i].chr));
                if (!ch) continue;
                proto = i;
                if (ch->canNotify() || ch->canIndicate()) ch->subscribe(ch->canNotify());
                bool ok = ch->writeValue(RING_PROTOS[i].cmd, RING_PROTOS[i].cmdLen, ch->canWrite());
                status = ok ? TRACKER_RING_OK : TRACKER_RING_WRITE_FAIL;
                if (ok) vTaskDelay(pdMS_TO_TICKS(1500));
                break;
            }
            c->disconnect();
        }
        NimBLEDevice::deleteClient(c);
    }
    Serial.printf("[RING] %02x:%02x:%02x:%02x:%02x:%02x status=%u proto=%d\n",
                  job.mac[0], job.mac[1], job.mac[2], job.mac[3], job.mac[4], job.mac[5],
                  (unsigned)status, proto == 0xFF ? -1 : (int)proto);
    if (job.done) job.done(job.mac, status, proto);
    bleCoexEnsureScanning();
}

static void ringTask(void*) {
    for (;;) {
        ulTaskNotifyTake(pdTRUE, portMAX_DELAY);
        RingJob job = s_job;
        ringRun(job);
        s_busy = false;
    }
}

static bool ringTaskEnsure(void) {
    if (s_task) return true;
#ifdef OUISPY_NIMBLE2
    BaseType_t rc = xTaskCreatePinnedToCoreWithCaps(ringTask, "trkRing", 6144, NULL, 3, &s_task, 0,
                                                    MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
#else
    BaseType_t rc = xTaskCreate(ringTask, "trkRing", 6144, NULL, 3, &s_task);
#endif
    if (rc != pdPASS) {
        s_task = nullptr;
        Serial.printf("[RING] task create failed rc=%d internalFree=%u\n", (int)rc,
                      (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL));
        return false;
    }
    return true;
}

bool trackerRingStart(const uint8_t mac[6], uint8_t addrType, TrackerRingDoneFn done) {
    if (s_busy) return false;
    if (!ringTaskEnsure()) return false;
    s_busy = true;
    memcpy(s_job.mac, mac, 6);
    s_job.addrType = addrType;
    s_job.done = done;
    xTaskNotifyGive(s_task);
    return true;
}
