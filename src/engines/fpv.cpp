// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#include "fpv.h"

#ifdef OUISPY_FPV

#include "fpv_logic.h"
#include "detector.h"
#include "enow_hub.h"
#include "../ble_gatt.h"
#include "../engine_registry.h"
#include "../mesh_espnow.h"
#include "../radio_coex.h"
#include <Arduino.h>
#include <driver/gpio.h>
#include <driver/parlio_rx.h>
#include <esp_cache.h>
#include <esp_heap_caps.h>
#include <esp_rom_gpio.h>
#include <esp_wifi.h>
#include <soc/gpio_sig_map.h>

extern "C" {
void phy_disable_agc(void);
void phy_rfagc_disable(void);
void phy_wifi_fbw_sel(uint32_t val);
void phy_force_rx_gain(bool enable, uint8_t gainIdx);
void phy_set_freq(uint16_t freqMhz, int offset);
int lmac_stop_hw_txq(void);
}

using namespace fpv;

namespace {

struct RegOp {
    uint32_t addr;
    uint32_t keep;
    uint32_t set;
};

constexpr RegOp kUngate[] = {
    {0x60095004u, 0xfffef0ffu, 0x00010000u},
    {0x600a08ccu, 0xff87ffffu, 0x00000000u},
    {0x600a70b8u, 0xfffffff8u, 0x00000001u},
    {0x600a9c04u, 0x00000000u, 0xffffffffu},
    {0x600a0800u, 0xffffffffu, 0x00000004u},
    {0x600a20b4u, 0xfffffffeu, 0x00000000u},
    {0x600a9018u, 0xff03ffffu, 0x006c0000u},
    {0x600a9018u, 0xfffc0fffu, 0x0001a000u},
    {0x600a9018u, 0xfffff03fu, 0x00000640u},
    {0x600a9018u, 0xffffffc0u, 0x01000018u},
    {0x600a9008u, 0xfe01ffffu, 0x00060000u},
};

constexpr uint32_t kRegDumpCtrl = 0x600a9004u;
constexpr uint32_t kDumpCtrlEnable = 0x80000000u;
constexpr uint32_t kDumpCtrlStartDone = 0x000c0000u;
constexpr uint32_t kDumpCtrlFirst = 0x00020000u;
constexpr uint32_t kDumpCtrlLenMask = 0x0001ffffu;
constexpr uint32_t kDumpLen = 16384u;

constexpr uint32_t kRegTxq0 = 0x600a4d6cu;
constexpr uint32_t kTxqStride = 0x10u;
constexpr uint32_t kTxqCount = 5u;
constexpr uint32_t kTxqEnable = 0x80000000u;

constexpr uint32_t kRegFbw = 0x600a0874u;
constexpr uint32_t kFbwMask = 0x003f0000u;
constexpr uint32_t kRegGain = 0x600a702cu;
constexpr uint32_t kGainMask = 0xff800000u;
constexpr uint32_t kRegAgc = 0x600a7030u;
constexpr uint32_t kAgcMask = 0xe0000000u;
constexpr uint32_t kRegRfAgcA = 0x600a705cu;
constexpr uint32_t kRegRfAgcB = 0x600a284cu;
constexpr uint32_t kRfAgcBMask = 0xf7080000u;

constexpr uint8_t kRxGainIdx = 52;
constexpr uint8_t kLaneDiag[8] = {6, 7, 8, 9, 16, 17, 18, 19};
constexpr gpio_num_t kLanePad[8] = {GPIO_NUM_1, GPIO_NUM_0, GPIO_NUM_23, GPIO_NUM_7,
                                    GPIO_NUM_10, GPIO_NUM_5, GPIO_NUM_3, GPIO_NUM_4};

constexpr size_t kCapBytes = 512;
constexpr size_t kCapSkip = 32;
constexpr uint8_t kCapsPerChannel = 2;
constexpr uint32_t kSettleMs = 4;
constexpr uint32_t kStopPeriodMs = 50;
constexpr uint32_t kHopDwellMs = 2000;
constexpr uint32_t kNotifyMinMs = 250;
constexpr uint32_t kNotifyKeepMs = 1000;
constexpr uint32_t kLogPeriodMs = 1000;
constexpr uint8_t kStreakDetect = 2;

enum Stage : uint16_t {
    kStPark = 0x01,
    kStRadio = 0x02,
    kStWifiCfg = 0x04,
    kStPhy = 0x08,
    kStTxq = 0x10,
    kStPins = 0x20,
    kStRx = 0x40,
};

struct Cmd {
    uint8_t op;
    uint8_t a;
    uint8_t restore;
};

struct SavedWifi {
    wifi_band_mode_t band;
    wifi_protocols_t protocols;
    wifi_bandwidths_t bandwidths;
    wifi_country_t country;
    wifi_ps_type_t ps;
};

struct SavedPhy {
    uint32_t fbw;
    uint32_t gain;
    uint32_t agc;
    uint32_t rfagcA;
    uint32_t rfagcB;
    uint32_t txq[kTxqCount];
};

TaskHandle_t s_task = nullptr;
QueueHandle_t s_q = nullptr;
portMUX_TYPE s_mux = portMUX_INITIALIZER_UNLOCKED;

volatile bool s_busy = false;
volatile bool s_abort = false;
uint16_t s_stages = 0;
uint8_t s_parked = 0;
SavedWifi s_wifi = {};
SavedPhy s_phy = {};

parlio_rx_unit_handle_t s_rx = nullptr;
parlio_rx_delimiter_handle_t s_delim = nullptr;
uint8_t* s_buf = nullptr;

uint8_t s_mode = kModeOff;
uint8_t s_chan = 0;
uint8_t s_prevChan = 0;
uint8_t s_threshold = kDefaultThreshold;
uint8_t s_floor = kFallbackFloor;
uint8_t s_err = kErrNone;
uint8_t s_level[kChannelCount];
uint8_t s_coh[kChannelCount];
uint8_t s_streak[kChannelCount];
uint32_t s_lastPush[kChannelCount];
uint64_t s_flagMask = 0;
uint8_t s_curLevel = 0;
uint8_t s_curCoh = 0;
uint32_t s_passes = 0;
LockTracker s_lock;

uint8_t s_scanPos = 0;
uint8_t s_hopList[kChannelCount];
uint8_t s_hopCount = 0;
uint8_t s_hopIdx = 0;
uint32_t s_hopSince = 0;
bool s_hopDwelling = false;
uint32_t s_lastStop = 0;

uint32_t s_capErr = 0;
uint32_t s_invalidRun = 0;
uint32_t s_tuneUs = 0;
uint32_t s_tuneN = 0;
uint32_t s_passUs = 0;
uint32_t s_passStart = 0;
uint32_t s_lastNotify = 0;
uint32_t s_lastLog = 0;
bool s_dirty = false;

inline volatile uint32_t& reg(uint32_t addr) { return *(volatile uint32_t*)(uintptr_t)addr; }
inline void fence() { __asm__ __volatile__("fence iorw, iorw" ::: "memory"); }

void IRAM_ATTR rxStub(void*, wifi_promiscuous_pkt_type_t) {}

bool wifiUsingEngine(EngineId id) {
    return id == ENGINE_FLOCK_WIFI || id == ENGINE_SKYSPY || id == ENGINE_WARDRIVE || id == ENGINE_PCAP ||
           id == ENGINE_FOXHUNTER || (id == ENGINE_DETECTOR && detectorUsesWifi());
}

void markDirty() { s_dirty = true; }

void maybeNotify(bool force) {
    uint32_t now = millis();
    uint32_t gap = now - s_lastNotify;
    if (!force && !(s_dirty && gap >= kNotifyMinMs) && gap < kNotifyKeepMs) return;
    s_lastNotify = now;
    s_dirty = false;
    bleGattNotifyFpvState();
}

void setError(uint8_t e) {
    if (s_err == e) return;
    s_err = e;
    markDirty();
}

uint8_t flaggedCount() {
    uint8_t n = 0;
    for (uint8_t i = 0; i < kChannelCount; i++) n += (s_flagMask >> i) & 1u;
    return n;
}

void ungateModem() {
    for (const RegOp& op : kUngate) reg(op.addr) = (reg(op.addr) & op.keep) | op.set;
    uint32_t ctrl = reg(kRegDumpCtrl);
    ctrl &= ~(kDumpCtrlEnable | kDumpCtrlStartDone);
    ctrl |= kDumpCtrlFirst;
    ctrl = (ctrl & ~kDumpCtrlLenMask) | kDumpLen;
    reg(kRegDumpCtrl) = ctrl;
    fence();
    reg(kRegDumpCtrl) = ctrl | kDumpCtrlEnable;
    fence();
}

void phyHold() {
    phy_disable_agc();
    phy_rfagc_disable();
    phy_wifi_fbw_sel(1);
    phy_force_rx_gain(true, kRxGainIdx);
}

void savePhy() {
    s_phy.fbw = reg(kRegFbw) & kFbwMask;
    s_phy.gain = reg(kRegGain) & kGainMask;
    s_phy.agc = reg(kRegAgc) & kAgcMask;
    s_phy.rfagcA = reg(kRegRfAgcA);
    s_phy.rfagcB = reg(kRegRfAgcB) & kRfAgcBMask;
    for (uint32_t q = 0; q < kTxqCount; q++) s_phy.txq[q] = reg(kRegTxq0 - q * kTxqStride);
}

void restorePhy() {
    reg(kRegFbw) = (reg(kRegFbw) & ~kFbwMask) | s_phy.fbw;
    reg(kRegGain) = (reg(kRegGain) & ~kGainMask) | s_phy.gain;
    reg(kRegAgc) = (reg(kRegAgc) & ~kAgcMask) | s_phy.agc;
    reg(kRegRfAgcA) = s_phy.rfagcA;
    reg(kRegRfAgcB) = (reg(kRegRfAgcB) & ~kRfAgcBMask) | s_phy.rfagcB;
    fence();
}

bool lockTxReceiveOnly() {
    (void)lmac_stop_hw_txq();
    for (uint32_t q = 0; q < kTxqCount; q++) reg(kRegTxq0 - q * kTxqStride) &= ~kTxqEnable;
    fence();
    for (uint32_t q = 0; q < kTxqCount; q++)
        if (reg(kRegTxq0 - q * kTxqStride) & kTxqEnable) return false;
    return true;
}

void restoreTxq() {
    for (uint32_t q = 0; q < kTxqCount; q++) reg(kRegTxq0 - q * kTxqStride) = s_phy.txq[q];
    fence();
}

bool routePins() {
    uint64_t mask = 0;
    for (int i = 0; i < 8; i++) mask |= (uint64_t)1 << kLanePad[i];
    gpio_config_t cfg = {};
    cfg.pin_bit_mask = mask;
    cfg.mode = GPIO_MODE_INPUT_OUTPUT;
    cfg.pull_up_en = GPIO_PULLUP_DISABLE;
    cfg.pull_down_en = GPIO_PULLDOWN_DISABLE;
    cfg.intr_type = GPIO_INTR_DISABLE;
    if (gpio_config(&cfg) != ESP_OK) return false;
    for (int i = 0; i < 8; i++)
        esp_rom_gpio_connect_out_signal(kLanePad[i], MODEM_DIAG0_IDX + kLaneDiag[i], false, false);
    fence();
    return true;
}

void releasePins() {
    for (int i = 0; i < 8; i++) {
        gpio_reset_pin(kLanePad[i]);
        esp_rom_gpio_connect_out_signal(kLanePad[i], SIG_GPIO_OUT_IDX, false, false);
    }
}

bool startRx() {
    parlio_rx_unit_config_t cfg = {};
    cfg.trans_queue_depth = 1;
    cfg.max_recv_size = kCapBytes;
    cfg.dma_burst_size = 32;
    cfg.data_width = 8;
    cfg.clk_src = PARLIO_CLK_SRC_DEFAULT;
    cfg.exp_clk_freq_hz = 40000000u;
    cfg.clk_in_gpio_num = (gpio_num_t)-1;
    cfg.clk_out_gpio_num = (gpio_num_t)-1;
    cfg.valid_gpio_num = (gpio_num_t)-1;
    for (int i = 0; i < 8; i++) cfg.data_gpio_nums[i] = kLanePad[i];
    cfg.flags.free_clk = 1;
    if (parlio_new_rx_unit(&cfg, &s_rx) != ESP_OK) return false;
    parlio_rx_soft_delimiter_config_t dc = {};
    dc.sample_edge = PARLIO_SAMPLE_EDGE_POS;
    dc.bit_pack_order = PARLIO_BIT_PACK_ORDER_LSB;
    dc.eof_data_len = kCapBytes;
    dc.timeout_ticks = 0;
    if (parlio_new_rx_soft_delimiter(&dc, &s_delim) != ESP_OK) return false;
    if (parlio_rx_unit_enable(s_rx, false) != ESP_OK) return false;
    if (parlio_rx_soft_delimiter_start_stop(s_rx, s_delim, true) != ESP_OK) return false;
    s_buf = (uint8_t*)heap_caps_aligned_alloc(64, kCapBytes, MALLOC_CAP_DMA | MALLOC_CAP_INTERNAL);
    return s_buf != nullptr;
}

void stopRx() {
    if (s_rx) {
        parlio_rx_unit_disable(s_rx);
        if (s_delim) parlio_del_rx_delimiter(s_delim);
        parlio_del_rx_unit(s_rx);
    }
    s_delim = nullptr;
    s_rx = nullptr;
    if (s_buf) heap_caps_free(s_buf);
    s_buf = nullptr;
}

bool recoverRx() {
    parlio_rx_unit_disable(s_rx);
    if (parlio_rx_unit_enable(s_rx, true) != ESP_OK) return false;
    return parlio_rx_soft_delimiter_start_stop(s_rx, s_delim, true) == ESP_OK;
}

bool capture() {
    parlio_receive_config_t rc = {};
    rc.delimiter = s_delim;
    if (parlio_rx_unit_receive(s_rx, s_buf, kCapBytes, &rc) != ESP_OK) {
        s_capErr++;
        recoverRx();
        return false;
    }
    if (parlio_rx_unit_wait_all_done(s_rx, 20) != ESP_OK) {
        s_capErr++;
        recoverRx();
        return false;
    }
    esp_cache_msync(s_buf, kCapBytes, ESP_CACHE_MSYNC_FLAG_DIR_M2C);
    return true;
}

bool measureHere(Measure* out) {
    uint32_t lvl = 0, coh = 0;
    uint8_t n = 0;
    uint8_t clip = 0;
    for (uint8_t k = 0; k < kCapsPerChannel; k++) {
        if (!capture()) continue;
        Measure m = measureIq(s_buf + kCapSkip, kCapBytes - kCapSkip);
        if (!m.valid) continue;
        lvl += m.level;
        coh += m.coherence;
        if (m.clipPct > clip) clip = m.clipPct;
        n++;
    }
    if (n == 0) {
        s_invalidRun++;
        if (s_invalidRun == 20)
            Serial.println("[FPV] WARN 20 invalid captures in a row (modem clock idle or coex gap)");
        if (s_invalidRun >= 50) setError(kErrCapture);
        return false;
    }
    if (s_invalidRun >= 20) Serial.printf("[FPV] captures valid again after %u invalid\n", (unsigned)s_invalidRun);
    s_invalidRun = 0;
    if (s_err == kErrCapture) setError(kErrNone);
    out->valid = true;
    out->level = (uint8_t)(lvl / n);
    out->coherence = (uint8_t)(coh / n);
    out->clipPct = clip;
    return true;
}

bool tune(uint8_t idx) {
    Center c;
    uint16_t want = freqMhz(idx);
    if (!planBootstrap(want, &c)) return false;
    uint32_t t0 = micros();
    esp_err_t e = esp_wifi_set_channel(c.wifiChannel, WIFI_SECOND_CHAN_NONE);
    if (e != ESP_OK) {
        Serial.printf("[FPV] tune %c%u %uMHz failed wifi ch%u rc=0x%x\n", bandLetter(idx), (unsigned)bandNumber(idx),
                      (unsigned)want, (unsigned)c.wifiChannel, (int)e);
        setError(kErrTune);
        return false;
    }
    if (want != c.mhz) phy_set_freq(want, 0);
    ungateModem();
    phyHold();
    s_tuneUs += micros() - t0;
    s_tuneN++;
    if (s_err == kErrTune) setError(kErrNone);
    return true;
}

void applyMeasure(uint8_t idx, const Measure& m) {
    if (s_level[idx] == kNoLevel) {
        s_level[idx] = m.level;
        s_coh[idx] = m.coherence;
    } else {
        s_level[idx] = smoothLevel(s_level[idx], m.level);
        s_coh[idx] = smoothLevel(s_coh[idx], m.coherence);
    }
}

void pushDetect(uint8_t idx) {
    uint32_t now = millis();
    if (s_lastPush[idx] != 0 && now - s_lastPush[idx] < engineGetRediscoverMs()) return;
    s_lastPush[idx] = now ? now : 1;
    DetectionEvent evt;
    memset(&evt, 0, sizeof(evt));
    evt.engine_id = ENGINE_SKYSPY;
    pseudoMac(idx, evt.mac);
    evt.rssi = levelToRssi(s_level[idx]);
    evt.channel = (uint8_t)(idx + 1);
    evt.timestamp_ms = now;
    evt.method = METHOD_ODID_FPV;
    uavId(idx, evt.ext.odid.uav_id);
    snprintf(evt.ext.odid.self_id, sizeof(evt.ext.odid.self_id), "analog video coh %u%%", (unsigned)s_coh[idx]);
    evt.ext.odid.altitude_msl = -1000;
    evt.ext.odid.height_agl = -1000;
    evt.ext.odid.altitude_baro = -1000;
    evt.ext.odid.operator_alt = -1000;
    evt.ext.odid.area_ceiling = -1000;
    evt.ext.odid.area_floor = -1000;
    evt.ext.odid.speed = 255;
    evt.ext.odid.heading = 361;
    evt.ext.odid.vert_speed = 63;
    evt.ext.odid.loc_timestamp = 0xFFFF;
    pushDetection(&evt);
    Serial.printf("[FPV] detect %c%u %uMHz lvl=%u coh=%u%%\n", bandLetter(idx), (unsigned)bandNumber(idx),
                  (unsigned)freqMhz(idx), (unsigned)s_level[idx], (unsigned)s_coh[idx]);
}

void setFlag(uint8_t idx, bool on) {
    bool was = (s_flagMask >> idx) & 1u;
    if (on == was) return;
    portENTER_CRITICAL(&s_mux);
    if (on) s_flagMask |= (uint64_t)1 << idx;
    else s_flagMask &= ~((uint64_t)1 << idx);
    portEXIT_CRITICAL(&s_mux);
    Serial.printf("[FPV] flag%c %c%u %uMHz lvl=%u coh=%u%% floor=%u\n", on ? '+' : '-', bandLetter(idx),
                  (unsigned)bandNumber(idx), (unsigned)freqMhz(idx), (unsigned)s_level[idx], (unsigned)s_coh[idx],
                  (unsigned)s_floor);
    markDirty();
}

void finishPass() {
    s_floor = noiseFloor(s_level, kChannelCount);
    for (uint8_t i = 0; i < kChannelCount; i++) {
        if (!supported(i) || s_level[i] == kNoLevel) continue;
        bool hit = isTransmitter(s_level[i], s_coh[i], s_floor, s_threshold);
        if (hit) {
            if (s_streak[i] < 255) s_streak[i]++;
        } else {
            s_streak[i] = 0;
        }
        setFlag(i, s_streak[i] >= 1);
        if (s_streak[i] >= kStreakDetect) pushDetect(i);
    }
    s_passes++;
    s_passUs = micros() - s_passStart;
    markDirty();
}

void setMode(uint8_t mode) {
    if (s_mode == mode) return;
    s_mode = mode;
    s_scanPos = 0;
    s_hopDwelling = false;
    s_hopCount = 0;
    s_passStart = micros();
    static const char* const names[] = {"OFF", "STOP", "SCAN", "SWEEP", "HOP"};
    Serial.printf("[FPV] mode %s\n", names[mode < 5 ? mode : 0]);
    markDirty();
}

void selectChannel(uint8_t idx) {
    if (!supported(idx)) {
        Serial.printf("[FPV] channel %u unsupported (outside 5180-5885 MHz)\n", (unsigned)idx);
        setError(kErrUnsupported);
        return;
    }
    if (s_err == kErrUnsupported) setError(kErrNone);
    if (!tune(idx)) return;
    s_chan = idx;
    s_lock.reset();
    s_curLevel = 0;
    s_curCoh = 0;
    char nm[3];
    channelName(idx, nm);
    Center c;
    planBootstrap(freqMhz(idx), &c);
    Serial.printf("[FPV] tune %s %uMHz via wifi ch%u\n", nm, (unsigned)freqMhz(idx), (unsigned)c.wifiChannel);
    markDirty();
}

void stepStop() {
    uint32_t now = millis();
    if (now - s_lastStop < kStopPeriodMs) {
        vTaskDelay(pdMS_TO_TICKS(5));
        return;
    }
    s_lastStop = now;
    Measure m;
    if (!measureHere(&m)) {
        if (s_lock.update(false)) {
            Serial.printf("[FPV] lock lost %c%u (no capture)\n", bandLetter(s_chan), (unsigned)bandNumber(s_chan));
            markDirty();
        }
        return;
    }
    applyMeasure(s_chan, m);
    s_curLevel = m.level;
    s_curCoh = m.coherence;
    bool hit = isTransmitter(m.level, m.coherence, s_floor, s_threshold);
    if (s_lock.update(hit)) {
        Serial.printf("[FPV] lock %s %c%u %uMHz lvl=%u coh=%u%% floor=%u\n", s_lock.locked ? "acquired" : "lost",
                      bandLetter(s_chan), (unsigned)bandNumber(s_chan), (unsigned)freqMhz(s_chan), (unsigned)m.level,
                      (unsigned)m.coherence, (unsigned)s_floor);
        markDirty();
    }
    setFlag(s_chan, s_lock.locked || hit);
    if (s_lock.locked) pushDetect(s_chan);
    markDirty();
}

bool stepPassChannel() {
    while (s_scanPos < kChannelCount && !supported(s_scanPos)) s_scanPos++;
    if (s_scanPos >= kChannelCount) return true;
    uint8_t idx = s_scanPos++;
    if (!tune(idx)) return false;
    vTaskDelay(pdMS_TO_TICKS(kSettleMs));
    Measure m;
    if (measureHere(&m)) applyMeasure(idx, m);
    return false;
}

void startHopList() {
    s_hopCount = 0;
    for (uint8_t i = 0; i < kChannelCount; i++)
        if ((s_flagMask >> i) & 1u) s_hopList[s_hopCount++] = i;
    s_hopIdx = 0;
    s_hopDwelling = s_hopCount > 0;
    s_hopSince = 0;
}

void stepScan() {
    if (!stepPassChannel()) return;
    finishPass();
    uint8_t best = kNoChannel;
    for (uint8_t i = 0; i < kChannelCount; i++) {
        if (!((s_flagMask >> i) & 1u)) continue;
        if (best == kNoChannel || s_level[i] > s_level[best]) best = i;
    }
    if (best != kNoChannel) {
        Serial.printf("[FPV] scan hit %c%u %uMHz lvl=%u\n", bandLetter(best), (unsigned)bandNumber(best),
                      (unsigned)freqMhz(best), (unsigned)s_level[best]);
        setMode(kModeStop);
        selectChannel(best);
    } else {
        Serial.printf("[FPV] scan found no transmitter (floor=%u thr=%u passUs=%u)\n", (unsigned)s_floor,
                      (unsigned)s_threshold, (unsigned)s_passUs);
        setMode(kModeStop);
        selectChannel(supported(s_prevChan) ? s_prevChan : s_chan);
    }
}

void stepSweep() {
    if (!stepPassChannel()) return;
    finishPass();
    s_scanPos = 0;
    s_passStart = micros();
}

void stepHop() {
    if (!s_hopDwelling) {
        if (!stepPassChannel()) return;
        finishPass();
        s_scanPos = 0;
        s_passStart = micros();
        startHopList();
        if (s_hopCount > 0) selectChannel(s_hopList[0]);
        s_hopSince = millis();
        return;
    }
    uint32_t now = millis();
    if (now - s_hopSince >= kHopDwellMs) {
        s_hopIdx++;
        if (s_hopIdx >= s_hopCount) {
            s_hopDwelling = false;
            s_scanPos = 0;
            s_passStart = micros();
            return;
        }
        selectChannel(s_hopList[s_hopIdx]);
        s_hopSince = now;
        return;
    }
    stepStop();
}

void logSummary() {
    uint32_t now = millis();
    if (now - s_lastLog < kLogPeriodMs) return;
    s_lastLog = now;
    static const char* const names[] = {"OFF", "STOP", "SCAN", "SWEEP", "HOP"};
    char nm[3];
    channelName(s_chan, nm);
    Serial.printf("[FPV] ch=%s %uMHz mode=%s lvl=%u coh=%u%% floor=%u thr=%u lock=%d flagged=%u passes=%u tuneAvgUs=%u "
                  "passUs=%u capErr=%u err=%u\n",
                  nm, (unsigned)freqMhz(s_chan), names[s_mode < 5 ? s_mode : 0], (unsigned)s_curLevel,
                  (unsigned)s_curCoh, (unsigned)s_floor, (unsigned)s_threshold, s_lock.locked ? 1 : 0,
                  (unsigned)flaggedCount(), (unsigned)s_passes, (unsigned)(s_tuneN ? s_tuneUs / s_tuneN : 0),
                  (unsigned)s_passUs, (unsigned)s_capErr, (unsigned)s_err);
}

bool wifiConfigure() {
    esp_wifi_get_band_mode(&s_wifi.band);
    esp_wifi_get_protocols(WIFI_IF_STA, &s_wifi.protocols);
    esp_wifi_get_bandwidths(WIFI_IF_STA, &s_wifi.bandwidths);
    esp_wifi_get_country(&s_wifi.country);
    esp_wifi_get_ps(&s_wifi.ps);
    esp_wifi_set_promiscuous(false);
    esp_err_t e;
    wifi_country_t country = s_wifi.country;
    country.policy = WIFI_COUNTRY_POLICY_MANUAL;
    country.wifi_5g_channel_mask = WIFI_CHANNEL_132 | WIFI_CHANNEL_136 | WIFI_CHANNEL_140 | WIFI_CHANNEL_144 |
                                   WIFI_CHANNEL_149 | WIFI_CHANNEL_153 | WIFI_CHANNEL_157 | WIFI_CHANNEL_161 |
                                   WIFI_CHANNEL_165 | WIFI_CHANNEL_169 | WIFI_CHANNEL_173 | WIFI_CHANNEL_177;
    if ((e = esp_wifi_set_country(&country)) != ESP_OK) Serial.printf("[FPV] set_country rc=0x%x\n", (int)e);
    if ((e = esp_wifi_set_band_mode(WIFI_BAND_MODE_5G_ONLY)) != ESP_OK) {
        Serial.printf("[FPV] set_band_mode rc=0x%x\n", (int)e);
        return false;
    }
    if ((e = esp_wifi_set_ps(WIFI_PS_NONE)) != ESP_OK) Serial.printf("[FPV] set_ps rc=0x%x\n", (int)e);
    wifi_protocols_t proto = {};
    proto.ghz_2g = s_wifi.protocols.ghz_2g;
    proto.ghz_5g = WIFI_PROTOCOL_11A | WIFI_PROTOCOL_11N;
    if ((e = esp_wifi_set_protocols(WIFI_IF_STA, &proto)) != ESP_OK) {
        Serial.printf("[FPV] set_protocols rc=0x%x\n", (int)e);
        return false;
    }
    wifi_bandwidths_t bw = {};
    bw.ghz_2g = s_wifi.bandwidths.ghz_2g;
    bw.ghz_5g = WIFI_BW40;
    if ((e = esp_wifi_set_bandwidths(WIFI_IF_STA, &bw)) != ESP_OK) {
        Serial.printf("[FPV] set_bandwidths rc=0x%x\n", (int)e);
        return false;
    }
    wifi_promiscuous_filter_t none = {};
    esp_wifi_set_promiscuous_filter(&none);
    esp_wifi_set_promiscuous(true);
    return true;
}

void wifiRestore() {
    esp_wifi_set_promiscuous(false);
    esp_wifi_set_band_mode(s_wifi.band);
    esp_wifi_set_protocols(WIFI_IF_STA, &s_wifi.protocols);
    esp_wifi_set_bandwidths(WIFI_IF_STA, &s_wifi.bandwidths);
    esp_wifi_set_country(&s_wifi.country);
    esp_wifi_set_ps(s_wifi.ps);
}

void teardown(bool restoreEngines) {
    s_mode = kModeOff;
    if (s_stages & kStRx) stopRx();
    if (s_stages & kStPins) releasePins();
    if (s_stages & kStPhy) restorePhy();
    if (s_stages & kStTxq) restoreTxq();
    if (s_stages & kStWifiCfg) wifiRestore();
    if (s_stages & kStRadio) {
        wifiCoexCycleRadio(rxStub, 1);
        wifiCoexUnregister(rxStub);
    }
    uint8_t parked = s_parked;
    s_parked = 0;
    s_stages = 0;
    s_lock.reset();
    portENTER_CRITICAL(&s_mux);
    s_flagMask = 0;
    portEXIT_CRITICAL(&s_mux);
    s_busy = false;
    if (restoreEngines) {
        for (int i = 0; i < ENGINE_COUNT; i++) {
            if (!(parked & ENGINE_BITMASK(i))) continue;
            bool ok = engineEnable((EngineId)i);
            Serial.printf("[FPV] restore engine %d %s\n", i, ok ? "ok" : "refused");
        }
    }
    bleGattNotifyEngineState();
    markDirty();
    maybeNotify(true);
}

bool enter(uint8_t startMode) {
    if (s_busy) return true;
    s_abort = false;
    if (meshIsEnabled() || enowHubActive() || wifiRadioExternallyOwned()) {
        Serial.println("[FPV] refused: mesh or ESP-NOW hub owns the radio");
        setError(kErrMesh);
        markDirty();
        maybeNotify(true);
        return false;
    }
    s_busy = true;
    s_err = kErrNone;
    s_stages = 0;
    s_parked = 0;
    Serial.println("[FPV] enter: parking Wi-Fi engines");
    for (int i = 0; i < ENGINE_COUNT; i++) {
        EngineId id = (EngineId)i;
        if (engineGetState(id) == ESTATE_DISABLED || !wifiUsingEngine(id)) continue;
        s_parked |= ENGINE_BITMASK(i);
        engineDisable(id);
        Serial.printf("[FPV] parked engine %d\n", i);
    }
    s_stages |= kStPark;
    bleGattNotifyEngineState();
    if (s_abort) { teardown(false); return false; }

    wifiCoexRegister(rxStub, 0);
    s_stages |= kStRadio;
    savePhy();
    s_stages |= kStWifiCfg;
    if (!wifiConfigure()) {
        setError(kErrRadio);
        teardown(true);
        return false;
    }
    if (s_abort) { teardown(false); return false; }

    phyHold();
    s_stages |= kStPhy;
    if (!lockTxReceiveOnly()) {
        Serial.println("[FPV] tx queues could not be disabled");
        setError(kErrRadio);
        teardown(true);
        return false;
    }
    s_stages |= kStTxq;
    ungateModem();
    if (!routePins()) {
        setError(kErrRadio);
        teardown(true);
        return false;
    }
    s_stages |= kStPins;
    if (!startRx()) {
        Serial.println("[FPV] parlio rx start failed");
        setError(kErrCapture);
        s_stages |= kStRx;
        teardown(true);
        return false;
    }
    s_stages |= kStRx;
    if (s_abort) { teardown(false); return false; }

    s_prevChan = supported(s_chan) ? s_chan : 0;
    s_passes = 0;
    s_floor = kFallbackFloor;
    s_curLevel = 0;
    s_curCoh = 0;
    s_invalidRun = 0;
    s_tuneUs = s_tuneN = 0;
    memset(s_level, kNoLevel, sizeof(s_level));
    memset(s_coh, 0, sizeof(s_coh));
    memset(s_streak, 0, sizeof(s_streak));
    memset(s_lastPush, 0, sizeof(s_lastPush));
    s_mode = kModeOff;
    selectChannel(s_prevChan);
    setMode(startMode);
    Serial.println("[FPV] active: receive only, Wi-Fi scanning paused");
    bleGattNotifyEngineState();
    markDirty();
    maybeNotify(true);
    return true;
}

void leave(bool restoreEngines) {
    if (!s_busy) return;
    Serial.println("[FPV] leave: restoring radio");
    teardown(restoreEngines);
    Serial.println("[FPV] left");
}

void handle(const Cmd& c) {
    switch (c.op) {
        case kOpEnter:
            enter(c.a >= kModeStop && c.a <= kModeHop ? c.a : kModeScan);
            break;
        case kOpLeave:
            leave(c.restore != 0);
            break;
        case kOpMode:
            if (c.a < kModeStop || c.a > kModeHop) break;
            if (!s_busy) {
                enter(c.a);
                break;
            }
            if (c.a == kModeStop) {
                setMode(kModeStop);
                selectChannel(supported(s_chan) ? s_chan : s_prevChan);
            } else {
                if (s_mode == kModeStop) s_prevChan = s_chan;
                s_mode = kModeOff;
                setMode(c.a);
            }
            maybeNotify(true);
            break;
        case kOpTune:
            if (!s_busy && !enter(kModeStop)) break;
            setMode(kModeStop);
            selectChannel(c.a);
            maybeNotify(true);
            break;
        case kOpStep: {
            if (!s_busy && !enter(kModeStop)) break;
            uint8_t next = stepChannel(s_chan, (int8_t)c.a);
            if (next == kNoChannel) break;
            setMode(kModeStop);
            selectChannel(next);
            maybeNotify(true);
            break;
        }
        case kOpThreshold:
            if (c.a == 0) break;
            s_threshold = c.a;
            Serial.printf("[FPV] threshold %u\n", (unsigned)s_threshold);
            markDirty();
            maybeNotify(true);
            break;
        default:
            break;
    }
}

void step() {
    if (meshIsEnabled() || enowHubActive()) {
        Serial.println("[FPV] mesh or ESP-NOW hub enabled: leaving");
        leave(true);
        return;
    }
    switch (s_mode) {
        case kModeStop: stepStop(); break;
        case kModeScan: stepScan(); break;
        case kModeSweep: stepSweep(); break;
        case kModeHop: stepHop(); break;
        default: vTaskDelay(pdMS_TO_TICKS(20)); break;
    }
    logSummary();
    maybeNotify(false);
    vTaskDelay(1);
}

void fpvTask(void*) {
    Cmd c;
    for (;;) {
        TickType_t wait = s_busy ? 0 : pdMS_TO_TICKS(250);
        if (xQueueReceive(s_q, &c, wait) == pdTRUE) {
            handle(c);
            continue;
        }
        if (s_busy) step();
    }
}

}  // namespace

