// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

Session _$SessionFromJson(Map<String, dynamic> json) {
  return _Session.fromJson(json);
}

/// @nodoc
mixin _$Session {
  String get id => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get nodeId => throw _privateConstructorUsedError;
  int get startedAt => throw _privateConstructorUsedError;
  int? get endedAt => throw _privateConstructorUsedError;
  int get enginesActive => throw _privateConstructorUsedError;
  int get detectionCount => throw _privateConstructorUsedError;
  int get uniqueMacCount => throw _privateConstructorUsedError;
  double get distanceKm => throw _privateConstructorUsedError;
  bool get exported => throw _privateConstructorUsedError;
  bool get isWardrive => throw _privateConstructorUsedError;

  /// Serializes this Session to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionCopyWith<Session> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionCopyWith<$Res> {
  factory $SessionCopyWith(Session value, $Res Function(Session) then) =
      _$SessionCopyWithImpl<$Res, Session>;
  @useResult
  $Res call({
    String id,
    String name,
    String nodeId,
    int startedAt,
    int? endedAt,
    int enginesActive,
    int detectionCount,
    int uniqueMacCount,
    double distanceKm,
    bool exported,
    bool isWardrive,
  });
}

/// @nodoc
class _$SessionCopyWithImpl<$Res, $Val extends Session>
    implements $SessionCopyWith<$Res> {
  _$SessionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? nodeId = null,
    Object? startedAt = null,
    Object? endedAt = freezed,
    Object? enginesActive = null,
    Object? detectionCount = null,
    Object? uniqueMacCount = null,
    Object? distanceKm = null,
    Object? exported = null,
    Object? isWardrive = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            nodeId: null == nodeId
                ? _value.nodeId
                : nodeId // ignore: cast_nullable_to_non_nullable
                      as String,
            startedAt: null == startedAt
                ? _value.startedAt
                : startedAt // ignore: cast_nullable_to_non_nullable
                      as int,
            endedAt: freezed == endedAt
                ? _value.endedAt
                : endedAt // ignore: cast_nullable_to_non_nullable
                      as int?,
            enginesActive: null == enginesActive
                ? _value.enginesActive
                : enginesActive // ignore: cast_nullable_to_non_nullable
                      as int,
            detectionCount: null == detectionCount
                ? _value.detectionCount
                : detectionCount // ignore: cast_nullable_to_non_nullable
                      as int,
            uniqueMacCount: null == uniqueMacCount
                ? _value.uniqueMacCount
                : uniqueMacCount // ignore: cast_nullable_to_non_nullable
                      as int,
            distanceKm: null == distanceKm
                ? _value.distanceKm
                : distanceKm // ignore: cast_nullable_to_non_nullable
                      as double,
            exported: null == exported
                ? _value.exported
                : exported // ignore: cast_nullable_to_non_nullable
                      as bool,
            isWardrive: null == isWardrive
                ? _value.isWardrive
                : isWardrive // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionImplCopyWith<$Res> implements $SessionCopyWith<$Res> {
  factory _$$SessionImplCopyWith(
    _$SessionImpl value,
    $Res Function(_$SessionImpl) then,
  ) = __$$SessionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String name,
    String nodeId,
    int startedAt,
    int? endedAt,
    int enginesActive,
    int detectionCount,
    int uniqueMacCount,
    double distanceKm,
    bool exported,
    bool isWardrive,
  });
}

