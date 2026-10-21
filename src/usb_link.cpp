#include "usb_link.h"

#ifdef OUISPY_USB_LINK

#include <Arduino.h>
#include <esp_heap_caps.h>
#include <freertos/FreeRTOS.h>
#include <freertos/ringbuf.h>
#include <freertos/task.h>
#include <stdlib.h>
#include <string>
#include "ble_gatt.h"

struct UsbLinkPort {
    const char* name;
    UsbLinkWriteFn write;
    void* ctx;
    uint8_t* rxFrame;
    size_t rxLen;
    uint8_t* txFrame;
    uint8_t* scratch;
    RingbufHandle_t ring;
    StaticRingbuffer_t ringStruct;
    volatile uint32_t subscribed;
    volatile bool up;
    uint32_t lastRxMs;
    volatile uint32_t dropped;
    uint32_t lastDropLog;
};

namespace {

constexpr uint8_t kSync0 = 0xA5;
constexpr uint8_t kSync1 = 0x5A;
constexpr uint8_t kProtoVersion = 1;
constexpr size_t kHeader = 7;
constexpr size_t kMaxPayload = 1024;
constexpr size_t kMaxFrame = kHeader + kMaxPayload + 2;
constexpr size_t kMaxChars = 32;
constexpr size_t kMaxPorts = 2;
constexpr uint32_t kLinkTimeoutMs = 4000;
constexpr size_t kRingPsram = 16384;
constexpr size_t kRingInternal = 4096;

enum FrameType : uint8_t {
    kHello = 0x01,
    kWrite = 0x02,
    kWriteNoAck = 0x03,
    kRead = 0x04,
    kSubscribe = 0x05,
    kPing = 0x06,
    kHelloAck = 0x81,
    kWriteAck = 0x82,
    kReadRsp = 0x84,
    kSubscribeAck = 0x85,
    kPong = 0x86,
    kNotify = 0x90,
};

struct LinkChar {
    uint16_t id;
    NimBLECharacteristic* chr;
    OuispyCharacteristicCallbacks* cb;
};

LinkChar chars[kMaxChars];
size_t charCount = 0;
UsbLinkPort* ports[kMaxPorts];
size_t portCount = 0;
volatile uint8_t portsUp = 0;
portMUX_TYPE upMux = portMUX_INITIALIZER_UNLOCKED;

uint8_t* linkAlloc(size_t n) {
    void* p = heap_caps_malloc(n, MALLOC_CAP_SPIRAM);
    if (p == nullptr) p = malloc(n);
    return (uint8_t*)p;
}

uint16_t crc16(const uint8_t* d, size_t n) {
    uint16_t crc = 0xFFFF;
    for (size_t i = 0; i < n; i++) {
        crc ^= (uint16_t)d[i] << 8;
        for (int b = 0; b < 8; b++) {
            crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
        }
    }
    return crc;
}

size_t encode(uint8_t* out, uint8_t type, uint16_t id, const uint8_t* d, size_t n) {
    out[0] = kSync0;
    out[1] = kSync1;
    out[2] = type;
    out[3] = (uint8_t)(id & 0xFF);
    out[4] = (uint8_t)(id >> 8);
    out[5] = (uint8_t)(n & 0xFF);
    out[6] = (uint8_t)(n >> 8);
    if (n) memcpy(out + kHeader, d, n);
    uint16_t crc = crc16(out + 2, kHeader - 2 + n);
    out[kHeader + n] = (uint8_t)(crc & 0xFF);
    out[kHeader + n + 1] = (uint8_t)(crc >> 8);
    return kHeader + n + 2;
}

int indexOf(const NimBLECharacteristic* chr) {
    for (size_t i = 0; i < charCount; i++) {
        if (chars[i].chr == chr) return (int)i;
    }
    return -1;
}

int indexOfId(uint16_t id) {
    for (size_t i = 0; i < charCount; i++) {
        if (chars[i].id == id) return (int)i;
    }
    return -1;
}

void reply(UsbLinkPort* p, uint8_t type, uint16_t id, const uint8_t* d, size_t n) {
    p->write(p->txFrame, encode(p->txFrame, type, id, d, n), p->ctx);
}

bool enqueue(UsbLinkPort* p, uint16_t id, const uint8_t* d, size_t n, TickType_t wait) {
    if (p->ring == nullptr || n > kMaxPayload) return false;
    void* slot = nullptr;
    if (xRingbufferSendAcquire(p->ring, &slot, kHeader + n + 2, wait) != pdTRUE) {
        p->dropped++;
        return false;
    }
    encode((uint8_t*)slot, kNotify, id, d, n);
    xRingbufferSendComplete(p->ring, slot);
    return true;
}

void setLink(UsbLinkPort* p, bool up) {
    if (p->up == up) return;
    p->up = up;
    if (!up) p->subscribed = 0;
    bool anyBefore;
    bool anyAfter;
    portENTER_CRITICAL(&upMux);
    anyBefore = portsUp != 0;
    portsUp = up ? (uint8_t)(portsUp + 1) : (uint8_t)(portsUp - 1);
    anyAfter = portsUp != 0;
    portEXIT_CRITICAL(&upMux);
    Serial.printf("[USB] link %s port=%s\n", up ? "up" : "down", p->name);
    if (anyBefore != anyAfter) bleGattUsbLinkChanged(anyAfter);
}

void sendHelloAck(UsbLinkPort* p) {
    uint8_t* s = p->scratch;
    s[0] = kProtoVersion;
    s[1] = (uint8_t)(kMaxPayload & 0xFF);
    s[2] = (uint8_t)(kMaxPayload >> 8);
    s[3] = (uint8_t)charCount;
    for (size_t i = 0; i < charCount; i++) {
        s[4 + i * 2] = (uint8_t)(chars[i].id & 0xFF);
        s[5 + i * 2] = (uint8_t)(chars[i].id >> 8);
    }
    reply(p, kHelloAck, 0, s, 4 + charCount * 2);
}

void handle(UsbLinkPort* port, uint8_t type, uint16_t id, const uint8_t* p, size_t n) {
    port->lastRxMs = millis();
    if (type == kHello) {
        port->subscribed = 0;
        sendHelloAck(port);
        setLink(port, true);
        return;
    }
    if (!port->up) return;
    if (type == kPing) {
        reply(port, kPong, 0, nullptr, 0);
        return;
    }
    int i = indexOfId(id);
    uint8_t status = i < 0 ? 1 : 0;
    switch (type) {
        case kWrite:
        case kWriteNoAck:
            if (i >= 0) {
                chars[i].chr->setValue(p, n);
                if (chars[i].cb) chars[i].cb->onWrite(chars[i].chr);
            }
            if (type == kWrite) reply(port, kWriteAck, id, &status, 1);
            break;
        case kRead: {
            if (i < 0) {
                reply(port, kReadRsp, id, &status, 1);
                break;
            }
            if (chars[i].cb) chars[i].cb->onRead(chars[i].chr);
            NimBLEAttValue v = chars[i].chr->getValue();
            size_t len = v.size() > kMaxPayload - 1 ? kMaxPayload - 1 : v.size();
            port->scratch[0] = 0;
            memcpy(port->scratch + 1, v.data(), len);
            reply(port, kReadRsp, id, port->scratch, len + 1);
            break;
        }
        case kSubscribe:
            if (i >= 0 && n >= 1) {
                if (p[0]) {
                    port->subscribed = port->subscribed | (1u << i);
                } else {
                    port->subscribed = port->subscribed & ~(1u << i);
                }
            } else {
                status = 1;
            }
            reply(port, kSubscribeAck, id, &status, 1);
            break;
        default:
            break;
    }
}

void feed(UsbLinkPort* p, uint8_t c) {
    uint8_t* f = p->rxFrame;
    if (p->rxLen == 0) {
        if (c == kSync0) f[p->rxLen++] = c;
        return;
    }
    if (p->rxLen == 1) {
        if (c == kSync1) {
            f[p->rxLen++] = c;
        } else if (c != kSync0) {
            p->rxLen = 0;
        }
        return;
    }
    f[p->rxLen++] = c;
    if (p->rxLen < kHeader) return;
    size_t n = (size_t)f[5] | ((size_t)f[6] << 8);
    if (n > kMaxPayload) {
        p->rxLen = 0;
        return;
    }
    if (p->rxLen < kHeader + n + 2) return;
    uint16_t want = (uint16_t)f[kHeader + n] | ((uint16_t)f[kHeader + n + 1] << 8);
    if (crc16(f + 2, kHeader - 2 + n) == want) {
        handle(p, f[2], (uint16_t)(f[3] | (f[4] << 8)), f + kHeader, n);
        p->lastRxMs = millis();
    }
    p->rxLen = 0;
}

size_t serialWrite(const uint8_t* d, size_t n, void*) {
    return Serial.write(d, n);
}

void linkTask(void* arg) {
    UsbLinkPort* port = (UsbLinkPort*)arg;
    uint8_t buf[256];
    for (;;) {
        int avail = Serial.available();
        while (avail > 0) {
            size_t want = avail > (int)sizeof(buf) ? sizeof(buf) : (size_t)avail;
            size_t got = Serial.read(buf, want);
            if (got == 0) break;
            usbLinkPortFeed(port, buf, got);
            avail = Serial.available();
        }
        usbLinkPortPump(port);
        vTaskDelay(1);
    }
}

}

