// Copyright (c) 2026 Luke Switzer
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_link.dart';
import 'package:oui_spy/core/meshtastic/meshtastic_proto.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum MtLinkState { off, scanning, connecting, ready, error }

extension MtLinkStateText on MtLinkState {
  String get label => switch (this) {
        MtLinkState.off => 'Off',
        MtLinkState.scanning => 'Looking',
        MtLinkState.connecting => 'Connecting',
        MtLinkState.ready => 'Ready',
        MtLinkState.error => 'Error',
      };
}

class MeshtasticState {
  const MeshtasticState({
    this.link = MtLinkState.off,
    this.radioId = '',
    this.radioName = '',
    this.error = '',
    this.myNum,
    this.nodes = const {},
    this.channels = const [],
    this.channelIndex,
    this.inbox = const [],
    this.found = const [],
    this.sent = 0,
    this.heard = 0,
    this.lastSent,
  });

  final MtLinkState link;
  final String radioId;
  final String radioName;
  final String error;
  final int? myNum;
  final Map<int, MtNode> nodes;
  final List<MtChannel> channels;
  final int? channelIndex;
  final List<MtText> inbox;
  final List<MtRadioFound> found;
  final int sent;
  final int heard;
  final DateTime? lastSent;

  bool get hasRadio => radioId.isNotEmpty;

  List<MtChannel> get privateChannels => [for (final c in channels) if (c.isPrivate) c];

  MtChannel? get channel {
    for (final c in channels) {
      if (c.index == channelIndex && c.isPrivate) return c;
    }
    return null;
  }

  MeshtasticState copyWith({
    MtLinkState? link,
    String? radioId,
    String? radioName,
    String? error,
    int? myNum,
    Map<int, MtNode>? nodes,
    List<MtChannel>? channels,
    int? channelIndex,
    bool clearChannel = false,
    List<MtText>? inbox,
    List<MtRadioFound>? found,
    int? sent,
    int? heard,
    DateTime? lastSent,
  }) =>
      MeshtasticState(
        link: link ?? this.link,
        radioId: radioId ?? this.radioId,
        radioName: radioName ?? this.radioName,
        error: error ?? this.error,
        myNum: myNum ?? this.myNum,
        nodes: nodes ?? this.nodes,
        channels: channels ?? this.channels,
        channelIndex: clearChannel ? null : (channelIndex ?? this.channelIndex),
        inbox: inbox ?? this.inbox,
        found: found ?? this.found,
        sent: sent ?? this.sent,
        heard: heard ?? this.heard,
        lastSent: lastSent ?? this.lastSent,
      );
}

/// The phone's own Meshtastic radio, over Bluetooth. Nothing is sent by radio unless the user taps a send button,
/// and it is only ever sent on a channel that has its own key. The radio's key is read to tell public from private
/// and is neither kept nor shown.
class MeshtasticNotifier extends StateNotifier<MeshtasticState> {
  MeshtasticNotifier({
    required MeshtasticBle ble,
    Random? random,
    this.setupTimeout = const Duration(seconds: 20),
    DateTime Function()? clock,
  })  : _ble = ble,
        _random = random ?? Random.secure(),
        _clock = clock ?? DateTime.now,
        super(const MeshtasticState()) {
    _load();
  }

  static const _kId = 'mt_radio_id', _kName = 'mt_radio_name', _kChannel = 'mt_channel';
  static const inboxLimit = 50;

