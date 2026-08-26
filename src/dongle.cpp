#ifdef OUISPY_DONGLE

#include "dongle.h"
#include <Arduino.h>
#include <SPI.h>
#include <LittleFS.h>
#include "dongle_st7735.h"
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include "engine_registry.h"
#include "mesh_espnow.h"
#include "ble_gatt.h"

#ifdef DONGLE_SD_MMC
#include <SD_MMC.h>
#define DONGLE_SD SD_MMC
#else
#include <SD.h>
#define DONGLE_SD SD
#endif

#ifndef DONGLE_SPI_BUS
#define DONGLE_SPI_BUS FSPI
#endif

#define DONGLE_DIR       "/OUISPY"
#define DONGLE_SEQ_PATH  DONGLE_DIR "/seq.txt"
#define DONGLE_REDRAW_MS 400u
#define DONGLE_CSV_FLUSH_MS 4000u
#define DONGLE_COLS      26
#define DONGLE_ROWS      9

#define DONGLE_WIGLE_BOARD  "T-Dongle"

extern bool hwGpsUtc(uint32_t* epochOut);

static SPIClass s_spi(DONGLE_SPI_BUS);
static DongleST7735 s_tft(&s_spi, DONGLE_TFT_CS, DONGLE_TFT_DC, DONGLE_TFT_RST);
static bool s_tftReady = false;

static SemaphoreHandle_t s_sdMutex = nullptr;
static SemaphoreHandle_t s_ledMutex = nullptr;
static bool s_sdReady = false;
static uint16_t s_seq = 0;
static File s_detCsv;
static File s_wigleCsv;
static File s_pcapFile;
static uint32_t s_lastCsvFlush = 0;
static uint32_t s_pcapBytes = 0;
static uint16_t s_pcapIdx = 0;

static uint32_t s_hits = 0;
static uint32_t s_wifiHits = 0;
static uint32_t s_bleHits = 0;
static uint32_t s_wigleRows = 0;
static uint32_t s_lastDraw = 0;
static char s_lastLine[DONGLE_ROWS][DONGLE_COLS + 1];

#define DONGLE_FIELD_MAX 28

typedef struct {
    char     text[DONGLE_FIELD_MAX];
    uint16_t color;
} DongleField;

static DongleField s_fNode, s_fApp, s_fMesh, s_fSd, s_fGps;
static DongleField s_fWifi, s_fBle, s_fLog;
static DongleField s_fHit1, s_fHit2, s_fWd;
static DongleField s_fStrip[7];
static uint32_t s_wdStartMs = 0;
static uint16_t s_wifiIconColor = 1;
static uint16_t s_bleIconColor = 1;
static bool s_chromeDrawn = false;
static uint16_t s_engStripMask = 0xFFFF;
static bool s_btnDown = false;
static uint32_t s_btnChangeMs = 0;

#define DONGLE_SEEN_BYTES 2048
#define DONGLE_SEEN_BITS  (DONGLE_SEEN_BYTES * 8)

#define DONGLE_ENG_SEEN_BYTES 256
#define DONGLE_ENG_SEEN_BITS  (DONGLE_ENG_SEEN_BYTES * 8)

static uint8_t s_wifiSeen[DONGLE_SEEN_BYTES];
static uint8_t s_bleSeen[DONGLE_SEEN_BYTES];
static uint8_t s_engSeen[ENGINE_COUNT][DONGLE_ENG_SEEN_BYTES];
static uint32_t s_engCount[ENGINE_COUNT];

static uint32_t macHash(const uint8_t* mac) {
    uint32_t h = 2166136261u;
    for (int i = 0; i < 6; i++) {
        h ^= mac[i];
        h *= 16777619u;
    }
    return h;
}

static bool markSeen(uint8_t* set, uint32_t bits, const uint8_t* mac) {
    uint32_t h1 = macHash(mac);
    uint32_t h2 = (h1 ^ (h1 >> 13)) * 2654435761u;
    uint32_t i1 = h1 % bits;
    uint32_t i2 = h2 % bits;
    uint8_t m1 = (uint8_t)(1u << (i1 & 7));
    uint8_t m2 = (uint8_t)(1u << (i2 & 7));
    bool had = (set[i1 >> 3] & m1) && (set[i2 >> 3] & m2);
    set[i1 >> 3] |= m1;
    set[i2 >> 3] |= m2;
    return !had;
}

static uint8_t  s_ledR = 255, s_ledG = 255, s_ledB = 255;
static uint32_t s_ledFlashUntil = 0;
static uint32_t s_ledFlashStart = 0;
static uint16_t s_ledFlashStepMs = 70;
static uint8_t  s_ledFlashR = 0, s_ledFlashG = 0, s_ledFlashB = 0;

typedef struct {
    uint8_t r, g, b;
    uint8_t pulses;
    uint16_t stepMs;
} DongleLedPattern;

static const DongleLedPattern kEngLed[ENGINE_COUNT] = {
    { 90, 60,  0, 2, 70 },
    {  0, 30, 90, 2, 70 },
    { 20, 90,  0, 2, 70 },
    { 90,  0, 60, 1, 40 },
    {  0, 80, 90, 3, 60 },
    { 90,  0,  0, 3, 90 },
    { 40, 40, 40, 1, 50 },
    { 90, 80,  0, 1, 90 },
};

