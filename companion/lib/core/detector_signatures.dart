import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int sigTracker = 0x01;
const int sigFlipper = 0x02;
const int sigDeauth = 0x04;
const int sigProbe = 0x08;
const int sigPwnagotchi = 0x10;
const int sigGlasses = 0x20;
const int sigAll = 0x3F;

class DetectorSignature {
  final int bit;
  final String label;
  final String short;
  final IconData icon;
  final String desc;
  const DetectorSignature(this.bit, this.label, this.short, this.icon, this.desc);
}

const List<DetectorSignature> detectorSignatures = [
  DetectorSignature(sigTracker, 'Find My / AirTag', 'Find My', Icons.track_changes,
      'Apple Find My trackers (AirTag) broadcasting offline-finding — owner out of range'),
  DetectorSignature(sigFlipper, 'Flipper Zero', 'Flipper', Icons.developer_board,
      'Flipper Zero BLE advertisements'),
  DetectorSignature(sigDeauth, 'Deauth attack', 'Deauth', Icons.wifi_off,
      'WiFi deauth / disassociation attack frames'),
  DetectorSignature(sigProbe, 'Probe requests', 'Probe', Icons.wifi_find,
      'Devices probing for saved WiFi networks'),
  DetectorSignature(sigPwnagotchi, 'Pwnagotchi', 'Pwnagotchi', Icons.smart_toy,
      'Pwnagotchi handshake-harvester beacons'),
  DetectorSignature(sigGlasses, 'Meta glasses', 'Meta glasses', Icons.visibility,
      'Meta Ray-Ban / smart glasses (BLE, visible at power-on/pairing)'),
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
