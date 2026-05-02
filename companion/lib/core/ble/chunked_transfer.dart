import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Opcodes for chunked transfer protocol.
class ChunkOp {
  const ChunkOp._();
  static const start = 0x01;
  static const data = 0x02;
  static const commit = 0x03;
  static const abort = 0x04;
  static const ack = 0x05;
}

/// Chunked transfer for payloads exceeding BLE MTU.
///
/// Protocol:
///   START:  opcode(0x01)[1] + total_length[4] + crc32[4] = 9 bytes
///   DATA:   opcode(0x02)[1] + seq_num[2] + payload[N]   = 3+N bytes
///   COMMIT: opcode(0x03)[1]                               = 1 byte
///   ABORT:  opcode(0x04)[1]                               = 1 byte
///   ACK:    opcode(0x05)[1] + seq_num[2] + status[1]     = 4 bytes (notify)
class ChunkedTransfer {
  ChunkedTransfer({
    required this.characteristic,
    required this.mtu,
    this.ackTimeout = const Duration(seconds: 5),
  });

  final BluetoothCharacteristic characteristic;
  final int mtu;
  final Duration ackTimeout;

  /// Send a large payload using chunked transfer.
  /// Returns true on success, false on abort/failure.
  Future<bool> send(
    Uint8List payload, {
    StreamSubscription<List<int>>? ackSubscription,
  }) async {
    final crc = _crc32(payload);
    final chunkSize = mtu - 3; // 3 bytes for opcode + seq_num

    // START packet
    final startPacket = ByteData(9);
    startPacket.setUint8(0, ChunkOp.start);
    startPacket.setUint32(1, payload.length, Endian.little);
    startPacket.setUint32(5, crc, Endian.little);
    await characteristic.write(
      startPacket.buffer.asUint8List(),
      withoutResponse: false,
    );

    // DATA packets
    int offset = 0;
    int seqNum = 0;
    while (offset < payload.length) {
      final end = (offset + chunkSize).clamp(0, payload.length);
      final chunk = payload.sublist(offset, end);

      final dataPacket = Uint8List(3 + chunk.length);
      final view = ByteData.sublistView(dataPacket);
      view.setUint8(0, ChunkOp.data);
      view.setUint16(1, seqNum, Endian.little);
      dataPacket.setRange(3, 3 + chunk.length, chunk);

      await characteristic.write(dataPacket, withoutResponse: false);

      offset = end;
      seqNum++;
    }

    // COMMIT packet
    await characteristic.write(
      Uint8List.fromList([ChunkOp.commit]),
      withoutResponse: false,
    );

    return true;
  }

  /// Receive a large payload using chunked transfer.
  /// Listens on characteristic notifications for START/DATA/COMMIT.
  Stream<Uint8List> receive() {
    final controller = StreamController<Uint8List>();
    Uint8List? buffer;
    int expectedLength = 0;
    int expectedCrc = 0;
    int writeOffset = 0;

    final sub = characteristic.onValueReceived.listen((data) {
      if (data.isEmpty) return;
      final opcode = data[0];
      final view = ByteData.sublistView(Uint8List.fromList(data));

      switch (opcode) {
        case ChunkOp.start:
          expectedLength = view.getUint32(1, Endian.little);
          expectedCrc = view.getUint32(5, Endian.little);
          buffer = Uint8List(expectedLength);
          writeOffset = 0;

        case ChunkOp.data:
          if (buffer == null) return;
          final payload = data.sublist(3);
          final end = (writeOffset + payload.length).clamp(0, expectedLength);
          buffer!.setRange(writeOffset, end, payload);
          writeOffset = end;

        case ChunkOp.commit:
          if (buffer == null) return;
          final actualCrc = _crc32(buffer!);
          if (actualCrc == expectedCrc) {
            controller.add(buffer!);
          } else {
            controller.addError(
              Exception('CRC mismatch: expected $expectedCrc, got $actualCrc'),
            );
          }
          buffer = null;

        case ChunkOp.abort:
          buffer = null;
          controller.addError(Exception('Transfer aborted by remote'));
      }
    });

    controller.onCancel = () => sub.cancel();
    return controller.stream;
  }

  /// CRC32 (IEEE 802.3) matching the firmware implementation.
  static int _crc32(Uint8List data) {
    int crc = 0xFFFFFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int j = 0; j < 8; j++) {
        if (crc & 1 == 1) {
          crc = (crc >> 1) ^ 0xEDB88320;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFFFFFF;
  }
}