static char s_hitEng[10] = "";
static char s_hitMac[18] = "";
static char s_hitName[DONGLE_COLS + 1] = "";
static int8_t s_hitRssi = 0;
static uint8_t s_hitChan = 0;
static bool s_haveHit = false;

static uint32_t s_epochBase = 0;
static uint32_t s_epochBaseMs = 0;
static bool s_stamped = false;
static char s_stampStr[16] = "";

static const char kEngLetter[ENGINE_COUNT] = { 'D', 'B', 'F', 'X', 'S', 'U', 'W', 'P' };

static const char* wigleDevice(void) {
    return strstr(OUISPY_BOARD, "c5") != nullptr ? "ESP32-C5" : "ESP32-S3";
}

static const char* engShortName(uint8_t id) {
    switch ((EngineId)id) {
        case ENGINE_DETECTOR:   return "DETECT";
        case ENGINE_FLOCK_BLE:  return "FLOCKB";
        case ENGINE_FLOCK_WIFI: return "FLOCKW";
        case ENGINE_FOXHUNTER:  return "FOXHNT";
        case ENGINE_SKYSPY:     return "SKYSPY";
        case ENGINE_UNIPWN:     return "UNIPWN";
        case ENGINE_WARDRIVE:   return "WARDRV";
        case ENGINE_PCAP:       return "PCAP";
        default:                return "?";
    }
}

static void sdLock(void)   { if (s_sdMutex) xSemaphoreTake(s_sdMutex, portMAX_DELAY); }
static void sdUnlock(void) { if (s_sdMutex) xSemaphoreGive(s_sdMutex); }

static void apa102Byte(uint8_t b) {
    for (int i = 0; i < 8; i++) {
        digitalWrite(DONGLE_LED_DI, (b & 0x80) ? HIGH : LOW);
        digitalWrite(DONGLE_LED_CI, HIGH);
        b = (uint8_t)(b << 1);
        digitalWrite(DONGLE_LED_CI, LOW);
    }
}

void dongleLedInit(void) {
    if (!s_ledMutex) s_ledMutex = xSemaphoreCreateMutex();
    pinMode(DONGLE_LED_DI, OUTPUT);
    pinMode(DONGLE_LED_CI, OUTPUT);
    digitalWrite(DONGLE_LED_DI, LOW);
    digitalWrite(DONGLE_LED_CI, LOW);
    dongleLedSet(0, 0, 0);
}

void dongleLedSet(uint8_t r, uint8_t g, uint8_t b) {
    uint8_t bright = (uint8_t)(hwNeopixelBrightness >> 3);
    if (bright == 0) bright = 1;
    if (bright > 31) bright = 31;
    if (s_ledMutex) xSemaphoreTake(s_ledMutex, portMAX_DELAY);
    for (int i = 0; i < 4; i++) apa102Byte(0x00);
    apa102Byte((uint8_t)(0xE0 | bright));
    apa102Byte(b);
    apa102Byte(g);
    apa102Byte(r);
    for (int i = 0; i < 4; i++) apa102Byte(0xFF);
    if (s_ledMutex) xSemaphoreGive(s_ledMutex);
}

static bool utcNow(uint32_t* out) {
    int64_t ts = (int64_t)currentGps.timestamp_ms;
    uint32_t now = millis();
    if (ts > 1577836800000LL && ts < 4102444800000LL) {
        s_epochBase = (uint32_t)(ts / 1000);
        s_epochBaseMs = now;
    } else if (s_epochBase == 0) {
        uint32_t e = 0;
        if (hwGpsUtc(&e)) {
            s_epochBase = e;
            s_epochBaseMs = now;
        }
    }
    if (s_epochBase == 0) return false;
    uint32_t e = s_epochBase + (now - s_epochBaseMs) / 1000u;
    if (e < 1577836800u || e > 4102444800u) return false;
    *out = e;
    return true;
}

static void fmtUtc(uint32_t epoch, char* out, size_t len) {
    uint32_t days = epoch / 86400u;
    uint32_t rem  = epoch % 86400u;
    uint32_t hh = rem / 3600u, mm = (rem % 3600u) / 60u, ss = rem % 60u;
    int32_t z = (int32_t)days + 719468;
    int32_t era = (z >= 0 ? z : z - 146096) / 146097;
    uint32_t doe = (uint32_t)(z - era * 146097);
    uint32_t yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    int32_t y = (int32_t)yoe + era * 400;
    uint32_t doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    uint32_t mp = (5 * doy + 2) / 153;
    uint32_t d = doy - (153 * mp + 2) / 5 + 1;
    uint32_t m = mp + (mp < 10 ? 3 : -9);
    if (m <= 2) y++;
    snprintf(out, len, "%04d-%02u-%02u %02u:%02u:%02u",
             (int)y, (unsigned)m, (unsigned)d,
             (unsigned)hh, (unsigned)mm, (unsigned)ss);
}

static void csvEscape(const char* in, char* out, size_t outLen) {
    bool quote = false;
    for (const char* p = in; *p; p++) {
        if (*p == ',' || *p == '"' || *p == '\n' || *p == '\r') { quote = true; break; }
    }
    size_t o = 0;
    if (quote && o + 1 < outLen) out[o++] = '"';
    for (const char* p = in; *p && o + 2 < outLen; p++) {
        if (*p == '"' && quote) {
            if (o + 3 >= outLen) break;
            out[o++] = '"';
        }
        out[o++] = *p;
    }
    if (quote && o + 1 < outLen) out[o++] = '"';
    out[o] = '\0';
}