/// @nodoc
class __$$SessionImplCopyWithImpl<$Res>
    extends _$SessionCopyWithImpl<$Res, _$SessionImpl>
    implements _$$SessionImplCopyWith<$Res> {
  __$$SessionImplCopyWithImpl(
    _$SessionImpl _value,
    $Res Function(_$SessionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? name = null,
    Object? nodeId = null,
    Object? startedAt = null,
    Object? endedAt = freezed,
    Object? enginesActive = null,
    Object? detectionCount = null,
    Object? uniqueMacCount = null,
    Object? distanceKm = null,
    Object? exported = null,
    Object? isWardrive = null,
  }) {
    return _then(
      _$SessionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        nodeId: null == nodeId
            ? _value.nodeId
            : nodeId // ignore: cast_nullable_to_non_nullable
                  as String,
        startedAt: null == startedAt
            ? _value.startedAt
            : startedAt // ignore: cast_nullable_to_non_nullable
                  as int,
        endedAt: freezed == endedAt
            ? _value.endedAt
            : endedAt // ignore: cast_nullable_to_non_nullable
                  as int?,
        enginesActive: null == enginesActive
            ? _value.enginesActive
            : enginesActive // ignore: cast_nullable_to_non_nullable
                  as int,
        detectionCount: null == detectionCount
            ? _value.detectionCount
            : detectionCount // ignore: cast_nullable_to_non_nullable
                  as int,
        uniqueMacCount: null == uniqueMacCount
            ? _value.uniqueMacCount
            : uniqueMacCount // ignore: cast_nullable_to_non_nullable
                  as int,
        distanceKm: null == distanceKm
            ? _value.distanceKm
            : distanceKm // ignore: cast_nullable_to_non_nullable
                  as double,
        exported: null == exported
            ? _value.exported
            : exported // ignore: cast_nullable_to_non_nullable
                  as bool,
        isWardrive: null == isWardrive
            ? _value.isWardrive
            : isWardrive // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionImpl implements _Session {
  const _$SessionImpl({
    required this.id,
    required this.name,
    required this.nodeId,
    required this.startedAt,
    this.endedAt,
    this.enginesActive = 0,
    this.detectionCount = 0,
    this.uniqueMacCount = 0,
    this.distanceKm = 0.0,
    this.exported = false,
    this.isWardrive = false,
  });

  factory _$SessionImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionImplFromJson(json);

  @override
  final String id;
  @override
  final String name;
  @override
  final String nodeId;
  @override
  final int startedAt;
  @override
  final int? endedAt;
  @override
  @JsonKey()
  final int enginesActive;
  @override
  @JsonKey()
  final int detectionCount;
  @override
  @JsonKey()
  final int uniqueMacCount;
  @override
  @JsonKey()
  final double distanceKm;
  @override
  @JsonKey()
  final bool exported;
  @override
  @JsonKey()
  final bool isWardrive;

  @override
  String toString() {
    return 'Session(id: $id, name: $name, nodeId: $nodeId, startedAt: $startedAt, endedAt: $endedAt, enginesActive: $enginesActive, detectionCount: $detectionCount, uniqueMacCount: $uniqueMacCount, distanceKm: $distanceKm, exported: $exported, isWardrive: $isWardrive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.nodeId, nodeId) || other.nodeId == nodeId) &&
            (identical(other.startedAt, startedAt) ||
                other.startedAt == startedAt) &&
            (identical(other.endedAt, endedAt) || other.endedAt == endedAt) &&
            (identical(other.enginesActive, enginesActive) ||
                other.enginesActive == enginesActive) &&
            (identical(other.detectionCount, detectionCount) ||
                other.detectionCount == detectionCount) &&
            (identical(other.uniqueMacCount, uniqueMacCount) ||
                other.uniqueMacCount == uniqueMacCount) &&
            (identical(other.distanceKm, distanceKm) ||
                other.distanceKm == distanceKm) &&
            (identical(other.exported, exported) ||
                other.exported == exported) &&
            (identical(other.isWardrive, isWardrive) ||
                other.isWardrive == isWardrive));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    name,
    nodeId,
    startedAt,
    endedAt,
    enginesActive,
    detectionCount,
    uniqueMacCount,
    distanceKm,
    exported,
    isWardrive,
  );

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      __$$SessionImplCopyWithImpl<_$SessionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionImplToJson(this);
  }
}

abstract class _Session implements Session {
  const factory _Session({
    required final String id,
    required final String name,
    required final String nodeId,
    required final int startedAt,
    final int? endedAt,
    final int enginesActive,
    final int detectionCount,
    final int uniqueMacCount,
    final double distanceKm,
    final bool exported,
    final bool isWardrive,
  }) = _$SessionImpl;

  factory _Session.fromJson(Map<String, dynamic> json) = _$SessionImpl.fromJson;

  @override
  String get id;
  @override
  String get name;
  @override
  String get nodeId;
  @override
  int get startedAt;
  @override
  int? get endedAt;
  @override
  int get enginesActive;
  @override
  int get detectionCount;
  @override
  int get uniqueMacCount;
  @override
  double get distanceKm;
  @override
  bool get exported;
  @override
  bool get isWardrive;

  /// Create a copy of Session
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionImplCopyWith<_$SessionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
