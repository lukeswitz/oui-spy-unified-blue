import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const int sigTracker = 0x01;
const int sigFlipper = 0x02;
const int sigDeauth = 0x04;
const int sigProbe = 0x08;
const int sigPwnagotchi = 0x10;
const int sigAll = 0x1F;

class DetectorSignature {
  final int bit;
  final String label;
  final String desc;
  const DetectorSignature(this.bit, this.label, this.desc);
}

const List<DetectorSignature> detectorSignatures = [
  DetectorSignature(
      sigTracker, 'Find My / AirTag', 'Apple Find My trackers persistently following you'),
  DetectorSignature(sigFlipper, 'Flipper Zero', 'Flipper Zero BLE advertisements'),
  DetectorSignature(
      sigDeauth, 'Deauth attack', 'WiFi deauth / disassociation attack frames'),
  DetectorSignature(sigProbe, 'Probe requests', 'Devices probing for saved WiFi networks'),
  DetectorSignature(
      sigPwnagotchi, 'Pwnagotchi', 'Pwnagotchi handshake-harvester beacons'),
];

class DetectorSigMaskNotifier extends StateNotifier<int> {
  DetectorSigMaskNotifier() : super(sigAll) {
    _load();
  }
  static const _key = 'detector_sig_mask';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = (prefs.getInt(_key) ?? sigAll) & sigAll;
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
