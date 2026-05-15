import 'package:oui_spy/core/models/detection.dart';
import 'package:oui_spy/core/models/engine.dart';

const _bleMethods = {
  'ble_adv',
  'odid_ble',
  'unitree_ble',
  'oui_match',
  'name_match',
  'mfg_id',
  'raven_uuid',
  'ble_watchlist',
  'ble_proximity',
};

const _wifiMethods = {
  'wifi_ap',
  'wifi_probe',
  'flock_oui',
  'oui_addr1',
  'oui_addr2',
  'oui_addr3',
  'ssid',
  'wildcard_probe',
  'odid_nan',
  'odid_beacon',
  'wifi_watchlist',
  'wifi_proximity',
};

bool isBleMethod(String method) => _bleMethods.contains(method);
bool isWifiMethod(String method) => _wifiMethods.contains(method);

bool isBleDetectionRaw({required String method, required Engine engine, required int channel}) {
  if (_bleMethods.contains(method)) return true;
  if (_wifiMethods.contains(method)) return false;
  if (engine.isBle && !engine.isDualRadio) return true;
  if (engine.isWifi && !engine.isDualRadio) return false;
  if (channel >= 1 && channel <= 14) return false;
  if (channel >= 30) return false;
  return true;
}

extension DetectionRadio on Detection {
  bool get isBleDetection =>
      isBleDetectionRaw(method: method, engine: engine, channel: channel);
  bool get isWifiDetection => !isBleDetection;
}
