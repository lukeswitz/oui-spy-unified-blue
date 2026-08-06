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
const int sigAll = 0x7F;

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
      'Ray-Ban / Oakley Meta smart glasses — Luxottica CID 0x0D53, service 0xFD5F, name or frame OUI (excludes Quest/Portal)'),
  DetectorSignature(sigAxon, 'Axon (Law Enforcement)', 'Axon', Icons.local_police,
      'Axon Enterprise hardware — Taser, body cameras, Signal (BLE CID 0x034D, service 0xFC81, or OUI 00:25:DF; promiscuous WiFi OUI 00:25:DF)'),
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
