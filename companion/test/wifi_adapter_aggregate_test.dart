import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/link/wifi_adapter_controller.dart';

void main() {
  const s = WifiAdapterState.values;

  test('any running adapter makes the whole set running', () {
    expect(aggregateAdapterState([s[4], s[3]], attached: true), WifiAdapterState.running);
    expect(aggregateAdapterState([WifiAdapterState.starting, WifiAdapterState.running], attached: true),
        WifiAdapterState.running);
  });

  test('starting beats error, error beats idle', () {
    expect(aggregateAdapterState([WifiAdapterState.error, WifiAdapterState.starting], attached: true),
        WifiAdapterState.starting);
    expect(aggregateAdapterState([WifiAdapterState.error], attached: true), WifiAdapterState.error);
  });

  test('no active adapters reports present or absent', () {
    expect(aggregateAdapterState(const [], attached: true), WifiAdapterState.present);
    expect(aggregateAdapterState(const [], attached: false), WifiAdapterState.absent);
  });
}
