#ifndef USB_LINK_H
#define USB_LINK_H

#include <stddef.h>
#include <stdint.h>

#if defined(OUISPY_NIMBLE2_API) && defined(__cplusplus) && __has_include(<NimBLEDevice.h>)
#define OUISPY_USB_LINK 1

#define USB_LINK_RX_BUFFER 2048

void usbLinkRegister(NimBLECharacteristic* chr, OuispyCharacteristicCallbacks* cb);
void usbLinkInit(void);
bool usbLinkUp(void);
bool usbLinkSubscribed(const NimBLECharacteristic* chr);
void usbLinkNotify(const NimBLECharacteristic* chr, const uint8_t* data, size_t len);
bool usbLinkSendBlocking(const NimBLECharacteristic* chr, const uint8_t* data, size_t len,
                         uint32_t timeoutMs);

struct UsbLinkPort;
typedef size_t (*UsbLinkWriteFn)(const uint8_t* data, size_t len, void* ctx);
UsbLinkPort* usbLinkPortCreate(const char* name, UsbLinkWriteFn write, void* ctx);
void usbLinkPortFeed(UsbLinkPort* port, const uint8_t* data, size_t len);
void usbLinkPortPump(UsbLinkPort* port);
void usbLinkPortDown(UsbLinkPort* port);

#ifdef OUISPY_USB_NCM
void usbNcmInit(void);
#endif
#endif

#endif
