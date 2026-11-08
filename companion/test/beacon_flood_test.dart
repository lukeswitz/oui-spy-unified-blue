import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/beacon_flood.dart';
import 'package:oui_spy/core/classify/observation.dart';

String _mac(int tag, int n) =>
    '02:${tag.toRadixString(16).padLeft(2, '0')}:00:${n.toRadixString(16).padLeft(2, '0')}:40:01'.toUpperCase();

Observation _ap(String mac, {int rssi = -50, int channel = 6}) => Observation(
      key: 'WIFI:$mac',
      kind: RadioKind.wifi,
      mac: mac,
      rssi: rssi,
      channel: channel,
      isAp: true,
    );

const _afterWarmup = BeaconFlood.warmupMs + 1000;

BeaconFlood _armed() {
  final f = BeaconFlood()..enabled = true;
  f.consider(_ap('00:11:22:33:44:55'), 0, () => false);
  return f;
}

void _burst(BeaconFlood f, int tag, int count, {int rssiStep = 0, bool unknown = true, int at = _afterWarmup}) {
  for (var i = 0; i < count; i++) {
    f.consider(_ap(_mac(tag, i), rssi: -50 - (i * rssiStep) % 40), at, () => unknown);
  }
  f.tick(at);
}

void main() {
  test('burst of unregistered fake APs on one channel flags', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps);
    final n = f.notice!;
    expect(n.title(), 'Wi-Fi beacon flood');
    expect(n.popupCount, BeaconFlood.minAps);
    expect(n.families, ['channel 6']);
    expect(n.medianRssi, -50);
  });

  test('one under the minimum stays quiet', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps - 1);
    expect(f.notice, isNull);
  });

  test('networks seen during warm-up are the baseline', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps, at: 1000);
    expect(f.notice, isNull);
  });

  test('registered makers are a busy street, not a flood', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps * 2, unknown: false);
    expect(f.notice, isNull);
  });

  test('spread signal levels never flag', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps * 2, rssiStep: 7);
    expect(f.notice, isNull);
  });

  test('one AP with many BSSIDs counts once', () {
    final f = _armed();
    for (var i = 0; i < BeaconFlood.minAps * 2; i++) {
      final mac = '${(0x02 | (i << 2) & 0xFF).toRadixString(16).padLeft(2, '0')}:05:06:07:08:${i.toRadixString(16).padLeft(2, '0')}';
      f.consider(_ap(mac.toUpperCase()), _afterWarmup, () => true);
    }
    f.tick(_afterWarmup);
    expect(f.notice, isNull);
  });

  test('off by default and clears when switched off', () {
    final off = BeaconFlood();
    _burst(off, 1, BeaconFlood.minAps * 2);
    expect(off.notice, isNull);
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps);
    expect(f.notice, isNotNull);
    f.enabled = false;
    f.tick(_afterWarmup + 1);
    expect(f.notice, isNull);
  });

  test('notice holds, then clears after the hold time', () {
    final f = _armed();
    _burst(f, 1, BeaconFlood.minAps);
    f.dismiss();
    expect(f.notice!.showDialog, isFalse);
    f.tick(_afterWarmup + BeaconFlood.windowMs + 1);
    expect(f.notice, isNotNull);
    f.tick(_afterWarmup + BeaconFlood.holdMs + 1);
    expect(f.notice, isNull);
  });
}
