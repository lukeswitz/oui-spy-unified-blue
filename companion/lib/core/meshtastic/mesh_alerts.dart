// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/classify/signature_engine.dart' show SignatureClass;
import 'package:oui_spy/core/dashboard/dashboard_meshtastic.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_state.dart';
import 'package:oui_spy/core/notifications/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MeshAlertType {
  flock('Flock', 'Flock cameras and their gear'),
  drone('Drones', 'Remote ID drones'),
  detector('Detector and watchlist', 'Board detections and your watchlist hits'),
  foxhunt('Foxhunt', 'Target getting close, when foxhunt alerts are on'),
  nodes('Node down and up', 'A mesh node dropped off or came back');

  const MeshAlertType(this.label, this.hint);

  final String label;
  final String hint;
}

const meshAlertDefaultTypes = {
  MeshAlertType.flock,
  MeshAlertType.drone,
  MeshAlertType.detector,
  MeshAlertType.nodes,
};

const meshAlertMaxNodes = 4;
const meshAlertMinGap = 10;
const meshAlertMaxGap = 600;
const meshAlertDefaultGap = 60;
const meshAlertMinCap = 1;
const meshAlertMaxCap = 200;
const meshAlertDefaultCap = 50;

/// The alert type of a notification, or null when it is never sent: the silent suspected-detection channel.
/// Class alerts for drones travel on the detector channel and carry the kind `drone`.
MeshAlertType? meshAlertTypeOf(AlertEvent e) => switch (e.channel) {
      NotifChannel.flock => MeshAlertType.flock,
      NotifChannel.drone => MeshAlertType.drone,
      NotifChannel.foxhunt => MeshAlertType.foxhunt,
      NotifChannel.nodes => MeshAlertType.nodes,
      NotifChannel.detector => e.kind == SignatureClass.drone.name ? MeshAlertType.drone : MeshAlertType.detector,
      _ => null,
    };

/// The message for an alert: "OUI-APEX title: detail" on one line, cut on a character boundary to fit one packet.
String meshAlertText(String title, String detail, {int maxBytes = MeshtasticProto.maxTextBytes}) {
  final d = detail.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' · ').trim();
  final flat = d.isEmpty ? 'OUI-APEX $title' : 'OUI-APEX $title: $d';
  if (utf8.encode(flat).length <= maxBytes) return flat;
  const ellipsis = '…';
  final room = maxBytes - utf8.encode(ellipsis).length;
  final out = StringBuffer();
  var bytes = 0;
  for (final rune in flat.runes) {
    final ch = String.fromCharCode(rune);
    final n = utf8.encode(ch).length;
    if (bytes + n > room) break;
    out.write(ch);
    bytes += n;
  }
  return '${out.toString().trimRight()}$ellipsis';
}

/// Splits a list of node ids like `!0a1b2c3d` on spaces, commas and semicolons. The broadcast id and the zero id
/// are bad: either would not reach one node.
({List<int> nodes, List<String> bad}) parseMeshNodeIds(String text) {
  final nodes = <int>[];
  final bad = <String>[];
  for (final raw in text.split(RegExp(r'[\s,;]+')).where((s) => s.isNotEmpty)) {
    final id = raw.toLowerCase();
    final value = isMeshNodeId(id) ? int.parse(id.substring(1), radix: 16) : null;
    if (value == null || value == 0 || value == MeshtasticProto.broadcast) {
      bad.add(raw);
    } else if (!nodes.contains(value)) {
      nodes.add(value);
    }
  }
  return (nodes: nodes, bad: bad);
}

String meshAlertDay(DateTime t) =>
    '${t.year.toString().padLeft(4, '0')}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';

enum MeshAlertVerdict { send, tooSoon, capReached }

