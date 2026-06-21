#ifdef OUISPY_BLE_TARGET
#include <Arduino.h>
#include <NimBLEDevice.h>

void setup() {
    Serial.begin(115200);
    delay(300);
    Serial.println("[TARGET] Flock BLE target — advertising name 'Penguin'");
    NimBLEDevice::init("Penguin");
    NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
    NimBLEAdvertisementData ad;
    ad.setName("Penguin");
    adv->setAdvertisementData(ad);
    adv->setMinInterval(0x20);
    adv->setMaxInterval(0x40);
    adv->start();
    Serial.println("[TARGET] advertising started");
}

void loop() {
    delay(5000);
    Serial.println("[TARGET] alive, advertising 'Penguin'");
}
#endif
