import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:path_provider/path_provider.dart';

class DebugLog {
  DebugLog._();
  static IOSink? _sink;
  static bool _ready = false;

  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/oui_spy.log');
      _sink = file.openWrite(mode: FileMode.append);
      _ready = true;
      log('=== OUI-SPY started ===');
    } catch (e) {
      // ignore: avoid_print
      if (kDebugMode) print('[LOG] Failed to init file logger: $e');
    }
  }

  static void log(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '[$ts] $msg';
    // ignore: avoid_print
    if (kDebugMode) print(line);
    if (_ready && _sink != null) {
      _sink!.writeln(line);
    }
  }

  static void dispose() {
    _sink?.close();
  }
}
