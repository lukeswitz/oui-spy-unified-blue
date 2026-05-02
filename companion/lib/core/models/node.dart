import 'package:freezed_annotation/freezed_annotation.dart';

part 'node.freezed.dart';
part 'node.g.dart';

/// Represents a connected OUI-SPY hardware node.
@freezed
class Node with _$Node {
  const factory Node({
    required String id,
    required String name,
    required String macAddress,
    String? firmwareVersion,
    int? lastSeen,
    String? configJson,
    String? configHash,
    required int createdAt,
  }) = _Node;

  factory Node.fromJson(Map<String, dynamic> json) => _$NodeFromJson(json);
}

/// BLE connection state for a node.
enum NodeConnectionState {
  disconnected,
  scanning,
  connecting,
  negotiating,
  syncing,
  ready,
  reconnecting,
}
