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

#ifndef ROLE_MANAGER
#define ROLE_MANAGER 0
#endif

#ifndef ROLE_NAME
#define ROLE_NAME "X"
#endif

static const uint8_t kBroadcast[6] = {0xFF,0xFF,0xFF,0xFF,0xFF,0xFF};

enum : uint8_t {
  PKT_CORE_REPLY   = 1,
  PKT_CORE_REQUEST = 2,
  PKT_PAIR_ACK     = 3,
  PKT_DATA         = 4,
};

struct __attribute__((packed)) Pkt {
  uint8_t  type;
  uint8_t  src[6];
  uint32_t seq;
  uint8_t  pad[5];
};

struct RxEvent {
  uint8_t sender[6];
  Pkt     pkt;
};

static QueueHandle_t rxQ = nullptr;

static uint8_t myMac[6] = {0};
static uint8_t peerMac[6] = {0};
static volatile bool paired = false;
static volatile uint32_t txCount=0, txFail=0, rxBcast=0, rxUcast=0, rxData=0;
static uint8_t lastSrc[6] = {0};
static uint32_t lastSeq = 0;

static void IRAM_ATTR onRecv(const uint8_t *mac, const uint8_t *data, int len) {
  if (!rxQ || len < (int)sizeof(Pkt)) return;
  RxEvent ev;
  memcpy(ev.sender, mac, 6);
  memcpy(&ev.pkt, data, sizeof(Pkt));
  BaseType_t hpw = pdFALSE;
  xQueueSendFromISR(rxQ, &ev, &hpw);
  if (hpw) portYIELD_FROM_ISR();
}

static void onSend(const uint8_t *mac, esp_now_send_status_t status) {
  if (status != ESP_NOW_SEND_SUCCESS) txFail++;
}

static bool isBroadcast(const uint8_t *mac) {
  for (int i = 0; i < 6; i++) if (mac[i] != 0xFF) return false;
  return true;
}

static bool addUnicastPeer(const uint8_t *mac) {
  esp_now_peer_info_t p = {};
  memcpy(p.peer_addr, mac, 6);
  p.channel = MESH_CH;
  p.ifidx   = WIFI_IF_STA;
  p.encrypt = false;
  if (esp_now_is_peer_exist(mac)) return true;
  return esp_now_add_peer(&p) == ESP_OK;
}

static void sendPkt(const uint8_t *dst, uint8_t type, uint32_t seq) {
  Pkt p = {};
  p.type = type;
  memcpy(p.src, myMac, 6);
  p.seq = seq;
  esp_err_t e = esp_now_send(dst, (const uint8_t*)&p, sizeof(p));
  if (e == ESP_OK) txCount++; else txFail++;
}

static void rxTask(void *) {
  RxEvent ev;
  for (;;) {
    if (xQueueReceive(rxQ, &ev, portMAX_DELAY) != pdTRUE) continue;
    if (isBroadcast(ev.sender)) rxBcast++; else rxUcast++;

#if ROLE_MANAGER
    if (ev.pkt.type == PKT_CORE_REQUEST && !paired) {
      memcpy(peerMac, ev.pkt.src, 6);
      if (addUnicastPeer(peerMac)) {
        sendPkt(peerMac, PKT_PAIR_ACK, 0);
        paired = true;
        Serial.printf("[MGR] PAIRED with %02X:%02X:%02X:%02X:%02X:%02X\n",
          peerMac[0],peerMac[1],peerMac[2],peerMac[3],peerMac[4],peerMac[5]);
      }
    } else if (ev.pkt.type == PKT_DATA) {
      rxData++;
      memcpy(lastSrc, ev.pkt.src, 6);
      lastSeq = ev.pkt.seq;
    }
#else
    if (ev.pkt.type == PKT_CORE_REPLY && !paired) {
      memcpy(peerMac, ev.pkt.src, 6);
      if (addUnicastPeer(peerMac)) {
        sendPkt(peerMac, PKT_CORE_REQUEST, 0);
        Serial.printf("[NODE] saw mgr %02X:%02X:%02X:%02X:%02X:%02X — sent CORE_REQUEST\n",
          peerMac[0],peerMac[1],peerMac[2],peerMac[3],peerMac[4],peerMac[5]);
      }
    } else if (ev.pkt.type == PKT_PAIR_ACK) {
      paired = true;
      Serial.println("[NODE] PAIR_ACK received — paired");
    }
#endif
  }
}

static void initNimBLE() {
  esp_read_mac(myMac, ESP_MAC_WIFI_STA);
  String name = String(ROLE_NAME) + "-" + String(myMac[4], HEX) + String(myMac[5], HEX);
  NimBLEDevice::init(name.c_str());
  NimBLEDevice::setPower(ESP_PWR_LVL_P9);
  NimBLEServer *srv = NimBLEDevice::createServer();
  NimBLEService *svc = srv->createService("12345678-0000-0000-0000-000000000001");
  NimBLECharacteristic *chr = svc->createCharacteristic(
      "12345678-0000-0000-0000-000000000002",
      NIMBLE_PROPERTY::READ);
  chr->setValue("gate2");
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
  Serial.printf("=== GATE2 PAIR TEST (role=%s) ===\n", ROLE_MANAGER ? "MANAGER" : "NODE");

  rxQ = xQueueCreate(32, sizeof(RxEvent));
  xTaskCreatePinnedToCore(rxTask, "rxTask", 4096, nullptr, 2, nullptr, 1);

  initNimBLE();
  Serial.println("NimBLE up");

  if (!initEspNow()) { Serial.println("ESPNOW FAIL"); while (1) delay(1000); }
  Serial.println("ESPNOW up");

  Serial.printf("MAC : %02X:%02X:%02X:%02X:%02X:%02X | CH: %d\n",
    myMac[0],myMac[1],myMac[2],myMac[3],myMac[4],myMac[5], MESH_CH);
  Serial.println("==== READY ====");
}

void loop() {
  static uint32_t nextTx = 0, nextStat = 0;
  uint32_t now = millis();

  if (now >= nextTx) {
#if ROLE_MANAGER
    if (!paired) {
      sendPkt(kBroadcast, PKT_CORE_REPLY, 0);
      nextTx = now + 3000;
    } else {
      nextTx = now + 60000;
    }
#else
    if (paired) {
      static uint32_t dseq = 0;
      sendPkt(peerMac, PKT_DATA, ++dseq);
      nextTx = now + 1000;
    } else {
      nextTx = now + 500;
    }
#endif
  }

  if (now >= nextStat) {
    nextStat = now + 5000;
    uint8_t ch = 0; wifi_second_chan_t sec;
    esp_wifi_get_channel(&ch, &sec);
    Serial.printf("[STAT] paired=%d tx=%lu fail=%lu rxB=%lu rxU=%lu rxDATA=%lu last_seq=%lu from=%02X:%02X:%02X:%02X:%02X:%02X ch=%u heap=%u\n",
      paired ? 1 : 0,
      (unsigned long)txCount,(unsigned long)txFail,
      (unsigned long)rxBcast,(unsigned long)rxUcast,(unsigned long)rxData,
      (unsigned long)lastSeq,
      lastSrc[0],lastSrc[1],lastSrc[2],lastSrc[3],lastSrc[4],lastSrc[5],
      (unsigned)ch, (unsigned)ESP.getFreeHeap());
  }

  delay(10);
}