void usbLinkRegister(NimBLECharacteristic* chr, OuispyCharacteristicCallbacks* cb) {
    if (chr == nullptr || charCount >= kMaxChars) return;
    std::string u = chr->getUUID().toString();
    chars[charCount].id = (uint16_t)strtoul(u.substr(0, 8).c_str(), nullptr, 16);
    chars[charCount].chr = chr;
    chars[charCount].cb = cb;
    charCount++;
}

UsbLinkPort* usbLinkPortCreate(const char* name, UsbLinkWriteFn write, void* ctx) {
    if (portCount >= kMaxPorts) return nullptr;
    UsbLinkPort* p = (UsbLinkPort*)calloc(1, sizeof(UsbLinkPort));
    if (p == nullptr) return nullptr;
    p->name = name;
    p->write = write;
    p->ctx = ctx;
    p->rxFrame = linkAlloc(kMaxFrame);
    p->txFrame = linkAlloc(kMaxFrame);
    p->scratch = linkAlloc(kMaxPayload);
    if (p->rxFrame == nullptr || p->txFrame == nullptr || p->scratch == nullptr) {
        Serial.printf("[USB] port %s disabled: no memory for frame buffers\n", name);
        return nullptr;
    }
    const char* where = "psram";
    uint8_t* storage = (uint8_t*)heap_caps_malloc(kRingPsram, MALLOC_CAP_SPIRAM);
    if (storage != nullptr) {
        p->ring = xRingbufferCreateStatic(kRingPsram, RINGBUF_TYPE_NOSPLIT, storage, &p->ringStruct);
        if (p->ring == nullptr) heap_caps_free(storage);
    }
    if (p->ring == nullptr) {
        where = "internal";
        p->ring = xRingbufferCreate(kRingInternal, RINGBUF_TYPE_NOSPLIT);
    }
    ports[portCount++] = p;
    Serial.printf("[USB] link ready port=%s chars=%u ring=%s\n", name, (unsigned)charCount,
                  p->ring ? where : "none");
    return p;
}