MeshAlertVerdict meshAlertVerdict({
  required DateTime now,
  required DateTime? lastSent,
  required int sentToday,
  required int gapSeconds,
  required int dailyCap,
}) {
  if (sentToday >= dailyCap) return MeshAlertVerdict.capReached;
  if (lastSent != null && now.difference(lastSent).inSeconds < gapSeconds) return MeshAlertVerdict.tooSoon;
  return MeshAlertVerdict.send;
}

class MeshAlertState {
  const MeshAlertState({
    this.enabled = false,
    this.types = meshAlertDefaultTypes,
    this.gapSeconds = meshAlertDefaultGap,
    this.dailyCap = meshAlertDefaultCap,
    this.nodes = const [],
    this.day = '',
    this.sent = 0,
    this.skipped = 0,
    this.lastSent,
  });

  final bool enabled;
  final Set<MeshAlertType> types;
  final int gapSeconds;
  final int dailyCap;
  final List<String> nodes;
  final String day;
  final int sent;
  final int skipped;
  final DateTime? lastSent;

  int sentOn(DateTime now) => day == meshAlertDay(now) ? sent : 0;

  int skippedOn(DateTime now) => day == meshAlertDay(now) ? skipped : 0;

  MeshAlertState copyWith({
    bool? enabled,
    Set<MeshAlertType>? types,
    int? gapSeconds,
    int? dailyCap,
    List<String>? nodes,
    String? day,
    int? sent,
    int? skipped,
    DateTime? lastSent,
  }) =>
      MeshAlertState(
        enabled: enabled ?? this.enabled,
        types: types ?? this.types,
        gapSeconds: gapSeconds ?? this.gapSeconds,
        dailyCap: dailyCap ?? this.dailyCap,
        nodes: nodes ?? this.nodes,
        day: day ?? this.day,
        sent: sent ?? this.sent,
        skipped: skipped ?? this.skipped,
        lastSent: lastSent ?? this.lastSent,
      );
}

typedef MeshAlertSender = Future<String?> Function(String text, List<int> to);

/// Sends the app's alerts over the phone's Meshtastic radio without a tap, when the user turned that on. An alert
/// is skipped, and counted, when the radio cannot send it now or it breaks the gap or the daily cap. Nothing here
/// ever sends a position.
class MeshAlertNotifier extends StateNotifier<MeshAlertState> {
  MeshAlertNotifier({required MeshAlertSender send, DateTime Function()? clock})
      : _send = send,
        _clock = clock ?? DateTime.now,
        super(const MeshAlertState()) {
    _load();
  }

  static const _kOn = 'mt_alert_on',
      _kTypes = 'mt_alert_types',
      _kGap = 'mt_alert_gap',
      _kCap = 'mt_alert_cap',
      _kNodes = 'mt_alert_nodes',
      _kDay = 'mt_alert_day',
      _kSent = 'mt_alert_sent',
      _kSkipped = 'mt_alert_skipped',
      _kLast = 'mt_alert_last';

  final MeshAlertSender _send;
  final DateTime Function() _clock;
  bool _changed = false;

