// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

#ifndef ENGINE_DETECTOR_PRESETS_H
#define ENGINE_DETECTOR_PRESETS_H

#include <stdint.h>

// Rows must match companion/lib/core/node_filters.dart (detectorPresets); companion/test/detector_presets_test.dart checks it.
enum DetPresetKind : uint8_t { PR_OUI, PR_PROBE, PR_BEACON, PR_SVC, PR_CID, PR_NAME, PR_PFX, PR_MFR, PR_PAT, PR_UUID };

struct DetPresetRow {
    uint8_t kind;
    const char* id;
    const char* desc;
};

static const DetPresetRow PRESET_AXON[] = {
    {PR_OUI, "0025DF", "AXON"},
    {PR_PROBE, "0025DF", "AXON (WiFi)"},
    {PR_BEACON, "0025DF", "AXON (WiFi)"},
};
static const DetPresetRow PRESET_META[] = {
    {PR_OUI, "7C2A9E", "META/RAYBAN SMARTGLASSES"},
    {PR_PROBE, "7C2A9E", "META/RAYBAN SMARTGLASSES"},
    {PR_OUI, "985949", "META/RAYBAN SMARTGLASSES"},
    {PR_PROBE, "985949", "META/RAYBAN SMARTGLASSES"},
    {PR_OUI, "80AA1C", "META/RAYBAN SMARTGLASSES"},
    {PR_PROBE, "80AA1C", "META/RAYBAN SMARTGLASSES"},
    {PR_OUI, "384712", "META/RAYBAN SMARTGLASSES"},
    {PR_PROBE, "384712", "META/RAYBAN SMARTGLASSES"},
    {PR_CID, "0D53", "Meta glasses (Luxottica)"},
    {PR_SVC, "FD5F", "Meta glasses service"},
    {PR_CID, "058E", "Meta Platforms (headsets)"},
    {PR_CID, "01AB", "Meta Platforms"},
    {PR_SVC, "FEB7", "Meta Platforms service"},
    {PR_SVC, "FEB8", "Meta Platforms service"},
    {PR_NAME, "Ray-Ban", "Ray-Ban Meta glasses (BLE name)"},
    {PR_NAME, "Oakley", "Oakley Meta glasses (BLE name)"},
    {PR_NAME, "Wayfarer", "Ray-Ban Meta Wayfarer"},
};
static const DetPresetRow PRESET_IPRO[] = {
    {PR_PROBE, "D42DC5", "I-PRO"},
    {PR_OUI, "D42DC5", "I-PRO body cam"},
};
static const DetPresetRow PRESET_VERKADA[] = {
    {PR_PROBE, "E0A700", "Verkada"},
    {PR_BEACON, "E0A700", "Verkada"},
};
static const DetPresetRow PRESET_TRACKERS[] = {
    {PR_MFR, "004C:121910/FFFF30", "AirTag, separated"},
    {PR_MFR, "004C:121920/FFFF30", "Find My accessory, separated"},
    {PR_MFR, "004C:121930/FFFF30", "AirPods, separated"},
    {PR_SVC, "FD5A", "Samsung SmartTag"},
    {PR_SVC, "FD59", "Samsung SmartTag, not set up"},
    {PR_SVC, "FEED", "Tile"},
    {PR_SVC, "FEEC", "Tile, not activated"},
    {PR_SVC, "FE33", "Chipolo"},
    {PR_SVC, "FA25", "Pebblebee"},
    {PR_SVC, "FCB2", "Tracker (DULT standard)"},
};
static const DetPresetRow PRESET_DRONES[] = {
    {PR_SVC, "FFFA", "Remote ID broadcast (Bluetooth)"},
    {PR_CID, "08AA", "DJI CID (drones, RCs, Osmo)"},
    {PR_OUI, "4C43F6", "DJI OUI"},
    {PR_OUI, "882985", "DJI OUI"},
    {PR_BEACON, "B030C8", "Teal Drones (WiFi)"},
};
static const DetPresetRow PRESET_VEHICLES[] = {
    {PR_PAT, "S################C", "Tesla vehicle (name)"},
    {PR_SVC, "FE96", "Tesla svc UUID"},
    {PR_SVC, "FE97", "Tesla svc UUID"},
    {PR_CID, "022B", "Tesla CID"},
    {PR_NAME, "OBDII", "OBD-II dongle"},
    {PR_NAME, "OBDBLE", "OBD-II dongle"},
    {PR_NAME, "OBDLink", "OBDLink dongle"},
    {PR_NAME, "Vgate", "Vgate OBD dongle"},
    {PR_NAME, "vLinker", "vLinker OBD dongle"},
    {PR_NAME, "VEEPEAK", "Veepeak OBD dongle"},
};
static const DetPresetRow PRESET_WEARABLES[] = {
    {PR_CID, "03C2", "Snap Spectacles CID"},
    {PR_SVC, "FE45", "Snap Spectacles svc UUID"},
    {PR_OUI, "98A40E", "Snap Inc OUI"},
    {PR_CID, "10F9", "Even Realities glasses CID"},
    {PR_UUID, "7A2300015475A6A4654C8431F6AD49C4", "Brilliant Labs Frame glasses"},
    {PR_SVC, "FEA6", "GoPro camera"},
    {PR_SVC, "FEA5", "GoPro camera"},
    {PR_CID, "02F2", "GoPro CID"},
    {PR_CID, "10D7", "Insta360 camera CID"},
    {PR_SVC, "FC2D", "Insta360 camera"},
    {PR_SVC, "FC2E", "Insta360 camera"},
    {PR_SVC, "FC2F", "Insta360 camera"},
    {PR_SVC, "FC30", "Insta360 camera"},
    {PR_CID, "0FB2", "PLAUD voice recorder CID"},
};
static const DetPresetRow PRESET_FLIPPER[] = {
    {PR_OUI, "80E126", "FLIPPER ZERO"},
    {PR_PROBE, "80E126", "FLIPPER ZERO"},
    {PR_OUI, "80E127", "FLIPPER ZERO"},
    {PR_PROBE, "80E127", "FLIPPER ZERO"},
    {PR_OUI, "0CFA22", "FLIPPER ZERO"},
    {PR_PROBE, "0CFA22", "FLIPPER ZERO"},
    {PR_NAME, "Flipper", "Flipper Zero (BLE name)"},
    {PR_SVC, "3081", "Flipper Zero svc UUID (black)"},
    {PR_SVC, "3082", "Flipper Zero svc UUID (white)"},
    {PR_SVC, "3083", "Flipper Zero (transparent)"},
    {PR_SVC, "3080", "Flipper Zero"},
    {PR_PFX, "Flipper ", "Flipper Zero (name)"},
    {PR_CID, "0E29", "Flipper Devices CID"},
};
static const DetPresetRow PRESET_POLICE[] = {
    {PR_CID, "04EC", "Motorola Solutions company"},
    {PR_SVC, "FD8E", "Motorola Solutions svc UUID"},
    {PR_SVC, "FE04", "Motorola Solutions svc UUID"},
    {PR_CID, "060C", "Vuzix CID (smart glasses, HUDs)"},
    {PR_OUI, "00047D", "Motorola Solutions OUI"},
    {PR_OUI, "001885", "Motorola Solutions OUI"},
    {PR_OUI, "001F92", "Motorola Solutions OUI"},
    {PR_OUI, "4CCC34", "Motorola Solutions OUI"},
    {PR_OUI, "10746F", "Motorola Solutions (radios)"},
    {PR_OUI, "9C862B", "Motorola Solutions (radios)"},
    {PR_OUI, "B8E28C", "Motorola Solutions (radios)"},
    {PR_PROBE, "001D96", "WatchGuard Video camera"},
    {PR_BEACON, "001D96", "WatchGuard Video AP (WiFi)"},
    {PR_PROBE, "0023BD", "Digital Ally cam (WiFi)"},
    {PR_BEACON, "0023BD", "Digital Ally AP (WiFi)"},
    {PR_PROBE, "0009BC", "Utility / BodyWorn (WiFi)"},
    {PR_BEACON, "0009BC", "Utility car router"},
    {PR_PROBE, "0016ED", "Utility / BodyWorn (WiFi)"},
    {PR_BEACON, "0016ED", "Utility car router"},
    {PR_BEACON, "00BF15", "Genetec AutoVu reader"},
    {PR_BEACON, "0CBF15", "Genetec AutoVu reader"},
    {PR_BEACON, "D411D6", "ShotSpotter sensor (WiFi)"},
    {PR_BEACON, "701AD5", "Avigilon Alta camera (WiFi)"},
};

struct DetPreset {
    const char* key;
    const DetPresetRow* rows;
    uint8_t count;
};

#define DET_PRESET_ROWS(a) a, (uint8_t)(sizeof(a) / sizeof((a)[0]))

static const DetPreset DET_PRESETS[] = {
    {"axon", DET_PRESET_ROWS(PRESET_AXON)},
    {"meta", DET_PRESET_ROWS(PRESET_META)},
    {"ipro", DET_PRESET_ROWS(PRESET_IPRO)},
    {"verkada", DET_PRESET_ROWS(PRESET_VERKADA)},
    {"trackers", DET_PRESET_ROWS(PRESET_TRACKERS)},
    {"drones", DET_PRESET_ROWS(PRESET_DRONES)},
    {"vehicles", DET_PRESET_ROWS(PRESET_VEHICLES)},
    {"wearables", DET_PRESET_ROWS(PRESET_WEARABLES)},
    {"flipper", DET_PRESET_ROWS(PRESET_FLIPPER)},
    {"police", DET_PRESET_ROWS(PRESET_POLICE)},
};
#define DET_PRESET_COUNT (sizeof(DET_PRESETS) / sizeof(DET_PRESETS[0]))

#endif
