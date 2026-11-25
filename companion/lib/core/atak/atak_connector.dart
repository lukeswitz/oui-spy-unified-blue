import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/atak/cot.dart';
import 'package:oui_spy/core/debug_log.dart';
import 'package:oui_spy/core/models/detection.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AtakSettings {
  const AtakSettings({this.enabled = false, this.host = defaultHost, this.port = defaultPort, this.multicast = false});

  static const defaultHost = '127.0.0.1';
  static const defaultPort = 4242;
  static const multicastHost = '239.2.3.1';
  static const multicastPort = 6969;

  final bool enabled;
  final String host;
  final int port;
  final bool multicast;

  AtakSettings copyWith({bool? enabled, String? host, int? port, bool? multicast}) => AtakSettings(
        enabled: enabled ?? this.enabled,
        host: host ?? this.host,
        port: port ?? this.port,
        multicast: multicast ?? this.multicast,
      );

  static bool validPort(int p) => p > 0 && p < 65536;
}

/// Sends catches and Remote ID drones to ATAK as Cursor-on-Target over UDP; off by default.
class AtakConnector extends StateNotifier<AtakSettings> {
  AtakConnector() : super(const AtakSettings()) {
    _load();
  }

  static const _kOn = 'atak_on', _kHost = 'atak_host', _kPort = 'atak_port', _kMcast = 'atak_mcast';
  static const minGap = Duration(seconds: 5);

  RawDatagramSocket? _socket;
  final _lastSent = <String, DateTime>{};
  bool _changed = false;
  int sent = 0;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed) return;
    state = AtakSettings(
      enabled: p.getBool(_kOn) ?? false,
      host: p.getString(_kHost) ?? AtakSettings.defaultHost,
      port: p.getInt(_kPort) ?? AtakSettings.defaultPort,
      multicast: p.getBool(_kMcast) ?? false,
    );
  }

  Future<void> update(AtakSettings s) async {
    _changed = true;
    state = s;
    if (!s.enabled) {
      _socket?.close();
      _socket = null;
      _lastSent.clear();
    }
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, s.enabled);
    await p.setString(_kHost, s.host);
    await p.setInt(_kPort, s.port);
    await p.setBool(_kMcast, s.multicast);
  }

  Future<RawDatagramSocket> _sock() async =>
      _socket ??= await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);

  Future<int> send(Detection d) async {
    final s = state;
    if (!s.enabled) return 0;
    final now = DateTime.now();
    final events = cotEventsFor(d, now: now).where((e) {
      final last = _lastSent[e.uid];
      return last == null || now.difference(last) >= minGap;
    }).toList();
    if (events.isEmpty) return 0;
    try {
      final sock = await _sock();
      final targets = <(InternetAddress, int)>[
        (InternetAddress(s.host), s.port),
        if (s.multicast) (InternetAddress(AtakSettings.multicastHost), AtakSettings.multicastPort),
      ];
      for (final e in events) {
        final bytes = utf8.encode(e.toXml());
        for (final (addr, port) in targets) {
          sock.send(bytes, addr, port);
        }
        _lastSent[e.uid] = now;
      }
      sent += events.length;
      return events.length;
    } catch (e) {
      DebugLog.log('ATAK: send failed: $e');
      return 0;
    }
  }

  @override
  void dispose() {
    _socket?.close();
    super.dispose();
  }
}

final atakConnectorProvider = StateNotifierProvider<AtakConnector, AtakSettings>((ref) => AtakConnector());
