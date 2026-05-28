#include <Arduino.h>
#include <WiFi.h>
#include <esp_wifi.h>
#include <esp_now.h>
#include <NimBLEDevice.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>

#ifndef MESH_CH
#define MESH_CH 6
#endif

#ifndef ROLE_NAME
#define ROLE_NAME "UNKNOWN"
#endif

static const uint8_t kBroadcast[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};

struct __attribute__((packed)) TestPkt {
  uint32_t seq;
  uint8_t  src[6];
  uint8_t  pad[6];
};

struct RxEvent {
  uint8_t  src[6];
  TestPkt  pkt;
};

static QueueHandle_t rxQ = nullptr;

static volatile uint32_t txCount = 0;
static volatile uint32_t txFail  = 0;
static volatile uint32_t rxCount = 0;
static uint8_t lastSrc[6] = {0};
static uint32_t lastSeq = 0;
static uint8_t myMac[6] = {0};

static void IRAM_ATTR onRecv(const uint8_t *mac_addr, const uint8_t *data, int len) {
  if (!rxQ || len < (int)sizeof(TestPkt)) return;
  RxEvent ev;
  memcpy(ev.src, mac_addr, 6);
  memcpy(&ev.pkt, data, sizeof(TestPkt));
  BaseType_t hpw = pdFALSE;
  xQueueSendFromISR(rxQ, &ev, &hpw);
  if (hpw) portYIELD_FROM_ISR();
}

static void onSend(const uint8_t *mac, esp_now_send_status_t status) {
  if (status != ESP_NOW_SEND_SUCCESS) txFail++;
}

static void rxTask(void *) {
  RxEvent ev;
  for (;;) {
    if (xQueueReceive(rxQ, &ev, portMAX_DELAY) == pdTRUE) {
      rxCount++;
      memcpy(lastSrc, ev.src, 6);
      lastSeq = ev.pkt.seq;
    }
  }
}

static void initNimBLE() {
  String name = String(ROLE_NAME) + "-" + String(myMac[4], HEX) + String(myMac[5], HEX);
  NimBLEDevice::init(name.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEServer *srv = NimBLEDevice::createServer();
  NimBLEService *svc = srv->createService("12345678-0000-0000-0000-000000000001");
  NimBLECharacteristic *chr = svc->createCharacteristic(
      "12345678-0000-0000-0000-000000000002",
      NIMBLE_PROPERTY::READ);
  chr->setValue("gate0");
  svc->start();
  NimBLEAdvertising *adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(svc->getUUID());
  adv->start();
}

static bool initEspNow() {
  WiFi.mode(WIFI_AP_STA);
  WiFi.disconnect(false, false);
  esp_wifi_set_storage(WIFI_STORAGE_RAM);
  esp_wifi_set_ps(WIFI_PS_MIN_MODEM);
  esp_wifi_set_channel(MESH_CH, WIFI_SECOND_CHAN_NONE);

  esp_read_mac(myMac, ESP_MAC_WIFI_STA);

  if (esp_now_init() != ESP_OK) return false;
  esp_now_register_recv_cb(onRecv);
  esp_now_register_send_cb(onSend);

  esp_now_peer_info_t peer = {};
  memcpy(peer.peer_addr, kBroadcast, 6);
  peer.channel = MESH_CH;
  peer.ifidx   = WIFI_IF_STA;
  peer.encrypt = false;
  if (esp_now_add_peer(&peer) != ESP_OK) return false;
  return true;
}

void setup() {
  Serial.begin(115200);
  delay(800);
  Serial.println();
  Serial.println("=== GATE0 BARE TEST ===");
  Serial.printf("ROLE: %s | CH: %d\n", ROLE_NAME, MESH_CH);

  esp_read_mac(myMac, ESP_MAC_WIFI_STA);
  Serial.printf("MAC : %02X:%02X:%02X:%02X:%02X:%02X\n",
    myMac[0],myMac[1],myMac[2],myMac[3],myMac[4],myMac[5]);

  rxQ = xQueueCreate(32, sizeof(RxEvent));
  xTaskCreatePinnedToCore(rxTask, "rxTask", 4096, nullptr, 2, nullptr, 1);

  initNimBLE();
  Serial.println("NimBLE up");

  if (!initEspNow()) {
    Serial.println("ESPNOW init FAILED");
    while (1) delay(1000);
  }
  Serial.println("ESPNOW up");

  uint8_t ch = 0; wifi_second_chan_t sec;
  esp_wifi_get_channel(&ch, &sec);
  Serial.printf("CHANNEL after init: %d\n", ch);

  Serial.println("==== READY ====");
}

void loop() {
  static uint32_t nextTx = 0, nextStat = 0;
  uint32_t now = millis();

  if (now >= nextTx) {
    nextTx = now + 1000;
    TestPkt pkt = {};
    pkt.seq = txCount + 1;
    memcpy(pkt.src, myMac, 6);
    esp_err_t e = esp_now_send(kBroadcast, (const uint8_t*)&pkt, sizeof(pkt));
    if (e == ESP_OK) txCount++;
    else { txFail++; Serial.printf("send_err=%d\n", (int)e); }
  }

  if (now >= nextStat) {
    nextStat = now + 5000;
    uint8_t ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&ch, &sec);
    Serial.printf("[STAT] tx=%lu fail=%lu rx=%lu last_seq=%lu from=%02X:%02X:%02X:%02X:%02X:%02X ch=%u heap=%u\n",
      (unsigned long)txCount, (unsigned long)txFail, (unsigned long)rxCount,
      (unsigned long)lastSeq,
      lastSrc[0],lastSrc[1],lastSrc[2],lastSrc[3],lastSrc[4],lastSrc[5],
      (unsigned)ch, (unsigned)ESP.getFreeHeap());
  }

  delay(10);
}