static const char* wigleAuth(const DetectionEvent* e, bool isBle) {
    if (isBle) return "[LE]";
    switch (e->ext.wardrive.auth_mode) {
        case 0: return "[OPEN]";
        case 1: return "[WEP]";
        case 2: return "[WPA_PSK]";
        case 3: return "[WPA2_PSK]";
        case 4: return "[WPA_WPA2_PSK]";
        case 5: return "[WPA2_EAP]";
        case 6: return "[WPA3_SAE]";
        default: return "[WPA2_PSK]";
    }
}

static uint32_t chanToFreq(uint8_t ch) {
    if (ch >= 1 && ch <= 13) return 2407u + ch * 5u;
    if (ch == 14) return 2484u;
    if (ch >= 36 && ch <= 177) return 5000u + ch * 5u;
    return 0u;
}

static uint16_t nextSeq(void) {
    uint16_t n = 1;
    File f = DONGLE_SD.open(DONGLE_SEQ_PATH, FILE_READ);
    if (f) {
        char buf[12] = {0};
        size_t got = f.read((uint8_t*)buf, sizeof(buf) - 1);
        buf[got] = '\0';
        long v = atol(buf);
        if (v > 0 && v < 65535) n = (uint16_t)(v + 1);
        f.close();
    }
    File w = DONGLE_SD.open(DONGLE_SEQ_PATH, FILE_WRITE);
    if (w) {
        w.printf("%u", (unsigned)n);
        w.close();
    }
    return n;
}

static void openCsvFiles(void) {
    char path[48];
    snprintf(path, sizeof(path), DONGLE_DIR "/det_%04u.csv", (unsigned)s_seq);
    s_detCsv = DONGLE_SD.open(path, FILE_WRITE);
    if (s_detCsv) {
        s_detCsv.println("timestamp_ms,utc,engine,method,mac,rssi,channel,name,"
                         "lat,lon,alt,acc,node");
        s_detCsv.flush();
    }

    snprintf(path, sizeof(path), DONGLE_DIR "/wigle_%04u.csv", (unsigned)s_seq);
    s_wigleCsv = DONGLE_SD.open(path, FILE_WRITE);
    if (s_wigleCsv) {
        s_wigleCsv.printf("WigleWifi-1.6,appRelease=%s,model=OUI-SPY,release=%s,"
                          "device=%s,display=firmware,board=%s,brand=colonelpanic,"
                          "star=Sol,body=3,subBody=0\n",
                          FW_VERSION, FW_VERSION, wigleDevice(), DONGLE_WIGLE_BOARD);
        s_wigleCsv.println("MAC,SSID,AuthMode,FirstSeen,Channel,Frequency,RSSI,"
                           "CurrentLatitude,CurrentLongitude,AltitudeMeters,"
                           "AccuracyMeters,RCOIs,MfgrId,Type");
        s_wigleCsv.flush();
    }
}

static void stampFileNames(void) {
    if (!s_sdReady || s_stamped) return;
    uint32_t epoch = 0;
    if (!utcNow(&epoch)) return;
    s_stamped = true;

    char stamp[20];
    fmtUtc(epoch, stamp, sizeof(stamp));
    char compact[16];
    snprintf(compact, sizeof(compact), "%c%c%c%c%c%c%c%c_%c%c%c%c%c%c",
             stamp[0], stamp[1], stamp[2], stamp[3], stamp[5], stamp[6],
             stamp[8], stamp[9], stamp[11], stamp[12], stamp[14], stamp[15],
             stamp[17], stamp[18]);

    char oldPath[48], newPath[56];
    sdLock();
    if (s_detCsv) s_detCsv.close();
    if (s_wigleCsv) s_wigleCsv.close();

    snprintf(oldPath, sizeof(oldPath), DONGLE_DIR "/det_%04u.csv", (unsigned)s_seq);
    snprintf(newPath, sizeof(newPath), DONGLE_DIR "/det_%s.csv", compact);
    if (DONGLE_SD.rename(oldPath, newPath)) {
        s_detCsv = DONGLE_SD.open(newPath, FILE_APPEND);
    } else {
        s_detCsv = DONGLE_SD.open(oldPath, FILE_APPEND);
    }

    snprintf(oldPath, sizeof(oldPath), DONGLE_DIR "/wigle_%04u.csv", (unsigned)s_seq);
    snprintf(newPath, sizeof(newPath), DONGLE_DIR "/wigle_%s.csv", compact);
    if (DONGLE_SD.rename(oldPath, newPath)) {
        s_wigleCsv = DONGLE_SD.open(newPath, FILE_APPEND);
    } else {
        s_wigleCsv = DONGLE_SD.open(oldPath, FILE_APPEND);
    }
    sdUnlock();

    snprintf(s_stampStr, sizeof(s_stampStr), "%s", compact);
    Serial.printf("[DONGLE] files stamped %s\n", compact);
}

static bool sdMount(void) {
#ifdef DONGLE_SD_MMC
    SD_MMC.setPins(DONGLE_SD_CLK, DONGLE_SD_CMD, DONGLE_SD_D0,
                   DONGLE_SD_D1, DONGLE_SD_D2, DONGLE_SD_D3);
    if (!SD_MMC.begin("/sdcard", false)) return false;
#else
    if (!SD.begin(DONGLE_SD_CS, s_spi, DONGLE_SD_HZ)) return false;
#endif
    if (!DONGLE_SD.exists(DONGLE_DIR)) DONGLE_SD.mkdir(DONGLE_DIR);
    return true;
}