  DateTime get now => _clock();
  bool _sending = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed || !mounted) return;
    final saved = p.getStringList(_kTypes);
    final last = p.getInt(_kLast);
    state = MeshAlertState(
      enabled: p.getBool(_kOn) ?? false,
      types: saved == null ? meshAlertDefaultTypes : {for (final t in MeshAlertType.values) if (saved.contains(t.name)) t},
      gapSeconds: (p.getInt(_kGap) ?? meshAlertDefaultGap).clamp(meshAlertMinGap, meshAlertMaxGap),
      dailyCap: (p.getInt(_kCap) ?? meshAlertDefaultCap).clamp(meshAlertMinCap, meshAlertMaxCap),
      nodes: parseMeshNodeIds(p.getString(_kNodes) ?? '').nodes.map(meshtasticNodeId).toList(),
      day: p.getString(_kDay) ?? '',
      sent: p.getInt(_kSent) ?? 0,
      skipped: p.getInt(_kSkipped) ?? 0,
      lastSent: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    );
  }

  Future<void> setEnabled(bool on) async {
    _changed = true;
    state = state.copyWith(enabled: on);
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOn, on);
  }

  Future<void> setType(MeshAlertType type, bool on) async {
    _changed = true;
    final types = {...state.types};
    on ? types.add(type) : types.remove(type);
    state = state.copyWith(types: types);
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_kTypes, [for (final t in types) t.name]);
  }

  Future<void> setGap(int seconds) async {
    _changed = true;
    final v = seconds.clamp(meshAlertMinGap, meshAlertMaxGap);
    state = state.copyWith(gapSeconds: v);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kGap, v);
  }

  Future<void> setCap(int perDay) async {
    _changed = true;
    final v = perDay.clamp(meshAlertMinCap, meshAlertMaxCap);
    state = state.copyWith(dailyCap: v);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCap, v);
  }

  /// Saves the nodes to send to instead of the channel. Empty text clears them. Returns why it was not saved.
  Future<String?> setNodes(String text) async {
    final r = parseMeshNodeIds(text);
    if (r.bad.isNotEmpty) return 'A node id is ! and 8 hex digits, like !0a1b2c3d';
    if (r.nodes.length > meshAlertMaxNodes) return 'Up to $meshAlertMaxNodes nodes';
    _changed = true;
    final ids = r.nodes.map(meshtasticNodeId).toList();
    state = state.copyWith(nodes: ids);
    final p = await SharedPreferences.getInstance();
    await p.setString(_kNodes, ids.join(' '));
    return null;
  }

  Future<void> _store() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kDay, state.day);
    await p.setInt(_kSent, state.sent);
    await p.setInt(_kSkipped, state.skipped);
    final last = state.lastSent;
    if (last != null) await p.setInt(_kLast, last.millisecondsSinceEpoch);
  }

  MeshAlertState _rolled(DateTime now) {
    final day = meshAlertDay(now);
    return state.day == day ? state : state.copyWith(day: day, sent: 0, skipped: 0);
  }

  Future<void> _skip(DateTime now) async {
    if (!mounted) return;
    final s = _rolled(now);
    state = s.copyWith(skipped: s.skipped + 1);
    await _store();
  }

  void onAlert(AlertEvent e) => unawaited(handle(e));

  /// Sends [e] when automatic alerts are on and its type is chosen. Returns true when it went out.
  Future<bool> handle(AlertEvent e) async {
    if (!state.enabled) return false;
    final type = meshAlertTypeOf(e);
    if (type == null || !state.types.contains(type)) return false;
    final now = _clock();
    if (_sending) {
      await _skip(now);
      return false;
    }
    final s = _rolled(now);
    final verdict = meshAlertVerdict(
      now: now,
      lastSent: s.lastSent,
      sentToday: s.sent,
      gapSeconds: s.gapSeconds,
      dailyCap: s.dailyCap,
    );
    if (verdict != MeshAlertVerdict.send) {
      await _skip(now);
      return false;
    }
    _sending = true;
    String? why;
    try {
      why = await _send(meshAlertText(e.title, e.detail), parseMeshNodeIds(s.nodes.join(' ')).nodes);
    } finally {
      _sending = false;
    }
    if (!mounted) return why == null;
    if (why != null) {
      await _skip(now);
      return false;
    }
    final r = _rolled(now);
    state = r.copyWith(sent: r.sent + 1, lastSent: now);
    await _store();
    return true;
  }
}

final meshAlertProvider = StateNotifierProvider<MeshAlertNotifier, MeshAlertState>((ref) {
  final notifier = MeshAlertNotifier(
    send: (text, to) => ref.read(meshtasticProvider.notifier).sendAlert(text, to: to),
  );
  final service = ref.read(notificationServiceProvider);
  service.addAlertListener(notifier.onAlert);
  ref.onDispose(() => service.removeAlertListener(notifier.onAlert));
  return notifier;
});
