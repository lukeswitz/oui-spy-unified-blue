import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _banned = <RegExp>[
  RegExp(r'Radius\.circular\(\s*[1-9]'),
  RegExp(r'BorderRadius\.circular\(\s*[1-9]'),
  RegExp(r'BoxShadow\('),
  RegExp(r'Color\(0x'),
  RegExp(r'(Linear|Radial|Sweep)Gradient\('),
  RegExp(r'ShaderMask\('),
];

const _densityStops = <String>{
  'Color(0xFF3B82F6),',
  'Color(0xFF06B6D4),',
  'Color(0xFF22C55E),',
  'Color(0xFFEAB308),',
  'Color(0xFFF97316),',
  'Color(0xFFEF4444),',
  'Color(0xFFEC4899),',
};

const _lineAllow = <String, Set<String>>{
  'features/wardrive/wardrive_screen.dart': _densityStops,
};

String _code(String line) {
  final i = line.indexOf('//');
  return (i < 0 ? line : line.substring(0, i)).trim();
}

void main() {
  test('no rounded corners, shadows, or color literals in features and widgets', () {
    final hits = <String>[];
    for (final root in ['lib/features', 'lib/widgets']) {
      for (final f in Directory(root).listSync(recursive: true).whereType<File>()) {
        if (!f.path.endsWith('.dart')) continue;
        final rel = f.path.substring('lib/'.length);
        final allow = _lineAllow[rel] ?? const <String>{};
        final lines = f.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final code = _code(lines[i]);
          if (allow.contains(code)) continue;
          if (_banned.any((r) => r.hasMatch(code))) {
            hits.add('$rel:${i + 1}: $code');
          }
        }
      }
    }
    expect(hits, isEmpty, reason: '\n${hits.join('\n')}');
  });

  test('map backgroundColor follows the Map style', () {
    for (final p in [
      'lib/features/engines/drone_map_view.dart',
      'lib/features/geofence/geofence_screen.dart',
      'lib/features/wardrive/wardrive_screen.dart',
      'lib/features/config/config_detections_tab.dart',
    ]) {
      final src = File(p).readAsStringSync();
      expect(RegExp(r'backgroundColor:[^,]*isDark').hasMatch(src), isTrue, reason: p);
    }
  });
}