static void tftLine(uint8_t row, const char* text, uint16_t color) {
    if (!s_tftReady || row >= DONGLE_ROWS) return;
    char padded[DONGLE_COLS + 1];
    size_t n = strlen(text);
    if (n > DONGLE_COLS) n = DONGLE_COLS;
    memcpy(padded, text, n);
    memset(padded + n, ' ', DONGLE_COLS - n);
    padded[DONGLE_COLS] = '\0';
    if (strcmp(padded, s_lastLine[row]) == 0) return;
    strcpy(s_lastLine[row], padded);
    s_tft.setTextColor(color, DGX_BLACK);
    s_tft.setCursor(0, row * 8);
    s_tft.print(padded);
}

static void fld(DongleField* f, int16_t x, int16_t y, uint8_t size,
                uint16_t color, uint8_t width, const char* text) {
    if (!s_tftReady) return;
    char buf[DONGLE_FIELD_MAX];
    if (width >= sizeof(buf)) width = sizeof(buf) - 1;
    size_t n = strlen(text);
    if (n > width) n = width;
    memcpy(buf, text, n);
    memset(buf + n, ' ', width - n);
    buf[width] = '\0';
    if (color == f->color && strcmp(buf, f->text) == 0) return;
    f->color = color;
    strcpy(f->text, buf);
    s_tft.setTextSize(size);
    s_tft.setTextColor(color, DGX_BLACK);
    s_tft.setCursor(x, y);
    s_tft.print(buf);
    s_tft.setTextSize(1);
}

static void fmtCount(uint32_t v, char* out, size_t len) {
    if (v < 10000u)        snprintf(out, len, "%lu", (unsigned long)v);
    else if (v < 1000000u) snprintf(out, len, "%luk", (unsigned long)(v / 1000u));
    else                   snprintf(out, len, "%luM", (unsigned long)(v / 1000000u));
}

static void drawWifiIcon(int16_t x, int16_t y, uint16_t color) {
    if (color == s_wifiIconColor) return;
    s_wifiIconColor = color;
    s_tft.fillRect(x, y, 20, 17, DGX_BLACK);
    int16_t cx = x + 9, cy = y + 15;
    for (int16_t r = 4; r <= 10; r += 3) {
        for (int16_t dx = -r; dx <= r; dx++) {
            int16_t dy = (int16_t)(sqrtf((float)(r * r - dx * dx)) + 0.5f);
            if (dy < (r >> 1)) continue;
            s_tft.drawPixel(cx + dx, cy - dy, color);
        }
    }
    s_tft.fillRect(cx - 1, cy - 1, 2, 2, color);
}

static void drawBleIcon(int16_t x, int16_t y, uint16_t color) {
    if (color == s_bleIconColor) return;
    s_bleIconColor = color;
    s_tft.fillRect(x, y, 12, 15, DGX_BLACK);
    int16_t cx = x + 5;
    s_tft.drawLine(cx, y + 1, cx, y + 13, color);
    s_tft.drawLine(cx, y + 1, cx + 4, y + 4, color);
    s_tft.drawLine(cx + 4, y + 4, cx - 3, y + 10, color);
    s_tft.drawLine(cx, y + 13, cx + 4, y + 10, color);
    s_tft.drawLine(cx + 4, y + 10, cx - 3, y + 4, color);
}

static void tag(DongleField* f, int16_t x, const char* text, bool ok, uint16_t okColor) {
    fld(f, x, 2, 1, ok ? okColor : DGX_DIM, 3, text);
}

static void iconDetector(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawCircle(x + 6, y + 5, 4, c);
    s_tft.drawLine(x + 9, y + 8, x + 13, y + 12, c);
    s_tft.drawLine(x + 8, y + 9, x + 12, y + 13, c);
}

static void iconFlockBle(int16_t x, int16_t y, uint16_t c) {
    int16_t cx = x + 6;
    s_tft.drawLine(cx, y + 1, cx, y + 12, c);
    s_tft.drawLine(cx, y + 1, cx + 4, y + 4, c);
    s_tft.drawLine(cx + 4, y + 4, cx - 3, y + 9, c);
    s_tft.drawLine(cx, y + 12, cx + 4, y + 9, c);
    s_tft.drawLine(cx + 4, y + 9, cx - 3, y + 4, c);
}

static void iconFlockWifi(int16_t x, int16_t y, uint16_t c) {
    int16_t cx = x + 7, cy = y + 12;
    for (int16_t r = 4; r <= 10; r += 3) {
        for (int16_t dx = -r; dx <= r; dx++) {
            int16_t dy = (int16_t)(sqrtf((float)(r * r - dx * dx)) + 0.5f);
            if (dy < (r >> 1)) continue;
            s_tft.drawPixel(cx + dx, cy - dy, c);
        }
    }
    s_tft.fillRect(cx - 1, cy - 1, 2, 2, c);
}

static void iconFoxhunter(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawCircle(x + 7, y + 7, 5, c);
    s_tft.drawFastHLine(x + 0, y + 7, 14, c);
    s_tft.drawFastVLine(x + 7, y + 0, 14, c);
}

