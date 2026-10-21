import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:oui_spy/core/link/link_session.dart';

class NetLinkTarget {
  const NetLinkTarget(this.interfaceName);

  static const boardHost = '192.168.7.1';
  static const port = 4700;

  final String interfaceName;

  static bool get supported => Platform.isIOS || Platform.isMacOS;

  String get label => '$boardHost via $interfaceName';

  static Future<NetLinkTarget?> find() async {
    if (!supported) return null;
    final interfaces = await NetworkInterface.list(type: InternetAddressType.IPv4);
    for (final i in interfaces) {
      for (final a in i.addresses) {
        if (a.address.startsWith('192.168.7.') && a.address != boardHost) {
          return NetLinkTarget(i.name);
        }
      }
    }
    return null;
  }

  Future<LinkTransport> open() async {
    final socket = await Socket.connect(boardHost, port, timeout: const Duration(seconds: 3));
    socket.setOption(SocketOption.tcpNoDelay, true);
    return _TcpLinkTransport(socket);
  }
}

class _TcpLinkTransport implements LinkTransport {
  _TcpLinkTransport(this._socket);

  final Socket _socket;

  @override
  Stream<Uint8List> get input => _socket;

  @override
  Future<void> send(Uint8List bytes) async {
    _socket.add(bytes);
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    _socket.destroy();
  }
}