void fpvInit(void) {
    if (s_task) return;
    memset(s_level, kNoLevel, sizeof(s_level));
    s_q = xQueueCreate(8, sizeof(Cmd));
    if (!s_q) return;
    if (xTaskCreate(fpvTask, "fpv", 8192, nullptr, 4, &s_task) != pdPASS) {
        s_task = nullptr;
        Serial.println("[FPV] task create failed");
        return;
    }
    Serial.println("[FPV] ready");
}

bool fpvActive(void) { return s_busy; }

bool fpvBlocksEngine(EngineId id) { return s_busy && wifiUsingEngine(id); }

void fpvCommand(const uint8_t* data, size_t len) {
    if (!s_q || !data || len < 1) return;
    Cmd c = {data[0], (uint8_t)(len > 1 ? data[1] : 0), 1};
    if (c.op < kOpEnter || c.op > kOpThreshold) return;
    xQueueSend(s_q, &c, 0);
}

void fpvAbort(void) {
    if (!s_q || !s_busy) return;
    s_abort = true;
    Cmd c = {kOpLeave, 0, 0};
    xQueueSend(s_q, &c, 0);
    for (int i = 0; i < 300 && s_busy; i++) vTaskDelay(pdMS_TO_TICKS(10));
    if (s_busy) Serial.println("[FPV] abort timed out");
}