static void iconSkyspy(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawLine(x + 2, y + 2, x + 12, y + 11, c);
    s_tft.drawLine(x + 12, y + 2, x + 2, y + 11, c);
    s_tft.drawCircle(x + 2, y + 2, 2, c);
    s_tft.drawCircle(x + 12, y + 2, 2, c);
    s_tft.drawCircle(x + 2, y + 11, 2, c);
    s_tft.drawCircle(x + 12, y + 11, 2, c);
}

static void iconUnipwn(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawRect(x + 2, y + 2, 11, 9, c);
    s_tft.fillRect(x + 5, y + 5, 2, 2, c);
    s_tft.fillRect(x + 9, y + 5, 2, 2, c);
    s_tft.drawFastHLine(x + 5, y + 9, 6, c);
    s_tft.drawFastVLine(x + 7, y + 0, 2, c);
}

static void iconWardrive(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawFastHLine(x + 1, y + 9, 13, c);
    s_tft.drawLine(x + 1, y + 9, x + 3, y + 4, c);
    s_tft.drawLine(x + 3, y + 4, x + 11, y + 4, c);
    s_tft.drawLine(x + 11, y + 4, x + 14, y + 9, c);
    s_tft.drawCircle(x + 4, y + 11, 2, c);
    s_tft.drawCircle(x + 11, y + 11, 2, c);
}

static void iconPcap(int16_t x, int16_t y, uint16_t c) {
    s_tft.drawFastVLine(x + 7, y + 1, 7, c);
    s_tft.drawLine(x + 3, y + 5, x + 7, y + 9, c);
    s_tft.drawLine(x + 11, y + 5, x + 7, y + 9, c);
    s_tft.drawFastHLine(x + 1, y + 12, 13, c);
}

static void drawEngineIcon(uint8_t id, int16_t x, int16_t y, uint16_t c) {
    switch ((EngineId)id) {
        case ENGINE_DETECTOR:   iconDetector(x, y, c);   break;
        case ENGINE_FLOCK_BLE:  iconFlockBle(x, y, c);   break;
        case ENGINE_FLOCK_WIFI: iconFlockWifi(x, y, c);  break;
        case ENGINE_FOXHUNTER:  iconFoxhunter(x, y, c);  break;
        case ENGINE_SKYSPY:     iconSkyspy(x, y, c);     break;
        case ENGINE_UNIPWN:     iconUnipwn(x, y, c);     break;
        case ENGINE_WARDRIVE:   iconWardrive(x, y, c);   break;
        case ENGINE_PCAP:       iconPcap(x, y, c);       break;
        default: break;
    }
}

static const uint16_t kEngColor[ENGINE_COUNT] = {
    DGX_AMBER, DGX_RED, DGX_RED, DGX_MAGENTA,
    DGX_CYAN, DGX_YELLOW, DGX_WHITE, DGX_SKY
};

#define DONGLE_STRIP_N 7
static const uint8_t kStripEngines[DONGLE_STRIP_N] = {
    ENGINE_DETECTOR, ENGINE_FLOCK_BLE, ENGINE_FLOCK_WIFI, ENGINE_FOXHUNTER,
    ENGINE_SKYSPY, ENGINE_UNIPWN, ENGINE_PCAP
};

static void drawEngineStrip(uint8_t mask) {
    char buf[8];
    bool redrawIcons = (mask != s_engStripMask);
    s_engStripMask = mask;
    for (int i = 0; i < DONGLE_STRIP_N; i++) {
        uint8_t eid = kStripEngines[i];
        int16_t x = (int16_t)(3 + i * 22);
        bool on = (mask & (1 << eid)) != 0;
        uint16_t col = on ? kEngColor[eid] : DGX_SLATE;
        if (redrawIcons) {
            s_tft.fillRect(x, 57, 20, 13, DGX_BLACK);
            drawEngineIcon(eid, x + 3, 57, col);
        }
        uint32_t n = s_engCount[eid];
        if (n == 0)          buf[0] = '\0';
        else if (n < 1000u)  snprintf(buf, sizeof(buf), "%lu", (unsigned long)n);
        else if (n < 100000u) snprintf(buf, sizeof(buf), "%luk", (unsigned long)(n / 1000u));
        else                 snprintf(buf, sizeof(buf), "99k");
        fld(&s_fStrip[i], x + 1, 71, 1, n ? col : DGX_SLATE, 3, buf);
    }
}

