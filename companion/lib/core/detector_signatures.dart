// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int sigTracker = 0x01;
const int sigFlipper = 0x02;
const int sigDeauth = 0x04;
const int sigProbe = 0x08;
const int sigPwnagotchi = 0x10;
const int sigGlasses = 0x20;
const int sigAxon = 0x40;
const int sigCamera = 0x80;
const int sigMesh = 0x100;
const int sigBeaconFlood = 0x200;
const int sigWearable = 0x400;
const int sigVehicle = 0x800;
const int sigDrone = 0x1000;
const int sigAll = 0x1FFF;

const detectorMethodsByBit = {
  sigTracker: ['tracker', 'tag_flood'],
  sigFlipper: ['flipper'],
  sigDeauth: ['deauth_storm', 'join_flood'],
  sigProbe: ['probe_ssid', 'evil_twin', 'karma'],
  sigPwnagotchi: ['pwnagotchi'],
  sigGlasses: ['glasses'],
  sigAxon: ['axon'],
  sigCamera: ['camera', 'amazon'],
  sigMesh: ['mesh'],
  sigBeaconFlood: ['beacon_flood'],
  sigWearable: ['wearable_cam'],
  sigVehicle: ['vehicle'],
  sigDrone: ['drone_ble'],
};

class DetectorSignature {
  final int bit;
  final String label;
  final String short;
  final IconData icon;
  final String desc;
  const DetectorSignature(this.bit, this.label, this.short, this.icon, this.desc);
}

const List<DetectorSignature> detectorSignatures = [
  DetectorSignature(sigTracker, 'Trackers', 'Trackers', Icons.track_changes,
      'Apple Find My (AirTag, AirPods and other Find My items), Samsung SmartTag, Tile, Google Find Hub, Chipolo, Pebblebee and DULT-standard tags away from their owner. Alerts as nearby (3 s), following (5 min) and returning (3 sightings over 10 min), and when new tag addresses keep appearing too fast to be real tags'),
  DetectorSignature(sigFlipper, 'Flipper Zero', 'Flipper', Icons.developer_board,
      'Flipper Zero BLE advertisements: service 0x3080-0x3083, Flipper Devices CID 0x0E29, or a Flipper address prefix'),
  DetectorSignature(sigDeauth, 'Deauth attack', 'Deauth', Icons.wifi_off,
      'WiFi deauth / disassociation attack frames, and floods of join requests at one access point'),
  DetectorSignature(sigProbe, 'Probe requests & rogue APs', 'Probe', Icons.wifi_find,
      'Devices probing for saved WiFi networks, evil-twin APs (one SSID from a second BSSID of another vendor) and KARMA APs (one BSSID beaconing 5+ SSIDs)'),
  DetectorSignature(sigPwnagotchi, 'Pwnagotchi', 'Pwna-\ngotchi', Icons.smart_toy,
      'Pwnagotchi handshake-harvester beacons'),
  DetectorSignature(sigGlasses, 'Meta glasses', 'Meta glasses', Icons.visibility,
      'Ray-Ban / Oakley Meta smart glasses — Luxottica CID 0x0D53, service 0xFD5F, name or frame OUI (excludes Quest/Portal)'),
  DetectorSignature(sigAxon, 'Axon & duty equipment', 'Axon', Icons.local_police,
      'Axon Enterprise hardware (BLE CID 0x034D, service 0xFC81/0xFE6B/0xFE6C, OUI 00:25:DF). Motorola Solutions radios and body cams by BLE CID 0x04EC or service 0xFD8E/0xFE04. Also Motorola Solutions, Harris, Kenwood, Tait, Hytera, WatchGuard, Digital Ally, i-PRO, Utility and Skydio OUIs, reported as suspected because those vendors also sell non-police gear'),
  DetectorSignature(sigCamera, 'Security cameras & Amazon', 'Cameras', Icons.videocam,
      'Security, doorbell, plate-reader and dash cameras by vendor OUI on any Wi-Fi frame or BLE address (Ring, Nest, Arlo, Blink, Wyze, Hikvision, Dahua and more), or by a camera brand in the network or device name. A matching vendor and name is rated verified, a name alone high, and a vendor alone suspected; Amazon Sidewalk BLE (CID 0x0171, service 0xFE03) and Amazon BLE services 0xFE00/0xFE15/0xFCDC/0xFD41'),
  DetectorSignature(sigMesh, 'Mesh radios', 'Mesh', Icons.hub,
      'Meshtastic nodes (service 6ba1b218-…-eafd, or name) and MeshCore nodes (name)'),
  DetectorSignature(sigBeaconFlood, 'Wi-Fi beacon flood', 'Beacon flood', Icons.wifi_channel,
      'One radio faking a crowd of Wi-Fi networks: 15+ access points on one channel at the same signal level within seconds'),
  DetectorSignature(sigWearable, 'Wearable cameras', 'Wearables', Icons.camera_alt,
      'GoPro and Insta360 cameras, Snap Spectacles, Even Realities and Vuzix glasses, Brilliant Labs Frame and PLAUD voice recorders, by BLE company ID or service. Snap also by its Wi-Fi and BLE address prefix (suspected)'),
  DetectorSignature(sigVehicle, 'Vehicles', 'Vehicles', Icons.directions_car,
      'Teslas (BLE CID 0x022B, service 0xFE96/0xFE97, or a vehicle name like S…C) and Bluetooth OBD-II dongles (OBDII, OBDLink, Vgate, vLinker, Veepeak)'),
  DetectorSignature(sigDrone, 'Drones (Bluetooth)', 'Drones', Icons.flight,
      'Drones broadcasting Remote ID over BLE (service 0xFFFA) and DJI drones, controllers and Osmo cameras (CID 0x08AA). Teal drones by Wi-Fi address prefix (suspected)'),
];

class DetectorSigMaskNotifier extends StateNotifier<int> {
  DetectorSigMaskNotifier() : super(0) {
    _load();
  }
  static const _key = 'detector_sig_mask';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getInt(_key) ?? 0) & sigAll;
  }

  Future<void> setBit(int bit, bool on) async {
    state = (on ? (state | bit) : (state & ~bit)) & sigAll;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, state);
  }
}

final detectorSigMaskProvider =
    StateNotifierProvider<DetectorSigMaskNotifier, int>(
        (ref) => DetectorSigMaskNotifier());
