import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:oui_spy/core/ble/ble_manager.dart';
import 'package:oui_spy/core/link/link_net.dart';
import 'package:oui_spy/core/link/link_session.dart';

class _Transport implements LinkTransport {
  bool closed = false;

  @override
  Stream<Uint8List> get input => const Stream.empty();

  @override
  Future<void> send(Uint8List bytes) async {}

  @override
  Future<void> close() async => closed = true;
}

class _SlowTarget extends NetLinkTarget {
  _SlowTarget() : super('test0');

  final gate = Completer<LinkTransport>();

  @override
  Future<LinkTransport> open() => gate.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('stop while a link is opening closes it and stays disconnected', () async {
    final ble = BleManager();
    final target = _SlowTarget();
    final transport = _Transport();

    final pending = ble.connectNetLink(target, sessionId: 's');
    await Future<void>.delayed(Duration.zero);
    expect(ble.currentConnectionState, NodeConnectionState.connecting);

    await ble.disconnect();
    expect(ble.stopCount, 1);

    target.gate.complete(transport);
    await pending;

    expect(transport.closed, isTrue);
    expect(ble.isUsbLinked, isFalse);
    expect(ble.currentConnectionState, NodeConnectionState.disconnected);
  });
}