  final MeshtasticBle _ble;
  final Random _random;
  final DateTime Function() _clock;
  final Duration setupTimeout;
  MeshtasticLink? _link;
  StreamSubscription<void>? _numSub;
  Completer<void>? _setup;
  int _nonce = 0;
  bool _draining = false;
  bool _again = false;
  bool _changed = false;

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (_changed || !mounted) return;
    state = state.copyWith(
      radioId: p.getString(_kId) ?? '',
      radioName: p.getString(_kName) ?? '',
      channelIndex: p.getInt(_kChannel),
    );
  }

  Future<void> scan() async {
    _changed = true;
    state = state.copyWith(link: MtLinkState.scanning, error: '', found: const []);
    try {
      final found = await _ble.scan();
      if (!mounted) return;
      state = state.copyWith(link: MtLinkState.off, found: found);
    } catch (e) {
      if (mounted) state = state.copyWith(link: MtLinkState.error, error: "couldn't look for radios ($e)");
    }
  }

  Future<void> connect({MtRadioFound? radio}) async {
    _changed = true;
    final id = radio?.id ?? state.radioId;
    if (id.isEmpty) return;
    final name = radio?.name ?? state.radioName;
    await _drop();
    state = state.copyWith(link: MtLinkState.connecting, radioId: id, radioName: name, error: '', channels: const [], nodes: const {});
    final p = await SharedPreferences.getInstance();
    await p.setString(_kId, id);
    await p.setString(_kName, name);
    try {
      final link = await _ble.open(id);
      if (!mounted) {
        await link.close();
        return;
      }
      _link = link;
      unawaited(link.closed.then((_) => _lost(link)));
      _numSub = link.fromNum.listen((_) => _drain());
      _nonce = 1 + _random.nextInt(0x7FFFFFFE);
      final setup = _setup = Completer<void>();
      await (() async {
        await link.writeToRadio(MeshtasticProto.encodeWantConfig(_nonce));
        await _drain();
        await setup.future;
      })()
          .timeout(setupTimeout);
      if (!mounted) return;
      final saved = p.getInt(_kChannel);
      final keep = state.privateChannels.any((c) => c.index == saved) ? saved : null;
      state = state.copyWith(link: MtLinkState.ready, channelIndex: keep, clearChannel: keep == null);
    } on TimeoutException {
      await _fail('the radio connected but never finished sending its setup (pair it: Android asks for its PIN, 123456 unless it was changed)');
    } catch (e) {
      await _fail("couldn't reach the radio: out of range, or held by another phone or the Meshtastic app ($e)");
    }
  }

  Future<void> _fail(String why) async {
    await _drop();
    if (mounted) state = state.copyWith(link: MtLinkState.error, error: why);
  }

  void _lost(MeshtasticLink link) {
    if (!mounted || _link != link) return;
    _link = null;
    _numSub?.cancel();
    _numSub = null;
    state = state.copyWith(link: MtLinkState.error, error: 'the radio disconnected');
  }

  Future<void> _drop() async {
    final l = _link;
    _link = null;
    await _numSub?.cancel();
    _numSub = null;
    _setup = null;
    if (l != null) await l.close();
  }

  Future<void> disconnect() async {
    await _drop();
    if (mounted) state = state.copyWith(link: MtLinkState.off, error: '');
  }

  /// Disconnects and forgets the saved radio and channel.
  Future<void> forget() async {
    _changed = true;
    await _drop();
    final p = await SharedPreferences.getInstance();
    await p.remove(_kId);
    await p.remove(_kName);
    await p.remove(_kChannel);
    if (mounted) {
      state = const MeshtasticState();
    }
  }

  /// Reads the radio until its queue is empty. Notifications that arrive during a read start another pass.
  Future<void> _drain() async {
    final link = _link;
    if (link == null) return;
    if (_draining) {
      _again = true;
      return;
    }
    _draining = true;
    try {
      do {
        _again = false;
        while (true) {
          final bytes = await link.readFromRadio();
          if (bytes.isEmpty) break;
          _handle(MeshtasticProto.decodeFromRadio(bytes));
        }
      } while (_again && _link == link);
    } finally {
      _draining = false;
    }
  }

  void _handle(FromRadio m) {
    if (!mounted) return;
    switch (m) {
      case FromMyInfo():
        state = state.copyWith(myNum: m.nodeNum);
      case FromNodeInfo():
        state = state.copyWith(nodes: {...state.nodes, m.node.nodeNum: m.node});
      case FromChannel():
        final rest = [for (final c in state.channels) if (c.index != m.channel.index) c];
        state = state.copyWith(channels: [...rest, m.channel]..sort((a, b) => a.index.compareTo(b.index)));
      case FromConfigComplete():
        if (m.id == _nonce) {
          final s = _setup;
          if (s != null && !s.isCompleted) s.complete();
        }
      case FromPacket():
        _packet(m.packet);
      case FromOther():
        break;
    }
  }

  void _packet(MtPacket p) {
    if (p.portnum != MeshtasticProto.portText || p.from == state.myNum) return;
    final ch = state.channels.where((c) => c.index == p.channel).firstOrNull;
    if (ch == null || !ch.isPrivate) return;
    final text = utf8.decode(p.payload, allowMalformed: true);
    final at = p.rxTime > 0 ? DateTime.fromMillisecondsSinceEpoch(p.rxTime * 1000) : _clock();
    final inbox = [MtText(from: p.from, channel: p.channel, text: text, at: at, snr: p.snr, rssi: p.rssi), ...state.inbox];
    state = state.copyWith(inbox: inbox.take(inboxLimit).toList(), heard: state.heard + 1);
  }

  /// Chooses the channel to send on. Only a channel with its own key can be chosen.
  Future<String?> selectChannel(int index) async {
    final c = state.channels.where((c) => c.index == index).firstOrNull;
    if (c == null || !c.isPrivate) {
      return '${c?.label ?? 'That channel'} has no key of its own. The app sends only on a private channel';
    }
    _changed = true;
    state = state.copyWith(channelIndex: index);
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kChannel, index);
    return null;
  }

  String? _sendCheck() {
    if (state.link != MtLinkState.ready || _link == null) return 'The radio is not connected';
    if (state.channel == null) return 'Pick a private channel first';
    return null;
  }

  int _packetId() => 1 + _random.nextInt(0xFFFFFFFE);

  Future<String?> _send(Uint8List bytes) async {
    try {
      await _link!.writeToRadio(bytes);
    } catch (e) {
      return "Not sent: the radio didn't take it ($e)";
    }
    if (mounted) state = state.copyWith(sent: state.sent + 1, lastSent: _clock());
    return null;
  }

  /// Sends a text message on the chosen private channel. Returns why it was not sent, or null.
  Future<String?> sendText(String text) async {
    final why = _sendCheck();
    if (why != null) return why;
    final t = text.trim();
    if (t.isEmpty) return 'Type a message first';
    if (utf8.encode(t).length > MeshtasticProto.maxTextBytes) return 'Messages are up to ${MeshtasticProto.maxTextBytes} characters';
    return _send(MeshtasticProto.encodeText(t, channel: state.channel!.index, id: _packetId()));
  }

  /// Sends a position on the chosen private channel.
  Future<String?> sendPosition(double lat, double lon, {double? altitude}) async {
    final why = _sendCheck();
    if (why != null) return why;
    if (lat < -90 || lat > 90 || lon < -180 || lon > 180 || (lat == 0 && lon == 0)) return 'No valid position yet';
    return _send(MeshtasticProto.encodePosition(lat, lon,
        altitude: altitude?.round(), time: _clock(), channel: state.channel!.index, id: _packetId()));
  }

  @override
  void dispose() {
    _numSub?.cancel();
    _link?.close();
    super.dispose();
  }
}

final meshtasticProvider = StateNotifierProvider<MeshtasticNotifier, MeshtasticState>((ref) {
  return MeshtasticNotifier(ble: FbpMeshtasticBle());
});