static void tftDraw(void) {
    if (!s_tftReady) return;
    char buf[40];

    bool phone = bleGattIsConnected();
    bool mgr   = meshManagerJoined();
    uint8_t mask = engineGetActiveMask();

    fld(&s_fNode, 2, 2, 1, phone ? DGX_WHITE : DGX_GREY, 4, meshGetLocalNodeId());
    tag(&s_fApp,  74, "APP", phone, DGX_LIME);
    tag(&s_fMesh, 96, "MSH", mgr,   DGX_CYAN);
    fld(&s_fSd,  118, 2, 1, s_sdReady ? DGX_LIME : DGX_RED,   3, "SD");
    fld(&s_fGps, 136, 2, 1, gpsValid  ? DGX_LIME : DGX_AMBER, 3, "GPS");

    if (!s_chromeDrawn) {
        s_chromeDrawn = true;
        s_tft.drawFastHLine(0, 11, 160, DGX_SLATE);
        s_tft.drawRect(0, 12, 102, 43, DGX_SLATE);
        s_tft.drawFastHLine(2, 36, 98, DGX_SLATE);
        s_tft.drawRect(102, 12, 58, 43, DGX_SLATE);
        s_tft.drawFastHLine(0, 55, 160, DGX_SLATE);
    }

    const uint8_t wifiMask = (1 << ENGINE_FLOCK_WIFI) | (1 << ENGINE_WARDRIVE) |
                             (1 << ENGINE_PCAP) | (1 << ENGINE_SKYSPY);
    const uint8_t bleMask  = (1 << ENGINE_FLOCK_BLE) | (1 << ENGINE_UNIPWN) |
                             (1 << ENGINE_DETECTOR) | (1 << ENGINE_FOXHUNTER);
    drawWifiIcon(3, 14, (mask & wifiMask) ? DGX_LIME : DGX_GREY);
    drawBleIcon(7, 38, (mask & bleMask) ? DGX_SKY : DGX_GREY);

    fmtCount(s_wifiHits, buf, sizeof(buf));
    fld(&s_fWifi, 28, 12, 3, DGX_LIME, 4, buf);

    fmtCount(s_bleHits, buf, sizeof(buf));
    fld(&s_fBle, 28, 39, 2, DGX_SKY, 4, buf);

    uint8_t sats = currentGps.satellite_count;
    if (gpsValid) snprintf(buf, sizeof(buf), "SAT %u", (unsigned)sats);
    else          snprintf(buf, sizeof(buf), "NO FIX");
    fld(&s_fHit1, 106, 14, 1,
        !gpsValid ? DGX_RED : (sats >= 5 ? DGX_LIME : DGX_AMBER), 8, buf);

    if (!s_sdReady)          snprintf(buf, sizeof(buf), "NO SD");
    else if (s_pcapBytes)    snprintf(buf, sizeof(buf), "CAP %luk", (unsigned long)(s_pcapBytes / 1024u));
    else if (!gpsValid)      snprintf(buf, sizeof(buf), "LOG --");
    else                     snprintf(buf, sizeof(buf), "LOG %lu", (unsigned long)s_wigleRows);
    fld(&s_fHit2, 106, 24, 1,
        !s_sdReady ? DGX_RED : s_pcapBytes ? DGX_MAGENTA : (gpsValid ? DGX_AMBER : DGX_GREY), 8, buf);

    float mph = currentGps.speed * 2.23694f;
    if (gpsValid) snprintf(buf, sizeof(buf), "%dmph", (int)(mph + 0.5f));
    else          snprintf(buf, sizeof(buf), "--mph");
    fld(&s_fLog, 106, 34, 1, gpsValid ? DGX_WHITE : DGX_SLATE, 8, buf);

    bool wdOn = (mask & (1 << ENGINE_WARDRIVE)) != 0;
    if (wdOn && s_wdStartMs == 0) s_wdStartMs = millis();
    if (!wdOn) s_wdStartMs = 0;
    if (wdOn) {
        uint32_t secs = (millis() - s_wdStartMs) / 1000u;
        if (secs >= 3600u) snprintf(buf, sizeof(buf), "%luh%02lu",
                                    (unsigned long)(secs / 3600u),
                                    (unsigned long)((secs % 3600u) / 60u));
        else               snprintf(buf, sizeof(buf), "%lu:%02lu",
                                    (unsigned long)(secs / 60u),
                                    (unsigned long)(secs % 60u));
    } else {
        snprintf(buf, sizeof(buf), "idle");
    }
    fld(&s_fWd, 106, 44, 1, wdOn ? DGX_LIME : DGX_SLATE, 8, buf);

    drawEngineStrip(mask);
}

static void ledApply(uint8_t r, uint8_t g, uint8_t b) {
    if (r == s_ledR && g == s_ledG && b == s_ledB) return;
    s_ledR = r; s_ledG = g; s_ledB = b;
    dongleLedSet(r, g, b);
}

static void ledTick(uint32_t now) {
    if (!hwLedEnabled) { ledApply(0, 0, 0); return; }

    if (s_ledFlashUntil && (int32_t)(now - s_ledFlashUntil) < 0) {
        uint32_t phase = (now - s_ledFlashStart) / (s_ledFlashStepMs ? s_ledFlashStepMs : 70u);
        if (phase & 1u) ledApply(0, 0, 0);
        else            ledApply(s_ledFlashR, s_ledFlashG, s_ledFlashB);
        return;
    }
    s_ledFlashUntil = 0;

    if (engineGetActiveMask()) {
        ledApply(0, 6, 1);
        return;
    }
    ledApply(0, 0, 0);
}

static void buttonTick(uint32_t now) {
    bool down = digitalRead(DONGLE_BTN) == LOW;
    if (down == s_btnDown) { s_btnChangeMs = now; return; }
    if (now - s_btnChangeMs < 40u) return;
    s_btnChangeMs = now;
    s_btnDown = down;
    if (!down) return;

    bool running = engineGetState(ENGINE_WARDRIVE) != ESTATE_DISABLED;
    if (running) {
        engineDisable(ENGINE_WARDRIVE);
        Serial.println("[DONGLE] button -> wardrive stop");
    } else {
        engineEnable(ENGINE_WARDRIVE);
        Serial.println("[DONGLE] button -> wardrive start");
    }
    s_ledFlashR = 60; s_ledFlashG = 60; s_ledFlashB = 60;
    s_ledFlashUntil = now + 150u;
}