void usbLinkPortFeed(UsbLinkPort* port, const uint8_t* data, size_t len) {
    if (port == nullptr) return;
    for (size_t k = 0; k < len; k++) feed(port, data[k]);
}

void usbLinkPortPump(UsbLinkPort* port) {
    if (port == nullptr) return;
    size_t sz = 0;
    void* item = nullptr;
    while (port->ring && (item = xRingbufferReceive(port->ring, &sz, 0)) != nullptr) {
        if (port->up) port->write((const uint8_t*)item, sz, port->ctx);
        vRingbufferReturnItem(port->ring, item);
    }
    uint32_t now = millis();
    if (port->up && now - port->lastRxMs > kLinkTimeoutMs) setLink(port, false);
    if (port->dropped && now - port->lastDropLog > 10000) {
        port->lastDropLog = now;
        Serial.printf("[USB] port=%s tx dropped=%lu\n", port->name, (unsigned long)port->dropped);
    }
}

void usbLinkPortDown(UsbLinkPort* port) {
    if (port == nullptr) return;
    port->rxLen = 0;
    setLink(port, false);
}

void usbLinkInit(void) {
    UsbLinkPort* serial = usbLinkPortCreate("serial", serialWrite, nullptr);
    if (serial != nullptr) xTaskCreate(linkTask, "usbLink", 6144, serial, 3, nullptr);
#ifdef OUISPY_USB_NCM
    usbNcmInit();
#endif
}

bool usbLinkUp(void) {
    return portsUp != 0;
}

bool usbLinkSubscribed(const NimBLECharacteristic* chr) {
    if (portsUp == 0) return false;
    int i = indexOf(chr);
    if (i < 0) return false;
    for (size_t k = 0; k < portCount; k++) {
        if (ports[k]->up && (ports[k]->subscribed & (1u << i))) return true;
    }
    return false;
}

void usbLinkNotify(const NimBLECharacteristic* chr, const uint8_t* data, size_t len) {
    if (portsUp == 0) return;
    int i = indexOf(chr);
    if (i < 0) return;
    for (size_t k = 0; k < portCount; k++) {
        UsbLinkPort* p = ports[k];
        if (p->up && (p->subscribed & (1u << i))) enqueue(p, chars[i].id, data, len, 0);
    }
}

bool usbLinkSendBlocking(const NimBLECharacteristic* chr, const uint8_t* data, size_t len,
                         uint32_t timeoutMs) {
    int i = indexOf(chr);
    if (portsUp == 0 || i < 0) return false;
    bool ok = true;
    for (size_t k = 0; k < portCount; k++) {
        UsbLinkPort* p = ports[k];
        if (!p->up || !(p->subscribed & (1u << i))) continue;
        const uint8_t* d = data;
        size_t left = len;
        while (left > 0) {
            size_t n = left > kMaxPayload ? kMaxPayload : left;
            if (!enqueue(p, chars[i].id, d, n, pdMS_TO_TICKS(timeoutMs))) {
                ok = false;
                break;
            }
            d += n;
            left -= n;
        }
    }
    return ok;
}

#endif
