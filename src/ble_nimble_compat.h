#ifndef BLE_NIMBLE_COMPAT_H
#define BLE_NIMBLE_COMPAT_H

#if defined(OUISPY_NIMBLE2) && !defined(OUISPY_NIMBLE2_API)
#define OUISPY_NIMBLE2_API 1
#endif

#if defined(OUISPY_NIMBLE2_API) && defined(__cplusplus) && __has_include(<NimBLEDevice.h>)
#include <Arduino.h>
#include <esp_mac.h>
#include <NimBLEDevice.h>

class NimBLEAdvertisedDeviceCallbacks : public NimBLEScanCallbacks {
 public:
  virtual void onResult(NimBLEAdvertisedDevice* dev) {}
  void onResult(const NimBLEAdvertisedDevice* dev) override {
    onResult(const_cast<NimBLEAdvertisedDevice*>(dev));
  }
};

class OuispyCharacteristicCallbacks : public NimBLECharacteristicCallbacks {
 public:
  virtual void onWrite(NimBLECharacteristic* c) {}
  virtual void onRead(NimBLECharacteristic* c) {}
  void onWrite(NimBLECharacteristic* c, NimBLEConnInfo&) override { onWrite(c); }
  void onRead(NimBLECharacteristic* c, NimBLEConnInfo&) override { onRead(c); }
};

class OuispyServerCallbacks : public NimBLEServerCallbacks {
 public:
  virtual void onConnect(NimBLEServer* s) {}
  virtual void onDisconnect(NimBLEServer* s) {}
  void onConnect(NimBLEServer* s, NimBLEConnInfo&) override { onConnect(s); }
  void onDisconnect(NimBLEServer* s, NimBLEConnInfo&, int) override { onDisconnect(s); }
};

#define NimBLECharacteristicCallbacks OuispyCharacteristicCallbacks
#define NimBLEServerCallbacks OuispyServerCallbacks
#define setAdvertisedDeviceCallbacks setScanCallbacks
#define getNative getVal
#define getInitialized isInitialized
#endif

#if defined(OUISPY_NIMBLE2) && defined(__cplusplus) && __has_include(<NimBLEDevice.h>)
#define xTaskCreatePinnedToCore(fn, nm, st, ar, pr, hd, core) \
    xTaskCreatePinnedToCore((fn), (nm), (st), (ar), (pr), (hd), 0)
#define ledcSetup(ch, freq, res) ledcAttach(PIN_BUZZER, (freq), (res))
#define ledcAttachPin(pin, ch) ((void)0)
#define ledcWrite(ch, duty) ledcWrite(PIN_BUZZER, (duty))
#define ledcDetachPin(pin) ledcDetach(pin)
#endif

#endif
