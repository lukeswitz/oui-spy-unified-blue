#ifdef OUISPY_BLE_TARGET
#include <Arduino.h>
#include <NimBLEDevice.h>

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println("[TARGET] Flock BLE target — advertising name 'Penguin-1234567890'");
    NimBLEDevice::init("Penguin-1234567890");
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData ad;
    ad.setName("Penguin-1234567890");
    adv->setAdvertisementData(ad);
    adv->setMinInterval(0x20);
    adv->setMaxInterval(0x40);
    adv->start();
    Serial.println("[TARGET] advertising started");
}

void loop() {
    delay(5000);
    Serial.println("[TARGET] alive, advertising 'Penguin-1234567890'");
}
#endif
