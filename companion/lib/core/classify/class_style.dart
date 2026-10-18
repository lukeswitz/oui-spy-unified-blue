import 'package:flutter/material.dart';
import 'package:oui_spy/core/classify/signature_engine.dart';
import 'package:oui_spy/theme/app_theme.dart';

final _classColors = <SignatureClass, Color>{
  SignatureClass.finder: Color(0xFFE66B9B),
  SignatureClass.beacon: AppTheme.wardrive,
  SignatureClass.signage: Color(0xFF8890A8),
  SignatureClass.wearable: AppTheme.skySpy,
  SignatureClass.surveillance: AppTheme.error,
  SignatureClass.drone: AppTheme.warning,
  SignatureClass.hacking: AppTheme.uniPwn,
  SignatureClass.bodyworn: AppTheme.flockWifi,
  SignatureClass.lawEnforcement: Color(0xFF3B82F6),
  SignatureClass.vehicle: Color(0xFF84CC16),
  SignatureClass.glasses: AppTheme.wdgwars,
  SignatureClass.audio: AppTheme.flockBle,
  SignatureClass.camera: Color(0xFFF97316),
  SignatureClass.thermostat: AppTheme.foxhunter,
  SignatureClass.lock: Color(0xFFEAB308),
  SignatureClass.health: Color(0xFFEC4899),
  SignatureClass.home: AppTheme.wdgwarsAlt,
  SignatureClass.isp: Color(0xFF06B6D4),
  SignatureClass.mesh: Color(0xFF14B8A6),
  SignatureClass.phone: AppTheme.accent,
  SignatureClass.other: AppTheme.textDim,
};

Color classColor(SignatureClass k) => _classColors[k] ?? AppTheme.textDim;

IconData classIcon(SignatureClass c) => switch (c) {
      SignatureClass.finder => Icons.track_changes,
      SignatureClass.beacon => Icons.cell_tower,
      SignatureClass.signage => Icons.tv,
      SignatureClass.wearable || SignatureClass.bodyworn => Icons.watch,
      SignatureClass.surveillance => Icons.videocam,
      SignatureClass.drone => Icons.flight,
      SignatureClass.hacking => Icons.bug_report,
      SignatureClass.lawEnforcement => Icons.local_police,
      SignatureClass.vehicle => Icons.directions_car,
      SignatureClass.glasses => Icons.visibility,
      SignatureClass.audio => Icons.headphones,
      SignatureClass.camera => Icons.photo_camera,
      SignatureClass.thermostat => Icons.thermostat,
      SignatureClass.lock => Icons.lock,
      SignatureClass.health => Icons.favorite,
      SignatureClass.home => Icons.home,
      SignatureClass.isp => Icons.router,
      SignatureClass.mesh => Icons.hub,
      SignatureClass.phone => Icons.smartphone,
      SignatureClass.other => Icons.devices_other,
    };

SignatureClass? _classOfKind(String? kind) {
  for (final c in SignatureClass.values) {
    if (c.name == kind) return c;
  }
  return null;
}

Color alertKindColor(String? kind) {
  if (kind == 'flock') return AppTheme.flockWifi;
  final c = _classOfKind(kind);
  return c == null ? AppTheme.warning : classColor(c);
}

IconData alertKindIcon(String? kind) {
  if (kind == 'flock') return Icons.videocam;
  final c = _classOfKind(kind);
  return c == null ? Icons.warning_amber : classIcon(c);
}

String alertKindLabel(String? kind) {
  if (kind == 'flock') return 'FLOCK';
  final c = _classOfKind(kind);
  return c == null ? 'SIGNATURE' : c.label.toUpperCase();
}
