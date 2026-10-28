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
const int sigAll = 0x1FF;

const detectorMethodsByBit = {
  sigTracker: ['tracker'],
  sigFlipper: ['flipper'],
  sigDeauth: ['deauth_storm'],
  sigProbe: ['probe_ssid', 'evil_twin', 'karma'],
  sigPwnagotchi: ['pwnagotchi'],
  sigGlasses: ['glasses'],
  sigAxon: ['axon'],
  sigCamera: ['camera', 'amazon'],
  sigMesh: ['mesh'],
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
      'Apple Find My (AirTag), Samsung SmartTag, Tile and Google Find Hub tags away from their owner. Alerts as nearby (3 s), following (5 min) and returning (3 sightings over 10 min)'),
  DetectorSignature(sigFlipper, 'Flipper Zero', 'Flipper', Icons.developer_board,
      'Flipper Zero BLE advertisements'),
  DetectorSignature(sigDeauth, 'Deauth attack', 'Deauth', Icons.wifi_off,
      'WiFi deauth / disassociation attack frames'),
  DetectorSignature(sigProbe, 'Probe requests & rogue APs', 'Probe', Icons.wifi_find,
      'Devices probing for saved WiFi networks, evil-twin APs (one SSID from a second BSSID of another vendor) and KARMA APs (one BSSID beaconing 5+ SSIDs)'),
  DetectorSignature(sigPwnagotchi, 'Pwnagotchi', 'Pwna-\ngotchi', Icons.smart_toy,
      'Pwnagotchi handshake-harvester beacons'),
  DetectorSignature(sigGlasses, 'Meta glasses', 'Meta glasses', Icons.visibility,
      'Ray-Ban / Oakley Meta smart glasses — Luxottica CID 0x0D53, service 0xFD5F, name or frame OUI (excludes Quest/Portal)'),
  DetectorSignature(sigAxon, 'Axon & duty equipment', 'Axon', Icons.local_police,
      'Axon Enterprise hardware (BLE CID 0x034D, service 0xFC81/0xFE6B/0xFE6C, OUI 00:25:DF). Also Motorola Solutions, Harris, Kenwood, Tait, Hytera, WatchGuard, Digital Ally and Skydio OUIs, reported as suspected because those vendors also sell non-police gear'),
  DetectorSignature(sigCamera, 'Security cameras & Amazon', 'Cameras', Icons.videocam,
      'Security, doorbell, plate-reader and dash cameras by vendor OUI on any Wi-Fi frame or BLE address (Ring, Nest, Arlo, Blink, Wyze, Hikvision, Dahua and more); Amazon Sidewalk BLE (CID 0x0171, service 0xFE03) and Amazon BLE services 0xFE00/0xFE15/0xFCDC/0xFD41'),
  DetectorSignature(sigMesh, 'Mesh radios', 'Mesh', Icons.hub,
      'Meshtastic nodes (service 6ba1b218-…-eafd, or name) and MeshCore nodes (name)'),
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
