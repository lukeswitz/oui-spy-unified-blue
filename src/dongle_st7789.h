#ifndef DONGLE_ST7789_H
#define DONGLE_ST7789_H

#include <Arduino.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SPITFT.h>

#define DGX_BLACK   0x0000
#define DGX_WHITE   0xFFFF
#define DGX_RED     0xF800
#define DGX_GREEN   0x07E0
#define DGX_CYAN    0x07FF
#define DGX_MAGENTA 0xF81F
#define DGX_YELLOW  0xFFE0
#define DGX_LIME    0x9FE0
#define DGX_AMBER   0xFD20
#define DGX_BLUE    0x255F
#define DGX_SKY     0x5DFF
#define DGX_GREY    0x8410
#define DGX_DIM     0x39E7
#define DGX_SLATE   0x2124

#ifndef DONGLE_PANEL_W
#define DONGLE_PANEL_W 135
#endif
#ifndef DONGLE_PANEL_H
#define DONGLE_PANEL_H 240
#endif
#ifndef DONGLE_PANEL_OX
#define DONGLE_PANEL_OX 52
#endif
#ifndef DONGLE_PANEL_OY
#define DONGLE_PANEL_OY 40
#endif

class DongleST7789 : public Adafruit_SPITFT {
public:
    DongleST7789(SPIClass* spi, int8_t cs, int8_t dc, int8_t rst)
        : Adafruit_SPITFT(DONGLE_PANEL_W, DONGLE_PANEL_H, spi, cs, dc, rst) {}

    void begin(uint32_t freq = 40000000) override {
        invertOnCommand = 0x21;
        invertOffCommand = 0x20;
        initSPI(freq, SPI_MODE0);

        sendCommand(0x01);
        delay(150);
        sendCommand(0x11);
        delay(120);

        static const uint8_t colmod[] = {0x55};
        sendCommand(0x3A, colmod, 1);
        static const uint8_t gctrl[] = {0x35};
        sendCommand(0xB7, gctrl, 1);
        static const uint8_t vcoms[] = {0x28};
        sendCommand(0xBB, vcoms, 1);
        static const uint8_t lcmctrl[] = {0x0C};
        sendCommand(0xC0, lcmctrl, 1);
        static const uint8_t vdvvrhen[] = {0x01, 0xFF};
        sendCommand(0xC2, vdvvrhen, 2);
        static const uint8_t vrhs[] = {0x10};
        sendCommand(0xC3, vrhs, 1);
        static const uint8_t vdvset[] = {0x20};
        sendCommand(0xC4, vdvset, 1);
        static const uint8_t pwctrl1[] = {0xA4, 0xA1};
        sendCommand(0xD0, pwctrl1, 2);
        static const uint8_t ramctrl[] = {0x00, 0xC0};
        sendCommand(0xB0, ramctrl, 2);

        sendCommand(0x21);
        sendCommand(0x13);
        delay(10);
        sendCommand(0x29);
        delay(100);

        setRotation(0);
    }

    void setRotation(uint8_t m) override {
        rotation = m & 3;
        uint8_t madctl;
        switch (rotation) {
            case 1:
                madctl = 0x60 | 0x08;
                _width = DONGLE_PANEL_H; _height = DONGLE_PANEL_W;
                _xstart = DONGLE_PANEL_OY; _ystart = DONGLE_PANEL_OX;
                break;
            case 2:
                madctl = 0xC0 | 0x08;
                _width = DONGLE_PANEL_W; _height = DONGLE_PANEL_H;
                _xstart = DONGLE_PANEL_OX; _ystart = DONGLE_PANEL_OY;
                break;
            case 3:
                madctl = 0xA0 | 0x08;
                _width = DONGLE_PANEL_H; _height = DONGLE_PANEL_W;
                _xstart = DONGLE_PANEL_OY; _ystart = DONGLE_PANEL_OX;
                break;
            default:
                madctl = 0x00 | 0x08;
                _width = DONGLE_PANEL_W; _height = DONGLE_PANEL_H;
                _xstart = DONGLE_PANEL_OX; _ystart = DONGLE_PANEL_OY;
                break;
        }
        sendCommand(0x36, &madctl, 1);
    }

    void setAddrWindow(uint16_t x, uint16_t y, uint16_t w, uint16_t h) override {
        x += _xstart;
        y += _ystart;
        uint32_t xa = ((uint32_t)x << 16) | (uint32_t)(x + w - 1);
        uint32_t ya = ((uint32_t)y << 16) | (uint32_t)(y + h - 1);
        writeCommand(0x2A);
        SPI_WRITE32(xa);
        writeCommand(0x2B);
        SPI_WRITE32(ya);
        writeCommand(0x2C);
    }

};

#endif
