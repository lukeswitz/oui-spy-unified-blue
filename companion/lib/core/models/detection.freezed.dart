// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'detection.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

Detection _$DetectionFromJson(Map<String, dynamic> json) {
  return _Detection.fromJson(json);
}

/// @nodoc
mixin _$Detection {
  String get id => throw _privateConstructorUsedError;
  String get sessionId => throw _privateConstructorUsedError;
  String get nodeId => throw _privateConstructorUsedError;
  String get macAddress => throw _privateConstructorUsedError;
  Engine get engine => throw _privateConstructorUsedError;
  String get method => throw _privateConstructorUsedError;
  int get rssi => throw _privateConstructorUsedError;
  int get channel => throw _privateConstructorUsedError;
  int get deviceTimestampMs => throw _privateConstructorUsedError;
  DateTime get appTimestamp => throw _privateConstructorUsedError;
  String get deviceName => throw _privateConstructorUsedError;
  String get ssid => throw _privateConstructorUsedError;
  int get count => throw _privateConstructorUsedError;
  String get sourceNodeId => throw _privateConstructorUsedError;
  double? get latitude => throw _privateConstructorUsedError;
  double? get longitude => throw _privateConstructorUsedError;
  double? get altitude => throw _privateConstructorUsedError;
  double? get speed => throw _privateConstructorUsedError;
  double? get heading => throw _privateConstructorUsedError;
  double? get accuracy => throw _privateConstructorUsedError;
  int? get satelliteCount => throw _privateConstructorUsedError;
  FlockExtension? get flock => throw _privateConstructorUsedError;
  OdidExtension? get odid => throw _privateConstructorUsedError;
  UnipwnExtension? get unipwn => throw _privateConstructorUsedError;
  DetectorExtension? get detector => throw _privateConstructorUsedError;
  WardriveExtension? get wardrive => throw _privateConstructorUsedError;

  /// Serializes this Detection to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DetectionCopyWith<Detection> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DetectionCopyWith<$Res> {
  factory $DetectionCopyWith(Detection value, $Res Function(Detection) then) =
      _$DetectionCopyWithImpl<$Res, Detection>;
  @useResult
  $Res call({
    String id,
    String sessionId,
    String nodeId,
    String macAddress,
    Engine engine,
    String method,
    int rssi,
    int channel,
    int deviceTimestampMs,
    DateTime appTimestamp,
    String deviceName,
    String ssid,
    int count,
    String sourceNodeId,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? heading,
    double? accuracy,
    int? satelliteCount,
    FlockExtension? flock,
    OdidExtension? odid,
    UnipwnExtension? unipwn,
    DetectorExtension? detector,
    WardriveExtension? wardrive,
  });

  $FlockExtensionCopyWith<$Res>? get flock;
  $OdidExtensionCopyWith<$Res>? get odid;
  $UnipwnExtensionCopyWith<$Res>? get unipwn;
  $DetectorExtensionCopyWith<$Res>? get detector;
  $WardriveExtensionCopyWith<$Res>? get wardrive;
}

