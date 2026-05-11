#ifndef BLE_COMPAT_H
#define BLE_COMPAT_H

#include <Arduino.h>
#include <NimBLEDevice.h>
#include <soc/soc_caps.h>
#include <esp_idf_version.h>

#ifndef NIMBLE_CPP_VERSION_MAJOR
  #define NIMBLE_V2 0
#else
  #define NIMBLE_V2 (NIMBLE_CPP_VERSION_MAJOR >= 2)
#endif

#if NIMBLE_V2
  #define BLE_SCAN_CB_CLASS          NimBLEScanCallbacks
  #define BLE_SCAN_CB_ONRESULT(name) void onResult(const NimBLEAdvertisedDevice* name) override
  #define BLE_ADV_DEV                const NimBLEAdvertisedDevice*
  #define BLE_SRV_ON_CONNECT         void onConnect(NimBLEServer* server, NimBLEConnInfo& connInfo) override
  #define BLE_SRV_ON_DISCONNECT      void onDisconnect(NimBLEServer* server, NimBLEConnInfo& connInfo, int reason) override
  #define BLE_CHR_ON_WRITE           void onWrite(NimBLECharacteristic* chr, NimBLEConnInfo& connInfo) override
  #define BLE_CHR_ON_READ            void onRead(NimBLECharacteristic* chr, NimBLEConnInfo& connInfo) override
  #define BLE_POWER_MAX              9
#else
  #define BLE_SCAN_CB_CLASS          NimBLEAdvertisedDeviceCallbacks
  #define BLE_SCAN_CB_ONRESULT(name) void onResult(NimBLEAdvertisedDevice* name) override
  #define BLE_ADV_DEV                NimBLEAdvertisedDevice*
  #define BLE_SRV_ON_CONNECT         void onConnect(NimBLEServer* server) override
  #define BLE_SRV_ON_DISCONNECT      void onDisconnect(NimBLEServer* server) override
  #define BLE_CHR_ON_WRITE           void onWrite(NimBLECharacteristic* chr) override
  #define BLE_CHR_ON_READ            void onRead(NimBLECharacteristic* chr) override
  #define BLE_POWER_MAX              ESP_PWR_LVL_P9
#endif

static inline void bleScanSetCallbacks(NimBLEScan* scan, BLE_SCAN_CB_CLASS* cb) {
#if NIMBLE_V2
    scan->setScanCallbacks(cb);
    if (cb) scan->setDuplicateFilter(false);
#else
    scan->setAdvertisedDeviceCallbacks(cb, cb != nullptr);
#endif
}

static inline void bleScanClearCallbacks(NimBLEScan* scan) {
#if NIMBLE_V2
    scan->setScanCallbacks(nullptr);
#else
    scan->setAdvertisedDeviceCallbacks(nullptr, false);
#endif
}

#if ESP_ARDUINO_VERSION_MAJOR >= 3
  static inline void buzzerTone(uint8_t pin, uint32_t freq, uint8_t duty) {
      ledcAttach(pin, freq, 8);
      ledcWrite(pin, duty);
  }
  static inline void buzzerOff(uint8_t pin) {
      ledcWrite(pin, 0);
      ledcDetach(pin);
  }
#else
  static inline void buzzerTone(uint8_t pin, uint32_t freq, uint8_t duty) {
      ledcSetup(0, freq, 8);
      ledcAttachPin(pin, 0);
      ledcWrite(0, duty);
  }
  static inline void buzzerOff(uint8_t pin) {
      ledcWrite(0, 0);
      ledcDetachPin(pin);
  }
#endif

#if SOC_CPU_CORES_NUM > 1
  #define APP_CORE 1
#else
  #define APP_CORE 0
#endif

#if NIMBLE_V2
static inline void bleAdvGetMac(const NimBLEAdvertisedDevice* dev, uint8_t* out) {
    std::string s = dev->getAddress().toString();
    unsigned int m[6];
    sscanf(s.c_str(), "%02x:%02x:%02x:%02x:%02x:%02x",
           &m[0], &m[1], &m[2], &m[3], &m[4], &m[5]);
    for (int i = 0; i < 6; i++) out[i] = (uint8_t)m[i];
}
#else
static inline void bleAdvGetMac(NimBLEAdvertisedDevice* dev, uint8_t* out) {
    memcpy(out, dev->getAddress().getNative(), 6);
}
#endif

#if ESP_IDF_VERSION_MAJOR >= 5
  #define ESPNOW_RECV_CB_ARGS const esp_now_recv_info_t* _recvInfo, const uint8_t* data, int len
  #define ESPNOW_RECV_MAC     _recvInfo->src_addr
#else
  #define ESPNOW_RECV_CB_ARGS const uint8_t* _recvMac, const uint8_t* data, int len
  #define ESPNOW_RECV_MAC     _recvMac
#endif

#endif