void dongleInit(void) {
    if (!s_sdMutex) s_sdMutex = xSemaphoreCreateMutex();

    pinMode(DONGLE_BTN, INPUT_PULLUP);
    s_btnDown = digitalRead(DONGLE_BTN) == LOW;
    pinMode(DONGLE_TFT_BL, OUTPUT);
    digitalWrite(DONGLE_TFT_BL, !DONGLE_TFT_BL_ON);
    s_spi.begin(DONGLE_TFT_SCLK, DONGLE_TFT_MISO, DONGLE_TFT_MOSI, -1);
    s_tft.begin(DONGLE_TFT_HZ);
    s_tft.setRotation(DONGLE_TFT_ROTATION);
    s_tft.fillScreen(DGX_BLACK);
    s_tft.setTextSize(1);
    s_tft.setTextWrap(false);
    memset(s_lastLine, 0, sizeof(s_lastLine));
    s_tftReady = true;
    digitalWrite(DONGLE_TFT_BL, DONGLE_TFT_BL_ON);

    tftLine(0, "OUI-SPY " FW_VERSION, DGX_CYAN);
    tftLine(1, OUISPY_BOARD, DGX_WHITE);

    sdLock();
    s_sdReady = sdMount();
    if (s_sdReady) {
        s_seq = nextSeq();
        openCsvFiles();
    }
    sdUnlock();

    Serial.printf("[DONGLE] tft ready sd=%d seq=%u\n", s_sdReady ? 1 : 0, (unsigned)s_seq);
    if (s_sdReady) {
        Serial.printf("[DONGLE] SD %lluMB det=%d wigle=%d\n",
                      (unsigned long long)(DONGLE_SD.cardSize() / (1024ULL * 1024ULL)),
                      s_detCsv ? 1 : 0, s_wigleCsv ? 1 : 0);
    }
    memset(s_lastLine, 0, sizeof(s_lastLine));
    s_tft.fillScreen(DGX_BLACK);
    memset(&s_fNode, 0, sizeof(s_fNode)); memset(&s_fApp, 0, sizeof(s_fApp));
    memset(&s_fMesh, 0, sizeof(s_fMesh)); memset(&s_fSd, 0, sizeof(s_fSd));
    memset(&s_fGps, 0, sizeof(s_fGps));   memset(&s_fWifi, 0, sizeof(s_fWifi));
    memset(&s_fBle, 0, sizeof(s_fBle));   memset(&s_fLog, 0, sizeof(s_fLog));
    memset(&s_fHit1, 0, sizeof(s_fHit1)); memset(&s_fHit2, 0, sizeof(s_fHit2));
    s_wifiIconColor = 1;
    s_bleIconColor = 1;
    s_chromeDrawn = false;
    s_engStripMask = 0xFFFF;
    tftDraw();
}

bool dongleSdReady(void) { return s_sdReady; }

fs::FS& dongleSpoolFs(void) {
    if (s_sdReady) return DONGLE_SD;
    return LittleFS;
}

void dongleOnDetection(const DetectionEvent* evt) {
    if (!evt) return;
    s_hits++;

    bool isBle = (evt->engine_id == ENGINE_FLOCK_BLE ||
                  evt->engine_id == ENGINE_UNIPWN ||
                  evt->channel == 0);
    const char* name = "";
    if (evt->engine_id == ENGINE_WARDRIVE)
        name = isBle ? evt->ext.wardrive.device_name : evt->ext.wardrive.ssid;
    else if (evt->engine_id == ENGINE_FLOCK_BLE || evt->engine_id == ENGINE_FLOCK_WIFI)
        name = evt->ext.flock.name;
    else if (evt->engine_id == ENGINE_SKYSPY)
        name = evt->ext.odid.uav_id;
    else if (evt->engine_id == ENGINE_DETECTOR)
        name = evt->ext.detector.filter_desc;

    snprintf(s_hitEng, sizeof(s_hitEng), "%s", engShortName(evt->engine_id));
    snprintf(s_hitMac, sizeof(s_hitMac), "%02X:%02X:%02X:%02X:%02X:%02X",
             evt->mac[0], evt->mac[1], evt->mac[2],
             evt->mac[3], evt->mac[4], evt->mac[5]);
    snprintf(s_hitName, sizeof(s_hitName), "%s", name);
    s_hitRssi = evt->rssi;
    s_hitChan = evt->channel;
    s_haveHit = true;

    if (isBle) {
        if (markSeen(s_bleSeen, DONGLE_SEEN_BITS, evt->mac)) s_bleHits++;
    } else {
        if (markSeen(s_wifiSeen, DONGLE_SEEN_BITS, evt->mac)) s_wifiHits++;
    }
    if (evt->engine_id < ENGINE_COUNT &&
        markSeen(s_engSeen[evt->engine_id], DONGLE_ENG_SEEN_BITS, evt->mac)) {
        s_engCount[evt->engine_id]++;
    }

    uint8_t eid = evt->engine_id < ENGINE_COUNT ? evt->engine_id : ENGINE_WARDRIVE;
    const DongleLedPattern* pat = &kEngLed[eid];
    s_ledFlashR = pat->r; s_ledFlashG = pat->g; s_ledFlashB = pat->b;
    s_ledFlashStepMs = pat->stepMs;
    s_ledFlashStart = millis();
    s_ledFlashUntil = s_ledFlashStart + (uint32_t)pat->stepMs * pat->pulses * 2u;

    if (!s_sdReady) return;

    uint32_t epoch = 0;
    bool haveUtc = utcNow(&epoch);
    char utcStr[24] = "";
    if (haveUtc) fmtUtc(epoch, utcStr, sizeof(utcStr));

    char nameEsc[64];
    csvEscape(name, nameEsc, sizeof(nameEsc));

    sdLock();
    if (s_detCsv) {
        if (gpsValid) {
            s_detCsv.printf("%lu,%s,%s,%u,%s,%d,%u,%s,%.7f,%.7f,%.1f,%.1f,%s\n",
                            (unsigned long)evt->timestamp_ms, utcStr,
                            engShortName(evt->engine_id), (unsigned)evt->method,
                            s_hitMac, (int)evt->rssi, (unsigned)evt->channel, nameEsc,
                            currentGps.latitude, currentGps.longitude,
                            (double)currentGps.altitude, (double)currentGps.accuracy,
                            evt->source_node_id[0] ? evt->source_node_id : "local");
        } else {
            s_detCsv.printf("%lu,%s,%s,%u,%s,%d,%u,%s,,,,,%s\n",
                            (unsigned long)evt->timestamp_ms, utcStr,
                            engShortName(evt->engine_id), (unsigned)evt->method,
                            s_hitMac, (int)evt->rssi, (unsigned)evt->channel, nameEsc,
                            evt->source_node_id[0] ? evt->source_node_id : "local");
        }
    }

    if (s_wigleCsv && evt->engine_id == ENGINE_WARDRIVE && gpsValid && haveUtc) {
        s_wigleCsv.printf("%s,%s,%s,%s,%u,%lu,%d,%.7f,%.7f,%.1f,%.1f,,,%s\n",
                          s_hitMac, nameEsc, wigleAuth(evt, isBle), utcStr,
                          (unsigned)evt->channel,
                          (unsigned long)(isBle ? 0u : chanToFreq(evt->channel)),
                          (int)evt->rssi,
                          currentGps.latitude, currentGps.longitude,
                          (double)currentGps.altitude, (double)currentGps.accuracy,
                          isBle ? "BLE" : "WIFI");
        s_wigleRows++;
    }
    sdUnlock();
}