/// @nodoc
class _$DetectionCopyWithImpl<$Res, $Val extends Detection>
    implements $DetectionCopyWith<$Res> {
  _$DetectionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sessionId = null,
    Object? nodeId = null,
    Object? macAddress = null,
    Object? engine = null,
    Object? method = null,
    Object? rssi = null,
    Object? channel = null,
    Object? deviceTimestampMs = null,
    Object? appTimestamp = null,
    Object? deviceName = null,
    Object? ssid = null,
    Object? count = null,
    Object? sourceNodeId = null,
    Object? latitude = freezed,
    Object? longitude = freezed,
    Object? altitude = freezed,
    Object? speed = freezed,
    Object? heading = freezed,
    Object? accuracy = freezed,
    Object? satelliteCount = freezed,
    Object? flock = freezed,
    Object? odid = freezed,
    Object? unipwn = freezed,
    Object? detector = freezed,
    Object? wardrive = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            sessionId: null == sessionId
                ? _value.sessionId
                : sessionId // ignore: cast_nullable_to_non_nullable
                      as String,
            nodeId: null == nodeId
                ? _value.nodeId
                : nodeId // ignore: cast_nullable_to_non_nullable
                      as String,
            macAddress: null == macAddress
                ? _value.macAddress
                : macAddress // ignore: cast_nullable_to_non_nullable
                      as String,
            engine: null == engine
                ? _value.engine
                : engine // ignore: cast_nullable_to_non_nullable
                      as Engine,
            method: null == method
                ? _value.method
                : method // ignore: cast_nullable_to_non_nullable
                      as String,
            rssi: null == rssi
                ? _value.rssi
                : rssi // ignore: cast_nullable_to_non_nullable
                      as int,
            channel: null == channel
                ? _value.channel
                : channel // ignore: cast_nullable_to_non_nullable
                      as int,
            deviceTimestampMs: null == deviceTimestampMs
                ? _value.deviceTimestampMs
                : deviceTimestampMs // ignore: cast_nullable_to_non_nullable
                      as int,
            appTimestamp: null == appTimestamp
                ? _value.appTimestamp
                : appTimestamp // ignore: cast_nullable_to_non_nullable
                      as DateTime,
            deviceName: null == deviceName
                ? _value.deviceName
                : deviceName // ignore: cast_nullable_to_non_nullable
                      as String,
            ssid: null == ssid
                ? _value.ssid
                : ssid // ignore: cast_nullable_to_non_nullable
                      as String,
            count: null == count
                ? _value.count
                : count // ignore: cast_nullable_to_non_nullable
                      as int,
            sourceNodeId: null == sourceNodeId
                ? _value.sourceNodeId
                : sourceNodeId // ignore: cast_nullable_to_non_nullable
                      as String,
            latitude: freezed == latitude
                ? _value.latitude
                : latitude // ignore: cast_nullable_to_non_nullable
                      as double?,
            longitude: freezed == longitude
                ? _value.longitude
                : longitude // ignore: cast_nullable_to_non_nullable
                      as double?,
            altitude: freezed == altitude
                ? _value.altitude
                : altitude // ignore: cast_nullable_to_non_nullable
                      as double?,
            speed: freezed == speed
                ? _value.speed
                : speed // ignore: cast_nullable_to_non_nullable
                      as double?,
            heading: freezed == heading
                ? _value.heading
                : heading // ignore: cast_nullable_to_non_nullable
                      as double?,
            accuracy: freezed == accuracy
                ? _value.accuracy
                : accuracy // ignore: cast_nullable_to_non_nullable
                      as double?,
            satelliteCount: freezed == satelliteCount
                ? _value.satelliteCount
                : satelliteCount // ignore: cast_nullable_to_non_nullable
                      as int?,
            flock: freezed == flock
                ? _value.flock
                : flock // ignore: cast_nullable_to_non_nullable
                      as FlockExtension?,
            odid: freezed == odid
                ? _value.odid
                : odid // ignore: cast_nullable_to_non_nullable
                      as OdidExtension?,
            unipwn: freezed == unipwn
                ? _value.unipwn
                : unipwn // ignore: cast_nullable_to_non_nullable
                      as UnipwnExtension?,
            detector: freezed == detector
                ? _value.detector
                : detector // ignore: cast_nullable_to_non_nullable
                      as DetectorExtension?,
            wardrive: freezed == wardrive
                ? _value.wardrive
                : wardrive // ignore: cast_nullable_to_non_nullable
                      as WardriveExtension?,
          )
          as $Val,
    );
  }

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $FlockExtensionCopyWith<$Res>? get flock {
    if (_value.flock == null) {
      return null;
    }

    return $FlockExtensionCopyWith<$Res>(_value.flock!, (value) {
      return _then(_value.copyWith(flock: value) as $Val);
    });
  }

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $OdidExtensionCopyWith<$Res>? get odid {
    if (_value.odid == null) {
      return null;
    }

    return $OdidExtensionCopyWith<$Res>(_value.odid!, (value) {
      return _then(_value.copyWith(odid: value) as $Val);
    });
  }

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $UnipwnExtensionCopyWith<$Res>? get unipwn {
    if (_value.unipwn == null) {
      return null;
    }

    return $UnipwnExtensionCopyWith<$Res>(_value.unipwn!, (value) {
      return _then(_value.copyWith(unipwn: value) as $Val);
    });
  }

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $DetectorExtensionCopyWith<$Res>? get detector {
    if (_value.detector == null) {
      return null;
    }

    return $DetectorExtensionCopyWith<$Res>(_value.detector!, (value) {
      return _then(_value.copyWith(detector: value) as $Val);
    });
  }

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $WardriveExtensionCopyWith<$Res>? get wardrive {
    if (_value.wardrive == null) {
      return null;
    }

    return $WardriveExtensionCopyWith<$Res>(_value.wardrive!, (value) {
      return _then(_value.copyWith(wardrive: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$DetectionImplCopyWith<$Res>
    implements $DetectionCopyWith<$Res> {
  factory _$$DetectionImplCopyWith(
    _$DetectionImpl value,
    $Res Function(_$DetectionImpl) then,
  ) = __$$DetectionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    String sessionId,
    String nodeId,
    String macAddress,
    Engine engine,
    String method,
    int rssi,
    int channel,
    int deviceTimestampMs,
    DateTime appTimestamp,
    String deviceName,
    String ssid,
    int count,
    String sourceNodeId,
    double? latitude,
    double? longitude,
    double? altitude,
    double? speed,
    double? heading,
    double? accuracy,
    int? satelliteCount,
    FlockExtension? flock,
    OdidExtension? odid,
    UnipwnExtension? unipwn,
    DetectorExtension? detector,
    WardriveExtension? wardrive,
  });

  @override
  $FlockExtensionCopyWith<$Res>? get flock;
  @override
  $OdidExtensionCopyWith<$Res>? get odid;
  @override
  $UnipwnExtensionCopyWith<$Res>? get unipwn;
  @override
  $DetectorExtensionCopyWith<$Res>? get detector;
  @override
  $WardriveExtensionCopyWith<$Res>? get wardrive;
}

/// @nodoc
class __$$DetectionImplCopyWithImpl<$Res>
    extends _$DetectionCopyWithImpl<$Res, _$DetectionImpl>
    implements _$$DetectionImplCopyWith<$Res> {
  __$$DetectionImplCopyWithImpl(
    _$DetectionImpl _value,
    $Res Function(_$DetectionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? sessionId = null,
    Object? nodeId = null,
    Object? macAddress = null,
    Object? engine = null,
    Object? method = null,
    Object? rssi = null,
    Object? channel = null,
    Object? deviceTimestampMs = null,
    Object? appTimestamp = null,
    Object? deviceName = null,
    Object? ssid = null,
    Object? count = null,
    Object? sourceNodeId = null,
    Object? latitude = freezed,
    Object? longitude = freezed,
    Object? altitude = freezed,
    Object? speed = freezed,
    Object? heading = freezed,
    Object? accuracy = freezed,
    Object? satelliteCount = freezed,
    Object? flock = freezed,
    Object? odid = freezed,
    Object? unipwn = freezed,
    Object? detector = freezed,
    Object? wardrive = freezed,
  }) {
    return _then(
      _$DetectionImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        sessionId: null == sessionId
            ? _value.sessionId
            : sessionId // ignore: cast_nullable_to_non_nullable
                  as String,
        nodeId: null == nodeId
            ? _value.nodeId
            : nodeId // ignore: cast_nullable_to_non_nullable
                  as String,
        macAddress: null == macAddress
            ? _value.macAddress
            : macAddress // ignore: cast_nullable_to_non_nullable
                  as String,
        engine: null == engine
            ? _value.engine
            : engine // ignore: cast_nullable_to_non_nullable
                  as Engine,
        method: null == method
            ? _value.method
            : method // ignore: cast_nullable_to_non_nullable
                  as String,
        rssi: null == rssi
            ? _value.rssi
            : rssi // ignore: cast_nullable_to_non_nullable
                  as int,
        channel: null == channel
            ? _value.channel
            : channel // ignore: cast_nullable_to_non_nullable
                  as int,
        deviceTimestampMs: null == deviceTimestampMs
            ? _value.deviceTimestampMs
            : deviceTimestampMs // ignore: cast_nullable_to_non_nullable
                  as int,
        appTimestamp: null == appTimestamp
            ? _value.appTimestamp
            : appTimestamp // ignore: cast_nullable_to_non_nullable
                  as DateTime,
        deviceName: null == deviceName
            ? _value.deviceName
            : deviceName // ignore: cast_nullable_to_non_nullable
                  as String,
        ssid: null == ssid
            ? _value.ssid
            : ssid // ignore: cast_nullable_to_non_nullable
                  as String,
        count: null == count
            ? _value.count
            : count // ignore: cast_nullable_to_non_nullable
                  as int,
        sourceNodeId: null == sourceNodeId
            ? _value.sourceNodeId
            : sourceNodeId // ignore: cast_nullable_to_non_nullable
                  as String,
        latitude: freezed == latitude
            ? _value.latitude
            : latitude // ignore: cast_nullable_to_non_nullable
                  as double?,
        longitude: freezed == longitude
            ? _value.longitude
            : longitude // ignore: cast_nullable_to_non_nullable
                  as double?,
        altitude: freezed == altitude
            ? _value.altitude
            : altitude // ignore: cast_nullable_to_non_nullable
                  as double?,
        speed: freezed == speed
            ? _value.speed
            : speed // ignore: cast_nullable_to_non_nullable
                  as double?,
        heading: freezed == heading
            ? _value.heading
            : heading // ignore: cast_nullable_to_non_nullable
                  as double?,
        accuracy: freezed == accuracy
            ? _value.accuracy
            : accuracy // ignore: cast_nullable_to_non_nullable
                  as double?,
        satelliteCount: freezed == satelliteCount
            ? _value.satelliteCount
            : satelliteCount // ignore: cast_nullable_to_non_nullable
                  as int?,
        flock: freezed == flock
            ? _value.flock
            : flock // ignore: cast_nullable_to_non_nullable
                  as FlockExtension?,
        odid: freezed == odid
            ? _value.odid
            : odid // ignore: cast_nullable_to_non_nullable
                  as OdidExtension?,
        unipwn: freezed == unipwn
            ? _value.unipwn
            : unipwn // ignore: cast_nullable_to_non_nullable
                  as UnipwnExtension?,
        detector: freezed == detector
            ? _value.detector
            : detector // ignore: cast_nullable_to_non_nullable
                  as DetectorExtension?,
        wardrive: freezed == wardrive
            ? _value.wardrive
            : wardrive // ignore: cast_nullable_to_non_nullable
                  as WardriveExtension?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DetectionImpl implements _Detection {
  const _$DetectionImpl({
    required this.id,
    required this.sessionId,
    required this.nodeId,
    required this.macAddress,
    required this.engine,
    required this.method,
    required this.rssi,
    required this.channel,
    required this.deviceTimestampMs,
    required this.appTimestamp,
    this.deviceName = '',
    this.ssid = '',
    this.count = 1,
    this.sourceNodeId = '',
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
    this.satelliteCount,
    this.flock,
    this.odid,
    this.unipwn,
    this.detector,
    this.wardrive,
  });

  factory _$DetectionImpl.fromJson(Map<String, dynamic> json) =>
      _$$DetectionImplFromJson(json);

  @override
  final String id;
  @override
  final String sessionId;
  @override
  final String nodeId;
  @override
  final String macAddress;
  @override
  final Engine engine;
  @override
  final String method;
  @override
  final int rssi;
  @override
  final int channel;
  @override
  final int deviceTimestampMs;
  @override
  final DateTime appTimestamp;
  @override
  @JsonKey()
  final String deviceName;
  @override
  @JsonKey()
  final String ssid;
  @override
  @JsonKey()
  final int count;
  @override
  @JsonKey()
  final String sourceNodeId;
  @override
  final double? latitude;
  @override
  final double? longitude;
  @override
  final double? altitude;
  @override
  final double? speed;
  @override
  final double? heading;
  @override
  final double? accuracy;
  @override
  final int? satelliteCount;
  @override
  final FlockExtension? flock;
  @override
  final OdidExtension? odid;
  @override
  final UnipwnExtension? unipwn;
  @override
  final DetectorExtension? detector;
  @override
  final WardriveExtension? wardrive;

  @override
  String toString() {
    return 'Detection(id: $id, sessionId: $sessionId, nodeId: $nodeId, macAddress: $macAddress, engine: $engine, method: $method, rssi: $rssi, channel: $channel, deviceTimestampMs: $deviceTimestampMs, appTimestamp: $appTimestamp, deviceName: $deviceName, ssid: $ssid, count: $count, sourceNodeId: $sourceNodeId, latitude: $latitude, longitude: $longitude, altitude: $altitude, speed: $speed, heading: $heading, accuracy: $accuracy, satelliteCount: $satelliteCount, flock: $flock, odid: $odid, unipwn: $unipwn, detector: $detector, wardrive: $wardrive)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DetectionImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.sessionId, sessionId) ||
                other.sessionId == sessionId) &&
            (identical(other.nodeId, nodeId) || other.nodeId == nodeId) &&
            (identical(other.macAddress, macAddress) ||
                other.macAddress == macAddress) &&
            (identical(other.engine, engine) || other.engine == engine) &&
            (identical(other.method, method) || other.method == method) &&
            (identical(other.rssi, rssi) || other.rssi == rssi) &&
            (identical(other.channel, channel) || other.channel == channel) &&
            (identical(other.deviceTimestampMs, deviceTimestampMs) ||
                other.deviceTimestampMs == deviceTimestampMs) &&
            (identical(other.appTimestamp, appTimestamp) ||
                other.appTimestamp == appTimestamp) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.ssid, ssid) || other.ssid == ssid) &&
            (identical(other.count, count) || other.count == count) &&
            (identical(other.sourceNodeId, sourceNodeId) ||
                other.sourceNodeId == sourceNodeId) &&
            (identical(other.latitude, latitude) ||
                other.latitude == latitude) &&
            (identical(other.longitude, longitude) ||
                other.longitude == longitude) &&
            (identical(other.altitude, altitude) ||
                other.altitude == altitude) &&
            (identical(other.speed, speed) || other.speed == speed) &&
            (identical(other.heading, heading) || other.heading == heading) &&
            (identical(other.accuracy, accuracy) ||
                other.accuracy == accuracy) &&
            (identical(other.satelliteCount, satelliteCount) ||
                other.satelliteCount == satelliteCount) &&
            (identical(other.flock, flock) || other.flock == flock) &&
            (identical(other.odid, odid) || other.odid == odid) &&
            (identical(other.unipwn, unipwn) || other.unipwn == unipwn) &&
            (identical(other.detector, detector) ||
                other.detector == detector) &&
            (identical(other.wardrive, wardrive) ||
                other.wardrive == wardrive));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    id,
    sessionId,
    nodeId,
    macAddress,
    engine,
    method,
    rssi,
    channel,
    deviceTimestampMs,
    appTimestamp,
    deviceName,
    ssid,
    count,
    sourceNodeId,
    latitude,
    longitude,
    altitude,
    speed,
    heading,
    accuracy,
    satelliteCount,
    flock,
    odid,
    unipwn,
    detector,
    wardrive,
  ]);

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DetectionImplCopyWith<_$DetectionImpl> get copyWith =>
      __$$DetectionImplCopyWithImpl<_$DetectionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$DetectionImplToJson(this);
  }
}

