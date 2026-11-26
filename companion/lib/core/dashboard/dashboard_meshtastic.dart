// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

/// What the home dashboard says about its Meshtastic link (GET /api/meshtastic) and the settings the app can
/// change (POST /api/settings, key `meshtastic`). The radio port and the channel are set only here and on the
/// dashboard's own Settings tab; the dashboard checks every value again.
const meshEventKinds = ['new_devices', 'drones', 'lost_nodes', 'nodes'];

String meshEventTitle(String kind) => switch (kind) {
      'new_devices' => 'New devices',
      'drones' => 'Drones',
      'lost_nodes' => 'Lost nodes',
      'nodes' => 'Nodes',
      _ => kind,
    };

String meshEventHint(String kind) => switch (kind) {
      'new_devices' => 'A batch a minute',
      'drones' => 'When one is first heard',
      'lost_nodes' => 'A lost node seen again',
      'nodes' => 'Nodes joining and dropping',
      _ => '',
    };

String meshStateLabel(String state) => switch (state) {
      'connected' => 'Connected',
      'connecting' => 'Connecting',
      'retrying' => 'Not connected: retrying',
      'error' => 'Failed',
      _ => 'Off',
    };

/// A Meshtastic node id is `!` and eight hex digits.
bool isMeshNodeId(String s) => RegExp(r'^![0-9a-fA-F]{8}$').hasMatch(s.trim());

class MeshtasticConfig {
  const MeshtasticConfig({
    this.enabled = false,
    this.port = '',
    this.channel = 1,
    this.recipients = const [],
    this.send = const {'new_devices': false, 'drones': false, 'lost_nodes': false, 'nodes': false},
  });

  final bool enabled;
  final String port;
  final int channel;
  final List<String> recipients;
  final Map<String, bool> send;

  static MeshtasticConfig fromJson(Object? j) {
    if (j is! Map) return const MeshtasticConfig();
    final send = j['send'] is Map ? j['send'] as Map : const {};
    return MeshtasticConfig(
      enabled: j['enabled'] == true,
      port: j['port'] is String ? j['port'] as String : '',
      channel: j['channel'] is num ? (j['channel'] as num).toInt() : 1,
      recipients: [
        if (j['recipients'] is List)
          for (final r in j['recipients'] as List)
            if (r is String) r,
      ],
      send: {for (final k in meshEventKinds) k: send[k] == true},
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': enabled,
        'port': port,
        'channel': channel,
        'recipients': recipients,
        'send': send,
      };

  MeshtasticConfig copyWith({
    bool? enabled,
    String? port,
    int? channel,
    List<String>? recipients,
    Map<String, bool>? send,
  }) =>
      MeshtasticConfig(
        enabled: enabled ?? this.enabled,
        port: port ?? this.port,
        channel: channel ?? this.channel,
        recipients: recipients ?? this.recipients,
        send: send ?? this.send,
      );
}

class MeshChannel {
  const MeshChannel({required this.index, required this.name, required this.private});

  final int index;
  final String name;

  /// Has a key of its own. The dashboard never sends on a channel without one (the public default channel).
  final bool private;

  static MeshChannel? fromJson(Object? j) {
    if (j is! Map || j['index'] is! num) return null;
    return MeshChannel(
      index: (j['index'] as num).toInt(),
      name: j['name'] is String ? j['name'] as String : '',
      private: j['private'] == true,
    );
  }
}

class MeshHeard {
  const MeshHeard({required this.at, required this.from, required this.name, required this.channel, required this.text});

  final DateTime at;
  final String from;
  final String name;
  final int channel;
  final String text;

  String get who => name.isNotEmpty ? name : from;

  static MeshHeard? fromJson(Object? j) {
    if (j is! Map || j['text'] is! String) return null;
    final ts = j['ts'] is num ? (j['ts'] as num).toDouble() : 0.0;
    return MeshHeard(
      at: DateTime.fromMillisecondsSinceEpoch((ts * 1000).round()),
      from: j['from'] is String ? j['from'] as String : '',
      name: j['name'] is String ? j['name'] as String : '',
      channel: j['channel'] is num ? (j['channel'] as num).toInt() : 0,
      text: j['text'] as String,
    );
  }
}

class MeshtasticStatus {
  const MeshtasticStatus({
    this.config = const MeshtasticConfig(),
    this.state = 'off',
    this.error = '',
    this.radio = '',
    this.radioName = '',
    this.channelName = '',
    this.channels = const [],
    this.sent = 0,
    this.failed = 0,
    this.queued = 0,
    this.heard = 0,
    this.last,
    this.inbox = const [],
  });

  final MeshtasticConfig config;

  /// `off`, `connecting`, `connected`, `retrying` or `error`.
  final String state;
  final String error;
  final String radio;
  final String radioName;
  final String channelName;
  final List<MeshChannel> channels;
  final int sent, failed, queued, heard;
  final DateTime? last;
  final List<MeshHeard> inbox;

  bool get connected => state == 'connected';

  static MeshtasticStatus fromJson(Map<String, dynamic> j) {
    int n(String k) => j[k] is num ? (j[k] as num).toInt() : 0;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return MeshtasticStatus(
      config: MeshtasticConfig.fromJson(j['config']),
      state: s('state').isEmpty ? 'off' : s('state'),
      error: s('error'),
      radio: s('radio'),
      radioName: s('radio_name'),
      channelName: s('channel_name'),
      channels: [
        if (j['channels'] is List)
          for (final c in j['channels'] as List) ?MeshChannel.fromJson(c),
      ],
      sent: n('sent'),
      failed: n('failed'),
      queued: n('queued'),
      heard: n('heard'),
      last: j['last'] is num ? DateTime.fromMillisecondsSinceEpoch(((j['last'] as num) * 1000).round()) : null,
      inbox: [
        if (j['inbox'] is List)
          for (final m in j['inbox'] as List) ?MeshHeard.fromJson(m),
      ],
    );
  }
}

class MeshPort {
  const MeshPort({required this.device, this.desc = '', this.espressif = false});

  final String device;
  final String desc;
  final bool espressif;

  static MeshPort? fromJson(Object? j) {
    if (j is! Map || j['device'] is! String) return null;
    return MeshPort(
      device: j['device'] as String,
      desc: j['desc'] is String ? j['desc'] as String : '',
      espressif: j['espressif'] == true,
    );
  }
}
