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

#ifndef DONGLE_LED_DI
#define DONGLE_LED_DI 40
#endif
#ifndef DONGLE_LED_CI
#define DONGLE_LED_CI 39
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