void donglePcapOpen(uint16_t linktype) {
    if (!s_sdReady) return;
    sdLock();
    if (s_pcapFile) { s_pcapFile.close(); }
    char path[56];
    if (s_stampStr[0]) {
        snprintf(path, sizeof(path), DONGLE_DIR "/cap_%s_%02u_%s.pcap", s_stampStr,
                 (unsigned)(++s_pcapIdx), linktype == 256 ? "ble" : "wifi");
    } else {
        snprintf(path, sizeof(path), DONGLE_DIR "/cap_%04u_%02u_%s.pcap", (unsigned)s_seq,
                 (unsigned)(++s_pcapIdx), linktype == 256 ? "ble" : "wifi");
    }
    s_pcapFile = DONGLE_SD.open(path, FILE_WRITE);
    s_pcapBytes = 0;
    if (s_pcapFile) {
        uint8_t hdr[24];
        uint32_t magic = 0xA1B2C3D4u;
        uint16_t vmaj = 2, vmin = 4;
        int32_t zone = 0;
        uint32_t sigfigs = 0, snaplen = 2324u, net = linktype;
        memcpy(hdr + 0, &magic, 4);
        memcpy(hdr + 4, &vmaj, 2);
        memcpy(hdr + 6, &vmin, 2);
        memcpy(hdr + 8, &zone, 4);
        memcpy(hdr + 12, &sigfigs, 4);
        memcpy(hdr + 16, &snaplen, 4);
        memcpy(hdr + 20, &net, 4);
        s_pcapFile.write(hdr, sizeof(hdr));
        Serial.printf("[DONGLE] pcap -> %s\n", path);
    }
    sdUnlock();
}

void donglePcapWriteFramed(const uint8_t* data, uint32_t len) {
    if (!s_sdReady) return;
    sdLock();
    if (!s_pcapFile) { sdUnlock(); return; }
    uint32_t off = 0;
    while (off + 24u <= len) {
        uint32_t magic, recLen, caplen;
        memcpy(&magic, data + off, 4);
        memcpy(&recLen, data + off + 4, 4);
        if (magic != 0xCAFEBABEu || recLen < 16u) break;
        memcpy(&caplen, data + off + 16, 4);
        uint32_t total = 24u + caplen + 4u;
        if (off + total > len) break;
        s_pcapFile.write(data + off + 8, 16);
        s_pcapFile.write(data + off + 24, caplen);
        s_pcapBytes += 16u + caplen;
        off += total;
    }
    s_pcapFile.flush();
    sdUnlock();
}

void donglePcapClose(void) {
    sdLock();
    if (s_pcapFile) {
        s_pcapFile.close();
        Serial.printf("[DONGLE] pcap closed %lu bytes\n", (unsigned long)s_pcapBytes);
    }
    sdUnlock();
}

void dongleTick(void) {
    uint32_t now = millis();
    ledTick(now);
    buttonTick(now);
    if (now - s_lastDraw >= DONGLE_REDRAW_MS) {
        s_lastDraw = now;
        tftDraw();
    }
    if (!s_stamped) stampFileNames();
    if (s_sdReady && now - s_lastCsvFlush >= DONGLE_CSV_FLUSH_MS) {
        s_lastCsvFlush = now;
        sdLock();
        if (s_detCsv) s_detCsv.flush();
        if (s_wigleCsv) s_wigleCsv.flush();
        sdUnlock();
    }
}

#endif
