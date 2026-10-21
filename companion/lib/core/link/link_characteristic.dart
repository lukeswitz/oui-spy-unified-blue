import 'package:flutter_blue_plus/flutter_blue_plus.dart';

abstract class LinkCharacteristic {
  Guid get uuid;

  Future<void> write(List<int> value,
      {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15});

  Future<List<int>> read({int timeout = 15});

  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false});

  Stream<List<int>> get onValueReceived;
}

class BleLinkCharacteristic implements LinkCharacteristic {
  BleLinkCharacteristic(this._c);

  final BluetoothCharacteristic _c;

  @override
  Guid get uuid => _c.uuid;

  @override
  Future<void> write(List<int> value,
          {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) =>
      _c.write(value,
          withoutResponse: withoutResponse, allowLongWrite: allowLongWrite, timeout: timeout);

  @override
  Future<List<int>> read({int timeout = 15}) => _c.read(timeout: timeout);

  @override
  Future<bool> setNotifyValue(bool notify, {int timeout = 15, bool forceIndications = false}) =>
      _c.setNotifyValue(notify, timeout: timeout, forceIndications: forceIndications);

  @override
  Stream<List<int>> get onValueReceived => _c.onValueReceived;
}
