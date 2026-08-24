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
static uint32_t s_wigleRows = 0;
static uint32_t s_lastDraw = 0;
static char s_lastLine[DONGLE_ROWS][DONGLE_COLS + 1];

static char s_hitEng[10] = "";
static char s_hitMac[18] = "";
static char s_hitName[DONGLE_COLS + 1] = "";
static int8_t s_hitRssi = 0;
static uint8_t s_hitChan = 0;
static bool s_haveHit = false;

static uint32_t s_epochBase = 0;
static uint32_t s_epochBaseMs = 0;

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

static void tftDraw(void) {
    if (!s_tftReady) return;
    char line[64];

    bool phone = bleGattIsConnected();
    bool mgr = meshManagerJoined();
    snprintf(line, sizeof(line), "%s %s%s", meshGetLocalNodeId(),
             phone ? "PHONE" : "-----", mgr ? " MGR" : "");
    tftLine(0, line, phone ? DGX_GREEN : DGX_YELLOW);

    uint8_t mask = engineGetActiveMask();
    char eng[ENGINE_COUNT + 1];
    for (int i = 0; i < ENGINE_COUNT; i++)
        eng[i] = (mask & (1 << i)) ? kEngLetter[i] : '.';
    eng[ENGINE_COUNT] = '\0';
    snprintf(line, sizeof(line), "ENG %s", eng);
    tftLine(1, line, mask ? DGX_CYAN : DGX_WHITE);

    snprintf(line, sizeof(line), "HITS %lu", (unsigned long)s_hits);
    tftLine(2, line, DGX_WHITE);

    if (!s_sdReady) {
        tftLine(3, "SD  none", DGX_RED);
    } else if (s_pcapBytes) {
        snprintf(line, sizeof(line), "SD  %04u w%lu p%luk", (unsigned)s_seq,
                 (unsigned long)s_wigleRows, (unsigned long)(s_pcapBytes / 1024u));
        tftLine(3, line, DGX_GREEN);
    } else {
        snprintf(line, sizeof(line), "SD  %04u w%lu", (unsigned)s_seq,
                 (unsigned long)s_wigleRows);
        tftLine(3, line, DGX_GREEN);
    }

    if (gpsValid) {
        snprintf(line, sizeof(line), "GPS %.4f %.4f",
                 currentGps.latitude, currentGps.longitude);
        tftLine(4, line, DGX_GREEN);
    } else {
        tftLine(4, "GPS none", DGX_YELLOW);
    }

    if (s_haveHit) {
        snprintf(line, sizeof(line), "%s %d %u", s_hitEng, (int)s_hitRssi,
                 (unsigned)s_hitChan);
        tftLine(6, line, DGX_MAGENTA);
        tftLine(7, s_hitMac, DGX_WHITE);
        tftLine(8, s_hitName, DGX_WHITE);
    }
}

void dongleInit(void) {
    if (!s_sdMutex) s_sdMutex = xSemaphoreCreateMutex();

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
    snprintf(path, sizeof(path), DONGLE_DIR "/cap_%04u_%02u_%s.pcap", (unsigned)s_seq,
             (unsigned)(++s_pcapIdx), linktype == 256 ? "ble" : "wifi");
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
    if (now - s_lastDraw >= DONGLE_REDRAW_MS) {
        s_lastDraw = now;
        tftDraw();
    }
    if (s_sdReady && now - s_lastCsvFlush >= DONGLE_CSV_FLUSH_MS) {
        s_lastCsvFlush = now;
        sdLock();
        if (s_detCsv) s_detCsv.flush();
        if (s_wigleCsv) s_wigleCsv.flush();
        sdUnlock();
    }
}

#endif
