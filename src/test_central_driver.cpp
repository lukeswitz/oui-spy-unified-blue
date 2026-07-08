#ifdef OUISPY_TEST_CENTRAL
#include <Arduino.h>
#include <NimBLEDevice.h>

static const char* SVC        = "00000001-0a15-4b70-ba00-c010ae1ba01c";
static const char* CHR_ENGINE = "00000002-0a15-4b70-ba00-c010ae1ba01c";
static const char* CHR_HWCFG  = "00000020-0a15-4b70-ba00-c010ae1ba01c";
static const char* CHR_DETCFG = "00000100-0a15-4b70-ba00-c010ae1ba01c";

static NimBLEClient* cli = nullptr;
static NimBLEAdvertisedDevice target;
static volatile bool found = false;

class ScanCB : public NimBLEAdvertisedDeviceCallbacks {
    void onResult(NimBLEAdvertisedDevice* d) override {
        if (found) return;
        std::string n = d->haveName() ? d->getName() : "";
        if (n.rfind("OUI-SPY-", 0) == 0 && n.rfind("OUI-SPY-MGR", 0) != 0) {
            target = *d;
            found = true;
            NimBLEDevice::getScan()->stop();
            Serial.printf("[DRV] found node %s addr=%s\n",
                          n.c_str(), d->getAddress().toString().c_str());
        }
    }
};
static ScanCB scanCb;

static bool findNode(uint32_t ms) {
    found = false;
    NimBLEScan* s = NimBLEDevice::getScan();
    s->start(ms / 1000, false);
    uint32_t t0 = millis();
    while (!found && millis() - t0 < ms + 1000) delay(50);
    return found;
}

static bool writeChr(const char* chrUuid, const uint8_t* data, size_t len) {
    if (!cli || !cli->isConnected()) return false;
    NimBLERemoteService* svc = cli->getService(SVC);
    if (!svc) { Serial.println("[DRV] ERR no service"); return false; }
    NimBLERemoteCharacteristic* c = svc->getCharacteristic(chrUuid);
    if (!c) { Serial.printf("[DRV] ERR no chr %s\n", chrUuid); return false; }
    bool ok = c->writeValue(data, len, true);
    Serial.printf("[DRV] write %s len=%u ok=%d\n", chrUuid, (unsigned)len, ok);
    return ok;
}

static bool doConnect() {
    if (!cli) cli = NimBLEDevice::createClient();
    if (cli->isConnected()) return true;
    if (!cli->connect(&target)) { Serial.println("[DRV] connect FAIL"); return false; }
    Serial.println("[DRV] connected");
    delay(400);
    return true;
}

static void configureNode() {
    uint8_t hw[6] = {0, 0, 0, 100, 0, 1};        // offline scan ON
    writeChr(CHR_HWCFG, hw, 6);
    delay(150);
    uint8_t cfgBle[3] = {0x10, 0x00, 0x02};      // detector engine config: BLE-only radio mask
    writeChr(CHR_ENGINE, cfgBle, 3);
    delay(150);
    uint8_t clr[1] = {0x00};                     // detector watchlist: clear
    writeChr(CHR_DETCFG, clr, 1);
    delay(100);
    uint8_t add[8] = {0x01, 6, 0xC0, 0xFF, 0xEE, 0x00, 0x00, 0x01}; // add full-MAC filter
    writeChr(CHR_DETCFG, add, 8);
    delay(100);
    uint8_t en[2] = {0x01, 0x00};                // enable detector (engine 0)
    writeChr(CHR_ENGINE, en, 2);
    Serial.println("[DRV] configured: offline ON + detector BLE + watchlist + ENABLE");
}

void setup() {
    Serial.begin(115200);
    delay(500);
    Serial.println("\n[DRV] === OUI-SPY offline-scan reconnect test central ===");
    NimBLEDevice::init("OUISPY-TESTDRV");
    NimBLEDevice::setMTU(247);
    NimBLEDevice::getScan()->setAdvertisedDeviceCallbacks(&scanCb, false);
    NimBLEDevice::getScan()->setActiveScan(true);
}

void loop() {
    Serial.println("[DRV] scanning for node...");
    if (!findNode(10000)) { Serial.println("[DRV] node not found, retry"); delay(2000); return; }
    if (!doConnect()) { delay(3000); return; }
    configureNode();
    Serial.println("[DRV] HOLD connected 12s -- node should be SCANNING (eng bit0, [DETECTOR] Started)");
    delay(12000);

    for (int i = 0; i < 3; i++) {
        Serial.printf("[DRV] ===== cycle %d: DISCONNECT =====\n", i);
        cli->disconnect();
        Serial.println("[DRV] disconnected; wait 12s (<30s grace) -- node should KEEP scanning (offline)");
        delay(12000);
        Serial.printf("[DRV] ===== cycle %d: RECONNECT =====\n", i);
        if (!findNode(10000)) { Serial.println("[DRV] node not found on reconnect!"); break; }
        if (!doConnect()) { Serial.println("[DRV] reconnect FAIL"); break; }
        Serial.println("[DRV] reconnected; HOLD 12s -- node should STILL be scanning (BUG if not)");
        delay(12000);
    }
    Serial.println("[DRV] === test cycles complete, idle ===");
    while (true) delay(10000);
}
#endif