abstract class _Detection implements Detection {
  const factory _Detection({
    required final String id,
    required final String sessionId,
    required final String nodeId,
    required final String macAddress,
    required final Engine engine,
    required final String method,
    required final int rssi,
    required final int channel,
    required final int deviceTimestampMs,
    required final DateTime appTimestamp,
    final String deviceName,
    final String ssid,
    final int count,
    final String sourceNodeId,
    final double? latitude,
    final double? longitude,
    final double? altitude,
    final double? speed,
    final double? heading,
    final double? accuracy,
    final int? satelliteCount,
    final FlockExtension? flock,
    final OdidExtension? odid,
    final UnipwnExtension? unipwn,
    final DetectorExtension? detector,
    final WardriveExtension? wardrive,
  }) = _$DetectionImpl;

  factory _Detection.fromJson(Map<String, dynamic> json) =
      _$DetectionImpl.fromJson;

  @override
  String get id;
  @override
  String get sessionId;
  @override
  String get nodeId;
  @override
  String get macAddress;
  @override
  Engine get engine;
  @override
  String get method;
  @override
  int get rssi;
  @override
  int get channel;
  @override
  int get deviceTimestampMs;
  @override
  DateTime get appTimestamp;
  @override
  String get deviceName;
  @override
  String get ssid;
  @override
  int get count;
  @override
  String get sourceNodeId;
  @override
  double? get latitude;
  @override
  double? get longitude;
  @override
  double? get altitude;
  @override
  double? get speed;
  @override
  double? get heading;
  @override
  double? get accuracy;
  @override
  int? get satelliteCount;
  @override
  FlockExtension? get flock;
  @override
  OdidExtension? get odid;
  @override
  UnipwnExtension? get unipwn;
  @override
  DetectorExtension? get detector;
  @override
  WardriveExtension? get wardrive;

