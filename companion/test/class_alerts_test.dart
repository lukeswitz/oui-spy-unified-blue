import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/classify/device_registry.dart';
import 'package:oui_spy/core/classify/observation.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/core/notifications/class_alerts.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';

const _sig = Signature(id: 'fleet-flock', name: 'Flock Safety', kind: SignatureClass.surveillance);

void main() {
  test('Fieldwatch surveillance signature -> cameras alert titled by signature', () {
    const d = ClassifiedDevice(
      Observation(key: 'W:1', kind: RadioKind.wifi, mac: 'B4:1E:52:11:22:33', rssi: -61),
      [_sig],
      {'esp32'},
    );
    expect(alertClassOf(d, defaultAlertClasses), SignatureClass.surveillance);
    expect(alertClassOf(d, {SignatureClass.finder}), isNull);
    final (title, subtitle, body) =
        NotificationService.classNotificationText(d, ClassAlert.ofClass(SignatureClass.surveillance));
    expect(title, 'Surveillance: Flock Safety');
    expect(subtitle, 'Signature match');
    expect(body, '-61 dBm · Wi-Fi\nB4:1E:52:11:22:33');
  });

  test('Flock fleet alerts on the Flock toggle only, never as cameras', () {
    const flockSig = Signature(id: 'fleet-flock-cameras', name: 'Flock Safety Cameras', kind: SignatureClass.surveillance);
    const d = ClassifiedDevice(
      Observation(key: 'W:5', kind: RadioKind.wifi, mac: 'B4:1E:52:11:22:34', rssi: -60),
      [flockSig],
      {'esp32'},
    );
    expect(alertClassOf(d, alertableClasses.toSet()), isNull);
    expect(classAlertOf(d, alertableClasses.toSet(), flock: false), isNull);
    final a = classAlertOf(d, {}, flock: true)!;
    expect(a.kind, 'flock');
    expect(NotificationService.classNotificationText(d, a).$1, 'Flock: Flock Safety Cameras');
  });

  test('vendor classification (factory MAC, Axon) -> law-enforcement alert', () {
    const d = ClassifiedDevice(
      Observation(key: 'W:2', kind: RadioKind.wifi, mac: '00:25:DF:11:22:33', rssi: -70),
      [],
      {'esp32'},
      vendor: 'Axon Enterprise, Inc.',
    );
    expect(alertClassOf(d, defaultAlertClasses), SignatureClass.lawEnforcement);
    expect(NotificationService.classNotificationText(d, ClassAlert.ofClass(SignatureClass.lawEnforcement)).$1, 'Public safety: an Axon body camera or device');
  });

  test('low-confidence vendor guess never alerts; unrelated device never alerts', () {
    const weak = ClassifiedDevice(
      Observation(key: 'W:3', kind: RadioKind.wifi, mac: '00:11:22:33:44:55'),
      [],
      {'esp32'},
      vendor: 'Samsung Electronics Co.,Ltd',
    );
    expect(alertClassOf(weak, alertableClasses.toSet()), isNull);
    const randomized = ClassifiedDevice(
      Observation(key: 'W:4', kind: RadioKind.wifi, mac: '02:25:DF:11:22:33'),
      [],
      {'esp32'},
      vendor: 'Axon Enterprise, Inc.',
    );
    expect(alertClassOf(randomized, alertableClasses.toSet()), isNull);
  });
}