size_t fpvPackState(uint8_t* buf, size_t cap) {
    State s = {};
    portENTER_CRITICAL(&s_mux);
    s.flags = (s_busy ? kFlagActive : 0) | (s_lock.locked ? kFlagLocked : 0) |
              (((s_flagMask >> s_chan) & 1u) && s_busy ? kFlagFlagged : 0) | (s_parked ? kFlagParked : 0) |
              (s_err != kErrNone ? kFlagError : 0);
    s.mode = s_busy ? s_mode : kModeOff;
    s.channel = s_chan;
    s.mhz = freqMhz(s_chan);
    s.level = s_curLevel;
    s.coherence = s_curCoh;
    s.floor = s_floor;
    s.threshold = s_threshold;
    s.error = s_err;
    s.passes = s_passes;
    s.supportedMask = supportedMask();
    s.flaggedMask = s_flagMask;
    memcpy(s.levels, s_level, kChannelCount);
    memcpy(s.coh, s_coh, kChannelCount);
    portEXIT_CRITICAL(&s_mux);
    for (uint8_t i = 0; i < kChannelCount; i++) {
        if (!supported(i)) s.levels[i] = kNoLevel;
        s.flaggedCount += (s.flaggedMask >> i) & 1u;
    }
    return encodeState(s, buf, cap);
}

#endif
