import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:oui_spy/core/link/link_characteristic.dart';
import 'package:oui_spy/core/link/link_frame.dart';

abstract class LinkTransport {
  Stream<Uint8List> get input;

  Future<void> send(Uint8List bytes);

  Future<void> close();
}

FlutterBluePlusException _linkError(String function, String description) =>
    FlutterBluePlusException(ErrorPlatform.fbp, function, null, 'usb: $description');

int linkIdFor(Guid uuid) => int.parse(uuid.str128.substring(0, 8), radix: 16);

Guid linkGuidFor(int id, Guid service) =>
    Guid('${id.toRadixString(16).padLeft(8, '0')}${service.str128.substring(8)}');

class LinkSession {
  LinkSession(this._transport);

  static const pingEvery = Duration(seconds: 1);
  static const helloTimeout = Duration(seconds: 3);

  final LinkTransport _transport;
  final _parser = LinkFrameParser();
  final Map<int, StreamController<List<int>>> _notify = {};
  final _done = Completer<void>();
  StreamSubscription<Uint8List>? _sub;
  Timer? _pingTimer;
  Future<void> _chain = Future.value();
  Completer<LinkFrame>? _pending;
  int _pendingType = 0;
  int _pendingId = 0;
  List<int> _ids = const [];
  int _maxPayload = linkMaxPayload;
  bool _closed = false;

  List<int> get ids => _ids;
  int get maxPayload => _maxPayload;
  int get crcErrors => _parser.crcErrors;
  bool get isOpen => !_closed;
  Future<void> get done => _done.future;

  Future<void> open() async {
    _sub = _transport.input.listen(_onBytes,
        onError: (Object _) => close(), onDone: close, cancelOnError: true);
    final ack = await _request(LinkFrameType.hello, 0, const [linkProtocolVersion],
        LinkFrameType.helloAck, helloTimeout);
    final p = ack.payload;
    if (p.length < 4) throw _linkError('hello', 'short hello reply');
    _maxPayload = p[1] | (p[2] << 8);
    final count = p[3];
    if (p.length < 4 + count * 2) throw _linkError('hello', 'truncated characteristic list');
    _ids = [for (var i = 0; i < count; i++) p[4 + i * 2] | (p[5 + i * 2] << 8)];
    _pingTimer = Timer.periodic(pingEvery, (_) => _ping());
  }

  Future<void> write(int id, List<int> value, Duration timeout) async {
    if (value.length > _maxPayload) {
      throw _linkError('write', '${value.length} bytes exceeds $_maxPayload');
    }
    final ack = await _request(LinkFrameType.write, id, value, LinkFrameType.writeAck, timeout);
    if (ack.payload.isEmpty || ack.payload[0] != 0) {
      throw _linkError('write', 'board rejected write to 0x${id.toRadixString(16)}');
    }
  }

  Future<List<int>> read(int id, Duration timeout) async {
    final rsp = await _request(LinkFrameType.read, id, const [], LinkFrameType.readRsp, timeout);
    if (rsp.payload.isEmpty || rsp.payload[0] != 0) {
      throw _linkError('read', 'board rejected read of 0x${id.toRadixString(16)}');
    }
    return rsp.payload.sublist(1);
  }

  Future<void> subscribe(int id, bool on, Duration timeout) async {
    final ack = await _request(
        LinkFrameType.subscribe, id, [on ? 1 : 0], LinkFrameType.subscribeAck, timeout);
    if (ack.payload.isEmpty || ack.payload[0] != 0) {
      throw _linkError('setNotifyValue', 'board rejected subscribe to 0x${id.toRadixString(16)}');
    }
  }

  Stream<List<int>> notifications(int id) =>
      _notify.putIfAbsent(id, StreamController<List<int>>.broadcast).stream;

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _pingTimer?.cancel();
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(_linkError('link', 'link closed'));
    }
    await _sub?.cancel();
    for (final c in _notify.values) {
      await c.close();
    }
    _notify.clear();
    try {
      await _transport.close();
    } finally {
      if (!_done.isCompleted) _done.complete();
    }
  }

  void _ping() {
    if (_closed || _pending != null) return;
    _request(LinkFrameType.ping, 0, const [], LinkFrameType.pong, helloTimeout)
        .then((_) {}, onError: (Object _) {
      close();
    });
  }

  Future<LinkFrame> _request(int type, int id, List<int> payload, int expect, Duration timeout) {
    final op = _chain.then((_) async {
      if (_closed) throw _linkError('link', 'link closed');
      final c = Completer<LinkFrame>();
      _pending = c;
      _pendingType = expect;
      _pendingId = id;
      try {
        await _transport.send(encodeLinkFrame(type, id, payload));
        return await c.future.timeout(timeout,
            onTimeout: () => throw _linkError('link', 'no reply to 0x${type.toRadixString(16)}'));
      } finally {
        if (identical(_pending, c)) _pending = null;
      }
    });
    _chain = op.then((_) {}, onError: (Object _) {});
    return op;
  }

  void _onBytes(Uint8List bytes) {
    for (final f in _parser.add(bytes)) {
      if (f.type == LinkFrameType.notify) {
        _notify[f.id]?.add(f.payload);
        continue;
      }
      final pending = _pending;
      if (pending != null &&
          !pending.isCompleted &&
          f.type == _pendingType &&
          f.id == _pendingId) {
        pending.complete(f);
      }
    }
  }
}

class UsbLinkCharacteristic implements LinkCharacteristic {
  UsbLinkCharacteristic(this._session, this.uuid) : _id = linkIdFor(uuid);

  final LinkSession _session;
  final int _id;

  @override
  final Guid uuid;

  @override
  Future<void> write(List<int> value,
          {bool withoutResponse = false, bool allowLongWrite = false, int timeout = 15}) =>
      _session.write(_id, value, Duration(seconds: timeout));

  @override
  Future<List<int>> read({int timeout = 15}) => _session.read(_id, Duration(seconds: timeout));

  @override
  Future<bool> setNotifyValue(bool notify,
      {int timeout = 15, bool forceIndications = false}) async {
    await _session.subscribe(_id, notify, Duration(seconds: timeout));
    return true;
  }

  @override
  Stream<List<int>> get onValueReceived => _session.notifications(_id);
}
