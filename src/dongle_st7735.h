#ifndef DONGLE_ST7735_H
#define DONGLE_ST7735_H

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

class DongleST7735 : public Adafruit_SPITFT {
public:
    DongleST7735(SPIClass* spi, int8_t cs, int8_t dc, int8_t rst)
        : Adafruit_SPITFT(80, 160, spi, cs, dc, rst) {}

    void begin(uint32_t freq = 27000000) override {
        invertOnCommand = 0x20;
        invertOffCommand = 0x21;
        initSPI(freq, SPI_MODE0);

        sendCommand(0x01);
        delay(150);
        sendCommand(0x11);
        delay(500);

        static const uint8_t frmctr[] = {0x01, 0x2C, 0x2D};
        sendCommand(0xB1, frmctr, 3);
        sendCommand(0xB2, frmctr, 3);
        static const uint8_t frmctr3[] = {0x01, 0x2C, 0x2D, 0x01, 0x2C, 0x2D};
        sendCommand(0xB3, frmctr3, 6);
        static const uint8_t invctr[] = {0x07};
        sendCommand(0xB4, invctr, 1);
        static const uint8_t pwctr1[] = {0xA2, 0x02, 0x84};
        sendCommand(0xC0, pwctr1, 3);
        static const uint8_t pwctr2[] = {0xC5};
        sendCommand(0xC1, pwctr2, 1);
        static const uint8_t pwctr3[] = {0x0A, 0x00};
        sendCommand(0xC2, pwctr3, 2);
        static const uint8_t pwctr4[] = {0x8A, 0x2A};
        sendCommand(0xC3, pwctr4, 2);
        static const uint8_t pwctr5[] = {0x8A, 0xEE};
        sendCommand(0xC4, pwctr5, 2);
        static const uint8_t vmctr1[] = {0x0E};
        sendCommand(0xC5, vmctr1, 1);
        static const uint8_t colmod[] = {0x05};
        sendCommand(0x3A, colmod, 1);

        sendCommand(0x21);
        static const uint8_t caset[] = {0x00, 0x00, 0x00, 0x4F};
        sendCommand(0x2A, caset, 4);
        static const uint8_t raset[] = {0x00, 0x00, 0x00, 0x9F};
        sendCommand(0x2B, raset, 4);

        static const uint8_t gmctrp1[] = {
            0x02, 0x1c, 0x07, 0x12, 0x37, 0x32, 0x29, 0x2d,
            0x29, 0x25, 0x2B, 0x39, 0x00, 0x01, 0x03, 0x10};
        sendCommand(0xE0, gmctrp1, 16);
        static const uint8_t gmctrn1[] = {
            0x03, 0x1d, 0x07, 0x06, 0x2E, 0x2C, 0x29, 0x2D,
            0x2E, 0x2E, 0x37, 0x3F, 0x00, 0x00, 0x02, 0x10};
        sendCommand(0xE1, gmctrn1, 16);

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
                madctl = 0x80 | 0x20 | 0x08;
                _width = 160; _height = 80;
                _xstart = kRowStart; _ystart = kColStart;
                break;
            case 2:
                madctl = 0x08;
                _width = 80; _height = 160;
                _xstart = kColStart; _ystart = kRowStart;
                break;
            case 3:
                madctl = 0x40 | 0x20 | 0x08;
                _width = 160; _height = 80;
                _xstart = kRowStart; _ystart = kColStart;
                break;
            default:
                madctl = 0x40 | 0x80 | 0x08;
                _width = 80; _height = 160;
                _xstart = kColStart; _ystart = kRowStart;
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

private:
    static const int16_t kColStart = 26;
    static const int16_t kRowStart = 1;
};

#endif
