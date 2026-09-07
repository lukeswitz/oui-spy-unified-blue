#ifndef DONGLE_H
#define DONGLE_H

#include <stdint.h>
#include <FS.h>
#include "protocol.h"

#ifndef DONGLE_TFT_SCLK
#define DONGLE_TFT_SCLK 5
#endif
#ifndef DONGLE_TFT_MOSI
#define DONGLE_TFT_MOSI 3
#endif
#ifndef DONGLE_TFT_MISO
#define DONGLE_TFT_MISO -1
#endif
#ifndef DONGLE_TFT_DC
#define DONGLE_TFT_DC 2
#endif
#ifndef DONGLE_TFT_CS
#define DONGLE_TFT_CS 4
#endif
#ifndef DONGLE_TFT_RST
#define DONGLE_TFT_RST 1
#endif
#ifndef DONGLE_TFT_BL
#define DONGLE_TFT_BL 38
#endif
#ifndef DONGLE_TFT_BL_ON
#define DONGLE_TFT_BL_ON 0
#endif
#ifndef DONGLE_TFT_ROTATION
#define DONGLE_TFT_ROTATION 3
#endif
#ifndef DONGLE_TFT_HZ
#define DONGLE_TFT_HZ 27000000
#endif

#ifndef DONGLE_SD_HZ
#define DONGLE_SD_HZ 20000000
#endif

#ifndef DONGLE_BTN
#define DONGLE_BTN 0
#endif
#ifndef DONGLE_BTN_B
#define DONGLE_BTN_B -1
#endif
#ifndef DONGLE_BTN_PWR
#define DONGLE_BTN_PWR -1
#endif
#ifndef DONGLE_BTN_HOLD_MS
#define DONGLE_BTN_HOLD_MS 800
#endif

#ifndef DONGLE_LED_DI
#define DONGLE_LED_DI 40
#endif
#ifndef DONGLE_LED_CI
#define DONGLE_LED_CI 39
#endif

#ifndef DONGLE_LED_PIN
#define DONGLE_LED_PIN 10
#endif
#ifndef DONGLE_LED_ACTIVE_LOW
#define DONGLE_LED_ACTIVE_LOW 1
#endif

#ifndef DONGLE_PWR_HOLD
#define DONGLE_PWR_HOLD -1
#endif

#ifndef DONGLE_AXP_SDA
#define DONGLE_AXP_SDA 21
#endif
#ifndef DONGLE_AXP_SCL
#define DONGLE_AXP_SCL 22
#endif
#ifndef DONGLE_AXP_ADDR
#define DONGLE_AXP_ADDR 0x34
#endif

#ifndef DONGLE_WIGLE_BOARD
#define DONGLE_WIGLE_BOARD "T-Dongle"
#endif
#ifndef DONGLE_WIGLE_DEVICE
#define DONGLE_WIGLE_DEVICE ""
#endif

void dongleLedInit(void);
void dongleLedSet(uint8_t r, uint8_t g, uint8_t b);

void dongleInit(void);
void dongleTick(void);
void dongleOnDetection(const DetectionEvent* evt);
bool dongleSdReady(void);

fs::FS& dongleSpoolFs(void);

void donglePcapOpen(uint16_t linktype);
void donglePcapWriteFramed(const uint8_t* data, uint32_t len);
void donglePcapClose(void);

#endif