  /// Create a copy of Detection
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DetectionImplCopyWith<_$DetectionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

FlockExtension _$FlockExtensionFromJson(Map<String, dynamic> json) {
  return _FlockExtension.fromJson(json);
}

/// @nodoc
mixin _$FlockExtension {
  bool get isRaven => throw _privateConstructorUsedError;
  String? get ravenFirmware => throw _privateConstructorUsedError;

  /// Serializes this FlockExtension to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of FlockExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FlockExtensionCopyWith<FlockExtension> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FlockExtensionCopyWith<$Res> {
  factory $FlockExtensionCopyWith(
    FlockExtension value,
    $Res Function(FlockExtension) then,
  ) = _$FlockExtensionCopyWithImpl<$Res, FlockExtension>;
  @useResult
  $Res call({bool isRaven, String? ravenFirmware});
}

/// @nodoc
class _$FlockExtensionCopyWithImpl<$Res, $Val extends FlockExtension>
    implements $FlockExtensionCopyWith<$Res> {
  _$FlockExtensionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FlockExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? isRaven = null, Object? ravenFirmware = freezed}) {
    return _then(
      _value.copyWith(
            isRaven: null == isRaven
                ? _value.isRaven
                : isRaven // ignore: cast_nullable_to_non_nullable
                      as bool,
            ravenFirmware: freezed == ravenFirmware
                ? _value.ravenFirmware
                : ravenFirmware // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FlockExtensionImplCopyWith<$Res>
    implements $FlockExtensionCopyWith<$Res> {
  factory _$$FlockExtensionImplCopyWith(
    _$FlockExtensionImpl value,
    $Res Function(_$FlockExtensionImpl) then,
  ) = __$$FlockExtensionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool isRaven, String? ravenFirmware});
}

/// @nodoc
class __$$FlockExtensionImplCopyWithImpl<$Res>
    extends _$FlockExtensionCopyWithImpl<$Res, _$FlockExtensionImpl>
    implements _$$FlockExtensionImplCopyWith<$Res> {
  __$$FlockExtensionImplCopyWithImpl(
    _$FlockExtensionImpl _value,
    $Res Function(_$FlockExtensionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FlockExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? isRaven = null, Object? ravenFirmware = freezed}) {
    return _then(
      _$FlockExtensionImpl(
        isRaven: null == isRaven
            ? _value.isRaven
            : isRaven // ignore: cast_nullable_to_non_nullable
                  as bool,
        ravenFirmware: freezed == ravenFirmware
            ? _value.ravenFirmware
            : ravenFirmware // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$FlockExtensionImpl implements _FlockExtension {
  const _$FlockExtensionImpl({this.isRaven = false, this.ravenFirmware});

  factory _$FlockExtensionImpl.fromJson(Map<String, dynamic> json) =>
      _$$FlockExtensionImplFromJson(json);

  @override
  @JsonKey()
  final bool isRaven;
  @override
  final String? ravenFirmware;

  @override
  String toString() {
    return 'FlockExtension(isRaven: $isRaven, ravenFirmware: $ravenFirmware)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FlockExtensionImpl &&
            (identical(other.isRaven, isRaven) || other.isRaven == isRaven) &&
            (identical(other.ravenFirmware, ravenFirmware) ||
                other.ravenFirmware == ravenFirmware));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, isRaven, ravenFirmware);

  /// Create a copy of FlockExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FlockExtensionImplCopyWith<_$FlockExtensionImpl> get copyWith =>
      __$$FlockExtensionImplCopyWithImpl<_$FlockExtensionImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$FlockExtensionImplToJson(this);
  }
}

abstract class _FlockExtension implements FlockExtension {
  const factory _FlockExtension({
    final bool isRaven,
    final String? ravenFirmware,
  }) = _$FlockExtensionImpl;

  factory _FlockExtension.fromJson(Map<String, dynamic> json) =
      _$FlockExtensionImpl.fromJson;

  @override
  bool get isRaven;
  @override
  String? get ravenFirmware;

  /// Create a copy of FlockExtension
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FlockExtensionImplCopyWith<_$FlockExtensionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

OdidExtension _$OdidExtensionFromJson(Map<String, dynamic> json) {
  return _OdidExtension.fromJson(json);
}

/// @nodoc
mixin _$OdidExtension {
  String? get uavId => throw _privateConstructorUsedError;
  String? get operatorId => throw _privateConstructorUsedError;
  double? get droneLat => throw _privateConstructorUsedError;
  double? get droneLon => throw _privateConstructorUsedError;
  int? get altitudeMsl => throw _privateConstructorUsedError;
  int? get heightAgl => throw _privateConstructorUsedError;
  int? get droneSpeed => throw _privateConstructorUsedError;
  int? get droneHeading => throw _privateConstructorUsedError;
  double? get pilotLat => throw _privateConstructorUsedError;
  double? get pilotLon => throw _privateConstructorUsedError;
  String? get selfId => throw _privateConstructorUsedError;
  int? get altitudeBaro => throw _privateConstructorUsedError;
  int? get vertSpeed => throw _privateConstructorUsedError;
  int? get operatorAlt => throw _privateConstructorUsedError;
  int? get areaCount => throw _privateConstructorUsedError;
  int? get areaRadius => throw _privateConstructorUsedError;
  int? get areaCeiling => throw _privateConstructorUsedError;
  int? get areaFloor => throw _privateConstructorUsedError;
  int? get locTimestamp => throw _privateConstructorUsedError;
  int? get uaType => throw _privateConstructorUsedError;
  int? get idType => throw _privateConstructorUsedError;
  int? get opIdType => throw _privateConstructorUsedError;
  int? get opLocationType => throw _privateConstructorUsedError;
  int? get classification => throw _privateConstructorUsedError;
  int? get categoryEu => throw _privateConstructorUsedError;
  int? get classEu => throw _privateConstructorUsedError;
  int? get heightType => throw _privateConstructorUsedError;
  int? get status => throw _privateConstructorUsedError;
  int? get horizAcc => throw _privateConstructorUsedError;
  int? get vertAcc => throw _privateConstructorUsedError;
  int? get baroAcc => throw _privateConstructorUsedError;
  int? get speedAcc => throw _privateConstructorUsedError;
  int? get selfIdType => throw _privateConstructorUsedError;

  /// Serializes this OdidExtension to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of OdidExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $OdidExtensionCopyWith<OdidExtension> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $OdidExtensionCopyWith<$Res> {
  factory $OdidExtensionCopyWith(
    OdidExtension value,
    $Res Function(OdidExtension) then,
  ) = _$OdidExtensionCopyWithImpl<$Res, OdidExtension>;
  @useResult
  $Res call({
    String? uavId,
    String? operatorId,
    double? droneLat,
    double? droneLon,
    int? altitudeMsl,
    int? heightAgl,
    int? droneSpeed,
    int? droneHeading,
    double? pilotLat,
    double? pilotLon,
    String? selfId,
    int? altitudeBaro,
    int? vertSpeed,
    int? operatorAlt,
    int? areaCount,
    int? areaRadius,
    int? areaCeiling,
    int? areaFloor,
    int? locTimestamp,
    int? uaType,
    int? idType,
    int? opIdType,
    int? opLocationType,
    int? classification,
    int? categoryEu,
    int? classEu,
    int? heightType,
    int? status,
    int? horizAcc,
    int? vertAcc,
    int? baroAcc,
    int? speedAcc,
    int? selfIdType,
  });
}

/// @nodoc
class _$OdidExtensionCopyWithImpl<$Res, $Val extends OdidExtension>
    implements $OdidExtensionCopyWith<$Res> {
  _$OdidExtensionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of OdidExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uavId = freezed,
    Object? operatorId = freezed,
    Object? droneLat = freezed,
    Object? droneLon = freezed,
    Object? altitudeMsl = freezed,
    Object? heightAgl = freezed,
    Object? droneSpeed = freezed,
    Object? droneHeading = freezed,
    Object? pilotLat = freezed,
    Object? pilotLon = freezed,
    Object? selfId = freezed,
    Object? altitudeBaro = freezed,
    Object? vertSpeed = freezed,
    Object? operatorAlt = freezed,
    Object? areaCount = freezed,
    Object? areaRadius = freezed,
    Object? areaCeiling = freezed,
    Object? areaFloor = freezed,
    Object? locTimestamp = freezed,
    Object? uaType = freezed,
    Object? idType = freezed,
    Object? opIdType = freezed,
    Object? opLocationType = freezed,
    Object? classification = freezed,
    Object? categoryEu = freezed,
    Object? classEu = freezed,
    Object? heightType = freezed,
    Object? status = freezed,
    Object? horizAcc = freezed,
    Object? vertAcc = freezed,
    Object? baroAcc = freezed,
    Object? speedAcc = freezed,
    Object? selfIdType = freezed,
  }) {
    return _then(
      _value.copyWith(
            uavId: freezed == uavId
                ? _value.uavId
                : uavId // ignore: cast_nullable_to_non_nullable
                      as String?,
            operatorId: freezed == operatorId
                ? _value.operatorId
                : operatorId // ignore: cast_nullable_to_non_nullable
                      as String?,
            droneLat: freezed == droneLat
                ? _value.droneLat
                : droneLat // ignore: cast_nullable_to_non_nullable
                      as double?,
            droneLon: freezed == droneLon
                ? _value.droneLon
                : droneLon // ignore: cast_nullable_to_non_nullable
                      as double?,
            altitudeMsl: freezed == altitudeMsl
                ? _value.altitudeMsl
                : altitudeMsl // ignore: cast_nullable_to_non_nullable
                      as int?,
            heightAgl: freezed == heightAgl
                ? _value.heightAgl
                : heightAgl // ignore: cast_nullable_to_non_nullable
                      as int?,
            droneSpeed: freezed == droneSpeed
                ? _value.droneSpeed
                : droneSpeed // ignore: cast_nullable_to_non_nullable
                      as int?,
            droneHeading: freezed == droneHeading
                ? _value.droneHeading
                : droneHeading // ignore: cast_nullable_to_non_nullable
                      as int?,
            pilotLat: freezed == pilotLat
                ? _value.pilotLat
                : pilotLat // ignore: cast_nullable_to_non_nullable
                      as double?,
            pilotLon: freezed == pilotLon
                ? _value.pilotLon
                : pilotLon // ignore: cast_nullable_to_non_nullable
                      as double?,
            selfId: freezed == selfId
                ? _value.selfId
                : selfId // ignore: cast_nullable_to_non_nullable
                      as String?,
            altitudeBaro: freezed == altitudeBaro
                ? _value.altitudeBaro
                : altitudeBaro // ignore: cast_nullable_to_non_nullable
                      as int?,
            vertSpeed: freezed == vertSpeed
                ? _value.vertSpeed
                : vertSpeed // ignore: cast_nullable_to_non_nullable
                      as int?,
            operatorAlt: freezed == operatorAlt
                ? _value.operatorAlt
                : operatorAlt // ignore: cast_nullable_to_non_nullable
                      as int?,
            areaCount: freezed == areaCount
                ? _value.areaCount
                : areaCount // ignore: cast_nullable_to_non_nullable
                      as int?,
            areaRadius: freezed == areaRadius
                ? _value.areaRadius
                : areaRadius // ignore: cast_nullable_to_non_nullable
                      as int?,
            areaCeiling: freezed == areaCeiling
                ? _value.areaCeiling
                : areaCeiling // ignore: cast_nullable_to_non_nullable
                      as int?,
            areaFloor: freezed == areaFloor
                ? _value.areaFloor
                : areaFloor // ignore: cast_nullable_to_non_nullable
                      as int?,
            locTimestamp: freezed == locTimestamp
                ? _value.locTimestamp
                : locTimestamp // ignore: cast_nullable_to_non_nullable
                      as int?,
            uaType: freezed == uaType
                ? _value.uaType
                : uaType // ignore: cast_nullable_to_non_nullable
                      as int?,
            idType: freezed == idType
                ? _value.idType
                : idType // ignore: cast_nullable_to_non_nullable
                      as int?,
            opIdType: freezed == opIdType
                ? _value.opIdType
                : opIdType // ignore: cast_nullable_to_non_nullable
                      as int?,
            opLocationType: freezed == opLocationType
                ? _value.opLocationType
                : opLocationType // ignore: cast_nullable_to_non_nullable
                      as int?,
            classification: freezed == classification
                ? _value.classification
                : classification // ignore: cast_nullable_to_non_nullable
                      as int?,
            categoryEu: freezed == categoryEu
                ? _value.categoryEu
                : categoryEu // ignore: cast_nullable_to_non_nullable
                      as int?,
            classEu: freezed == classEu
                ? _value.classEu
                : classEu // ignore: cast_nullable_to_non_nullable
                      as int?,
            heightType: freezed == heightType
                ? _value.heightType
                : heightType // ignore: cast_nullable_to_non_nullable
                      as int?,
            status: freezed == status
                ? _value.status
                : status // ignore: cast_nullable_to_non_nullable
                      as int?,
            horizAcc: freezed == horizAcc
                ? _value.horizAcc
                : horizAcc // ignore: cast_nullable_to_non_nullable
                      as int?,
            vertAcc: freezed == vertAcc
                ? _value.vertAcc
                : vertAcc // ignore: cast_nullable_to_non_nullable
                      as int?,
            baroAcc: freezed == baroAcc
                ? _value.baroAcc
                : baroAcc // ignore: cast_nullable_to_non_nullable
                      as int?,
            speedAcc: freezed == speedAcc
                ? _value.speedAcc
                : speedAcc // ignore: cast_nullable_to_non_nullable
                      as int?,
            selfIdType: freezed == selfIdType
                ? _value.selfIdType
                : selfIdType // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$OdidExtensionImplCopyWith<$Res>
    implements $OdidExtensionCopyWith<$Res> {
  factory _$$OdidExtensionImplCopyWith(
    _$OdidExtensionImpl value,
    $Res Function(_$OdidExtensionImpl) then,
  ) = __$$OdidExtensionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String? uavId,
    String? operatorId,
    double? droneLat,
    double? droneLon,
    int? altitudeMsl,
    int? heightAgl,
    int? droneSpeed,
    int? droneHeading,
    double? pilotLat,
    double? pilotLon,
    String? selfId,
    int? altitudeBaro,
    int? vertSpeed,
    int? operatorAlt,
    int? areaCount,
    int? areaRadius,
    int? areaCeiling,
    int? areaFloor,
    int? locTimestamp,
    int? uaType,
    int? idType,
    int? opIdType,
    int? opLocationType,
    int? classification,
    int? categoryEu,
    int? classEu,
    int? heightType,
    int? status,
    int? horizAcc,
    int? vertAcc,
    int? baroAcc,
    int? speedAcc,
    int? selfIdType,
  });
}

/// @nodoc
class __$$OdidExtensionImplCopyWithImpl<$Res>
    extends _$OdidExtensionCopyWithImpl<$Res, _$OdidExtensionImpl>
    implements _$$OdidExtensionImplCopyWith<$Res> {
  __$$OdidExtensionImplCopyWithImpl(
    _$OdidExtensionImpl _value,
    $Res Function(_$OdidExtensionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of OdidExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? uavId = freezed,
    Object? operatorId = freezed,
    Object? droneLat = freezed,
    Object? droneLon = freezed,
    Object? altitudeMsl = freezed,
    Object? heightAgl = freezed,
    Object? droneSpeed = freezed,
    Object? droneHeading = freezed,
    Object? pilotLat = freezed,
    Object? pilotLon = freezed,
    Object? selfId = freezed,
    Object? altitudeBaro = freezed,
    Object? vertSpeed = freezed,
    Object? operatorAlt = freezed,
    Object? areaCount = freezed,
    Object? areaRadius = freezed,
    Object? areaCeiling = freezed,
    Object? areaFloor = freezed,
    Object? locTimestamp = freezed,
    Object? uaType = freezed,
    Object? idType = freezed,
    Object? opIdType = freezed,
    Object? opLocationType = freezed,
    Object? classification = freezed,
    Object? categoryEu = freezed,
    Object? classEu = freezed,
    Object? heightType = freezed,
    Object? status = freezed,
    Object? horizAcc = freezed,
    Object? vertAcc = freezed,
    Object? baroAcc = freezed,
    Object? speedAcc = freezed,
    Object? selfIdType = freezed,
  }) {
    return _then(
      _$OdidExtensionImpl(
        uavId: freezed == uavId
            ? _value.uavId
            : uavId // ignore: cast_nullable_to_non_nullable
                  as String?,
        operatorId: freezed == operatorId
            ? _value.operatorId
            : operatorId // ignore: cast_nullable_to_non_nullable
                  as String?,
        droneLat: freezed == droneLat
            ? _value.droneLat
            : droneLat // ignore: cast_nullable_to_non_nullable
                  as double?,
        droneLon: freezed == droneLon
            ? _value.droneLon
            : droneLon // ignore: cast_nullable_to_non_nullable
                  as double?,
        altitudeMsl: freezed == altitudeMsl
            ? _value.altitudeMsl
            : altitudeMsl // ignore: cast_nullable_to_non_nullable
                  as int?,
        heightAgl: freezed == heightAgl
            ? _value.heightAgl
            : heightAgl // ignore: cast_nullable_to_non_nullable
                  as int?,
        droneSpeed: freezed == droneSpeed
            ? _value.droneSpeed
            : droneSpeed // ignore: cast_nullable_to_non_nullable
                  as int?,
        droneHeading: freezed == droneHeading
            ? _value.droneHeading
            : droneHeading // ignore: cast_nullable_to_non_nullable
                  as int?,
        pilotLat: freezed == pilotLat
            ? _value.pilotLat
            : pilotLat // ignore: cast_nullable_to_non_nullable
                  as double?,
        pilotLon: freezed == pilotLon
            ? _value.pilotLon
            : pilotLon // ignore: cast_nullable_to_non_nullable
                  as double?,
        selfId: freezed == selfId
            ? _value.selfId
            : selfId // ignore: cast_nullable_to_non_nullable
                  as String?,
        altitudeBaro: freezed == altitudeBaro
            ? _value.altitudeBaro
            : altitudeBaro // ignore: cast_nullable_to_non_nullable
                  as int?,
        vertSpeed: freezed == vertSpeed
            ? _value.vertSpeed
            : vertSpeed // ignore: cast_nullable_to_non_nullable
                  as int?,
        operatorAlt: freezed == operatorAlt
            ? _value.operatorAlt
            : operatorAlt // ignore: cast_nullable_to_non_nullable
                  as int?,
        areaCount: freezed == areaCount
            ? _value.areaCount
            : areaCount // ignore: cast_nullable_to_non_nullable
                  as int?,
        areaRadius: freezed == areaRadius
            ? _value.areaRadius
            : areaRadius // ignore: cast_nullable_to_non_nullable
                  as int?,
        areaCeiling: freezed == areaCeiling
            ? _value.areaCeiling
            : areaCeiling // ignore: cast_nullable_to_non_nullable
                  as int?,
        areaFloor: freezed == areaFloor
            ? _value.areaFloor
            : areaFloor // ignore: cast_nullable_to_non_nullable
                  as int?,
        locTimestamp: freezed == locTimestamp
            ? _value.locTimestamp
            : locTimestamp // ignore: cast_nullable_to_non_nullable
                  as int?,
        uaType: freezed == uaType
            ? _value.uaType
            : uaType // ignore: cast_nullable_to_non_nullable
                  as int?,
        idType: freezed == idType
            ? _value.idType
            : idType // ignore: cast_nullable_to_non_nullable
                  as int?,
        opIdType: freezed == opIdType
            ? _value.opIdType
            : opIdType // ignore: cast_nullable_to_non_nullable
                  as int?,
        opLocationType: freezed == opLocationType
            ? _value.opLocationType
            : opLocationType // ignore: cast_nullable_to_non_nullable
                  as int?,
        classification: freezed == classification
            ? _value.classification
            : classification // ignore: cast_nullable_to_non_nullable
                  as int?,
        categoryEu: freezed == categoryEu
            ? _value.categoryEu
            : categoryEu // ignore: cast_nullable_to_non_nullable
                  as int?,
        classEu: freezed == classEu
            ? _value.classEu
            : classEu // ignore: cast_nullable_to_non_nullable
                  as int?,
        heightType: freezed == heightType
            ? _value.heightType
            : heightType // ignore: cast_nullable_to_non_nullable
                  as int?,
        status: freezed == status
            ? _value.status
            : status // ignore: cast_nullable_to_non_nullable
                  as int?,
        horizAcc: freezed == horizAcc
            ? _value.horizAcc
            : horizAcc // ignore: cast_nullable_to_non_nullable
                  as int?,
        vertAcc: freezed == vertAcc
            ? _value.vertAcc
            : vertAcc // ignore: cast_nullable_to_non_nullable
                  as int?,
        baroAcc: freezed == baroAcc
            ? _value.baroAcc
            : baroAcc // ignore: cast_nullable_to_non_nullable
                  as int?,
        speedAcc: freezed == speedAcc
            ? _value.speedAcc
            : speedAcc // ignore: cast_nullable_to_non_nullable
                  as int?,
        selfIdType: freezed == selfIdType
            ? _value.selfIdType
            : selfIdType // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$OdidExtensionImpl implements _OdidExtension {
  const _$OdidExtensionImpl({
    this.uavId,
    this.operatorId,
    this.droneLat,
    this.droneLon,
    this.altitudeMsl,
    this.heightAgl,
    this.droneSpeed,
    this.droneHeading,
    this.pilotLat,
    this.pilotLon,
    this.selfId,
    this.altitudeBaro,
    this.vertSpeed,
    this.operatorAlt,
    this.areaCount,
    this.areaRadius,
    this.areaCeiling,
    this.areaFloor,
    this.locTimestamp,
    this.uaType,
    this.idType,
    this.opIdType,
    this.opLocationType,
    this.classification,
    this.categoryEu,
    this.classEu,
    this.heightType,
    this.status,
    this.horizAcc,
    this.vertAcc,
    this.baroAcc,
    this.speedAcc,
    this.selfIdType,
  });

  factory _$OdidExtensionImpl.fromJson(Map<String, dynamic> json) =>
      _$$OdidExtensionImplFromJson(json);

  @override
  final String? uavId;
  @override
  final String? operatorId;
  @override
  final double? droneLat;
  @override
  final double? droneLon;
  @override
  final int? altitudeMsl;
  @override
  final int? heightAgl;
  @override
  final int? droneSpeed;
  @override
  final int? droneHeading;
  @override
  final double? pilotLat;
  @override
  final double? pilotLon;
  @override
  final String? selfId;
  @override
  final int? altitudeBaro;
  @override
  final int? vertSpeed;
  @override
  final int? operatorAlt;
  @override
  final int? areaCount;
  @override
  final int? areaRadius;
  @override
  final int? areaCeiling;
  @override
  final int? areaFloor;
  @override
  final int? locTimestamp;
  @override
  final int? uaType;
  @override
  final int? idType;
  @override
  final int? opIdType;
  @override
  final int? opLocationType;
  @override
  final int? classification;
  @override
  final int? categoryEu;
  @override
  final int? classEu;
  @override
  final int? heightType;
  @override
  final int? status;
  @override
  final int? horizAcc;
  @override
  final int? vertAcc;
  @override
  final int? baroAcc;
  @override
  final int? speedAcc;
  @override
  final int? selfIdType;

  @override
  String toString() {
    return 'OdidExtension(uavId: $uavId, operatorId: $operatorId, droneLat: $droneLat, droneLon: $droneLon, altitudeMsl: $altitudeMsl, heightAgl: $heightAgl, droneSpeed: $droneSpeed, droneHeading: $droneHeading, pilotLat: $pilotLat, pilotLon: $pilotLon, selfId: $selfId, altitudeBaro: $altitudeBaro, vertSpeed: $vertSpeed, operatorAlt: $operatorAlt, areaCount: $areaCount, areaRadius: $areaRadius, areaCeiling: $areaCeiling, areaFloor: $areaFloor, locTimestamp: $locTimestamp, uaType: $uaType, idType: $idType, opIdType: $opIdType, opLocationType: $opLocationType, classification: $classification, categoryEu: $categoryEu, classEu: $classEu, heightType: $heightType, status: $status, horizAcc: $horizAcc, vertAcc: $vertAcc, baroAcc: $baroAcc, speedAcc: $speedAcc, selfIdType: $selfIdType)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$OdidExtensionImpl &&
            (identical(other.uavId, uavId) || other.uavId == uavId) &&
            (identical(other.operatorId, operatorId) ||
                other.operatorId == operatorId) &&
            (identical(other.droneLat, droneLat) ||
                other.droneLat == droneLat) &&
            (identical(other.droneLon, droneLon) ||
                other.droneLon == droneLon) &&
            (identical(other.altitudeMsl, altitudeMsl) ||
                other.altitudeMsl == altitudeMsl) &&
            (identical(other.heightAgl, heightAgl) ||
                other.heightAgl == heightAgl) &&
            (identical(other.droneSpeed, droneSpeed) ||
                other.droneSpeed == droneSpeed) &&
            (identical(other.droneHeading, droneHeading) ||
                other.droneHeading == droneHeading) &&
            (identical(other.pilotLat, pilotLat) ||
                other.pilotLat == pilotLat) &&
            (identical(other.pilotLon, pilotLon) ||
                other.pilotLon == pilotLon) &&
            (identical(other.selfId, selfId) || other.selfId == selfId) &&
            (identical(other.altitudeBaro, altitudeBaro) ||
                other.altitudeBaro == altitudeBaro) &&
            (identical(other.vertSpeed, vertSpeed) ||
                other.vertSpeed == vertSpeed) &&
            (identical(other.operatorAlt, operatorAlt) ||
                other.operatorAlt == operatorAlt) &&
            (identical(other.areaCount, areaCount) ||
                other.areaCount == areaCount) &&
            (identical(other.areaRadius, areaRadius) ||
                other.areaRadius == areaRadius) &&
            (identical(other.areaCeiling, areaCeiling) ||
                other.areaCeiling == areaCeiling) &&
            (identical(other.areaFloor, areaFloor) ||
                other.areaFloor == areaFloor) &&
            (identical(other.locTimestamp, locTimestamp) ||
                other.locTimestamp == locTimestamp) &&
            (identical(other.uaType, uaType) || other.uaType == uaType) &&
            (identical(other.idType, idType) || other.idType == idType) &&
            (identical(other.opIdType, opIdType) ||
                other.opIdType == opIdType) &&
            (identical(other.opLocationType, opLocationType) ||
                other.opLocationType == opLocationType) &&
            (identical(other.classification, classification) ||
                other.classification == classification) &&
            (identical(other.categoryEu, categoryEu) ||
                other.categoryEu == categoryEu) &&
            (identical(other.classEu, classEu) || other.classEu == classEu) &&
            (identical(other.heightType, heightType) ||
                other.heightType == heightType) &&
            (identical(other.status, status) || other.status == status) &&
            (identical(other.horizAcc, horizAcc) ||
                other.horizAcc == horizAcc) &&
            (identical(other.vertAcc, vertAcc) || other.vertAcc == vertAcc) &&
            (identical(other.baroAcc, baroAcc) || other.baroAcc == baroAcc) &&
            (identical(other.speedAcc, speedAcc) ||
                other.speedAcc == speedAcc) &&
            (identical(other.selfIdType, selfIdType) ||
                other.selfIdType == selfIdType));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    uavId,
    operatorId,
    droneLat,
    droneLon,
    altitudeMsl,
    heightAgl,
    droneSpeed,
    droneHeading,
    pilotLat,
    pilotLon,
    selfId,
    altitudeBaro,
    vertSpeed,
    operatorAlt,
    areaCount,
    areaRadius,
    areaCeiling,
    areaFloor,
    locTimestamp,
    uaType,
    idType,
    opIdType,
    opLocationType,
    classification,
    categoryEu,
    classEu,
    heightType,
    status,
    horizAcc,
    vertAcc,
    baroAcc,
    speedAcc,
    selfIdType,
  ]);

  /// Create a copy of OdidExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$OdidExtensionImplCopyWith<_$OdidExtensionImpl> get copyWith =>
      __$$OdidExtensionImplCopyWithImpl<_$OdidExtensionImpl>(this, _$identity);

  @override
  Map<String, dynamic> toJson() {
    return _$$OdidExtensionImplToJson(this);
  }
}

abstract class _OdidExtension implements OdidExtension {
  const factory _OdidExtension({
    final String? uavId,
    final String? operatorId,
    final double? droneLat,
    final double? droneLon,
    final int? altitudeMsl,
    final int? heightAgl,
    final int? droneSpeed,
    final int? droneHeading,
    final double? pilotLat,
    final double? pilotLon,
    final String? selfId,
    final int? altitudeBaro,
    final int? vertSpeed,
    final int? operatorAlt,
    final int? areaCount,
    final int? areaRadius,
    final int? areaCeiling,
    final int? areaFloor,
    final int? locTimestamp,
    final int? uaType,
    final int? idType,
    final int? opIdType,
    final int? opLocationType,
    final int? classification,
    final int? categoryEu,
    final int? classEu,
    final int? heightType,
    final int? status,
    final int? horizAcc,
    final int? vertAcc,
    final int? baroAcc,
    final int? speedAcc,
    final int? selfIdType,
  }) = _$OdidExtensionImpl;

  factory _OdidExtension.fromJson(Map<String, dynamic> json) =
      _$OdidExtensionImpl.fromJson;

  @override
  String? get uavId;
  @override
  String? get operatorId;
  @override
  double? get droneLat;
  @override
  double? get droneLon;
  @override
  int? get altitudeMsl;
  @override
  int? get heightAgl;
  @override
  int? get droneSpeed;
  @override
  int? get droneHeading;
  @override
  double? get pilotLat;
  @override
  double? get pilotLon;
  @override
  String? get selfId;
  @override
  int? get altitudeBaro;
  @override
  int? get vertSpeed;
  @override
  int? get operatorAlt;
  @override
  int? get areaCount;
  @override
  int? get areaRadius;
  @override
  int? get areaCeiling;
  @override
  int? get areaFloor;
  @override
  int? get locTimestamp;
  @override
  int? get uaType;
  @override
  int? get idType;
  @override
  int? get opIdType;
  @override
  int? get opLocationType;
  @override
  int? get classification;
  @override
  int? get categoryEu;
  @override
  int? get classEu;
  @override
  int? get heightType;
  @override
  int? get status;
  @override
  int? get horizAcc;
  @override
  int? get vertAcc;
  @override
  int? get baroAcc;
  @override
  int? get speedAcc;
  @override
  int? get selfIdType;

  /// Create a copy of OdidExtension
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$OdidExtensionImplCopyWith<_$OdidExtensionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

UnipwnExtension _$UnipwnExtensionFromJson(Map<String, dynamic> json) {
  return _UnipwnExtension.fromJson(json);
}

/// @nodoc
mixin _$UnipwnExtension {
  String get robotType => throw _privateConstructorUsedError;
  bool get exploited => throw _privateConstructorUsedError;
  String? get serialNumber => throw _privateConstructorUsedError;

  /// Serializes this UnipwnExtension to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of UnipwnExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $UnipwnExtensionCopyWith<UnipwnExtension> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $UnipwnExtensionCopyWith<$Res> {
  factory $UnipwnExtensionCopyWith(
    UnipwnExtension value,
    $Res Function(UnipwnExtension) then,
  ) = _$UnipwnExtensionCopyWithImpl<$Res, UnipwnExtension>;
  @useResult
  $Res call({String robotType, bool exploited, String? serialNumber});
}

/// @nodoc
class _$UnipwnExtensionCopyWithImpl<$Res, $Val extends UnipwnExtension>
    implements $UnipwnExtensionCopyWith<$Res> {
  _$UnipwnExtensionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of UnipwnExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? robotType = null,
    Object? exploited = null,
    Object? serialNumber = freezed,
  }) {
    return _then(
      _value.copyWith(
            robotType: null == robotType
                ? _value.robotType
                : robotType // ignore: cast_nullable_to_non_nullable
                      as String,
            exploited: null == exploited
                ? _value.exploited
                : exploited // ignore: cast_nullable_to_non_nullable
                      as bool,
            serialNumber: freezed == serialNumber
                ? _value.serialNumber
                : serialNumber // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$UnipwnExtensionImplCopyWith<$Res>
    implements $UnipwnExtensionCopyWith<$Res> {
  factory _$$UnipwnExtensionImplCopyWith(
    _$UnipwnExtensionImpl value,
    $Res Function(_$UnipwnExtensionImpl) then,
  ) = __$$UnipwnExtensionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String robotType, bool exploited, String? serialNumber});
}

/// @nodoc
class __$$UnipwnExtensionImplCopyWithImpl<$Res>
    extends _$UnipwnExtensionCopyWithImpl<$Res, _$UnipwnExtensionImpl>
    implements _$$UnipwnExtensionImplCopyWith<$Res> {
  __$$UnipwnExtensionImplCopyWithImpl(
    _$UnipwnExtensionImpl _value,
    $Res Function(_$UnipwnExtensionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of UnipwnExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? robotType = null,
    Object? exploited = null,
    Object? serialNumber = freezed,
  }) {
    return _then(
      _$UnipwnExtensionImpl(
        robotType: null == robotType
            ? _value.robotType
            : robotType // ignore: cast_nullable_to_non_nullable
                  as String,
        exploited: null == exploited
            ? _value.exploited
            : exploited // ignore: cast_nullable_to_non_nullable
                  as bool,
        serialNumber: freezed == serialNumber
            ? _value.serialNumber
            : serialNumber // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$UnipwnExtensionImpl implements _UnipwnExtension {
  const _$UnipwnExtensionImpl({
    required this.robotType,
    this.exploited = false,
    this.serialNumber,
  });

  factory _$UnipwnExtensionImpl.fromJson(Map<String, dynamic> json) =>
      _$$UnipwnExtensionImplFromJson(json);

  @override
  final String robotType;
  @override
  @JsonKey()
  final bool exploited;
  @override
  final String? serialNumber;

  @override
  String toString() {
    return 'UnipwnExtension(robotType: $robotType, exploited: $exploited, serialNumber: $serialNumber)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$UnipwnExtensionImpl &&
            (identical(other.robotType, robotType) ||
                other.robotType == robotType) &&
            (identical(other.exploited, exploited) ||
                other.exploited == exploited) &&
            (identical(other.serialNumber, serialNumber) ||
                other.serialNumber == serialNumber));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode =>
      Object.hash(runtimeType, robotType, exploited, serialNumber);

  /// Create a copy of UnipwnExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$UnipwnExtensionImplCopyWith<_$UnipwnExtensionImpl> get copyWith =>
      __$$UnipwnExtensionImplCopyWithImpl<_$UnipwnExtensionImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$UnipwnExtensionImplToJson(this);
  }
}

abstract class _UnipwnExtension implements UnipwnExtension {
  const factory _UnipwnExtension({
    required final String robotType,
    final bool exploited,
    final String? serialNumber,
  }) = _$UnipwnExtensionImpl;

  factory _UnipwnExtension.fromJson(Map<String, dynamic> json) =
      _$UnipwnExtensionImpl.fromJson;

  @override
  String get robotType;
  @override
  bool get exploited;
  @override
  String? get serialNumber;

  /// Create a copy of UnipwnExtension
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$UnipwnExtensionImplCopyWith<_$UnipwnExtensionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

WardriveExtension _$WardriveExtensionFromJson(Map<String, dynamic> json) {
  return _WardriveExtension.fromJson(json);
}

/// @nodoc
mixin _$WardriveExtension {
  String get ssid => throw _privateConstructorUsedError;
  int get authMode => throw _privateConstructorUsedError;
  String get deviceName => throw _privateConstructorUsedError;

  /// Serializes this WardriveExtension to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of WardriveExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $WardriveExtensionCopyWith<WardriveExtension> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $WardriveExtensionCopyWith<$Res> {
  factory $WardriveExtensionCopyWith(
    WardriveExtension value,
    $Res Function(WardriveExtension) then,
  ) = _$WardriveExtensionCopyWithImpl<$Res, WardriveExtension>;
  @useResult
  $Res call({String ssid, int authMode, String deviceName});
}

/// @nodoc
class _$WardriveExtensionCopyWithImpl<$Res, $Val extends WardriveExtension>
    implements $WardriveExtensionCopyWith<$Res> {
  _$WardriveExtensionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of WardriveExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ssid = null,
    Object? authMode = null,
    Object? deviceName = null,
  }) {
    return _then(
      _value.copyWith(
            ssid: null == ssid
                ? _value.ssid
                : ssid // ignore: cast_nullable_to_non_nullable
                      as String,
            authMode: null == authMode
                ? _value.authMode
                : authMode // ignore: cast_nullable_to_non_nullable
                      as int,
            deviceName: null == deviceName
                ? _value.deviceName
                : deviceName // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$WardriveExtensionImplCopyWith<$Res>
    implements $WardriveExtensionCopyWith<$Res> {
  factory _$$WardriveExtensionImplCopyWith(
    _$WardriveExtensionImpl value,
    $Res Function(_$WardriveExtensionImpl) then,
  ) = __$$WardriveExtensionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String ssid, int authMode, String deviceName});
}

/// @nodoc
class __$$WardriveExtensionImplCopyWithImpl<$Res>
    extends _$WardriveExtensionCopyWithImpl<$Res, _$WardriveExtensionImpl>
    implements _$$WardriveExtensionImplCopyWith<$Res> {
  __$$WardriveExtensionImplCopyWithImpl(
    _$WardriveExtensionImpl _value,
    $Res Function(_$WardriveExtensionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of WardriveExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ssid = null,
    Object? authMode = null,
    Object? deviceName = null,
  }) {
    return _then(
      _$WardriveExtensionImpl(
        ssid: null == ssid
            ? _value.ssid
            : ssid // ignore: cast_nullable_to_non_nullable
                  as String,
        authMode: null == authMode
            ? _value.authMode
            : authMode // ignore: cast_nullable_to_non_nullable
                  as int,
        deviceName: null == deviceName
            ? _value.deviceName
            : deviceName // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$WardriveExtensionImpl implements _WardriveExtension {
  const _$WardriveExtensionImpl({
    this.ssid = '',
    this.authMode = 0,
    this.deviceName = '',
  });

  factory _$WardriveExtensionImpl.fromJson(Map<String, dynamic> json) =>
      _$$WardriveExtensionImplFromJson(json);

  @override
  @JsonKey()
  final String ssid;
  @override
  @JsonKey()
  final int authMode;
  @override
  @JsonKey()
  final String deviceName;

  @override
  String toString() {
    return 'WardriveExtension(ssid: $ssid, authMode: $authMode, deviceName: $deviceName)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$WardriveExtensionImpl &&
            (identical(other.ssid, ssid) || other.ssid == ssid) &&
            (identical(other.authMode, authMode) ||
                other.authMode == authMode) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, ssid, authMode, deviceName);

  /// Create a copy of WardriveExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$WardriveExtensionImplCopyWith<_$WardriveExtensionImpl> get copyWith =>
      __$$WardriveExtensionImplCopyWithImpl<_$WardriveExtensionImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$WardriveExtensionImplToJson(this);
  }
}

abstract class _WardriveExtension implements WardriveExtension {
  const factory _WardriveExtension({
    final String ssid,
    final int authMode,
    final String deviceName,
  }) = _$WardriveExtensionImpl;

  factory _WardriveExtension.fromJson(Map<String, dynamic> json) =
      _$WardriveExtensionImpl.fromJson;

  @override
  String get ssid;
  @override
  int get authMode;
  @override
  String get deviceName;

  /// Create a copy of WardriveExtension
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$WardriveExtensionImplCopyWith<_$WardriveExtensionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

DetectorExtension _$DetectorExtensionFromJson(Map<String, dynamic> json) {
  return _DetectorExtension.fromJson(json);
}

/// @nodoc
mixin _$DetectorExtension {
  String? get filterDescription => throw _privateConstructorUsedError;
  bool get isFullMac => throw _privateConstructorUsedError;

  /// Serializes this DetectorExtension to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of DetectorExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DetectorExtensionCopyWith<DetectorExtension> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DetectorExtensionCopyWith<$Res> {
  factory $DetectorExtensionCopyWith(
    DetectorExtension value,
    $Res Function(DetectorExtension) then,
  ) = _$DetectorExtensionCopyWithImpl<$Res, DetectorExtension>;
  @useResult
  $Res call({String? filterDescription, bool isFullMac});
}

/// @nodoc
class _$DetectorExtensionCopyWithImpl<$Res, $Val extends DetectorExtension>
    implements $DetectorExtensionCopyWith<$Res> {
  _$DetectorExtensionCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DetectorExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? filterDescription = freezed, Object? isFullMac = null}) {
    return _then(
      _value.copyWith(
            filterDescription: freezed == filterDescription
                ? _value.filterDescription
                : filterDescription // ignore: cast_nullable_to_non_nullable
                      as String?,
            isFullMac: null == isFullMac
                ? _value.isFullMac
                : isFullMac // ignore: cast_nullable_to_non_nullable
                      as bool,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DetectorExtensionImplCopyWith<$Res>
    implements $DetectorExtensionCopyWith<$Res> {
  factory _$$DetectorExtensionImplCopyWith(
    _$DetectorExtensionImpl value,
    $Res Function(_$DetectorExtensionImpl) then,
  ) = __$$DetectorExtensionImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String? filterDescription, bool isFullMac});
}

/// @nodoc
class __$$DetectorExtensionImplCopyWithImpl<$Res>
    extends _$DetectorExtensionCopyWithImpl<$Res, _$DetectorExtensionImpl>
    implements _$$DetectorExtensionImplCopyWith<$Res> {
  __$$DetectorExtensionImplCopyWithImpl(
    _$DetectorExtensionImpl _value,
    $Res Function(_$DetectorExtensionImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DetectorExtension
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? filterDescription = freezed, Object? isFullMac = null}) {
    return _then(
      _$DetectorExtensionImpl(
        filterDescription: freezed == filterDescription
            ? _value.filterDescription
            : filterDescription // ignore: cast_nullable_to_non_nullable
                  as String?,
        isFullMac: null == isFullMac
            ? _value.isFullMac
            : isFullMac // ignore: cast_nullable_to_non_nullable
                  as bool,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$DetectorExtensionImpl implements _DetectorExtension {
  const _$DetectorExtensionImpl({
    this.filterDescription,
    this.isFullMac = false,
  });

  factory _$DetectorExtensionImpl.fromJson(Map<String, dynamic> json) =>
      _$$DetectorExtensionImplFromJson(json);

  @override
  final String? filterDescription;
  @override
  @JsonKey()
  final bool isFullMac;

  @override
  String toString() {
    return 'DetectorExtension(filterDescription: $filterDescription, isFullMac: $isFullMac)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DetectorExtensionImpl &&
            (identical(other.filterDescription, filterDescription) ||
                other.filterDescription == filterDescription) &&
            (identical(other.isFullMac, isFullMac) ||
                other.isFullMac == isFullMac));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(runtimeType, filterDescription, isFullMac);

  /// Create a copy of DetectorExtension
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DetectorExtensionImplCopyWith<_$DetectorExtensionImpl> get copyWith =>
      __$$DetectorExtensionImplCopyWithImpl<_$DetectorExtensionImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$DetectorExtensionImplToJson(this);
  }
}

abstract class _DetectorExtension implements DetectorExtension {
  const factory _DetectorExtension({
    final String? filterDescription,
    final bool isFullMac,
  }) = _$DetectorExtensionImpl;

  factory _DetectorExtension.fromJson(Map<String, dynamic> json) =
      _$DetectorExtensionImpl.fromJson;

  @override
  String? get filterDescription;
  @override
  bool get isFullMac;

  /// Create a copy of DetectorExtension
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DetectorExtensionImplCopyWith<_$DetectorExtensionImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
