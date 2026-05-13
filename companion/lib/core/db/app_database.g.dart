// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $NodesTable extends Nodes with TableInfo<$NodesTable, Node> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NodesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firmwareVersionMeta = const VerificationMeta(
    'firmwareVersion',
  );
  @override
  late final GeneratedColumn<String> firmwareVersion = GeneratedColumn<String>(
    'firmware_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<int> lastSeen = GeneratedColumn<int>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _configHashMeta = const VerificationMeta(
    'configHash',
  );
  @override
  late final GeneratedColumn<String> configHash = GeneratedColumn<String>(
    'config_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    macAddress,
    firmwareVersion,
    lastSeen,
    configJson,
    configHash,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'nodes';
  @override
  VerificationContext validateIntegrity(
    Insertable<Node> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('firmware_version')) {
      context.handle(
        _firmwareVersionMeta,
        firmwareVersion.isAcceptableOrUnknown(
          data['firmware_version']!,
          _firmwareVersionMeta,
        ),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    }
    if (data.containsKey('config_hash')) {
      context.handle(
        _configHashMeta,
        configHash.isAcceptableOrUnknown(data['config_hash']!, _configHashMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Node map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Node(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      firmwareVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}firmware_version'],
      ),
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen'],
      ),
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      ),
      configHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_hash'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $NodesTable createAlias(String alias) {
    return $NodesTable(attachedDatabase, alias);
  }
}

class Node extends DataClass implements Insertable<Node> {
  final String id;
  final String name;
  final String macAddress;
  final String? firmwareVersion;
  final int? lastSeen;
  final String? configJson;
  final String? configHash;
  final int createdAt;
  const Node({
    required this.id,
    required this.name,
    required this.macAddress,
    this.firmwareVersion,
    this.lastSeen,
    this.configJson,
    this.configHash,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['mac_address'] = Variable<String>(macAddress);
    if (!nullToAbsent || firmwareVersion != null) {
      map['firmware_version'] = Variable<String>(firmwareVersion);
    }
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<int>(lastSeen);
    }
    if (!nullToAbsent || configJson != null) {
      map['config_json'] = Variable<String>(configJson);
    }
    if (!nullToAbsent || configHash != null) {
      map['config_hash'] = Variable<String>(configHash);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  NodesCompanion toCompanion(bool nullToAbsent) {
    return NodesCompanion(
      id: Value(id),
      name: Value(name),
      macAddress: Value(macAddress),
      firmwareVersion: firmwareVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(firmwareVersion),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      configJson: configJson == null && nullToAbsent
          ? const Value.absent()
          : Value(configJson),
      configHash: configHash == null && nullToAbsent
          ? const Value.absent()
          : Value(configHash),
      createdAt: Value(createdAt),
    );
  }

  factory Node.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Node(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      firmwareVersion: serializer.fromJson<String?>(json['firmwareVersion']),
      lastSeen: serializer.fromJson<int?>(json['lastSeen']),
      configJson: serializer.fromJson<String?>(json['configJson']),
      configHash: serializer.fromJson<String?>(json['configHash']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'macAddress': serializer.toJson<String>(macAddress),
      'firmwareVersion': serializer.toJson<String?>(firmwareVersion),
      'lastSeen': serializer.toJson<int?>(lastSeen),
      'configJson': serializer.toJson<String?>(configJson),
      'configHash': serializer.toJson<String?>(configHash),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Node copyWith({
    String? id,
    String? name,
    String? macAddress,
    Value<String?> firmwareVersion = const Value.absent(),
    Value<int?> lastSeen = const Value.absent(),
    Value<String?> configJson = const Value.absent(),
    Value<String?> configHash = const Value.absent(),
    int? createdAt,
  }) => Node(
    id: id ?? this.id,
    name: name ?? this.name,
    macAddress: macAddress ?? this.macAddress,
    firmwareVersion: firmwareVersion.present
        ? firmwareVersion.value
        : this.firmwareVersion,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
    configJson: configJson.present ? configJson.value : this.configJson,
    configHash: configHash.present ? configHash.value : this.configHash,
    createdAt: createdAt ?? this.createdAt,
  );
  Node copyWithCompanion(NodesCompanion data) {
    return Node(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      firmwareVersion: data.firmwareVersion.present
          ? data.firmwareVersion.value
          : this.firmwareVersion,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      configHash: data.configHash.present
          ? data.configHash.value
          : this.configHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Node(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('macAddress: $macAddress, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('configJson: $configJson, ')
          ..write('configHash: $configHash, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    macAddress,
    firmwareVersion,
    lastSeen,
    configJson,
    configHash,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Node &&
          other.id == this.id &&
          other.name == this.name &&
          other.macAddress == this.macAddress &&
          other.firmwareVersion == this.firmwareVersion &&
          other.lastSeen == this.lastSeen &&
          other.configJson == this.configJson &&
          other.configHash == this.configHash &&
          other.createdAt == this.createdAt);
}

class NodesCompanion extends UpdateCompanion<Node> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> macAddress;
  final Value<String?> firmwareVersion;
  final Value<int?> lastSeen;
  final Value<String?> configJson;
  final Value<String?> configHash;
  final Value<int> createdAt;
  final Value<int> rowid;
  const NodesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.firmwareVersion = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.configJson = const Value.absent(),
    this.configHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  NodesCompanion.insert({
    required String id,
    required String name,
    required String macAddress,
    this.firmwareVersion = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.configJson = const Value.absent(),
    this.configHash = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       macAddress = Value(macAddress),
       createdAt = Value(createdAt);
  static Insertable<Node> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? macAddress,
    Expression<String>? firmwareVersion,
    Expression<int>? lastSeen,
    Expression<String>? configJson,
    Expression<String>? configHash,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (macAddress != null) 'mac_address': macAddress,
      if (firmwareVersion != null) 'firmware_version': firmwareVersion,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (configJson != null) 'config_json': configJson,
      if (configHash != null) 'config_hash': configHash,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  NodesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? macAddress,
    Value<String?>? firmwareVersion,
    Value<int?>? lastSeen,
    Value<String?>? configJson,
    Value<String?>? configHash,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return NodesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      macAddress: macAddress ?? this.macAddress,
      firmwareVersion: firmwareVersion ?? this.firmwareVersion,
      lastSeen: lastSeen ?? this.lastSeen,
      configJson: configJson ?? this.configJson,
      configHash: configHash ?? this.configHash,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (firmwareVersion.present) {
      map['firmware_version'] = Variable<String>(firmwareVersion.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(lastSeen.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (configHash.present) {
      map['config_hash'] = Variable<String>(configHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NodesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('macAddress: $macAddress, ')
          ..write('firmwareVersion: $firmwareVersion, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('configJson: $configJson, ')
          ..write('configHash: $configHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionsTable extends Sessions with TableInfo<$SessionsTable, Session> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id)',
    ),
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<int> startedAt = GeneratedColumn<int>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<int> endedAt = GeneratedColumn<int>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _enginesActiveMeta = const VerificationMeta(
    'enginesActive',
  );
  @override
  late final GeneratedColumn<int> enginesActive = GeneratedColumn<int>(
    'engines_active',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _detectionCountMeta = const VerificationMeta(
    'detectionCount',
  );
  @override
  late final GeneratedColumn<int> detectionCount = GeneratedColumn<int>(
    'detection_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _uniqueMacCountMeta = const VerificationMeta(
    'uniqueMacCount',
  );
  @override
  late final GeneratedColumn<int> uniqueMacCount = GeneratedColumn<int>(
    'unique_mac_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _distanceKmMeta = const VerificationMeta(
    'distanceKm',
  );
  @override
  late final GeneratedColumn<double> distanceKm = GeneratedColumn<double>(
    'distance_km',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
    defaultValue: const Constant(0.0),
  );
  static const VerificationMeta _exportedMeta = const VerificationMeta(
    'exported',
  );
  @override
  late final GeneratedColumn<bool> exported = GeneratedColumn<bool>(
    'exported',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("exported" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _isWardriveMeta = const VerificationMeta(
    'isWardrive',
  );
  @override
  late final GeneratedColumn<bool> isWardrive = GeneratedColumn<bool>(
    'is_wardrive',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_wardrive" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
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
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<Session> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    if (data.containsKey('engines_active')) {
      context.handle(
        _enginesActiveMeta,
        enginesActive.isAcceptableOrUnknown(
          data['engines_active']!,
          _enginesActiveMeta,
        ),
      );
    }
    if (data.containsKey('detection_count')) {
      context.handle(
        _detectionCountMeta,
        detectionCount.isAcceptableOrUnknown(
          data['detection_count']!,
          _detectionCountMeta,
        ),
      );
    }
    if (data.containsKey('unique_mac_count')) {
      context.handle(
        _uniqueMacCountMeta,
        uniqueMacCount.isAcceptableOrUnknown(
          data['unique_mac_count']!,
          _uniqueMacCountMeta,
        ),
      );
    }
    if (data.containsKey('distance_km')) {
      context.handle(
        _distanceKmMeta,
        distanceKm.isAcceptableOrUnknown(data['distance_km']!, _distanceKmMeta),
      );
    }
    if (data.containsKey('exported')) {
      context.handle(
        _exportedMeta,
        exported.isAcceptableOrUnknown(data['exported']!, _exportedMeta),
      );
    }
    if (data.containsKey('is_wardrive')) {
      context.handle(
        _isWardriveMeta,
        isWardrive.isAcceptableOrUnknown(data['is_wardrive']!, _isWardriveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Session map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Session(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      )!,
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ended_at'],
      ),
      enginesActive: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}engines_active'],
      )!,
      detectionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}detection_count'],
      )!,
      uniqueMacCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}unique_mac_count'],
      )!,
      distanceKm: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}distance_km'],
      )!,
      exported: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}exported'],
      )!,
      isWardrive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_wardrive'],
      )!,
    );
  }

  @override
  $SessionsTable createAlias(String alias) {
    return $SessionsTable(attachedDatabase, alias);
  }
}

class Session extends DataClass implements Insertable<Session> {
  final String id;
  final String name;
  final String nodeId;
  final int startedAt;
  final int? endedAt;
  final int enginesActive;
  final int detectionCount;
  final int uniqueMacCount;
  final double distanceKm;
  final bool exported;
  final bool isWardrive;
  const Session({
    required this.id,
    required this.name,
    required this.nodeId,
    required this.startedAt,
    this.endedAt,
    required this.enginesActive,
    required this.detectionCount,
    required this.uniqueMacCount,
    required this.distanceKm,
    required this.exported,
    required this.isWardrive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['node_id'] = Variable<String>(nodeId);
    map['started_at'] = Variable<int>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<int>(endedAt);
    }
    map['engines_active'] = Variable<int>(enginesActive);
    map['detection_count'] = Variable<int>(detectionCount);
    map['unique_mac_count'] = Variable<int>(uniqueMacCount);
    map['distance_km'] = Variable<double>(distanceKm);
    map['exported'] = Variable<bool>(exported);
    map['is_wardrive'] = Variable<bool>(isWardrive);
    return map;
  }

  SessionsCompanion toCompanion(bool nullToAbsent) {
    return SessionsCompanion(
      id: Value(id),
      name: Value(name),
      nodeId: Value(nodeId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
      enginesActive: Value(enginesActive),
      detectionCount: Value(detectionCount),
      uniqueMacCount: Value(uniqueMacCount),
      distanceKm: Value(distanceKm),
      exported: Value(exported),
      isWardrive: Value(isWardrive),
    );
  }

  factory Session.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Session(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      nodeId: serializer.fromJson<String>(json['nodeId']),
      startedAt: serializer.fromJson<int>(json['startedAt']),
      endedAt: serializer.fromJson<int?>(json['endedAt']),
      enginesActive: serializer.fromJson<int>(json['enginesActive']),
      detectionCount: serializer.fromJson<int>(json['detectionCount']),
      uniqueMacCount: serializer.fromJson<int>(json['uniqueMacCount']),
      distanceKm: serializer.fromJson<double>(json['distanceKm']),
      exported: serializer.fromJson<bool>(json['exported']),
      isWardrive: serializer.fromJson<bool>(json['isWardrive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'nodeId': serializer.toJson<String>(nodeId),
      'startedAt': serializer.toJson<int>(startedAt),
      'endedAt': serializer.toJson<int?>(endedAt),
      'enginesActive': serializer.toJson<int>(enginesActive),
      'detectionCount': serializer.toJson<int>(detectionCount),
      'uniqueMacCount': serializer.toJson<int>(uniqueMacCount),
      'distanceKm': serializer.toJson<double>(distanceKm),
      'exported': serializer.toJson<bool>(exported),
      'isWardrive': serializer.toJson<bool>(isWardrive),
    };
  }

  Session copyWith({
    String? id,
    String? name,
    String? nodeId,
    int? startedAt,
    Value<int?> endedAt = const Value.absent(),
    int? enginesActive,
    int? detectionCount,
    int? uniqueMacCount,
    double? distanceKm,
    bool? exported,
    bool? isWardrive,
  }) => Session(
    id: id ?? this.id,
    name: name ?? this.name,
    nodeId: nodeId ?? this.nodeId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
    enginesActive: enginesActive ?? this.enginesActive,
    detectionCount: detectionCount ?? this.detectionCount,
    uniqueMacCount: uniqueMacCount ?? this.uniqueMacCount,
    distanceKm: distanceKm ?? this.distanceKm,
    exported: exported ?? this.exported,
    isWardrive: isWardrive ?? this.isWardrive,
  );
  Session copyWithCompanion(SessionsCompanion data) {
    return Session(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
      enginesActive: data.enginesActive.present
          ? data.enginesActive.value
          : this.enginesActive,
      detectionCount: data.detectionCount.present
          ? data.detectionCount.value
          : this.detectionCount,
      uniqueMacCount: data.uniqueMacCount.present
          ? data.uniqueMacCount.value
          : this.uniqueMacCount,
      distanceKm: data.distanceKm.present
          ? data.distanceKm.value
          : this.distanceKm,
      exported: data.exported.present ? data.exported.value : this.exported,
      isWardrive: data.isWardrive.present
          ? data.isWardrive.value
          : this.isWardrive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Session(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nodeId: $nodeId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('enginesActive: $enginesActive, ')
          ..write('detectionCount: $detectionCount, ')
          ..write('uniqueMacCount: $uniqueMacCount, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('exported: $exported, ')
          ..write('isWardrive: $isWardrive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Session &&
          other.id == this.id &&
          other.name == this.name &&
          other.nodeId == this.nodeId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt &&
          other.enginesActive == this.enginesActive &&
          other.detectionCount == this.detectionCount &&
          other.uniqueMacCount == this.uniqueMacCount &&
          other.distanceKm == this.distanceKm &&
          other.exported == this.exported &&
          other.isWardrive == this.isWardrive);
}

class SessionsCompanion extends UpdateCompanion<Session> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> nodeId;
  final Value<int> startedAt;
  final Value<int?> endedAt;
  final Value<int> enginesActive;
  final Value<int> detectionCount;
  final Value<int> uniqueMacCount;
  final Value<double> distanceKm;
  final Value<bool> exported;
  final Value<bool> isWardrive;
  final Value<int> rowid;
  const SessionsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.enginesActive = const Value.absent(),
    this.detectionCount = const Value.absent(),
    this.uniqueMacCount = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.exported = const Value.absent(),
    this.isWardrive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionsCompanion.insert({
    required String id,
    required String name,
    required String nodeId,
    required int startedAt,
    this.endedAt = const Value.absent(),
    this.enginesActive = const Value.absent(),
    this.detectionCount = const Value.absent(),
    this.uniqueMacCount = const Value.absent(),
    this.distanceKm = const Value.absent(),
    this.exported = const Value.absent(),
    this.isWardrive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       nodeId = Value(nodeId),
       startedAt = Value(startedAt);
  static Insertable<Session> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? nodeId,
    Expression<int>? startedAt,
    Expression<int>? endedAt,
    Expression<int>? enginesActive,
    Expression<int>? detectionCount,
    Expression<int>? uniqueMacCount,
    Expression<double>? distanceKm,
    Expression<bool>? exported,
    Expression<bool>? isWardrive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (nodeId != null) 'node_id': nodeId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (enginesActive != null) 'engines_active': enginesActive,
      if (detectionCount != null) 'detection_count': detectionCount,
      if (uniqueMacCount != null) 'unique_mac_count': uniqueMacCount,
      if (distanceKm != null) 'distance_km': distanceKm,
      if (exported != null) 'exported': exported,
      if (isWardrive != null) 'is_wardrive': isWardrive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? nodeId,
    Value<int>? startedAt,
    Value<int?>? endedAt,
    Value<int>? enginesActive,
    Value<int>? detectionCount,
    Value<int>? uniqueMacCount,
    Value<double>? distanceKm,
    Value<bool>? exported,
    Value<bool>? isWardrive,
    Value<int>? rowid,
  }) {
    return SessionsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      nodeId: nodeId ?? this.nodeId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      enginesActive: enginesActive ?? this.enginesActive,
      detectionCount: detectionCount ?? this.detectionCount,
      uniqueMacCount: uniqueMacCount ?? this.uniqueMacCount,
      distanceKm: distanceKm ?? this.distanceKm,
      exported: exported ?? this.exported,
      isWardrive: isWardrive ?? this.isWardrive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<int>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<int>(endedAt.value);
    }
    if (enginesActive.present) {
      map['engines_active'] = Variable<int>(enginesActive.value);
    }
    if (detectionCount.present) {
      map['detection_count'] = Variable<int>(detectionCount.value);
    }
    if (uniqueMacCount.present) {
      map['unique_mac_count'] = Variable<int>(uniqueMacCount.value);
    }
    if (distanceKm.present) {
      map['distance_km'] = Variable<double>(distanceKm.value);
    }
    if (exported.present) {
      map['exported'] = Variable<bool>(exported.value);
    }
    if (isWardrive.present) {
      map['is_wardrive'] = Variable<bool>(isWardrive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('nodeId: $nodeId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('enginesActive: $enginesActive, ')
          ..write('detectionCount: $detectionCount, ')
          ..write('uniqueMacCount: $uniqueMacCount, ')
          ..write('distanceKm: $distanceKm, ')
          ..write('exported: $exported, ')
          ..write('isWardrive: $isWardrive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DetectionsTable extends Detections
    with TableInfo<$DetectionsTable, Detection> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DetectionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id)',
    ),
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _engineMeta = const VerificationMeta('engine');
  @override
  late final GeneratedColumn<String> engine = GeneratedColumn<String>(
    'engine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detectionMethodMeta = const VerificationMeta(
    'detectionMethod',
  );
  @override
  late final GeneratedColumn<String> detectionMethod = GeneratedColumn<String>(
    'detection_method',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rssiMeta = const VerificationMeta('rssi');
  @override
  late final GeneratedColumn<int> rssi = GeneratedColumn<int>(
    'rssi',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _channelMeta = const VerificationMeta(
    'channel',
  );
  @override
  late final GeneratedColumn<int> channel = GeneratedColumn<int>(
    'channel',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceTimestampMsMeta = const VerificationMeta(
    'deviceTimestampMs',
  );
  @override
  late final GeneratedColumn<int> deviceTimestampMs = GeneratedColumn<int>(
    'device_timestamp_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _appTimestampMeta = const VerificationMeta(
    'appTimestamp',
  );
  @override
  late final GeneratedColumn<int> appTimestamp = GeneratedColumn<int>(
    'app_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _altitudeMeta = const VerificationMeta(
    'altitude',
  );
  @override
  late final GeneratedColumn<double> altitude = GeneratedColumn<double>(
    'altitude',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMeta = const VerificationMeta('speed');
  @override
  late final GeneratedColumn<double> speed = GeneratedColumn<double>(
    'speed',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _headingMeta = const VerificationMeta(
    'heading',
  );
  @override
  late final GeneratedColumn<double> heading = GeneratedColumn<double>(
    'heading',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMeta = const VerificationMeta(
    'accuracy',
  );
  @override
  late final GeneratedColumn<double> accuracy = GeneratedColumn<double>(
    'accuracy',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _satelliteCountMeta = const VerificationMeta(
    'satelliteCount',
  );
  @override
  late final GeneratedColumn<int> satelliteCount = GeneratedColumn<int>(
    'satellite_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ssidMeta = const VerificationMeta('ssid');
  @override
  late final GeneratedColumn<String> ssid = GeneratedColumn<String>(
    'ssid',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _authModeMeta = const VerificationMeta(
    'authMode',
  );
  @override
  late final GeneratedColumn<int> authMode = GeneratedColumn<int>(
    'auth_mode',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _countMeta = const VerificationMeta('count');
  @override
  late final GeneratedColumn<int> count = GeneratedColumn<int>(
    'count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _isRavenMeta = const VerificationMeta(
    'isRaven',
  );
  @override
  late final GeneratedColumn<bool> isRaven = GeneratedColumn<bool>(
    'is_raven',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_raven" IN (0, 1))',
    ),
  );
  static const VerificationMeta _ravenFirmwareMeta = const VerificationMeta(
    'ravenFirmware',
  );
  @override
  late final GeneratedColumn<String> ravenFirmware = GeneratedColumn<String>(
    'raven_firmware',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _uavIdMeta = const VerificationMeta('uavId');
  @override
  late final GeneratedColumn<String> uavId = GeneratedColumn<String>(
    'uav_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _operatorIdMeta = const VerificationMeta(
    'operatorId',
  );
  @override
  late final GeneratedColumn<String> operatorId = GeneratedColumn<String>(
    'operator_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _droneLatMeta = const VerificationMeta(
    'droneLat',
  );
  @override
  late final GeneratedColumn<double> droneLat = GeneratedColumn<double>(
    'drone_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _droneLonMeta = const VerificationMeta(
    'droneLon',
  );
  @override
  late final GeneratedColumn<double> droneLon = GeneratedColumn<double>(
    'drone_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _altitudeMslMeta = const VerificationMeta(
    'altitudeMsl',
  );
  @override
  late final GeneratedColumn<int> altitudeMsl = GeneratedColumn<int>(
    'altitude_msl',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _heightAglMeta = const VerificationMeta(
    'heightAgl',
  );
  @override
  late final GeneratedColumn<int> heightAgl = GeneratedColumn<int>(
    'height_agl',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _droneSpeedMeta = const VerificationMeta(
    'droneSpeed',
  );
  @override
  late final GeneratedColumn<int> droneSpeed = GeneratedColumn<int>(
    'drone_speed',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _droneHeadingMeta = const VerificationMeta(
    'droneHeading',
  );
  @override
  late final GeneratedColumn<int> droneHeading = GeneratedColumn<int>(
    'drone_heading',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pilotLatMeta = const VerificationMeta(
    'pilotLat',
  );
  @override
  late final GeneratedColumn<double> pilotLat = GeneratedColumn<double>(
    'pilot_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _pilotLonMeta = const VerificationMeta(
    'pilotLon',
  );
  @override
  late final GeneratedColumn<double> pilotLon = GeneratedColumn<double>(
    'pilot_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _robotTypeMeta = const VerificationMeta(
    'robotType',
  );
  @override
  late final GeneratedColumn<String> robotType = GeneratedColumn<String>(
    'robot_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exploitedMeta = const VerificationMeta(
    'exploited',
  );
  @override
  late final GeneratedColumn<bool> exploited = GeneratedColumn<bool>(
    'exploited',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("exploited" IN (0, 1))',
    ),
  );
  static const VerificationMeta _robotSerialMeta = const VerificationMeta(
    'robotSerial',
  );
  @override
  late final GeneratedColumn<String> robotSerial = GeneratedColumn<String>(
    'robot_serial',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filterDescriptionMeta = const VerificationMeta(
    'filterDescription',
  );
  @override
  late final GeneratedColumn<String> filterDescription =
      GeneratedColumn<String>(
        'filter_description',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _isFullMacMeta = const VerificationMeta(
    'isFullMac',
  );
  @override
  late final GeneratedColumn<bool> isFullMac = GeneratedColumn<bool>(
    'is_full_mac',
    aliasedName,
    true,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_full_mac" IN (0, 1))',
    ),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    nodeId,
    macAddress,
    deviceName,
    engine,
    detectionMethod,
    rssi,
    channel,
    deviceTimestampMs,
    appTimestamp,
    latitude,
    longitude,
    altitude,
    speed,
    heading,
    accuracy,
    satelliteCount,
    ssid,
    authMode,
    count,
    isRaven,
    ravenFirmware,
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
    robotType,
    exploited,
    robotSerial,
    filterDescription,
    isFullMac,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'detections';
  @override
  VerificationContext validateIntegrity(
    Insertable<Detection> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    if (data.containsKey('engine')) {
      context.handle(
        _engineMeta,
        engine.isAcceptableOrUnknown(data['engine']!, _engineMeta),
      );
    } else if (isInserting) {
      context.missing(_engineMeta);
    }
    if (data.containsKey('detection_method')) {
      context.handle(
        _detectionMethodMeta,
        detectionMethod.isAcceptableOrUnknown(
          data['detection_method']!,
          _detectionMethodMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_detectionMethodMeta);
    }
    if (data.containsKey('rssi')) {
      context.handle(
        _rssiMeta,
        rssi.isAcceptableOrUnknown(data['rssi']!, _rssiMeta),
      );
    } else if (isInserting) {
      context.missing(_rssiMeta);
    }
    if (data.containsKey('channel')) {
      context.handle(
        _channelMeta,
        channel.isAcceptableOrUnknown(data['channel']!, _channelMeta),
      );
    } else if (isInserting) {
      context.missing(_channelMeta);
    }
    if (data.containsKey('device_timestamp_ms')) {
      context.handle(
        _deviceTimestampMsMeta,
        deviceTimestampMs.isAcceptableOrUnknown(
          data['device_timestamp_ms']!,
          _deviceTimestampMsMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_deviceTimestampMsMeta);
    }
    if (data.containsKey('app_timestamp')) {
      context.handle(
        _appTimestampMeta,
        appTimestamp.isAcceptableOrUnknown(
          data['app_timestamp']!,
          _appTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_appTimestampMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    }
    if (data.containsKey('altitude')) {
      context.handle(
        _altitudeMeta,
        altitude.isAcceptableOrUnknown(data['altitude']!, _altitudeMeta),
      );
    }
    if (data.containsKey('speed')) {
      context.handle(
        _speedMeta,
        speed.isAcceptableOrUnknown(data['speed']!, _speedMeta),
      );
    }
    if (data.containsKey('heading')) {
      context.handle(
        _headingMeta,
        heading.isAcceptableOrUnknown(data['heading']!, _headingMeta),
      );
    }
    if (data.containsKey('accuracy')) {
      context.handle(
        _accuracyMeta,
        accuracy.isAcceptableOrUnknown(data['accuracy']!, _accuracyMeta),
      );
    }
    if (data.containsKey('satellite_count')) {
      context.handle(
        _satelliteCountMeta,
        satelliteCount.isAcceptableOrUnknown(
          data['satellite_count']!,
          _satelliteCountMeta,
        ),
      );
    }
    if (data.containsKey('ssid')) {
      context.handle(
        _ssidMeta,
        ssid.isAcceptableOrUnknown(data['ssid']!, _ssidMeta),
      );
    }
    if (data.containsKey('auth_mode')) {
      context.handle(
        _authModeMeta,
        authMode.isAcceptableOrUnknown(data['auth_mode']!, _authModeMeta),
      );
    }
    if (data.containsKey('count')) {
      context.handle(
        _countMeta,
        count.isAcceptableOrUnknown(data['count']!, _countMeta),
      );
    }
    if (data.containsKey('is_raven')) {
      context.handle(
        _isRavenMeta,
        isRaven.isAcceptableOrUnknown(data['is_raven']!, _isRavenMeta),
      );
    }
    if (data.containsKey('raven_firmware')) {
      context.handle(
        _ravenFirmwareMeta,
        ravenFirmware.isAcceptableOrUnknown(
          data['raven_firmware']!,
          _ravenFirmwareMeta,
        ),
      );
    }
    if (data.containsKey('uav_id')) {
      context.handle(
        _uavIdMeta,
        uavId.isAcceptableOrUnknown(data['uav_id']!, _uavIdMeta),
      );
    }
    if (data.containsKey('operator_id')) {
      context.handle(
        _operatorIdMeta,
        operatorId.isAcceptableOrUnknown(data['operator_id']!, _operatorIdMeta),
      );
    }
    if (data.containsKey('drone_lat')) {
      context.handle(
        _droneLatMeta,
        droneLat.isAcceptableOrUnknown(data['drone_lat']!, _droneLatMeta),
      );
    }
    if (data.containsKey('drone_lon')) {
      context.handle(
        _droneLonMeta,
        droneLon.isAcceptableOrUnknown(data['drone_lon']!, _droneLonMeta),
      );
    }
    if (data.containsKey('altitude_msl')) {
      context.handle(
        _altitudeMslMeta,
        altitudeMsl.isAcceptableOrUnknown(
          data['altitude_msl']!,
          _altitudeMslMeta,
        ),
      );
    }
    if (data.containsKey('height_agl')) {
      context.handle(
        _heightAglMeta,
        heightAgl.isAcceptableOrUnknown(data['height_agl']!, _heightAglMeta),
      );
    }
    if (data.containsKey('drone_speed')) {
      context.handle(
        _droneSpeedMeta,
        droneSpeed.isAcceptableOrUnknown(data['drone_speed']!, _droneSpeedMeta),
      );
    }
    if (data.containsKey('drone_heading')) {
      context.handle(
        _droneHeadingMeta,
        droneHeading.isAcceptableOrUnknown(
          data['drone_heading']!,
          _droneHeadingMeta,
        ),
      );
    }
    if (data.containsKey('pilot_lat')) {
      context.handle(
        _pilotLatMeta,
        pilotLat.isAcceptableOrUnknown(data['pilot_lat']!, _pilotLatMeta),
      );
    }
    if (data.containsKey('pilot_lon')) {
      context.handle(
        _pilotLonMeta,
        pilotLon.isAcceptableOrUnknown(data['pilot_lon']!, _pilotLonMeta),
      );
    }
    if (data.containsKey('robot_type')) {
      context.handle(
        _robotTypeMeta,
        robotType.isAcceptableOrUnknown(data['robot_type']!, _robotTypeMeta),
      );
    }
    if (data.containsKey('exploited')) {
      context.handle(
        _exploitedMeta,
        exploited.isAcceptableOrUnknown(data['exploited']!, _exploitedMeta),
      );
    }
    if (data.containsKey('robot_serial')) {
      context.handle(
        _robotSerialMeta,
        robotSerial.isAcceptableOrUnknown(
          data['robot_serial']!,
          _robotSerialMeta,
        ),
      );
    }
    if (data.containsKey('filter_description')) {
      context.handle(
        _filterDescriptionMeta,
        filterDescription.isAcceptableOrUnknown(
          data['filter_description']!,
          _filterDescriptionMeta,
        ),
      );
    }
    if (data.containsKey('is_full_mac')) {
      context.handle(
        _isFullMacMeta,
        isFullMac.isAcceptableOrUnknown(data['is_full_mac']!, _isFullMacMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Detection map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Detection(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      engine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine'],
      )!,
      detectionMethod: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detection_method'],
      )!,
      rssi: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi'],
      )!,
      channel: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}channel'],
      )!,
      deviceTimestampMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}device_timestamp_ms'],
      )!,
      appTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}app_timestamp'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      ),
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      ),
      altitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}altitude'],
      ),
      speed: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed'],
      ),
      heading: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}heading'],
      ),
      accuracy: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy'],
      ),
      satelliteCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}satellite_count'],
      ),
      ssid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ssid'],
      )!,
      authMode: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}auth_mode'],
      )!,
      count: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}count'],
      )!,
      isRaven: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_raven'],
      ),
      ravenFirmware: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raven_firmware'],
      ),
      uavId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}uav_id'],
      ),
      operatorId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}operator_id'],
      ),
      droneLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}drone_lat'],
      ),
      droneLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}drone_lon'],
      ),
      altitudeMsl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}altitude_msl'],
      ),
      heightAgl: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}height_agl'],
      ),
      droneSpeed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drone_speed'],
      ),
      droneHeading: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}drone_heading'],
      ),
      pilotLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pilot_lat'],
      ),
      pilotLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}pilot_lon'],
      ),
      robotType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}robot_type'],
      ),
      exploited: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}exploited'],
      ),
      robotSerial: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}robot_serial'],
      ),
      filterDescription: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}filter_description'],
      ),
      isFullMac: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_full_mac'],
      ),
    );
  }

  @override
  $DetectionsTable createAlias(String alias) {
    return $DetectionsTable(attachedDatabase, alias);
  }
}

class Detection extends DataClass implements Insertable<Detection> {
  final int id;
  final String sessionId;
  final String nodeId;
  final String macAddress;
  final String deviceName;
  final String engine;
  final String detectionMethod;
  final int rssi;
  final int channel;
  final int deviceTimestampMs;
  final int appTimestamp;
  final double? latitude;
  final double? longitude;
  final double? altitude;
  final double? speed;
  final double? heading;
  final double? accuracy;
  final int? satelliteCount;
  final String ssid;
  final int authMode;
  final int count;
  final bool? isRaven;
  final String? ravenFirmware;
  final String? uavId;
  final String? operatorId;
  final double? droneLat;
  final double? droneLon;
  final int? altitudeMsl;
  final int? heightAgl;
  final int? droneSpeed;
  final int? droneHeading;
  final double? pilotLat;
  final double? pilotLon;
  final String? robotType;
  final bool? exploited;
  final String? robotSerial;
  final String? filterDescription;
  final bool? isFullMac;
  const Detection({
    required this.id,
    required this.sessionId,
    required this.nodeId,
    required this.macAddress,
    required this.deviceName,
    required this.engine,
    required this.detectionMethod,
    required this.rssi,
    required this.channel,
    required this.deviceTimestampMs,
    required this.appTimestamp,
    this.latitude,
    this.longitude,
    this.altitude,
    this.speed,
    this.heading,
    this.accuracy,
    this.satelliteCount,
    required this.ssid,
    required this.authMode,
    required this.count,
    this.isRaven,
    this.ravenFirmware,
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
    this.robotType,
    this.exploited,
    this.robotSerial,
    this.filterDescription,
    this.isFullMac,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['node_id'] = Variable<String>(nodeId);
    map['mac_address'] = Variable<String>(macAddress);
    map['device_name'] = Variable<String>(deviceName);
    map['engine'] = Variable<String>(engine);
    map['detection_method'] = Variable<String>(detectionMethod);
    map['rssi'] = Variable<int>(rssi);
    map['channel'] = Variable<int>(channel);
    map['device_timestamp_ms'] = Variable<int>(deviceTimestampMs);
    map['app_timestamp'] = Variable<int>(appTimestamp);
    if (!nullToAbsent || latitude != null) {
      map['latitude'] = Variable<double>(latitude);
    }
    if (!nullToAbsent || longitude != null) {
      map['longitude'] = Variable<double>(longitude);
    }
    if (!nullToAbsent || altitude != null) {
      map['altitude'] = Variable<double>(altitude);
    }
    if (!nullToAbsent || speed != null) {
      map['speed'] = Variable<double>(speed);
    }
    if (!nullToAbsent || heading != null) {
      map['heading'] = Variable<double>(heading);
    }
    if (!nullToAbsent || accuracy != null) {
      map['accuracy'] = Variable<double>(accuracy);
    }
    if (!nullToAbsent || satelliteCount != null) {
      map['satellite_count'] = Variable<int>(satelliteCount);
    }
    map['ssid'] = Variable<String>(ssid);
    map['auth_mode'] = Variable<int>(authMode);
    map['count'] = Variable<int>(count);
    if (!nullToAbsent || isRaven != null) {
      map['is_raven'] = Variable<bool>(isRaven);
    }
    if (!nullToAbsent || ravenFirmware != null) {
      map['raven_firmware'] = Variable<String>(ravenFirmware);
    }
    if (!nullToAbsent || uavId != null) {
      map['uav_id'] = Variable<String>(uavId);
    }
    if (!nullToAbsent || operatorId != null) {
      map['operator_id'] = Variable<String>(operatorId);
    }
    if (!nullToAbsent || droneLat != null) {
      map['drone_lat'] = Variable<double>(droneLat);
    }
    if (!nullToAbsent || droneLon != null) {
      map['drone_lon'] = Variable<double>(droneLon);
    }
    if (!nullToAbsent || altitudeMsl != null) {
      map['altitude_msl'] = Variable<int>(altitudeMsl);
    }
    if (!nullToAbsent || heightAgl != null) {
      map['height_agl'] = Variable<int>(heightAgl);
    }
    if (!nullToAbsent || droneSpeed != null) {
      map['drone_speed'] = Variable<int>(droneSpeed);
    }
    if (!nullToAbsent || droneHeading != null) {
      map['drone_heading'] = Variable<int>(droneHeading);
    }
    if (!nullToAbsent || pilotLat != null) {
      map['pilot_lat'] = Variable<double>(pilotLat);
    }
    if (!nullToAbsent || pilotLon != null) {
      map['pilot_lon'] = Variable<double>(pilotLon);
    }
    if (!nullToAbsent || robotType != null) {
      map['robot_type'] = Variable<String>(robotType);
    }
    if (!nullToAbsent || exploited != null) {
      map['exploited'] = Variable<bool>(exploited);
    }
    if (!nullToAbsent || robotSerial != null) {
      map['robot_serial'] = Variable<String>(robotSerial);
    }
    if (!nullToAbsent || filterDescription != null) {
      map['filter_description'] = Variable<String>(filterDescription);
    }
    if (!nullToAbsent || isFullMac != null) {
      map['is_full_mac'] = Variable<bool>(isFullMac);
    }
    return map;
  }

  DetectionsCompanion toCompanion(bool nullToAbsent) {
    return DetectionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      nodeId: Value(nodeId),
      macAddress: Value(macAddress),
      deviceName: Value(deviceName),
      engine: Value(engine),
      detectionMethod: Value(detectionMethod),
      rssi: Value(rssi),
      channel: Value(channel),
      deviceTimestampMs: Value(deviceTimestampMs),
      appTimestamp: Value(appTimestamp),
      latitude: latitude == null && nullToAbsent
          ? const Value.absent()
          : Value(latitude),
      longitude: longitude == null && nullToAbsent
          ? const Value.absent()
          : Value(longitude),
      altitude: altitude == null && nullToAbsent
          ? const Value.absent()
          : Value(altitude),
      speed: speed == null && nullToAbsent
          ? const Value.absent()
          : Value(speed),
      heading: heading == null && nullToAbsent
          ? const Value.absent()
          : Value(heading),
      accuracy: accuracy == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracy),
      satelliteCount: satelliteCount == null && nullToAbsent
          ? const Value.absent()
          : Value(satelliteCount),
      ssid: Value(ssid),
      authMode: Value(authMode),
      count: Value(count),
      isRaven: isRaven == null && nullToAbsent
          ? const Value.absent()
          : Value(isRaven),
      ravenFirmware: ravenFirmware == null && nullToAbsent
          ? const Value.absent()
          : Value(ravenFirmware),
      uavId: uavId == null && nullToAbsent
          ? const Value.absent()
          : Value(uavId),
      operatorId: operatorId == null && nullToAbsent
          ? const Value.absent()
          : Value(operatorId),
      droneLat: droneLat == null && nullToAbsent
          ? const Value.absent()
          : Value(droneLat),
      droneLon: droneLon == null && nullToAbsent
          ? const Value.absent()
          : Value(droneLon),
      altitudeMsl: altitudeMsl == null && nullToAbsent
          ? const Value.absent()
          : Value(altitudeMsl),
      heightAgl: heightAgl == null && nullToAbsent
          ? const Value.absent()
          : Value(heightAgl),
      droneSpeed: droneSpeed == null && nullToAbsent
          ? const Value.absent()
          : Value(droneSpeed),
      droneHeading: droneHeading == null && nullToAbsent
          ? const Value.absent()
          : Value(droneHeading),
      pilotLat: pilotLat == null && nullToAbsent
          ? const Value.absent()
          : Value(pilotLat),
      pilotLon: pilotLon == null && nullToAbsent
          ? const Value.absent()
          : Value(pilotLon),
      robotType: robotType == null && nullToAbsent
          ? const Value.absent()
          : Value(robotType),
      exploited: exploited == null && nullToAbsent
          ? const Value.absent()
          : Value(exploited),
      robotSerial: robotSerial == null && nullToAbsent
          ? const Value.absent()
          : Value(robotSerial),
      filterDescription: filterDescription == null && nullToAbsent
          ? const Value.absent()
          : Value(filterDescription),
      isFullMac: isFullMac == null && nullToAbsent
          ? const Value.absent()
          : Value(isFullMac),
    );
  }

  factory Detection.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Detection(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      nodeId: serializer.fromJson<String>(json['nodeId']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      engine: serializer.fromJson<String>(json['engine']),
      detectionMethod: serializer.fromJson<String>(json['detectionMethod']),
      rssi: serializer.fromJson<int>(json['rssi']),
      channel: serializer.fromJson<int>(json['channel']),
      deviceTimestampMs: serializer.fromJson<int>(json['deviceTimestampMs']),
      appTimestamp: serializer.fromJson<int>(json['appTimestamp']),
      latitude: serializer.fromJson<double?>(json['latitude']),
      longitude: serializer.fromJson<double?>(json['longitude']),
      altitude: serializer.fromJson<double?>(json['altitude']),
      speed: serializer.fromJson<double?>(json['speed']),
      heading: serializer.fromJson<double?>(json['heading']),
      accuracy: serializer.fromJson<double?>(json['accuracy']),
      satelliteCount: serializer.fromJson<int?>(json['satelliteCount']),
      ssid: serializer.fromJson<String>(json['ssid']),
      authMode: serializer.fromJson<int>(json['authMode']),
      count: serializer.fromJson<int>(json['count']),
      isRaven: serializer.fromJson<bool?>(json['isRaven']),
      ravenFirmware: serializer.fromJson<String?>(json['ravenFirmware']),
      uavId: serializer.fromJson<String?>(json['uavId']),
      operatorId: serializer.fromJson<String?>(json['operatorId']),
      droneLat: serializer.fromJson<double?>(json['droneLat']),
      droneLon: serializer.fromJson<double?>(json['droneLon']),
      altitudeMsl: serializer.fromJson<int?>(json['altitudeMsl']),
      heightAgl: serializer.fromJson<int?>(json['heightAgl']),
      droneSpeed: serializer.fromJson<int?>(json['droneSpeed']),
      droneHeading: serializer.fromJson<int?>(json['droneHeading']),
      pilotLat: serializer.fromJson<double?>(json['pilotLat']),
      pilotLon: serializer.fromJson<double?>(json['pilotLon']),
      robotType: serializer.fromJson<String?>(json['robotType']),
      exploited: serializer.fromJson<bool?>(json['exploited']),
      robotSerial: serializer.fromJson<String?>(json['robotSerial']),
      filterDescription: serializer.fromJson<String?>(
        json['filterDescription'],
      ),
      isFullMac: serializer.fromJson<bool?>(json['isFullMac']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'nodeId': serializer.toJson<String>(nodeId),
      'macAddress': serializer.toJson<String>(macAddress),
      'deviceName': serializer.toJson<String>(deviceName),
      'engine': serializer.toJson<String>(engine),
      'detectionMethod': serializer.toJson<String>(detectionMethod),
      'rssi': serializer.toJson<int>(rssi),
      'channel': serializer.toJson<int>(channel),
      'deviceTimestampMs': serializer.toJson<int>(deviceTimestampMs),
      'appTimestamp': serializer.toJson<int>(appTimestamp),
      'latitude': serializer.toJson<double?>(latitude),
      'longitude': serializer.toJson<double?>(longitude),
      'altitude': serializer.toJson<double?>(altitude),
      'speed': serializer.toJson<double?>(speed),
      'heading': serializer.toJson<double?>(heading),
      'accuracy': serializer.toJson<double?>(accuracy),
      'satelliteCount': serializer.toJson<int?>(satelliteCount),
      'ssid': serializer.toJson<String>(ssid),
      'authMode': serializer.toJson<int>(authMode),
      'count': serializer.toJson<int>(count),
      'isRaven': serializer.toJson<bool?>(isRaven),
      'ravenFirmware': serializer.toJson<String?>(ravenFirmware),
      'uavId': serializer.toJson<String?>(uavId),
      'operatorId': serializer.toJson<String?>(operatorId),
      'droneLat': serializer.toJson<double?>(droneLat),
      'droneLon': serializer.toJson<double?>(droneLon),
      'altitudeMsl': serializer.toJson<int?>(altitudeMsl),
      'heightAgl': serializer.toJson<int?>(heightAgl),
      'droneSpeed': serializer.toJson<int?>(droneSpeed),
      'droneHeading': serializer.toJson<int?>(droneHeading),
      'pilotLat': serializer.toJson<double?>(pilotLat),
      'pilotLon': serializer.toJson<double?>(pilotLon),
      'robotType': serializer.toJson<String?>(robotType),
      'exploited': serializer.toJson<bool?>(exploited),
      'robotSerial': serializer.toJson<String?>(robotSerial),
      'filterDescription': serializer.toJson<String?>(filterDescription),
      'isFullMac': serializer.toJson<bool?>(isFullMac),
    };
  }

  Detection copyWith({
    int? id,
    String? sessionId,
    String? nodeId,
    String? macAddress,
    String? deviceName,
    String? engine,
    String? detectionMethod,
    int? rssi,
    int? channel,
    int? deviceTimestampMs,
    int? appTimestamp,
    Value<double?> latitude = const Value.absent(),
    Value<double?> longitude = const Value.absent(),
    Value<double?> altitude = const Value.absent(),
    Value<double?> speed = const Value.absent(),
    Value<double?> heading = const Value.absent(),
    Value<double?> accuracy = const Value.absent(),
    Value<int?> satelliteCount = const Value.absent(),
    String? ssid,
    int? authMode,
    int? count,
    Value<bool?> isRaven = const Value.absent(),
    Value<String?> ravenFirmware = const Value.absent(),
    Value<String?> uavId = const Value.absent(),
    Value<String?> operatorId = const Value.absent(),
    Value<double?> droneLat = const Value.absent(),
    Value<double?> droneLon = const Value.absent(),
    Value<int?> altitudeMsl = const Value.absent(),
    Value<int?> heightAgl = const Value.absent(),
    Value<int?> droneSpeed = const Value.absent(),
    Value<int?> droneHeading = const Value.absent(),
    Value<double?> pilotLat = const Value.absent(),
    Value<double?> pilotLon = const Value.absent(),
    Value<String?> robotType = const Value.absent(),
    Value<bool?> exploited = const Value.absent(),
    Value<String?> robotSerial = const Value.absent(),
    Value<String?> filterDescription = const Value.absent(),
    Value<bool?> isFullMac = const Value.absent(),
  }) => Detection(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    nodeId: nodeId ?? this.nodeId,
    macAddress: macAddress ?? this.macAddress,
    deviceName: deviceName ?? this.deviceName,
    engine: engine ?? this.engine,
    detectionMethod: detectionMethod ?? this.detectionMethod,
    rssi: rssi ?? this.rssi,
    channel: channel ?? this.channel,
    deviceTimestampMs: deviceTimestampMs ?? this.deviceTimestampMs,
    appTimestamp: appTimestamp ?? this.appTimestamp,
    latitude: latitude.present ? latitude.value : this.latitude,
    longitude: longitude.present ? longitude.value : this.longitude,
    altitude: altitude.present ? altitude.value : this.altitude,
    speed: speed.present ? speed.value : this.speed,
    heading: heading.present ? heading.value : this.heading,
    accuracy: accuracy.present ? accuracy.value : this.accuracy,
    satelliteCount: satelliteCount.present
        ? satelliteCount.value
        : this.satelliteCount,
    ssid: ssid ?? this.ssid,
    authMode: authMode ?? this.authMode,
    count: count ?? this.count,
    isRaven: isRaven.present ? isRaven.value : this.isRaven,
    ravenFirmware: ravenFirmware.present
        ? ravenFirmware.value
        : this.ravenFirmware,
    uavId: uavId.present ? uavId.value : this.uavId,
    operatorId: operatorId.present ? operatorId.value : this.operatorId,
    droneLat: droneLat.present ? droneLat.value : this.droneLat,
    droneLon: droneLon.present ? droneLon.value : this.droneLon,
    altitudeMsl: altitudeMsl.present ? altitudeMsl.value : this.altitudeMsl,
    heightAgl: heightAgl.present ? heightAgl.value : this.heightAgl,
    droneSpeed: droneSpeed.present ? droneSpeed.value : this.droneSpeed,
    droneHeading: droneHeading.present ? droneHeading.value : this.droneHeading,
    pilotLat: pilotLat.present ? pilotLat.value : this.pilotLat,
    pilotLon: pilotLon.present ? pilotLon.value : this.pilotLon,
    robotType: robotType.present ? robotType.value : this.robotType,
    exploited: exploited.present ? exploited.value : this.exploited,
    robotSerial: robotSerial.present ? robotSerial.value : this.robotSerial,
    filterDescription: filterDescription.present
        ? filterDescription.value
        : this.filterDescription,
    isFullMac: isFullMac.present ? isFullMac.value : this.isFullMac,
  );
  Detection copyWithCompanion(DetectionsCompanion data) {
    return Detection(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      engine: data.engine.present ? data.engine.value : this.engine,
      detectionMethod: data.detectionMethod.present
          ? data.detectionMethod.value
          : this.detectionMethod,
      rssi: data.rssi.present ? data.rssi.value : this.rssi,
      channel: data.channel.present ? data.channel.value : this.channel,
      deviceTimestampMs: data.deviceTimestampMs.present
          ? data.deviceTimestampMs.value
          : this.deviceTimestampMs,
      appTimestamp: data.appTimestamp.present
          ? data.appTimestamp.value
          : this.appTimestamp,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      altitude: data.altitude.present ? data.altitude.value : this.altitude,
      speed: data.speed.present ? data.speed.value : this.speed,
      heading: data.heading.present ? data.heading.value : this.heading,
      accuracy: data.accuracy.present ? data.accuracy.value : this.accuracy,
      satelliteCount: data.satelliteCount.present
          ? data.satelliteCount.value
          : this.satelliteCount,
      ssid: data.ssid.present ? data.ssid.value : this.ssid,
      authMode: data.authMode.present ? data.authMode.value : this.authMode,
      count: data.count.present ? data.count.value : this.count,
      isRaven: data.isRaven.present ? data.isRaven.value : this.isRaven,
      ravenFirmware: data.ravenFirmware.present
          ? data.ravenFirmware.value
          : this.ravenFirmware,
      uavId: data.uavId.present ? data.uavId.value : this.uavId,
      operatorId: data.operatorId.present
          ? data.operatorId.value
          : this.operatorId,
      droneLat: data.droneLat.present ? data.droneLat.value : this.droneLat,
      droneLon: data.droneLon.present ? data.droneLon.value : this.droneLon,
      altitudeMsl: data.altitudeMsl.present
          ? data.altitudeMsl.value
          : this.altitudeMsl,
      heightAgl: data.heightAgl.present ? data.heightAgl.value : this.heightAgl,
      droneSpeed: data.droneSpeed.present
          ? data.droneSpeed.value
          : this.droneSpeed,
      droneHeading: data.droneHeading.present
          ? data.droneHeading.value
          : this.droneHeading,
      pilotLat: data.pilotLat.present ? data.pilotLat.value : this.pilotLat,
      pilotLon: data.pilotLon.present ? data.pilotLon.value : this.pilotLon,
      robotType: data.robotType.present ? data.robotType.value : this.robotType,
      exploited: data.exploited.present ? data.exploited.value : this.exploited,
      robotSerial: data.robotSerial.present
          ? data.robotSerial.value
          : this.robotSerial,
      filterDescription: data.filterDescription.present
          ? data.filterDescription.value
          : this.filterDescription,
      isFullMac: data.isFullMac.present ? data.isFullMac.value : this.isFullMac,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Detection(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('nodeId: $nodeId, ')
          ..write('macAddress: $macAddress, ')
          ..write('deviceName: $deviceName, ')
          ..write('engine: $engine, ')
          ..write('detectionMethod: $detectionMethod, ')
          ..write('rssi: $rssi, ')
          ..write('channel: $channel, ')
          ..write('deviceTimestampMs: $deviceTimestampMs, ')
          ..write('appTimestamp: $appTimestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('speed: $speed, ')
          ..write('heading: $heading, ')
          ..write('accuracy: $accuracy, ')
          ..write('satelliteCount: $satelliteCount, ')
          ..write('ssid: $ssid, ')
          ..write('authMode: $authMode, ')
          ..write('count: $count, ')
          ..write('isRaven: $isRaven, ')
          ..write('ravenFirmware: $ravenFirmware, ')
          ..write('uavId: $uavId, ')
          ..write('operatorId: $operatorId, ')
          ..write('droneLat: $droneLat, ')
          ..write('droneLon: $droneLon, ')
          ..write('altitudeMsl: $altitudeMsl, ')
          ..write('heightAgl: $heightAgl, ')
          ..write('droneSpeed: $droneSpeed, ')
          ..write('droneHeading: $droneHeading, ')
          ..write('pilotLat: $pilotLat, ')
          ..write('pilotLon: $pilotLon, ')
          ..write('robotType: $robotType, ')
          ..write('exploited: $exploited, ')
          ..write('robotSerial: $robotSerial, ')
          ..write('filterDescription: $filterDescription, ')
          ..write('isFullMac: $isFullMac')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    sessionId,
    nodeId,
    macAddress,
    deviceName,
    engine,
    detectionMethod,
    rssi,
    channel,
    deviceTimestampMs,
    appTimestamp,
    latitude,
    longitude,
    altitude,
    speed,
    heading,
    accuracy,
    satelliteCount,
    ssid,
    authMode,
    count,
    isRaven,
    ravenFirmware,
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
    robotType,
    exploited,
    robotSerial,
    filterDescription,
    isFullMac,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Detection &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.nodeId == this.nodeId &&
          other.macAddress == this.macAddress &&
          other.deviceName == this.deviceName &&
          other.engine == this.engine &&
          other.detectionMethod == this.detectionMethod &&
          other.rssi == this.rssi &&
          other.channel == this.channel &&
          other.deviceTimestampMs == this.deviceTimestampMs &&
          other.appTimestamp == this.appTimestamp &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.altitude == this.altitude &&
          other.speed == this.speed &&
          other.heading == this.heading &&
          other.accuracy == this.accuracy &&
          other.satelliteCount == this.satelliteCount &&
          other.ssid == this.ssid &&
          other.authMode == this.authMode &&
          other.count == this.count &&
          other.isRaven == this.isRaven &&
          other.ravenFirmware == this.ravenFirmware &&
          other.uavId == this.uavId &&
          other.operatorId == this.operatorId &&
          other.droneLat == this.droneLat &&
          other.droneLon == this.droneLon &&
          other.altitudeMsl == this.altitudeMsl &&
          other.heightAgl == this.heightAgl &&
          other.droneSpeed == this.droneSpeed &&
          other.droneHeading == this.droneHeading &&
          other.pilotLat == this.pilotLat &&
          other.pilotLon == this.pilotLon &&
          other.robotType == this.robotType &&
          other.exploited == this.exploited &&
          other.robotSerial == this.robotSerial &&
          other.filterDescription == this.filterDescription &&
          other.isFullMac == this.isFullMac);
}

class DetectionsCompanion extends UpdateCompanion<Detection> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<String> nodeId;
  final Value<String> macAddress;
  final Value<String> deviceName;
  final Value<String> engine;
  final Value<String> detectionMethod;
  final Value<int> rssi;
  final Value<int> channel;
  final Value<int> deviceTimestampMs;
  final Value<int> appTimestamp;
  final Value<double?> latitude;
  final Value<double?> longitude;
  final Value<double?> altitude;
  final Value<double?> speed;
  final Value<double?> heading;
  final Value<double?> accuracy;
  final Value<int?> satelliteCount;
  final Value<String> ssid;
  final Value<int> authMode;
  final Value<int> count;
  final Value<bool?> isRaven;
  final Value<String?> ravenFirmware;
  final Value<String?> uavId;
  final Value<String?> operatorId;
  final Value<double?> droneLat;
  final Value<double?> droneLon;
  final Value<int?> altitudeMsl;
  final Value<int?> heightAgl;
  final Value<int?> droneSpeed;
  final Value<int?> droneHeading;
  final Value<double?> pilotLat;
  final Value<double?> pilotLon;
  final Value<String?> robotType;
  final Value<bool?> exploited;
  final Value<String?> robotSerial;
  final Value<String?> filterDescription;
  final Value<bool?> isFullMac;
  const DetectionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.engine = const Value.absent(),
    this.detectionMethod = const Value.absent(),
    this.rssi = const Value.absent(),
    this.channel = const Value.absent(),
    this.deviceTimestampMs = const Value.absent(),
    this.appTimestamp = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.speed = const Value.absent(),
    this.heading = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.satelliteCount = const Value.absent(),
    this.ssid = const Value.absent(),
    this.authMode = const Value.absent(),
    this.count = const Value.absent(),
    this.isRaven = const Value.absent(),
    this.ravenFirmware = const Value.absent(),
    this.uavId = const Value.absent(),
    this.operatorId = const Value.absent(),
    this.droneLat = const Value.absent(),
    this.droneLon = const Value.absent(),
    this.altitudeMsl = const Value.absent(),
    this.heightAgl = const Value.absent(),
    this.droneSpeed = const Value.absent(),
    this.droneHeading = const Value.absent(),
    this.pilotLat = const Value.absent(),
    this.pilotLon = const Value.absent(),
    this.robotType = const Value.absent(),
    this.exploited = const Value.absent(),
    this.robotSerial = const Value.absent(),
    this.filterDescription = const Value.absent(),
    this.isFullMac = const Value.absent(),
  });
  DetectionsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required String nodeId,
    required String macAddress,
    this.deviceName = const Value.absent(),
    required String engine,
    required String detectionMethod,
    required int rssi,
    required int channel,
    required int deviceTimestampMs,
    required int appTimestamp,
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.altitude = const Value.absent(),
    this.speed = const Value.absent(),
    this.heading = const Value.absent(),
    this.accuracy = const Value.absent(),
    this.satelliteCount = const Value.absent(),
    this.ssid = const Value.absent(),
    this.authMode = const Value.absent(),
    this.count = const Value.absent(),
    this.isRaven = const Value.absent(),
    this.ravenFirmware = const Value.absent(),
    this.uavId = const Value.absent(),
    this.operatorId = const Value.absent(),
    this.droneLat = const Value.absent(),
    this.droneLon = const Value.absent(),
    this.altitudeMsl = const Value.absent(),
    this.heightAgl = const Value.absent(),
    this.droneSpeed = const Value.absent(),
    this.droneHeading = const Value.absent(),
    this.pilotLat = const Value.absent(),
    this.pilotLon = const Value.absent(),
    this.robotType = const Value.absent(),
    this.exploited = const Value.absent(),
    this.robotSerial = const Value.absent(),
    this.filterDescription = const Value.absent(),
    this.isFullMac = const Value.absent(),
  }) : sessionId = Value(sessionId),
       nodeId = Value(nodeId),
       macAddress = Value(macAddress),
       engine = Value(engine),
       detectionMethod = Value(detectionMethod),
       rssi = Value(rssi),
       channel = Value(channel),
       deviceTimestampMs = Value(deviceTimestampMs),
       appTimestamp = Value(appTimestamp);
  static Insertable<Detection> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<String>? nodeId,
    Expression<String>? macAddress,
    Expression<String>? deviceName,
    Expression<String>? engine,
    Expression<String>? detectionMethod,
    Expression<int>? rssi,
    Expression<int>? channel,
    Expression<int>? deviceTimestampMs,
    Expression<int>? appTimestamp,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<double>? altitude,
    Expression<double>? speed,
    Expression<double>? heading,
    Expression<double>? accuracy,
    Expression<int>? satelliteCount,
    Expression<String>? ssid,
    Expression<int>? authMode,
    Expression<int>? count,
    Expression<bool>? isRaven,
    Expression<String>? ravenFirmware,
    Expression<String>? uavId,
    Expression<String>? operatorId,
    Expression<double>? droneLat,
    Expression<double>? droneLon,
    Expression<int>? altitudeMsl,
    Expression<int>? heightAgl,
    Expression<int>? droneSpeed,
    Expression<int>? droneHeading,
    Expression<double>? pilotLat,
    Expression<double>? pilotLon,
    Expression<String>? robotType,
    Expression<bool>? exploited,
    Expression<String>? robotSerial,
    Expression<String>? filterDescription,
    Expression<bool>? isFullMac,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (nodeId != null) 'node_id': nodeId,
      if (macAddress != null) 'mac_address': macAddress,
      if (deviceName != null) 'device_name': deviceName,
      if (engine != null) 'engine': engine,
      if (detectionMethod != null) 'detection_method': detectionMethod,
      if (rssi != null) 'rssi': rssi,
      if (channel != null) 'channel': channel,
      if (deviceTimestampMs != null) 'device_timestamp_ms': deviceTimestampMs,
      if (appTimestamp != null) 'app_timestamp': appTimestamp,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (altitude != null) 'altitude': altitude,
      if (speed != null) 'speed': speed,
      if (heading != null) 'heading': heading,
      if (accuracy != null) 'accuracy': accuracy,
      if (satelliteCount != null) 'satellite_count': satelliteCount,
      if (ssid != null) 'ssid': ssid,
      if (authMode != null) 'auth_mode': authMode,
      if (count != null) 'count': count,
      if (isRaven != null) 'is_raven': isRaven,
      if (ravenFirmware != null) 'raven_firmware': ravenFirmware,
      if (uavId != null) 'uav_id': uavId,
      if (operatorId != null) 'operator_id': operatorId,
      if (droneLat != null) 'drone_lat': droneLat,
      if (droneLon != null) 'drone_lon': droneLon,
      if (altitudeMsl != null) 'altitude_msl': altitudeMsl,
      if (heightAgl != null) 'height_agl': heightAgl,
      if (droneSpeed != null) 'drone_speed': droneSpeed,
      if (droneHeading != null) 'drone_heading': droneHeading,
      if (pilotLat != null) 'pilot_lat': pilotLat,
      if (pilotLon != null) 'pilot_lon': pilotLon,
      if (robotType != null) 'robot_type': robotType,
      if (exploited != null) 'exploited': exploited,
      if (robotSerial != null) 'robot_serial': robotSerial,
      if (filterDescription != null) 'filter_description': filterDescription,
      if (isFullMac != null) 'is_full_mac': isFullMac,
    });
  }

  DetectionsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<String>? nodeId,
    Value<String>? macAddress,
    Value<String>? deviceName,
    Value<String>? engine,
    Value<String>? detectionMethod,
    Value<int>? rssi,
    Value<int>? channel,
    Value<int>? deviceTimestampMs,
    Value<int>? appTimestamp,
    Value<double?>? latitude,
    Value<double?>? longitude,
    Value<double?>? altitude,
    Value<double?>? speed,
    Value<double?>? heading,
    Value<double?>? accuracy,
    Value<int?>? satelliteCount,
    Value<String>? ssid,
    Value<int>? authMode,
    Value<int>? count,
    Value<bool?>? isRaven,
    Value<String?>? ravenFirmware,
    Value<String?>? uavId,
    Value<String?>? operatorId,
    Value<double?>? droneLat,
    Value<double?>? droneLon,
    Value<int?>? altitudeMsl,
    Value<int?>? heightAgl,
    Value<int?>? droneSpeed,
    Value<int?>? droneHeading,
    Value<double?>? pilotLat,
    Value<double?>? pilotLon,
    Value<String?>? robotType,
    Value<bool?>? exploited,
    Value<String?>? robotSerial,
    Value<String?>? filterDescription,
    Value<bool?>? isFullMac,
  }) {
    return DetectionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      nodeId: nodeId ?? this.nodeId,
      macAddress: macAddress ?? this.macAddress,
      deviceName: deviceName ?? this.deviceName,
      engine: engine ?? this.engine,
      detectionMethod: detectionMethod ?? this.detectionMethod,
      rssi: rssi ?? this.rssi,
      channel: channel ?? this.channel,
      deviceTimestampMs: deviceTimestampMs ?? this.deviceTimestampMs,
      appTimestamp: appTimestamp ?? this.appTimestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      altitude: altitude ?? this.altitude,
      speed: speed ?? this.speed,
      heading: heading ?? this.heading,
      accuracy: accuracy ?? this.accuracy,
      satelliteCount: satelliteCount ?? this.satelliteCount,
      ssid: ssid ?? this.ssid,
      authMode: authMode ?? this.authMode,
      count: count ?? this.count,
      isRaven: isRaven ?? this.isRaven,
      ravenFirmware: ravenFirmware ?? this.ravenFirmware,
      uavId: uavId ?? this.uavId,
      operatorId: operatorId ?? this.operatorId,
      droneLat: droneLat ?? this.droneLat,
      droneLon: droneLon ?? this.droneLon,
      altitudeMsl: altitudeMsl ?? this.altitudeMsl,
      heightAgl: heightAgl ?? this.heightAgl,
      droneSpeed: droneSpeed ?? this.droneSpeed,
      droneHeading: droneHeading ?? this.droneHeading,
      pilotLat: pilotLat ?? this.pilotLat,
      pilotLon: pilotLon ?? this.pilotLon,
      robotType: robotType ?? this.robotType,
      exploited: exploited ?? this.exploited,
      robotSerial: robotSerial ?? this.robotSerial,
      filterDescription: filterDescription ?? this.filterDescription,
      isFullMac: isFullMac ?? this.isFullMac,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(engine.value);
    }
    if (detectionMethod.present) {
      map['detection_method'] = Variable<String>(detectionMethod.value);
    }
    if (rssi.present) {
      map['rssi'] = Variable<int>(rssi.value);
    }
    if (channel.present) {
      map['channel'] = Variable<int>(channel.value);
    }
    if (deviceTimestampMs.present) {
      map['device_timestamp_ms'] = Variable<int>(deviceTimestampMs.value);
    }
    if (appTimestamp.present) {
      map['app_timestamp'] = Variable<int>(appTimestamp.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (altitude.present) {
      map['altitude'] = Variable<double>(altitude.value);
    }
    if (speed.present) {
      map['speed'] = Variable<double>(speed.value);
    }
    if (heading.present) {
      map['heading'] = Variable<double>(heading.value);
    }
    if (accuracy.present) {
      map['accuracy'] = Variable<double>(accuracy.value);
    }
    if (satelliteCount.present) {
      map['satellite_count'] = Variable<int>(satelliteCount.value);
    }
    if (ssid.present) {
      map['ssid'] = Variable<String>(ssid.value);
    }
    if (authMode.present) {
      map['auth_mode'] = Variable<int>(authMode.value);
    }
    if (count.present) {
      map['count'] = Variable<int>(count.value);
    }
    if (isRaven.present) {
      map['is_raven'] = Variable<bool>(isRaven.value);
    }
    if (ravenFirmware.present) {
      map['raven_firmware'] = Variable<String>(ravenFirmware.value);
    }
    if (uavId.present) {
      map['uav_id'] = Variable<String>(uavId.value);
    }
    if (operatorId.present) {
      map['operator_id'] = Variable<String>(operatorId.value);
    }
    if (droneLat.present) {
      map['drone_lat'] = Variable<double>(droneLat.value);
    }
    if (droneLon.present) {
      map['drone_lon'] = Variable<double>(droneLon.value);
    }
    if (altitudeMsl.present) {
      map['altitude_msl'] = Variable<int>(altitudeMsl.value);
    }
    if (heightAgl.present) {
      map['height_agl'] = Variable<int>(heightAgl.value);
    }
    if (droneSpeed.present) {
      map['drone_speed'] = Variable<int>(droneSpeed.value);
    }
    if (droneHeading.present) {
      map['drone_heading'] = Variable<int>(droneHeading.value);
    }
    if (pilotLat.present) {
      map['pilot_lat'] = Variable<double>(pilotLat.value);
    }
    if (pilotLon.present) {
      map['pilot_lon'] = Variable<double>(pilotLon.value);
    }
    if (robotType.present) {
      map['robot_type'] = Variable<String>(robotType.value);
    }
    if (exploited.present) {
      map['exploited'] = Variable<bool>(exploited.value);
    }
    if (robotSerial.present) {
      map['robot_serial'] = Variable<String>(robotSerial.value);
    }
    if (filterDescription.present) {
      map['filter_description'] = Variable<String>(filterDescription.value);
    }
    if (isFullMac.present) {
      map['is_full_mac'] = Variable<bool>(isFullMac.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DetectionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('nodeId: $nodeId, ')
          ..write('macAddress: $macAddress, ')
          ..write('deviceName: $deviceName, ')
          ..write('engine: $engine, ')
          ..write('detectionMethod: $detectionMethod, ')
          ..write('rssi: $rssi, ')
          ..write('channel: $channel, ')
          ..write('deviceTimestampMs: $deviceTimestampMs, ')
          ..write('appTimestamp: $appTimestamp, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('altitude: $altitude, ')
          ..write('speed: $speed, ')
          ..write('heading: $heading, ')
          ..write('accuracy: $accuracy, ')
          ..write('satelliteCount: $satelliteCount, ')
          ..write('ssid: $ssid, ')
          ..write('authMode: $authMode, ')
          ..write('count: $count, ')
          ..write('isRaven: $isRaven, ')
          ..write('ravenFirmware: $ravenFirmware, ')
          ..write('uavId: $uavId, ')
          ..write('operatorId: $operatorId, ')
          ..write('droneLat: $droneLat, ')
          ..write('droneLon: $droneLon, ')
          ..write('altitudeMsl: $altitudeMsl, ')
          ..write('heightAgl: $heightAgl, ')
          ..write('droneSpeed: $droneSpeed, ')
          ..write('droneHeading: $droneHeading, ')
          ..write('pilotLat: $pilotLat, ')
          ..write('pilotLon: $pilotLon, ')
          ..write('robotType: $robotType, ')
          ..write('exploited: $exploited, ')
          ..write('robotSerial: $robotSerial, ')
          ..write('filterDescription: $filterDescription, ')
          ..write('isFullMac: $isFullMac')
          ..write(')'))
        .toString();
  }
}

class $EngineConfigsTable extends EngineConfigs
    with TableInfo<$EngineConfigsTable, EngineConfig> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $EngineConfigsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nodeIdMeta = const VerificationMeta('nodeId');
  @override
  late final GeneratedColumn<String> nodeId = GeneratedColumn<String>(
    'node_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES nodes (id)',
    ),
  );
  static const VerificationMeta _engineMeta = const VerificationMeta('engine');
  @override
  late final GeneratedColumn<String> engine = GeneratedColumn<String>(
    'engine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    nodeId,
    engine,
    configJson,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'engine_configs';
  @override
  VerificationContext validateIntegrity(
    Insertable<EngineConfig> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('node_id')) {
      context.handle(
        _nodeIdMeta,
        nodeId.isAcceptableOrUnknown(data['node_id']!, _nodeIdMeta),
      );
    } else if (isInserting) {
      context.missing(_nodeIdMeta);
    }
    if (data.containsKey('engine')) {
      context.handle(
        _engineMeta,
        engine.isAcceptableOrUnknown(data['engine']!, _engineMeta),
      );
    } else if (isInserting) {
      context.missing(_engineMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {nodeId, engine},
  ];
  @override
  EngineConfig map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return EngineConfig(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      nodeId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}node_id'],
      )!,
      engine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $EngineConfigsTable createAlias(String alias) {
    return $EngineConfigsTable(attachedDatabase, alias);
  }
}

class EngineConfig extends DataClass implements Insertable<EngineConfig> {
  final int id;
  final String nodeId;
  final String engine;
  final String configJson;
  final int updatedAt;
  const EngineConfig({
    required this.id,
    required this.nodeId,
    required this.engine,
    required this.configJson,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['node_id'] = Variable<String>(nodeId);
    map['engine'] = Variable<String>(engine);
    map['config_json'] = Variable<String>(configJson);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  EngineConfigsCompanion toCompanion(bool nullToAbsent) {
    return EngineConfigsCompanion(
      id: Value(id),
      nodeId: Value(nodeId),
      engine: Value(engine),
      configJson: Value(configJson),
      updatedAt: Value(updatedAt),
    );
  }

  factory EngineConfig.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return EngineConfig(
      id: serializer.fromJson<int>(json['id']),
      nodeId: serializer.fromJson<String>(json['nodeId']),
      engine: serializer.fromJson<String>(json['engine']),
      configJson: serializer.fromJson<String>(json['configJson']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'nodeId': serializer.toJson<String>(nodeId),
      'engine': serializer.toJson<String>(engine),
      'configJson': serializer.toJson<String>(configJson),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  EngineConfig copyWith({
    int? id,
    String? nodeId,
    String? engine,
    String? configJson,
    int? updatedAt,
  }) => EngineConfig(
    id: id ?? this.id,
    nodeId: nodeId ?? this.nodeId,
    engine: engine ?? this.engine,
    configJson: configJson ?? this.configJson,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  EngineConfig copyWithCompanion(EngineConfigsCompanion data) {
    return EngineConfig(
      id: data.id.present ? data.id.value : this.id,
      nodeId: data.nodeId.present ? data.nodeId.value : this.nodeId,
      engine: data.engine.present ? data.engine.value : this.engine,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('EngineConfig(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('engine: $engine, ')
          ..write('configJson: $configJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, nodeId, engine, configJson, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is EngineConfig &&
          other.id == this.id &&
          other.nodeId == this.nodeId &&
          other.engine == this.engine &&
          other.configJson == this.configJson &&
          other.updatedAt == this.updatedAt);
}

class EngineConfigsCompanion extends UpdateCompanion<EngineConfig> {
  final Value<int> id;
  final Value<String> nodeId;
  final Value<String> engine;
  final Value<String> configJson;
  final Value<int> updatedAt;
  const EngineConfigsCompanion({
    this.id = const Value.absent(),
    this.nodeId = const Value.absent(),
    this.engine = const Value.absent(),
    this.configJson = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  EngineConfigsCompanion.insert({
    this.id = const Value.absent(),
    required String nodeId,
    required String engine,
    required String configJson,
    required int updatedAt,
  }) : nodeId = Value(nodeId),
       engine = Value(engine),
       configJson = Value(configJson),
       updatedAt = Value(updatedAt);
  static Insertable<EngineConfig> custom({
    Expression<int>? id,
    Expression<String>? nodeId,
    Expression<String>? engine,
    Expression<String>? configJson,
    Expression<int>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (nodeId != null) 'node_id': nodeId,
      if (engine != null) 'engine': engine,
      if (configJson != null) 'config_json': configJson,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  EngineConfigsCompanion copyWith({
    Value<int>? id,
    Value<String>? nodeId,
    Value<String>? engine,
    Value<String>? configJson,
    Value<int>? updatedAt,
  }) {
    return EngineConfigsCompanion(
      id: id ?? this.id,
      nodeId: nodeId ?? this.nodeId,
      engine: engine ?? this.engine,
      configJson: configJson ?? this.configJson,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (nodeId.present) {
      map['node_id'] = Variable<String>(nodeId.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(engine.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('EngineConfigsCompanion(')
          ..write('id: $id, ')
          ..write('nodeId: $nodeId, ')
          ..write('engine: $engine, ')
          ..write('configJson: $configJson, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

class $BaselinesTable extends Baselines
    with TableInfo<$BaselinesTable, Baseline> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BaselinesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationNameMeta = const VerificationMeta(
    'locationName',
  );
  @override
  late final GeneratedColumn<String> locationName = GeneratedColumn<String>(
    'location_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _centerLatMeta = const VerificationMeta(
    'centerLat',
  );
  @override
  late final GeneratedColumn<double> centerLat = GeneratedColumn<double>(
    'center_lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _centerLonMeta = const VerificationMeta(
    'centerLon',
  );
  @override
  late final GeneratedColumn<double> centerLon = GeneratedColumn<double>(
    'center_lon',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _radiusMMeta = const VerificationMeta(
    'radiusM',
  );
  @override
  late final GeneratedColumn<double> radiusM = GeneratedColumn<double>(
    'radius_m',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _polygonJsonMeta = const VerificationMeta(
    'polygonJson',
  );
  @override
  late final GeneratedColumn<String> polygonJson = GeneratedColumn<String>(
    'polygon_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _detectionCountMeta = const VerificationMeta(
    'detectionCount',
  );
  @override
  late final GeneratedColumn<int> detectionCount = GeneratedColumn<int>(
    'detection_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    locationName,
    centerLat,
    centerLon,
    radiusM,
    polygonJson,
    createdAt,
    detectionCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'baselines';
  @override
  VerificationContext validateIntegrity(
    Insertable<Baseline> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('location_name')) {
      context.handle(
        _locationNameMeta,
        locationName.isAcceptableOrUnknown(
          data['location_name']!,
          _locationNameMeta,
        ),
      );
    }
    if (data.containsKey('center_lat')) {
      context.handle(
        _centerLatMeta,
        centerLat.isAcceptableOrUnknown(data['center_lat']!, _centerLatMeta),
      );
    } else if (isInserting) {
      context.missing(_centerLatMeta);
    }
    if (data.containsKey('center_lon')) {
      context.handle(
        _centerLonMeta,
        centerLon.isAcceptableOrUnknown(data['center_lon']!, _centerLonMeta),
      );
    } else if (isInserting) {
      context.missing(_centerLonMeta);
    }
    if (data.containsKey('radius_m')) {
      context.handle(
        _radiusMMeta,
        radiusM.isAcceptableOrUnknown(data['radius_m']!, _radiusMMeta),
      );
    } else if (isInserting) {
      context.missing(_radiusMMeta);
    }
    if (data.containsKey('polygon_json')) {
      context.handle(
        _polygonJsonMeta,
        polygonJson.isAcceptableOrUnknown(
          data['polygon_json']!,
          _polygonJsonMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('detection_count')) {
      context.handle(
        _detectionCountMeta,
        detectionCount.isAcceptableOrUnknown(
          data['detection_count']!,
          _detectionCountMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Baseline map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Baseline(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      locationName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}location_name'],
      ),
      centerLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lat'],
      )!,
      centerLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lon'],
      )!,
      radiusM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}radius_m'],
      )!,
      polygonJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}polygon_json'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      detectionCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}detection_count'],
      )!,
    );
  }

  @override
  $BaselinesTable createAlias(String alias) {
    return $BaselinesTable(attachedDatabase, alias);
  }
}

class Baseline extends DataClass implements Insertable<Baseline> {
  final String id;
  final String name;
  final String? locationName;
  final double centerLat;
  final double centerLon;
  final double radiusM;
  final String? polygonJson;
  final int createdAt;
  final int detectionCount;
  const Baseline({
    required this.id,
    required this.name,
    this.locationName,
    required this.centerLat,
    required this.centerLon,
    required this.radiusM,
    this.polygonJson,
    required this.createdAt,
    required this.detectionCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || locationName != null) {
      map['location_name'] = Variable<String>(locationName);
    }
    map['center_lat'] = Variable<double>(centerLat);
    map['center_lon'] = Variable<double>(centerLon);
    map['radius_m'] = Variable<double>(radiusM);
    if (!nullToAbsent || polygonJson != null) {
      map['polygon_json'] = Variable<String>(polygonJson);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['detection_count'] = Variable<int>(detectionCount);
    return map;
  }

  BaselinesCompanion toCompanion(bool nullToAbsent) {
    return BaselinesCompanion(
      id: Value(id),
      name: Value(name),
      locationName: locationName == null && nullToAbsent
          ? const Value.absent()
          : Value(locationName),
      centerLat: Value(centerLat),
      centerLon: Value(centerLon),
      radiusM: Value(radiusM),
      polygonJson: polygonJson == null && nullToAbsent
          ? const Value.absent()
          : Value(polygonJson),
      createdAt: Value(createdAt),
      detectionCount: Value(detectionCount),
    );
  }

  factory Baseline.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Baseline(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      locationName: serializer.fromJson<String?>(json['locationName']),
      centerLat: serializer.fromJson<double>(json['centerLat']),
      centerLon: serializer.fromJson<double>(json['centerLon']),
      radiusM: serializer.fromJson<double>(json['radiusM']),
      polygonJson: serializer.fromJson<String?>(json['polygonJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      detectionCount: serializer.fromJson<int>(json['detectionCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'locationName': serializer.toJson<String?>(locationName),
      'centerLat': serializer.toJson<double>(centerLat),
      'centerLon': serializer.toJson<double>(centerLon),
      'radiusM': serializer.toJson<double>(radiusM),
      'polygonJson': serializer.toJson<String?>(polygonJson),
      'createdAt': serializer.toJson<int>(createdAt),
      'detectionCount': serializer.toJson<int>(detectionCount),
    };
  }

  Baseline copyWith({
    String? id,
    String? name,
    Value<String?> locationName = const Value.absent(),
    double? centerLat,
    double? centerLon,
    double? radiusM,
    Value<String?> polygonJson = const Value.absent(),
    int? createdAt,
    int? detectionCount,
  }) => Baseline(
    id: id ?? this.id,
    name: name ?? this.name,
    locationName: locationName.present ? locationName.value : this.locationName,
    centerLat: centerLat ?? this.centerLat,
    centerLon: centerLon ?? this.centerLon,
    radiusM: radiusM ?? this.radiusM,
    polygonJson: polygonJson.present ? polygonJson.value : this.polygonJson,
    createdAt: createdAt ?? this.createdAt,
    detectionCount: detectionCount ?? this.detectionCount,
  );
  Baseline copyWithCompanion(BaselinesCompanion data) {
    return Baseline(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      locationName: data.locationName.present
          ? data.locationName.value
          : this.locationName,
      centerLat: data.centerLat.present ? data.centerLat.value : this.centerLat,
      centerLon: data.centerLon.present ? data.centerLon.value : this.centerLon,
      radiusM: data.radiusM.present ? data.radiusM.value : this.radiusM,
      polygonJson: data.polygonJson.present
          ? data.polygonJson.value
          : this.polygonJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      detectionCount: data.detectionCount.present
          ? data.detectionCount.value
          : this.detectionCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Baseline(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('locationName: $locationName, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('radiusM: $radiusM, ')
          ..write('polygonJson: $polygonJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('detectionCount: $detectionCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    locationName,
    centerLat,
    centerLon,
    radiusM,
    polygonJson,
    createdAt,
    detectionCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Baseline &&
          other.id == this.id &&
          other.name == this.name &&
          other.locationName == this.locationName &&
          other.centerLat == this.centerLat &&
          other.centerLon == this.centerLon &&
          other.radiusM == this.radiusM &&
          other.polygonJson == this.polygonJson &&
          other.createdAt == this.createdAt &&
          other.detectionCount == this.detectionCount);
}

class BaselinesCompanion extends UpdateCompanion<Baseline> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> locationName;
  final Value<double> centerLat;
  final Value<double> centerLon;
  final Value<double> radiusM;
  final Value<String?> polygonJson;
  final Value<int> createdAt;
  final Value<int> detectionCount;
  final Value<int> rowid;
  const BaselinesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.locationName = const Value.absent(),
    this.centerLat = const Value.absent(),
    this.centerLon = const Value.absent(),
    this.radiusM = const Value.absent(),
    this.polygonJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.detectionCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BaselinesCompanion.insert({
    required String id,
    required String name,
    this.locationName = const Value.absent(),
    required double centerLat,
    required double centerLon,
    required double radiusM,
    this.polygonJson = const Value.absent(),
    required int createdAt,
    this.detectionCount = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       centerLat = Value(centerLat),
       centerLon = Value(centerLon),
       radiusM = Value(radiusM),
       createdAt = Value(createdAt);
  static Insertable<Baseline> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? locationName,
    Expression<double>? centerLat,
    Expression<double>? centerLon,
    Expression<double>? radiusM,
    Expression<String>? polygonJson,
    Expression<int>? createdAt,
    Expression<int>? detectionCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (locationName != null) 'location_name': locationName,
      if (centerLat != null) 'center_lat': centerLat,
      if (centerLon != null) 'center_lon': centerLon,
      if (radiusM != null) 'radius_m': radiusM,
      if (polygonJson != null) 'polygon_json': polygonJson,
      if (createdAt != null) 'created_at': createdAt,
      if (detectionCount != null) 'detection_count': detectionCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BaselinesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String?>? locationName,
    Value<double>? centerLat,
    Value<double>? centerLon,
    Value<double>? radiusM,
    Value<String?>? polygonJson,
    Value<int>? createdAt,
    Value<int>? detectionCount,
    Value<int>? rowid,
  }) {
    return BaselinesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      locationName: locationName ?? this.locationName,
      centerLat: centerLat ?? this.centerLat,
      centerLon: centerLon ?? this.centerLon,
      radiusM: radiusM ?? this.radiusM,
      polygonJson: polygonJson ?? this.polygonJson,
      createdAt: createdAt ?? this.createdAt,
      detectionCount: detectionCount ?? this.detectionCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (locationName.present) {
      map['location_name'] = Variable<String>(locationName.value);
    }
    if (centerLat.present) {
      map['center_lat'] = Variable<double>(centerLat.value);
    }
    if (centerLon.present) {
      map['center_lon'] = Variable<double>(centerLon.value);
    }
    if (radiusM.present) {
      map['radius_m'] = Variable<double>(radiusM.value);
    }
    if (polygonJson.present) {
      map['polygon_json'] = Variable<String>(polygonJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (detectionCount.present) {
      map['detection_count'] = Variable<int>(detectionCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BaselinesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('locationName: $locationName, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('radiusM: $radiusM, ')
          ..write('polygonJson: $polygonJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('detectionCount: $detectionCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BaselineDevicesTable extends BaselineDevices
    with TableInfo<$BaselineDevicesTable, BaselineDevice> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BaselineDevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _baselineIdMeta = const VerificationMeta(
    'baselineId',
  );
  @override
  late final GeneratedColumn<String> baselineId = GeneratedColumn<String>(
    'baseline_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES baselines (id)',
    ),
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceNameMeta = const VerificationMeta(
    'deviceName',
  );
  @override
  late final GeneratedColumn<String> deviceName = GeneratedColumn<String>(
    'device_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _engineMeta = const VerificationMeta('engine');
  @override
  late final GeneratedColumn<String> engine = GeneratedColumn<String>(
    'engine',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _rssiAvgMeta = const VerificationMeta(
    'rssiAvg',
  );
  @override
  late final GeneratedColumn<int> rssiAvg = GeneratedColumn<int>(
    'rssi_avg',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<int> firstSeen = GeneratedColumn<int>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fingerprintIdMeta = const VerificationMeta(
    'fingerprintId',
  );
  @override
  late final GeneratedColumn<String> fingerprintId = GeneratedColumn<String>(
    'fingerprint_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    baselineId,
    macAddress,
    deviceName,
    engine,
    rssiAvg,
    firstSeen,
    fingerprintId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'baseline_devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<BaselineDevice> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('baseline_id')) {
      context.handle(
        _baselineIdMeta,
        baselineId.isAcceptableOrUnknown(data['baseline_id']!, _baselineIdMeta),
      );
    } else if (isInserting) {
      context.missing(_baselineIdMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('device_name')) {
      context.handle(
        _deviceNameMeta,
        deviceName.isAcceptableOrUnknown(data['device_name']!, _deviceNameMeta),
      );
    }
    if (data.containsKey('engine')) {
      context.handle(
        _engineMeta,
        engine.isAcceptableOrUnknown(data['engine']!, _engineMeta),
      );
    } else if (isInserting) {
      context.missing(_engineMeta);
    }
    if (data.containsKey('rssi_avg')) {
      context.handle(
        _rssiAvgMeta,
        rssiAvg.isAcceptableOrUnknown(data['rssi_avg']!, _rssiAvgMeta),
      );
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('fingerprint_id')) {
      context.handle(
        _fingerprintIdMeta,
        fingerprintId.isAcceptableOrUnknown(
          data['fingerprint_id']!,
          _fingerprintIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {baselineId, macAddress},
  ];
  @override
  BaselineDevice map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BaselineDevice(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      baselineId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}baseline_id'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      deviceName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_name'],
      )!,
      engine: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}engine'],
      )!,
      rssiAvg: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rssi_avg'],
      ),
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen'],
      )!,
      fingerprintId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint_id'],
      ),
    );
  }

  @override
  $BaselineDevicesTable createAlias(String alias) {
    return $BaselineDevicesTable(attachedDatabase, alias);
  }
}

class BaselineDevice extends DataClass implements Insertable<BaselineDevice> {
  final int id;
  final String baselineId;
  final String macAddress;
  final String deviceName;
  final String engine;
  final int? rssiAvg;
  final int firstSeen;
  final String? fingerprintId;
  const BaselineDevice({
    required this.id,
    required this.baselineId,
    required this.macAddress,
    required this.deviceName,
    required this.engine,
    this.rssiAvg,
    required this.firstSeen,
    this.fingerprintId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['baseline_id'] = Variable<String>(baselineId);
    map['mac_address'] = Variable<String>(macAddress);
    map['device_name'] = Variable<String>(deviceName);
    map['engine'] = Variable<String>(engine);
    if (!nullToAbsent || rssiAvg != null) {
      map['rssi_avg'] = Variable<int>(rssiAvg);
    }
    map['first_seen'] = Variable<int>(firstSeen);
    if (!nullToAbsent || fingerprintId != null) {
      map['fingerprint_id'] = Variable<String>(fingerprintId);
    }
    return map;
  }

  BaselineDevicesCompanion toCompanion(bool nullToAbsent) {
    return BaselineDevicesCompanion(
      id: Value(id),
      baselineId: Value(baselineId),
      macAddress: Value(macAddress),
      deviceName: Value(deviceName),
      engine: Value(engine),
      rssiAvg: rssiAvg == null && nullToAbsent
          ? const Value.absent()
          : Value(rssiAvg),
      firstSeen: Value(firstSeen),
      fingerprintId: fingerprintId == null && nullToAbsent
          ? const Value.absent()
          : Value(fingerprintId),
    );
  }

  factory BaselineDevice.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BaselineDevice(
      id: serializer.fromJson<int>(json['id']),
      baselineId: serializer.fromJson<String>(json['baselineId']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      deviceName: serializer.fromJson<String>(json['deviceName']),
      engine: serializer.fromJson<String>(json['engine']),
      rssiAvg: serializer.fromJson<int?>(json['rssiAvg']),
      firstSeen: serializer.fromJson<int>(json['firstSeen']),
      fingerprintId: serializer.fromJson<String?>(json['fingerprintId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'baselineId': serializer.toJson<String>(baselineId),
      'macAddress': serializer.toJson<String>(macAddress),
      'deviceName': serializer.toJson<String>(deviceName),
      'engine': serializer.toJson<String>(engine),
      'rssiAvg': serializer.toJson<int?>(rssiAvg),
      'firstSeen': serializer.toJson<int>(firstSeen),
      'fingerprintId': serializer.toJson<String?>(fingerprintId),
    };
  }

  BaselineDevice copyWith({
    int? id,
    String? baselineId,
    String? macAddress,
    String? deviceName,
    String? engine,
    Value<int?> rssiAvg = const Value.absent(),
    int? firstSeen,
    Value<String?> fingerprintId = const Value.absent(),
  }) => BaselineDevice(
    id: id ?? this.id,
    baselineId: baselineId ?? this.baselineId,
    macAddress: macAddress ?? this.macAddress,
    deviceName: deviceName ?? this.deviceName,
    engine: engine ?? this.engine,
    rssiAvg: rssiAvg.present ? rssiAvg.value : this.rssiAvg,
    firstSeen: firstSeen ?? this.firstSeen,
    fingerprintId: fingerprintId.present
        ? fingerprintId.value
        : this.fingerprintId,
  );
  BaselineDevice copyWithCompanion(BaselineDevicesCompanion data) {
    return BaselineDevice(
      id: data.id.present ? data.id.value : this.id,
      baselineId: data.baselineId.present
          ? data.baselineId.value
          : this.baselineId,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      deviceName: data.deviceName.present
          ? data.deviceName.value
          : this.deviceName,
      engine: data.engine.present ? data.engine.value : this.engine,
      rssiAvg: data.rssiAvg.present ? data.rssiAvg.value : this.rssiAvg,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      fingerprintId: data.fingerprintId.present
          ? data.fingerprintId.value
          : this.fingerprintId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BaselineDevice(')
          ..write('id: $id, ')
          ..write('baselineId: $baselineId, ')
          ..write('macAddress: $macAddress, ')
          ..write('deviceName: $deviceName, ')
          ..write('engine: $engine, ')
          ..write('rssiAvg: $rssiAvg, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('fingerprintId: $fingerprintId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    baselineId,
    macAddress,
    deviceName,
    engine,
    rssiAvg,
    firstSeen,
    fingerprintId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BaselineDevice &&
          other.id == this.id &&
          other.baselineId == this.baselineId &&
          other.macAddress == this.macAddress &&
          other.deviceName == this.deviceName &&
          other.engine == this.engine &&
          other.rssiAvg == this.rssiAvg &&
          other.firstSeen == this.firstSeen &&
          other.fingerprintId == this.fingerprintId);
}

class BaselineDevicesCompanion extends UpdateCompanion<BaselineDevice> {
  final Value<int> id;
  final Value<String> baselineId;
  final Value<String> macAddress;
  final Value<String> deviceName;
  final Value<String> engine;
  final Value<int?> rssiAvg;
  final Value<int> firstSeen;
  final Value<String?> fingerprintId;
  const BaselineDevicesCompanion({
    this.id = const Value.absent(),
    this.baselineId = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.deviceName = const Value.absent(),
    this.engine = const Value.absent(),
    this.rssiAvg = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.fingerprintId = const Value.absent(),
  });
  BaselineDevicesCompanion.insert({
    this.id = const Value.absent(),
    required String baselineId,
    required String macAddress,
    this.deviceName = const Value.absent(),
    required String engine,
    this.rssiAvg = const Value.absent(),
    required int firstSeen,
    this.fingerprintId = const Value.absent(),
  }) : baselineId = Value(baselineId),
       macAddress = Value(macAddress),
       engine = Value(engine),
       firstSeen = Value(firstSeen);
  static Insertable<BaselineDevice> custom({
    Expression<int>? id,
    Expression<String>? baselineId,
    Expression<String>? macAddress,
    Expression<String>? deviceName,
    Expression<String>? engine,
    Expression<int>? rssiAvg,
    Expression<int>? firstSeen,
    Expression<String>? fingerprintId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (baselineId != null) 'baseline_id': baselineId,
      if (macAddress != null) 'mac_address': macAddress,
      if (deviceName != null) 'device_name': deviceName,
      if (engine != null) 'engine': engine,
      if (rssiAvg != null) 'rssi_avg': rssiAvg,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (fingerprintId != null) 'fingerprint_id': fingerprintId,
    });
  }

  BaselineDevicesCompanion copyWith({
    Value<int>? id,
    Value<String>? baselineId,
    Value<String>? macAddress,
    Value<String>? deviceName,
    Value<String>? engine,
    Value<int?>? rssiAvg,
    Value<int>? firstSeen,
    Value<String?>? fingerprintId,
  }) {
    return BaselineDevicesCompanion(
      id: id ?? this.id,
      baselineId: baselineId ?? this.baselineId,
      macAddress: macAddress ?? this.macAddress,
      deviceName: deviceName ?? this.deviceName,
      engine: engine ?? this.engine,
      rssiAvg: rssiAvg ?? this.rssiAvg,
      firstSeen: firstSeen ?? this.firstSeen,
      fingerprintId: fingerprintId ?? this.fingerprintId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (baselineId.present) {
      map['baseline_id'] = Variable<String>(baselineId.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (deviceName.present) {
      map['device_name'] = Variable<String>(deviceName.value);
    }
    if (engine.present) {
      map['engine'] = Variable<String>(engine.value);
    }
    if (rssiAvg.present) {
      map['rssi_avg'] = Variable<int>(rssiAvg.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<int>(firstSeen.value);
    }
    if (fingerprintId.present) {
      map['fingerprint_id'] = Variable<String>(fingerprintId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BaselineDevicesCompanion(')
          ..write('id: $id, ')
          ..write('baselineId: $baselineId, ')
          ..write('macAddress: $macAddress, ')
          ..write('deviceName: $deviceName, ')
          ..write('engine: $engine, ')
          ..write('rssiAvg: $rssiAvg, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('fingerprintId: $fingerprintId')
          ..write(')'))
        .toString();
  }
}

class $FingerprintsTable extends Fingerprints
    with TableInfo<$FingerprintsTable, Fingerprint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FingerprintsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _primaryMacMeta = const VerificationMeta(
    'primaryMac',
  );
  @override
  late final GeneratedColumn<String> primaryMac = GeneratedColumn<String>(
    'primary_mac',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _advIntervalMsMeta = const VerificationMeta(
    'advIntervalMs',
  );
  @override
  late final GeneratedColumn<double> advIntervalMs = GeneratedColumn<double>(
    'adv_interval_ms',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _txPowerMeta = const VerificationMeta(
    'txPower',
  );
  @override
  late final GeneratedColumn<int> txPower = GeneratedColumn<int>(
    'tx_power',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _serviceUuidsMeta = const VerificationMeta(
    'serviceUuids',
  );
  @override
  late final GeneratedColumn<String> serviceUuids = GeneratedColumn<String>(
    'service_uuids',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mfgDataStructureMeta = const VerificationMeta(
    'mfgDataStructure',
  );
  @override
  late final GeneratedColumn<String> mfgDataStructure = GeneratedColumn<String>(
    'mfg_data_structure',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rssiEnvelopeMeta = const VerificationMeta(
    'rssiEnvelope',
  );
  @override
  late final GeneratedColumn<String> rssiEnvelope = GeneratedColumn<String>(
    'rssi_envelope',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _probeIntervalMsMeta = const VerificationMeta(
    'probeIntervalMs',
  );
  @override
  late final GeneratedColumn<double> probeIntervalMs = GeneratedColumn<double>(
    'probe_interval_ms',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ieOrderMeta = const VerificationMeta(
    'ieOrder',
  );
  @override
  late final GeneratedColumn<String> ieOrder = GeneratedColumn<String>(
    'ie_order',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    primaryMac,
    advIntervalMs,
    txPower,
    serviceUuids,
    mfgDataStructure,
    rssiEnvelope,
    probeIntervalMs,
    ieOrder,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fingerprints';
  @override
  VerificationContext validateIntegrity(
    Insertable<Fingerprint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('primary_mac')) {
      context.handle(
        _primaryMacMeta,
        primaryMac.isAcceptableOrUnknown(data['primary_mac']!, _primaryMacMeta),
      );
    } else if (isInserting) {
      context.missing(_primaryMacMeta);
    }
    if (data.containsKey('adv_interval_ms')) {
      context.handle(
        _advIntervalMsMeta,
        advIntervalMs.isAcceptableOrUnknown(
          data['adv_interval_ms']!,
          _advIntervalMsMeta,
        ),
      );
    }
    if (data.containsKey('tx_power')) {
      context.handle(
        _txPowerMeta,
        txPower.isAcceptableOrUnknown(data['tx_power']!, _txPowerMeta),
      );
    }
    if (data.containsKey('service_uuids')) {
      context.handle(
        _serviceUuidsMeta,
        serviceUuids.isAcceptableOrUnknown(
          data['service_uuids']!,
          _serviceUuidsMeta,
        ),
      );
    }
    if (data.containsKey('mfg_data_structure')) {
      context.handle(
        _mfgDataStructureMeta,
        mfgDataStructure.isAcceptableOrUnknown(
          data['mfg_data_structure']!,
          _mfgDataStructureMeta,
        ),
      );
    }
    if (data.containsKey('rssi_envelope')) {
      context.handle(
        _rssiEnvelopeMeta,
        rssiEnvelope.isAcceptableOrUnknown(
          data['rssi_envelope']!,
          _rssiEnvelopeMeta,
        ),
      );
    }
    if (data.containsKey('probe_interval_ms')) {
      context.handle(
        _probeIntervalMsMeta,
        probeIntervalMs.isAcceptableOrUnknown(
          data['probe_interval_ms']!,
          _probeIntervalMsMeta,
        ),
      );
    }
    if (data.containsKey('ie_order')) {
      context.handle(
        _ieOrderMeta,
        ieOrder.isAcceptableOrUnknown(data['ie_order']!, _ieOrderMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Fingerprint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Fingerprint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      primaryMac: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}primary_mac'],
      )!,
      advIntervalMs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}adv_interval_ms'],
      ),
      txPower: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tx_power'],
      ),
      serviceUuids: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}service_uuids'],
      ),
      mfgDataStructure: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mfg_data_structure'],
      ),
      rssiEnvelope: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rssi_envelope'],
      ),
      probeIntervalMs: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}probe_interval_ms'],
      ),
      ieOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ie_order'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $FingerprintsTable createAlias(String alias) {
    return $FingerprintsTable(attachedDatabase, alias);
  }
}

class Fingerprint extends DataClass implements Insertable<Fingerprint> {
  final String id;
  final String primaryMac;
  final double? advIntervalMs;
  final int? txPower;
  final String? serviceUuids;
  final String? mfgDataStructure;
  final String? rssiEnvelope;
  final double? probeIntervalMs;
  final String? ieOrder;
  final int createdAt;
  final int updatedAt;
  const Fingerprint({
    required this.id,
    required this.primaryMac,
    this.advIntervalMs,
    this.txPower,
    this.serviceUuids,
    this.mfgDataStructure,
    this.rssiEnvelope,
    this.probeIntervalMs,
    this.ieOrder,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['primary_mac'] = Variable<String>(primaryMac);
    if (!nullToAbsent || advIntervalMs != null) {
      map['adv_interval_ms'] = Variable<double>(advIntervalMs);
    }
    if (!nullToAbsent || txPower != null) {
      map['tx_power'] = Variable<int>(txPower);
    }
    if (!nullToAbsent || serviceUuids != null) {
      map['service_uuids'] = Variable<String>(serviceUuids);
    }
    if (!nullToAbsent || mfgDataStructure != null) {
      map['mfg_data_structure'] = Variable<String>(mfgDataStructure);
    }
    if (!nullToAbsent || rssiEnvelope != null) {
      map['rssi_envelope'] = Variable<String>(rssiEnvelope);
    }
    if (!nullToAbsent || probeIntervalMs != null) {
      map['probe_interval_ms'] = Variable<double>(probeIntervalMs);
    }
    if (!nullToAbsent || ieOrder != null) {
      map['ie_order'] = Variable<String>(ieOrder);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  FingerprintsCompanion toCompanion(bool nullToAbsent) {
    return FingerprintsCompanion(
      id: Value(id),
      primaryMac: Value(primaryMac),
      advIntervalMs: advIntervalMs == null && nullToAbsent
          ? const Value.absent()
          : Value(advIntervalMs),
      txPower: txPower == null && nullToAbsent
          ? const Value.absent()
          : Value(txPower),
      serviceUuids: serviceUuids == null && nullToAbsent
          ? const Value.absent()
          : Value(serviceUuids),
      mfgDataStructure: mfgDataStructure == null && nullToAbsent
          ? const Value.absent()
          : Value(mfgDataStructure),
      rssiEnvelope: rssiEnvelope == null && nullToAbsent
          ? const Value.absent()
          : Value(rssiEnvelope),
      probeIntervalMs: probeIntervalMs == null && nullToAbsent
          ? const Value.absent()
          : Value(probeIntervalMs),
      ieOrder: ieOrder == null && nullToAbsent
          ? const Value.absent()
          : Value(ieOrder),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory Fingerprint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Fingerprint(
      id: serializer.fromJson<String>(json['id']),
      primaryMac: serializer.fromJson<String>(json['primaryMac']),
      advIntervalMs: serializer.fromJson<double?>(json['advIntervalMs']),
      txPower: serializer.fromJson<int?>(json['txPower']),
      serviceUuids: serializer.fromJson<String?>(json['serviceUuids']),
      mfgDataStructure: serializer.fromJson<String?>(json['mfgDataStructure']),
      rssiEnvelope: serializer.fromJson<String?>(json['rssiEnvelope']),
      probeIntervalMs: serializer.fromJson<double?>(json['probeIntervalMs']),
      ieOrder: serializer.fromJson<String?>(json['ieOrder']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'primaryMac': serializer.toJson<String>(primaryMac),
      'advIntervalMs': serializer.toJson<double?>(advIntervalMs),
      'txPower': serializer.toJson<int?>(txPower),
      'serviceUuids': serializer.toJson<String?>(serviceUuids),
      'mfgDataStructure': serializer.toJson<String?>(mfgDataStructure),
      'rssiEnvelope': serializer.toJson<String?>(rssiEnvelope),
      'probeIntervalMs': serializer.toJson<double?>(probeIntervalMs),
      'ieOrder': serializer.toJson<String?>(ieOrder),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  Fingerprint copyWith({
    String? id,
    String? primaryMac,
    Value<double?> advIntervalMs = const Value.absent(),
    Value<int?> txPower = const Value.absent(),
    Value<String?> serviceUuids = const Value.absent(),
    Value<String?> mfgDataStructure = const Value.absent(),
    Value<String?> rssiEnvelope = const Value.absent(),
    Value<double?> probeIntervalMs = const Value.absent(),
    Value<String?> ieOrder = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => Fingerprint(
    id: id ?? this.id,
    primaryMac: primaryMac ?? this.primaryMac,
    advIntervalMs: advIntervalMs.present
        ? advIntervalMs.value
        : this.advIntervalMs,
    txPower: txPower.present ? txPower.value : this.txPower,
    serviceUuids: serviceUuids.present ? serviceUuids.value : this.serviceUuids,
    mfgDataStructure: mfgDataStructure.present
        ? mfgDataStructure.value
        : this.mfgDataStructure,
    rssiEnvelope: rssiEnvelope.present ? rssiEnvelope.value : this.rssiEnvelope,
    probeIntervalMs: probeIntervalMs.present
        ? probeIntervalMs.value
        : this.probeIntervalMs,
    ieOrder: ieOrder.present ? ieOrder.value : this.ieOrder,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  Fingerprint copyWithCompanion(FingerprintsCompanion data) {
    return Fingerprint(
      id: data.id.present ? data.id.value : this.id,
      primaryMac: data.primaryMac.present
          ? data.primaryMac.value
          : this.primaryMac,
      advIntervalMs: data.advIntervalMs.present
          ? data.advIntervalMs.value
          : this.advIntervalMs,
      txPower: data.txPower.present ? data.txPower.value : this.txPower,
      serviceUuids: data.serviceUuids.present
          ? data.serviceUuids.value
          : this.serviceUuids,
      mfgDataStructure: data.mfgDataStructure.present
          ? data.mfgDataStructure.value
          : this.mfgDataStructure,
      rssiEnvelope: data.rssiEnvelope.present
          ? data.rssiEnvelope.value
          : this.rssiEnvelope,
      probeIntervalMs: data.probeIntervalMs.present
          ? data.probeIntervalMs.value
          : this.probeIntervalMs,
      ieOrder: data.ieOrder.present ? data.ieOrder.value : this.ieOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Fingerprint(')
          ..write('id: $id, ')
          ..write('primaryMac: $primaryMac, ')
          ..write('advIntervalMs: $advIntervalMs, ')
          ..write('txPower: $txPower, ')
          ..write('serviceUuids: $serviceUuids, ')
          ..write('mfgDataStructure: $mfgDataStructure, ')
          ..write('rssiEnvelope: $rssiEnvelope, ')
          ..write('probeIntervalMs: $probeIntervalMs, ')
          ..write('ieOrder: $ieOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    primaryMac,
    advIntervalMs,
    txPower,
    serviceUuids,
    mfgDataStructure,
    rssiEnvelope,
    probeIntervalMs,
    ieOrder,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Fingerprint &&
          other.id == this.id &&
          other.primaryMac == this.primaryMac &&
          other.advIntervalMs == this.advIntervalMs &&
          other.txPower == this.txPower &&
          other.serviceUuids == this.serviceUuids &&
          other.mfgDataStructure == this.mfgDataStructure &&
          other.rssiEnvelope == this.rssiEnvelope &&
          other.probeIntervalMs == this.probeIntervalMs &&
          other.ieOrder == this.ieOrder &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FingerprintsCompanion extends UpdateCompanion<Fingerprint> {
  final Value<String> id;
  final Value<String> primaryMac;
  final Value<double?> advIntervalMs;
  final Value<int?> txPower;
  final Value<String?> serviceUuids;
  final Value<String?> mfgDataStructure;
  final Value<String?> rssiEnvelope;
  final Value<double?> probeIntervalMs;
  final Value<String?> ieOrder;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const FingerprintsCompanion({
    this.id = const Value.absent(),
    this.primaryMac = const Value.absent(),
    this.advIntervalMs = const Value.absent(),
    this.txPower = const Value.absent(),
    this.serviceUuids = const Value.absent(),
    this.mfgDataStructure = const Value.absent(),
    this.rssiEnvelope = const Value.absent(),
    this.probeIntervalMs = const Value.absent(),
    this.ieOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FingerprintsCompanion.insert({
    required String id,
    required String primaryMac,
    this.advIntervalMs = const Value.absent(),
    this.txPower = const Value.absent(),
    this.serviceUuids = const Value.absent(),
    this.mfgDataStructure = const Value.absent(),
    this.rssiEnvelope = const Value.absent(),
    this.probeIntervalMs = const Value.absent(),
    this.ieOrder = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       primaryMac = Value(primaryMac),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<Fingerprint> custom({
    Expression<String>? id,
    Expression<String>? primaryMac,
    Expression<double>? advIntervalMs,
    Expression<int>? txPower,
    Expression<String>? serviceUuids,
    Expression<String>? mfgDataStructure,
    Expression<String>? rssiEnvelope,
    Expression<double>? probeIntervalMs,
    Expression<String>? ieOrder,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (primaryMac != null) 'primary_mac': primaryMac,
      if (advIntervalMs != null) 'adv_interval_ms': advIntervalMs,
      if (txPower != null) 'tx_power': txPower,
      if (serviceUuids != null) 'service_uuids': serviceUuids,
      if (mfgDataStructure != null) 'mfg_data_structure': mfgDataStructure,
      if (rssiEnvelope != null) 'rssi_envelope': rssiEnvelope,
      if (probeIntervalMs != null) 'probe_interval_ms': probeIntervalMs,
      if (ieOrder != null) 'ie_order': ieOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FingerprintsCompanion copyWith({
    Value<String>? id,
    Value<String>? primaryMac,
    Value<double?>? advIntervalMs,
    Value<int?>? txPower,
    Value<String?>? serviceUuids,
    Value<String?>? mfgDataStructure,
    Value<String?>? rssiEnvelope,
    Value<double?>? probeIntervalMs,
    Value<String?>? ieOrder,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return FingerprintsCompanion(
      id: id ?? this.id,
      primaryMac: primaryMac ?? this.primaryMac,
      advIntervalMs: advIntervalMs ?? this.advIntervalMs,
      txPower: txPower ?? this.txPower,
      serviceUuids: serviceUuids ?? this.serviceUuids,
      mfgDataStructure: mfgDataStructure ?? this.mfgDataStructure,
      rssiEnvelope: rssiEnvelope ?? this.rssiEnvelope,
      probeIntervalMs: probeIntervalMs ?? this.probeIntervalMs,
      ieOrder: ieOrder ?? this.ieOrder,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (primaryMac.present) {
      map['primary_mac'] = Variable<String>(primaryMac.value);
    }
    if (advIntervalMs.present) {
      map['adv_interval_ms'] = Variable<double>(advIntervalMs.value);
    }
    if (txPower.present) {
      map['tx_power'] = Variable<int>(txPower.value);
    }
    if (serviceUuids.present) {
      map['service_uuids'] = Variable<String>(serviceUuids.value);
    }
    if (mfgDataStructure.present) {
      map['mfg_data_structure'] = Variable<String>(mfgDataStructure.value);
    }
    if (rssiEnvelope.present) {
      map['rssi_envelope'] = Variable<String>(rssiEnvelope.value);
    }
    if (probeIntervalMs.present) {
      map['probe_interval_ms'] = Variable<double>(probeIntervalMs.value);
    }
    if (ieOrder.present) {
      map['ie_order'] = Variable<String>(ieOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FingerprintsCompanion(')
          ..write('id: $id, ')
          ..write('primaryMac: $primaryMac, ')
          ..write('advIntervalMs: $advIntervalMs, ')
          ..write('txPower: $txPower, ')
          ..write('serviceUuids: $serviceUuids, ')
          ..write('mfgDataStructure: $mfgDataStructure, ')
          ..write('rssiEnvelope: $rssiEnvelope, ')
          ..write('probeIntervalMs: $probeIntervalMs, ')
          ..write('ieOrder: $ieOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FingerprintMacsTable extends FingerprintMacs
    with TableInfo<$FingerprintMacsTable, FingerprintMac> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FingerprintMacsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _fingerprintIdMeta = const VerificationMeta(
    'fingerprintId',
  );
  @override
  late final GeneratedColumn<String> fingerprintId = GeneratedColumn<String>(
    'fingerprint_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES fingerprints (id)',
    ),
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<int> firstSeen = GeneratedColumn<int>(
    'first_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<int> lastSeen = GeneratedColumn<int>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    fingerprintId,
    macAddress,
    firstSeen,
    lastSeen,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fingerprint_macs';
  @override
  VerificationContext validateIntegrity(
    Insertable<FingerprintMac> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('fingerprint_id')) {
      context.handle(
        _fingerprintIdMeta,
        fingerprintId.isAcceptableOrUnknown(
          data['fingerprint_id']!,
          _fingerprintIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintIdMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_firstSeenMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {fingerprintId, macAddress},
  ];
  @override
  FingerprintMac map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FingerprintMac(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      fingerprintId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint_id'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_seen'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen'],
      )!,
    );
  }

  @override
  $FingerprintMacsTable createAlias(String alias) {
    return $FingerprintMacsTable(attachedDatabase, alias);
  }
}

class FingerprintMac extends DataClass implements Insertable<FingerprintMac> {
  final int id;
  final String fingerprintId;
  final String macAddress;
  final int firstSeen;
  final int lastSeen;
  const FingerprintMac({
    required this.id,
    required this.fingerprintId,
    required this.macAddress,
    required this.firstSeen,
    required this.lastSeen,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['fingerprint_id'] = Variable<String>(fingerprintId);
    map['mac_address'] = Variable<String>(macAddress);
    map['first_seen'] = Variable<int>(firstSeen);
    map['last_seen'] = Variable<int>(lastSeen);
    return map;
  }

  FingerprintMacsCompanion toCompanion(bool nullToAbsent) {
    return FingerprintMacsCompanion(
      id: Value(id),
      fingerprintId: Value(fingerprintId),
      macAddress: Value(macAddress),
      firstSeen: Value(firstSeen),
      lastSeen: Value(lastSeen),
    );
  }

  factory FingerprintMac.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FingerprintMac(
      id: serializer.fromJson<int>(json['id']),
      fingerprintId: serializer.fromJson<String>(json['fingerprintId']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      firstSeen: serializer.fromJson<int>(json['firstSeen']),
      lastSeen: serializer.fromJson<int>(json['lastSeen']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'fingerprintId': serializer.toJson<String>(fingerprintId),
      'macAddress': serializer.toJson<String>(macAddress),
      'firstSeen': serializer.toJson<int>(firstSeen),
      'lastSeen': serializer.toJson<int>(lastSeen),
    };
  }

  FingerprintMac copyWith({
    int? id,
    String? fingerprintId,
    String? macAddress,
    int? firstSeen,
    int? lastSeen,
  }) => FingerprintMac(
    id: id ?? this.id,
    fingerprintId: fingerprintId ?? this.fingerprintId,
    macAddress: macAddress ?? this.macAddress,
    firstSeen: firstSeen ?? this.firstSeen,
    lastSeen: lastSeen ?? this.lastSeen,
  );
  FingerprintMac copyWithCompanion(FingerprintMacsCompanion data) {
    return FingerprintMac(
      id: data.id.present ? data.id.value : this.id,
      fingerprintId: data.fingerprintId.present
          ? data.fingerprintId.value
          : this.fingerprintId,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FingerprintMac(')
          ..write('id: $id, ')
          ..write('fingerprintId: $fingerprintId, ')
          ..write('macAddress: $macAddress, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, fingerprintId, macAddress, firstSeen, lastSeen);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FingerprintMac &&
          other.id == this.id &&
          other.fingerprintId == this.fingerprintId &&
          other.macAddress == this.macAddress &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen);
}

class FingerprintMacsCompanion extends UpdateCompanion<FingerprintMac> {
  final Value<int> id;
  final Value<String> fingerprintId;
  final Value<String> macAddress;
  final Value<int> firstSeen;
  final Value<int> lastSeen;
  const FingerprintMacsCompanion({
    this.id = const Value.absent(),
    this.fingerprintId = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
  });
  FingerprintMacsCompanion.insert({
    this.id = const Value.absent(),
    required String fingerprintId,
    required String macAddress,
    required int firstSeen,
    required int lastSeen,
  }) : fingerprintId = Value(fingerprintId),
       macAddress = Value(macAddress),
       firstSeen = Value(firstSeen),
       lastSeen = Value(lastSeen);
  static Insertable<FingerprintMac> custom({
    Expression<int>? id,
    Expression<String>? fingerprintId,
    Expression<String>? macAddress,
    Expression<int>? firstSeen,
    Expression<int>? lastSeen,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fingerprintId != null) 'fingerprint_id': fingerprintId,
      if (macAddress != null) 'mac_address': macAddress,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
    });
  }

  FingerprintMacsCompanion copyWith({
    Value<int>? id,
    Value<String>? fingerprintId,
    Value<String>? macAddress,
    Value<int>? firstSeen,
    Value<int>? lastSeen,
  }) {
    return FingerprintMacsCompanion(
      id: id ?? this.id,
      fingerprintId: fingerprintId ?? this.fingerprintId,
      macAddress: macAddress ?? this.macAddress,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (fingerprintId.present) {
      map['fingerprint_id'] = Variable<String>(fingerprintId.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<int>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(lastSeen.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FingerprintMacsCompanion(')
          ..write('id: $id, ')
          ..write('fingerprintId: $fingerprintId, ')
          ..write('macAddress: $macAddress, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen')
          ..write(')'))
        .toString();
  }
}

class $GeofencesTable extends Geofences
    with TableInfo<$GeofencesTable, Geofence> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GeofencesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _zoneTypeMeta = const VerificationMeta(
    'zoneType',
  );
  @override
  late final GeneratedColumn<String> zoneType = GeneratedColumn<String>(
    'zone_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _centerLatMeta = const VerificationMeta(
    'centerLat',
  );
  @override
  late final GeneratedColumn<double> centerLat = GeneratedColumn<double>(
    'center_lat',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _centerLonMeta = const VerificationMeta(
    'centerLon',
  );
  @override
  late final GeneratedColumn<double> centerLon = GeneratedColumn<double>(
    'center_lon',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _radiusMMeta = const VerificationMeta(
    'radiusM',
  );
  @override
  late final GeneratedColumn<double> radiusM = GeneratedColumn<double>(
    'radius_m',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _polygonJsonMeta = const VerificationMeta(
    'polygonJson',
  );
  @override
  late final GeneratedColumn<String> polygonJson = GeneratedColumn<String>(
    'polygon_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _corridorJsonMeta = const VerificationMeta(
    'corridorJson',
  );
  @override
  late final GeneratedColumn<String> corridorJson = GeneratedColumn<String>(
    'corridor_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alertOnFlockMeta = const VerificationMeta(
    'alertOnFlock',
  );
  @override
  late final GeneratedColumn<bool> alertOnFlock = GeneratedColumn<bool>(
    'alert_on_flock',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("alert_on_flock" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _alertOnDroneMeta = const VerificationMeta(
    'alertOnDrone',
  );
  @override
  late final GeneratedColumn<bool> alertOnDrone = GeneratedColumn<bool>(
    'alert_on_drone',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("alert_on_drone" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _alertOnNewMeta = const VerificationMeta(
    'alertOnNew',
  );
  @override
  late final GeneratedColumn<bool> alertOnNew = GeneratedColumn<bool>(
    'alert_on_new',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("alert_on_new" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _alertOnStalkingMeta = const VerificationMeta(
    'alertOnStalking',
  );
  @override
  late final GeneratedColumn<bool> alertOnStalking = GeneratedColumn<bool>(
    'alert_on_stalking',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("alert_on_stalking" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _alertModeMeta = const VerificationMeta(
    'alertMode',
  );
  @override
  late final GeneratedColumn<String> alertMode = GeneratedColumn<String>(
    'alert_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('push'),
  );
  static const VerificationMeta _enabledMeta = const VerificationMeta(
    'enabled',
  );
  @override
  late final GeneratedColumn<bool> enabled = GeneratedColumn<bool>(
    'enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _excludeFromWardriveMeta =
      const VerificationMeta('excludeFromWardrive');
  @override
  late final GeneratedColumn<bool> excludeFromWardrive = GeneratedColumn<bool>(
    'exclude_from_wardrive',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("exclude_from_wardrive" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    zoneType,
    centerLat,
    centerLon,
    radiusM,
    polygonJson,
    corridorJson,
    alertOnFlock,
    alertOnDrone,
    alertOnNew,
    alertOnStalking,
    alertMode,
    enabled,
    excludeFromWardrive,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'geofences';
  @override
  VerificationContext validateIntegrity(
    Insertable<Geofence> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('zone_type')) {
      context.handle(
        _zoneTypeMeta,
        zoneType.isAcceptableOrUnknown(data['zone_type']!, _zoneTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_zoneTypeMeta);
    }
    if (data.containsKey('center_lat')) {
      context.handle(
        _centerLatMeta,
        centerLat.isAcceptableOrUnknown(data['center_lat']!, _centerLatMeta),
      );
    }
    if (data.containsKey('center_lon')) {
      context.handle(
        _centerLonMeta,
        centerLon.isAcceptableOrUnknown(data['center_lon']!, _centerLonMeta),
      );
    }
    if (data.containsKey('radius_m')) {
      context.handle(
        _radiusMMeta,
        radiusM.isAcceptableOrUnknown(data['radius_m']!, _radiusMMeta),
      );
    }
    if (data.containsKey('polygon_json')) {
      context.handle(
        _polygonJsonMeta,
        polygonJson.isAcceptableOrUnknown(
          data['polygon_json']!,
          _polygonJsonMeta,
        ),
      );
    }
    if (data.containsKey('corridor_json')) {
      context.handle(
        _corridorJsonMeta,
        corridorJson.isAcceptableOrUnknown(
          data['corridor_json']!,
          _corridorJsonMeta,
        ),
      );
    }
    if (data.containsKey('alert_on_flock')) {
      context.handle(
        _alertOnFlockMeta,
        alertOnFlock.isAcceptableOrUnknown(
          data['alert_on_flock']!,
          _alertOnFlockMeta,
        ),
      );
    }
    if (data.containsKey('alert_on_drone')) {
      context.handle(
        _alertOnDroneMeta,
        alertOnDrone.isAcceptableOrUnknown(
          data['alert_on_drone']!,
          _alertOnDroneMeta,
        ),
      );
    }
    if (data.containsKey('alert_on_new')) {
      context.handle(
        _alertOnNewMeta,
        alertOnNew.isAcceptableOrUnknown(
          data['alert_on_new']!,
          _alertOnNewMeta,
        ),
      );
    }
    if (data.containsKey('alert_on_stalking')) {
      context.handle(
        _alertOnStalkingMeta,
        alertOnStalking.isAcceptableOrUnknown(
          data['alert_on_stalking']!,
          _alertOnStalkingMeta,
        ),
      );
    }
    if (data.containsKey('alert_mode')) {
      context.handle(
        _alertModeMeta,
        alertMode.isAcceptableOrUnknown(data['alert_mode']!, _alertModeMeta),
      );
    }
    if (data.containsKey('enabled')) {
      context.handle(
        _enabledMeta,
        enabled.isAcceptableOrUnknown(data['enabled']!, _enabledMeta),
      );
    }
    if (data.containsKey('exclude_from_wardrive')) {
      context.handle(
        _excludeFromWardriveMeta,
        excludeFromWardrive.isAcceptableOrUnknown(
          data['exclude_from_wardrive']!,
          _excludeFromWardriveMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Geofence map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Geofence(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      zoneType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}zone_type'],
      )!,
      centerLat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lat'],
      ),
      centerLon: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}center_lon'],
      ),
      radiusM: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}radius_m'],
      ),
      polygonJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}polygon_json'],
      ),
      corridorJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corridor_json'],
      ),
      alertOnFlock: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}alert_on_flock'],
      )!,
      alertOnDrone: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}alert_on_drone'],
      )!,
      alertOnNew: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}alert_on_new'],
      )!,
      alertOnStalking: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}alert_on_stalking'],
      )!,
      alertMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alert_mode'],
      )!,
      enabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}enabled'],
      )!,
      excludeFromWardrive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}exclude_from_wardrive'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $GeofencesTable createAlias(String alias) {
    return $GeofencesTable(attachedDatabase, alias);
  }
}

class Geofence extends DataClass implements Insertable<Geofence> {
  final String id;
  final String name;
  final String zoneType;
  final double? centerLat;
  final double? centerLon;
  final double? radiusM;
  final String? polygonJson;
  final String? corridorJson;
  final bool alertOnFlock;
  final bool alertOnDrone;
  final bool alertOnNew;
  final bool alertOnStalking;
  final String alertMode;
  final bool enabled;
  final bool excludeFromWardrive;
  final int createdAt;
  const Geofence({
    required this.id,
    required this.name,
    required this.zoneType,
    this.centerLat,
    this.centerLon,
    this.radiusM,
    this.polygonJson,
    this.corridorJson,
    required this.alertOnFlock,
    required this.alertOnDrone,
    required this.alertOnNew,
    required this.alertOnStalking,
    required this.alertMode,
    required this.enabled,
    required this.excludeFromWardrive,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['zone_type'] = Variable<String>(zoneType);
    if (!nullToAbsent || centerLat != null) {
      map['center_lat'] = Variable<double>(centerLat);
    }
    if (!nullToAbsent || centerLon != null) {
      map['center_lon'] = Variable<double>(centerLon);
    }
    if (!nullToAbsent || radiusM != null) {
      map['radius_m'] = Variable<double>(radiusM);
    }
    if (!nullToAbsent || polygonJson != null) {
      map['polygon_json'] = Variable<String>(polygonJson);
    }
    if (!nullToAbsent || corridorJson != null) {
      map['corridor_json'] = Variable<String>(corridorJson);
    }
    map['alert_on_flock'] = Variable<bool>(alertOnFlock);
    map['alert_on_drone'] = Variable<bool>(alertOnDrone);
    map['alert_on_new'] = Variable<bool>(alertOnNew);
    map['alert_on_stalking'] = Variable<bool>(alertOnStalking);
    map['alert_mode'] = Variable<String>(alertMode);
    map['enabled'] = Variable<bool>(enabled);
    map['exclude_from_wardrive'] = Variable<bool>(excludeFromWardrive);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  GeofencesCompanion toCompanion(bool nullToAbsent) {
    return GeofencesCompanion(
      id: Value(id),
      name: Value(name),
      zoneType: Value(zoneType),
      centerLat: centerLat == null && nullToAbsent
          ? const Value.absent()
          : Value(centerLat),
      centerLon: centerLon == null && nullToAbsent
          ? const Value.absent()
          : Value(centerLon),
      radiusM: radiusM == null && nullToAbsent
          ? const Value.absent()
          : Value(radiusM),
      polygonJson: polygonJson == null && nullToAbsent
          ? const Value.absent()
          : Value(polygonJson),
      corridorJson: corridorJson == null && nullToAbsent
          ? const Value.absent()
          : Value(corridorJson),
      alertOnFlock: Value(alertOnFlock),
      alertOnDrone: Value(alertOnDrone),
      alertOnNew: Value(alertOnNew),
      alertOnStalking: Value(alertOnStalking),
      alertMode: Value(alertMode),
      enabled: Value(enabled),
      excludeFromWardrive: Value(excludeFromWardrive),
      createdAt: Value(createdAt),
    );
  }

  factory Geofence.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Geofence(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      zoneType: serializer.fromJson<String>(json['zoneType']),
      centerLat: serializer.fromJson<double?>(json['centerLat']),
      centerLon: serializer.fromJson<double?>(json['centerLon']),
      radiusM: serializer.fromJson<double?>(json['radiusM']),
      polygonJson: serializer.fromJson<String?>(json['polygonJson']),
      corridorJson: serializer.fromJson<String?>(json['corridorJson']),
      alertOnFlock: serializer.fromJson<bool>(json['alertOnFlock']),
      alertOnDrone: serializer.fromJson<bool>(json['alertOnDrone']),
      alertOnNew: serializer.fromJson<bool>(json['alertOnNew']),
      alertOnStalking: serializer.fromJson<bool>(json['alertOnStalking']),
      alertMode: serializer.fromJson<String>(json['alertMode']),
      enabled: serializer.fromJson<bool>(json['enabled']),
      excludeFromWardrive: serializer.fromJson<bool>(
        json['excludeFromWardrive'],
      ),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'zoneType': serializer.toJson<String>(zoneType),
      'centerLat': serializer.toJson<double?>(centerLat),
      'centerLon': serializer.toJson<double?>(centerLon),
      'radiusM': serializer.toJson<double?>(radiusM),
      'polygonJson': serializer.toJson<String?>(polygonJson),
      'corridorJson': serializer.toJson<String?>(corridorJson),
      'alertOnFlock': serializer.toJson<bool>(alertOnFlock),
      'alertOnDrone': serializer.toJson<bool>(alertOnDrone),
      'alertOnNew': serializer.toJson<bool>(alertOnNew),
      'alertOnStalking': serializer.toJson<bool>(alertOnStalking),
      'alertMode': serializer.toJson<String>(alertMode),
      'enabled': serializer.toJson<bool>(enabled),
      'excludeFromWardrive': serializer.toJson<bool>(excludeFromWardrive),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  Geofence copyWith({
    String? id,
    String? name,
    String? zoneType,
    Value<double?> centerLat = const Value.absent(),
    Value<double?> centerLon = const Value.absent(),
    Value<double?> radiusM = const Value.absent(),
    Value<String?> polygonJson = const Value.absent(),
    Value<String?> corridorJson = const Value.absent(),
    bool? alertOnFlock,
    bool? alertOnDrone,
    bool? alertOnNew,
    bool? alertOnStalking,
    String? alertMode,
    bool? enabled,
    bool? excludeFromWardrive,
    int? createdAt,
  }) => Geofence(
    id: id ?? this.id,
    name: name ?? this.name,
    zoneType: zoneType ?? this.zoneType,
    centerLat: centerLat.present ? centerLat.value : this.centerLat,
    centerLon: centerLon.present ? centerLon.value : this.centerLon,
    radiusM: radiusM.present ? radiusM.value : this.radiusM,
    polygonJson: polygonJson.present ? polygonJson.value : this.polygonJson,
    corridorJson: corridorJson.present ? corridorJson.value : this.corridorJson,
    alertOnFlock: alertOnFlock ?? this.alertOnFlock,
    alertOnDrone: alertOnDrone ?? this.alertOnDrone,
    alertOnNew: alertOnNew ?? this.alertOnNew,
    alertOnStalking: alertOnStalking ?? this.alertOnStalking,
    alertMode: alertMode ?? this.alertMode,
    enabled: enabled ?? this.enabled,
    excludeFromWardrive: excludeFromWardrive ?? this.excludeFromWardrive,
    createdAt: createdAt ?? this.createdAt,
  );
  Geofence copyWithCompanion(GeofencesCompanion data) {
    return Geofence(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      zoneType: data.zoneType.present ? data.zoneType.value : this.zoneType,
      centerLat: data.centerLat.present ? data.centerLat.value : this.centerLat,
      centerLon: data.centerLon.present ? data.centerLon.value : this.centerLon,
      radiusM: data.radiusM.present ? data.radiusM.value : this.radiusM,
      polygonJson: data.polygonJson.present
          ? data.polygonJson.value
          : this.polygonJson,
      corridorJson: data.corridorJson.present
          ? data.corridorJson.value
          : this.corridorJson,
      alertOnFlock: data.alertOnFlock.present
          ? data.alertOnFlock.value
          : this.alertOnFlock,
      alertOnDrone: data.alertOnDrone.present
          ? data.alertOnDrone.value
          : this.alertOnDrone,
      alertOnNew: data.alertOnNew.present
          ? data.alertOnNew.value
          : this.alertOnNew,
      alertOnStalking: data.alertOnStalking.present
          ? data.alertOnStalking.value
          : this.alertOnStalking,
      alertMode: data.alertMode.present ? data.alertMode.value : this.alertMode,
      enabled: data.enabled.present ? data.enabled.value : this.enabled,
      excludeFromWardrive: data.excludeFromWardrive.present
          ? data.excludeFromWardrive.value
          : this.excludeFromWardrive,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Geofence(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('zoneType: $zoneType, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('radiusM: $radiusM, ')
          ..write('polygonJson: $polygonJson, ')
          ..write('corridorJson: $corridorJson, ')
          ..write('alertOnFlock: $alertOnFlock, ')
          ..write('alertOnDrone: $alertOnDrone, ')
          ..write('alertOnNew: $alertOnNew, ')
          ..write('alertOnStalking: $alertOnStalking, ')
          ..write('alertMode: $alertMode, ')
          ..write('enabled: $enabled, ')
          ..write('excludeFromWardrive: $excludeFromWardrive, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    zoneType,
    centerLat,
    centerLon,
    radiusM,
    polygonJson,
    corridorJson,
    alertOnFlock,
    alertOnDrone,
    alertOnNew,
    alertOnStalking,
    alertMode,
    enabled,
    excludeFromWardrive,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Geofence &&
          other.id == this.id &&
          other.name == this.name &&
          other.zoneType == this.zoneType &&
          other.centerLat == this.centerLat &&
          other.centerLon == this.centerLon &&
          other.radiusM == this.radiusM &&
          other.polygonJson == this.polygonJson &&
          other.corridorJson == this.corridorJson &&
          other.alertOnFlock == this.alertOnFlock &&
          other.alertOnDrone == this.alertOnDrone &&
          other.alertOnNew == this.alertOnNew &&
          other.alertOnStalking == this.alertOnStalking &&
          other.alertMode == this.alertMode &&
          other.enabled == this.enabled &&
          other.excludeFromWardrive == this.excludeFromWardrive &&
          other.createdAt == this.createdAt);
}

class GeofencesCompanion extends UpdateCompanion<Geofence> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> zoneType;
  final Value<double?> centerLat;
  final Value<double?> centerLon;
  final Value<double?> radiusM;
  final Value<String?> polygonJson;
  final Value<String?> corridorJson;
  final Value<bool> alertOnFlock;
  final Value<bool> alertOnDrone;
  final Value<bool> alertOnNew;
  final Value<bool> alertOnStalking;
  final Value<String> alertMode;
  final Value<bool> enabled;
  final Value<bool> excludeFromWardrive;
  final Value<int> createdAt;
  final Value<int> rowid;
  const GeofencesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.zoneType = const Value.absent(),
    this.centerLat = const Value.absent(),
    this.centerLon = const Value.absent(),
    this.radiusM = const Value.absent(),
    this.polygonJson = const Value.absent(),
    this.corridorJson = const Value.absent(),
    this.alertOnFlock = const Value.absent(),
    this.alertOnDrone = const Value.absent(),
    this.alertOnNew = const Value.absent(),
    this.alertOnStalking = const Value.absent(),
    this.alertMode = const Value.absent(),
    this.enabled = const Value.absent(),
    this.excludeFromWardrive = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GeofencesCompanion.insert({
    required String id,
    required String name,
    required String zoneType,
    this.centerLat = const Value.absent(),
    this.centerLon = const Value.absent(),
    this.radiusM = const Value.absent(),
    this.polygonJson = const Value.absent(),
    this.corridorJson = const Value.absent(),
    this.alertOnFlock = const Value.absent(),
    this.alertOnDrone = const Value.absent(),
    this.alertOnNew = const Value.absent(),
    this.alertOnStalking = const Value.absent(),
    this.alertMode = const Value.absent(),
    this.enabled = const Value.absent(),
    this.excludeFromWardrive = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       zoneType = Value(zoneType),
       createdAt = Value(createdAt);
  static Insertable<Geofence> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? zoneType,
    Expression<double>? centerLat,
    Expression<double>? centerLon,
    Expression<double>? radiusM,
    Expression<String>? polygonJson,
    Expression<String>? corridorJson,
    Expression<bool>? alertOnFlock,
    Expression<bool>? alertOnDrone,
    Expression<bool>? alertOnNew,
    Expression<bool>? alertOnStalking,
    Expression<String>? alertMode,
    Expression<bool>? enabled,
    Expression<bool>? excludeFromWardrive,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (zoneType != null) 'zone_type': zoneType,
      if (centerLat != null) 'center_lat': centerLat,
      if (centerLon != null) 'center_lon': centerLon,
      if (radiusM != null) 'radius_m': radiusM,
      if (polygonJson != null) 'polygon_json': polygonJson,
      if (corridorJson != null) 'corridor_json': corridorJson,
      if (alertOnFlock != null) 'alert_on_flock': alertOnFlock,
      if (alertOnDrone != null) 'alert_on_drone': alertOnDrone,
      if (alertOnNew != null) 'alert_on_new': alertOnNew,
      if (alertOnStalking != null) 'alert_on_stalking': alertOnStalking,
      if (alertMode != null) 'alert_mode': alertMode,
      if (enabled != null) 'enabled': enabled,
      if (excludeFromWardrive != null)
        'exclude_from_wardrive': excludeFromWardrive,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GeofencesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? zoneType,
    Value<double?>? centerLat,
    Value<double?>? centerLon,
    Value<double?>? radiusM,
    Value<String?>? polygonJson,
    Value<String?>? corridorJson,
    Value<bool>? alertOnFlock,
    Value<bool>? alertOnDrone,
    Value<bool>? alertOnNew,
    Value<bool>? alertOnStalking,
    Value<String>? alertMode,
    Value<bool>? enabled,
    Value<bool>? excludeFromWardrive,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return GeofencesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      zoneType: zoneType ?? this.zoneType,
      centerLat: centerLat ?? this.centerLat,
      centerLon: centerLon ?? this.centerLon,
      radiusM: radiusM ?? this.radiusM,
      polygonJson: polygonJson ?? this.polygonJson,
      corridorJson: corridorJson ?? this.corridorJson,
      alertOnFlock: alertOnFlock ?? this.alertOnFlock,
      alertOnDrone: alertOnDrone ?? this.alertOnDrone,
      alertOnNew: alertOnNew ?? this.alertOnNew,
      alertOnStalking: alertOnStalking ?? this.alertOnStalking,
      alertMode: alertMode ?? this.alertMode,
      enabled: enabled ?? this.enabled,
      excludeFromWardrive: excludeFromWardrive ?? this.excludeFromWardrive,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (zoneType.present) {
      map['zone_type'] = Variable<String>(zoneType.value);
    }
    if (centerLat.present) {
      map['center_lat'] = Variable<double>(centerLat.value);
    }
    if (centerLon.present) {
      map['center_lon'] = Variable<double>(centerLon.value);
    }
    if (radiusM.present) {
      map['radius_m'] = Variable<double>(radiusM.value);
    }
    if (polygonJson.present) {
      map['polygon_json'] = Variable<String>(polygonJson.value);
    }
    if (corridorJson.present) {
      map['corridor_json'] = Variable<String>(corridorJson.value);
    }
    if (alertOnFlock.present) {
      map['alert_on_flock'] = Variable<bool>(alertOnFlock.value);
    }
    if (alertOnDrone.present) {
      map['alert_on_drone'] = Variable<bool>(alertOnDrone.value);
    }
    if (alertOnNew.present) {
      map['alert_on_new'] = Variable<bool>(alertOnNew.value);
    }
    if (alertOnStalking.present) {
      map['alert_on_stalking'] = Variable<bool>(alertOnStalking.value);
    }
    if (alertMode.present) {
      map['alert_mode'] = Variable<String>(alertMode.value);
    }
    if (enabled.present) {
      map['enabled'] = Variable<bool>(enabled.value);
    }
    if (excludeFromWardrive.present) {
      map['exclude_from_wardrive'] = Variable<bool>(excludeFromWardrive.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GeofencesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('zoneType: $zoneType, ')
          ..write('centerLat: $centerLat, ')
          ..write('centerLon: $centerLon, ')
          ..write('radiusM: $radiusM, ')
          ..write('polygonJson: $polygonJson, ')
          ..write('corridorJson: $corridorJson, ')
          ..write('alertOnFlock: $alertOnFlock, ')
          ..write('alertOnDrone: $alertOnDrone, ')
          ..write('alertOnNew: $alertOnNew, ')
          ..write('alertOnStalking: $alertOnStalking, ')
          ..write('alertMode: $alertMode, ')
          ..write('enabled: $enabled, ')
          ..write('excludeFromWardrive: $excludeFromWardrive, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GeofenceAlertsTable extends GeofenceAlerts
    with TableInfo<$GeofenceAlertsTable, GeofenceAlert> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GeofenceAlertsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _geofenceIdMeta = const VerificationMeta(
    'geofenceId',
  );
  @override
  late final GeneratedColumn<String> geofenceId = GeneratedColumn<String>(
    'geofence_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES geofences (id)',
    ),
  );
  static const VerificationMeta _detectionIdMeta = const VerificationMeta(
    'detectionId',
  );
  @override
  late final GeneratedColumn<int> detectionId = GeneratedColumn<int>(
    'detection_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _alertTypeMeta = const VerificationMeta(
    'alertType',
  );
  @override
  late final GeneratedColumn<String> alertType = GeneratedColumn<String>(
    'alert_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _triggeredAtMeta = const VerificationMeta(
    'triggeredAt',
  );
  @override
  late final GeneratedColumn<int> triggeredAt = GeneratedColumn<int>(
    'triggered_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _acknowledgedMeta = const VerificationMeta(
    'acknowledged',
  );
  @override
  late final GeneratedColumn<bool> acknowledged = GeneratedColumn<bool>(
    'acknowledged',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("acknowledged" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    geofenceId,
    detectionId,
    alertType,
    macAddress,
    triggeredAt,
    acknowledged,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'geofence_alerts';
  @override
  VerificationContext validateIntegrity(
    Insertable<GeofenceAlert> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('geofence_id')) {
      context.handle(
        _geofenceIdMeta,
        geofenceId.isAcceptableOrUnknown(data['geofence_id']!, _geofenceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_geofenceIdMeta);
    }
    if (data.containsKey('detection_id')) {
      context.handle(
        _detectionIdMeta,
        detectionId.isAcceptableOrUnknown(
          data['detection_id']!,
          _detectionIdMeta,
        ),
      );
    }
    if (data.containsKey('alert_type')) {
      context.handle(
        _alertTypeMeta,
        alertType.isAcceptableOrUnknown(data['alert_type']!, _alertTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_alertTypeMeta);
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('triggered_at')) {
      context.handle(
        _triggeredAtMeta,
        triggeredAt.isAcceptableOrUnknown(
          data['triggered_at']!,
          _triggeredAtMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_triggeredAtMeta);
    }
    if (data.containsKey('acknowledged')) {
      context.handle(
        _acknowledgedMeta,
        acknowledged.isAcceptableOrUnknown(
          data['acknowledged']!,
          _acknowledgedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GeofenceAlert map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GeofenceAlert(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      geofenceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}geofence_id'],
      )!,
      detectionId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}detection_id'],
      ),
      alertType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}alert_type'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      triggeredAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}triggered_at'],
      )!,
      acknowledged: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}acknowledged'],
      )!,
    );
  }

  @override
  $GeofenceAlertsTable createAlias(String alias) {
    return $GeofenceAlertsTable(attachedDatabase, alias);
  }
}

class GeofenceAlert extends DataClass implements Insertable<GeofenceAlert> {
  final int id;
  final String geofenceId;
  final int? detectionId;
  final String alertType;
  final String macAddress;
  final int triggeredAt;
  final bool acknowledged;
  const GeofenceAlert({
    required this.id,
    required this.geofenceId,
    this.detectionId,
    required this.alertType,
    required this.macAddress,
    required this.triggeredAt,
    required this.acknowledged,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['geofence_id'] = Variable<String>(geofenceId);
    if (!nullToAbsent || detectionId != null) {
      map['detection_id'] = Variable<int>(detectionId);
    }
    map['alert_type'] = Variable<String>(alertType);
    map['mac_address'] = Variable<String>(macAddress);
    map['triggered_at'] = Variable<int>(triggeredAt);
    map['acknowledged'] = Variable<bool>(acknowledged);
    return map;
  }

  GeofenceAlertsCompanion toCompanion(bool nullToAbsent) {
    return GeofenceAlertsCompanion(
      id: Value(id),
      geofenceId: Value(geofenceId),
      detectionId: detectionId == null && nullToAbsent
          ? const Value.absent()
          : Value(detectionId),
      alertType: Value(alertType),
      macAddress: Value(macAddress),
      triggeredAt: Value(triggeredAt),
      acknowledged: Value(acknowledged),
    );
  }

  factory GeofenceAlert.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GeofenceAlert(
      id: serializer.fromJson<int>(json['id']),
      geofenceId: serializer.fromJson<String>(json['geofenceId']),
      detectionId: serializer.fromJson<int?>(json['detectionId']),
      alertType: serializer.fromJson<String>(json['alertType']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      triggeredAt: serializer.fromJson<int>(json['triggeredAt']),
      acknowledged: serializer.fromJson<bool>(json['acknowledged']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'geofenceId': serializer.toJson<String>(geofenceId),
      'detectionId': serializer.toJson<int?>(detectionId),
      'alertType': serializer.toJson<String>(alertType),
      'macAddress': serializer.toJson<String>(macAddress),
      'triggeredAt': serializer.toJson<int>(triggeredAt),
      'acknowledged': serializer.toJson<bool>(acknowledged),
    };
  }

  GeofenceAlert copyWith({
    int? id,
    String? geofenceId,
    Value<int?> detectionId = const Value.absent(),
    String? alertType,
    String? macAddress,
    int? triggeredAt,
    bool? acknowledged,
  }) => GeofenceAlert(
    id: id ?? this.id,
    geofenceId: geofenceId ?? this.geofenceId,
    detectionId: detectionId.present ? detectionId.value : this.detectionId,
    alertType: alertType ?? this.alertType,
    macAddress: macAddress ?? this.macAddress,
    triggeredAt: triggeredAt ?? this.triggeredAt,
    acknowledged: acknowledged ?? this.acknowledged,
  );
  GeofenceAlert copyWithCompanion(GeofenceAlertsCompanion data) {
    return GeofenceAlert(
      id: data.id.present ? data.id.value : this.id,
      geofenceId: data.geofenceId.present
          ? data.geofenceId.value
          : this.geofenceId,
      detectionId: data.detectionId.present
          ? data.detectionId.value
          : this.detectionId,
      alertType: data.alertType.present ? data.alertType.value : this.alertType,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      triggeredAt: data.triggeredAt.present
          ? data.triggeredAt.value
          : this.triggeredAt,
      acknowledged: data.acknowledged.present
          ? data.acknowledged.value
          : this.acknowledged,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GeofenceAlert(')
          ..write('id: $id, ')
          ..write('geofenceId: $geofenceId, ')
          ..write('detectionId: $detectionId, ')
          ..write('alertType: $alertType, ')
          ..write('macAddress: $macAddress, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('acknowledged: $acknowledged')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    geofenceId,
    detectionId,
    alertType,
    macAddress,
    triggeredAt,
    acknowledged,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GeofenceAlert &&
          other.id == this.id &&
          other.geofenceId == this.geofenceId &&
          other.detectionId == this.detectionId &&
          other.alertType == this.alertType &&
          other.macAddress == this.macAddress &&
          other.triggeredAt == this.triggeredAt &&
          other.acknowledged == this.acknowledged);
}

class GeofenceAlertsCompanion extends UpdateCompanion<GeofenceAlert> {
  final Value<int> id;
  final Value<String> geofenceId;
  final Value<int?> detectionId;
  final Value<String> alertType;
  final Value<String> macAddress;
  final Value<int> triggeredAt;
  final Value<bool> acknowledged;
  const GeofenceAlertsCompanion({
    this.id = const Value.absent(),
    this.geofenceId = const Value.absent(),
    this.detectionId = const Value.absent(),
    this.alertType = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.triggeredAt = const Value.absent(),
    this.acknowledged = const Value.absent(),
  });
  GeofenceAlertsCompanion.insert({
    this.id = const Value.absent(),
    required String geofenceId,
    this.detectionId = const Value.absent(),
    required String alertType,
    required String macAddress,
    required int triggeredAt,
    this.acknowledged = const Value.absent(),
  }) : geofenceId = Value(geofenceId),
       alertType = Value(alertType),
       macAddress = Value(macAddress),
       triggeredAt = Value(triggeredAt);
  static Insertable<GeofenceAlert> custom({
    Expression<int>? id,
    Expression<String>? geofenceId,
    Expression<int>? detectionId,
    Expression<String>? alertType,
    Expression<String>? macAddress,
    Expression<int>? triggeredAt,
    Expression<bool>? acknowledged,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (geofenceId != null) 'geofence_id': geofenceId,
      if (detectionId != null) 'detection_id': detectionId,
      if (alertType != null) 'alert_type': alertType,
      if (macAddress != null) 'mac_address': macAddress,
      if (triggeredAt != null) 'triggered_at': triggeredAt,
      if (acknowledged != null) 'acknowledged': acknowledged,
    });
  }

  GeofenceAlertsCompanion copyWith({
    Value<int>? id,
    Value<String>? geofenceId,
    Value<int?>? detectionId,
    Value<String>? alertType,
    Value<String>? macAddress,
    Value<int>? triggeredAt,
    Value<bool>? acknowledged,
  }) {
    return GeofenceAlertsCompanion(
      id: id ?? this.id,
      geofenceId: geofenceId ?? this.geofenceId,
      detectionId: detectionId ?? this.detectionId,
      alertType: alertType ?? this.alertType,
      macAddress: macAddress ?? this.macAddress,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      acknowledged: acknowledged ?? this.acknowledged,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (geofenceId.present) {
      map['geofence_id'] = Variable<String>(geofenceId.value);
    }
    if (detectionId.present) {
      map['detection_id'] = Variable<int>(detectionId.value);
    }
    if (alertType.present) {
      map['alert_type'] = Variable<String>(alertType.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (triggeredAt.present) {
      map['triggered_at'] = Variable<int>(triggeredAt.value);
    }
    if (acknowledged.present) {
      map['acknowledged'] = Variable<bool>(acknowledged.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GeofenceAlertsCompanion(')
          ..write('id: $id, ')
          ..write('geofenceId: $geofenceId, ')
          ..write('detectionId: $detectionId, ')
          ..write('alertType: $alertType, ')
          ..write('macAddress: $macAddress, ')
          ..write('triggeredAt: $triggeredAt, ')
          ..write('acknowledged: $acknowledged')
          ..write(')'))
        .toString();
  }
}

class $StalkingSuspectsTable extends StalkingSuspects
    with TableInfo<$StalkingSuspectsTable, StalkingSuspect> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StalkingSuspectsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _macAddressMeta = const VerificationMeta(
    'macAddress',
  );
  @override
  late final GeneratedColumn<String> macAddress = GeneratedColumn<String>(
    'mac_address',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _sessionsSeenMeta = const VerificationMeta(
    'sessionsSeen',
  );
  @override
  late final GeneratedColumn<int> sessionsSeen = GeneratedColumn<int>(
    'sessions_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _locationsSeenMeta = const VerificationMeta(
    'locationsSeen',
  );
  @override
  late final GeneratedColumn<int> locationsSeen = GeneratedColumn<int>(
    'locations_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stalkingScoreMeta = const VerificationMeta(
    'stalkingScore',
  );
  @override
  late final GeneratedColumn<double> stalkingScore = GeneratedColumn<double>(
    'stalking_score',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _firstFlaggedMeta = const VerificationMeta(
    'firstFlagged',
  );
  @override
  late final GeneratedColumn<int> firstFlagged = GeneratedColumn<int>(
    'first_flagged',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<int> lastSeen = GeneratedColumn<int>(
    'last_seen',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('active'),
  );
  static const VerificationMeta _whitelistedMeta = const VerificationMeta(
    'whitelisted',
  );
  @override
  late final GeneratedColumn<bool> whitelisted = GeneratedColumn<bool>(
    'whitelisted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("whitelisted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    macAddress,
    sessionsSeen,
    locationsSeen,
    stalkingScore,
    firstFlagged,
    lastSeen,
    status,
    whitelisted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'stalking_suspects';
  @override
  VerificationContext validateIntegrity(
    Insertable<StalkingSuspect> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('mac_address')) {
      context.handle(
        _macAddressMeta,
        macAddress.isAcceptableOrUnknown(data['mac_address']!, _macAddressMeta),
      );
    } else if (isInserting) {
      context.missing(_macAddressMeta);
    }
    if (data.containsKey('sessions_seen')) {
      context.handle(
        _sessionsSeenMeta,
        sessionsSeen.isAcceptableOrUnknown(
          data['sessions_seen']!,
          _sessionsSeenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sessionsSeenMeta);
    }
    if (data.containsKey('locations_seen')) {
      context.handle(
        _locationsSeenMeta,
        locationsSeen.isAcceptableOrUnknown(
          data['locations_seen']!,
          _locationsSeenMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_locationsSeenMeta);
    }
    if (data.containsKey('stalking_score')) {
      context.handle(
        _stalkingScoreMeta,
        stalkingScore.isAcceptableOrUnknown(
          data['stalking_score']!,
          _stalkingScoreMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_stalkingScoreMeta);
    }
    if (data.containsKey('first_flagged')) {
      context.handle(
        _firstFlaggedMeta,
        firstFlagged.isAcceptableOrUnknown(
          data['first_flagged']!,
          _firstFlaggedMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_firstFlaggedMeta);
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    } else if (isInserting) {
      context.missing(_lastSeenMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('whitelisted')) {
      context.handle(
        _whitelistedMeta,
        whitelisted.isAcceptableOrUnknown(
          data['whitelisted']!,
          _whitelistedMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StalkingSuspect map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StalkingSuspect(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      macAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac_address'],
      )!,
      sessionsSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sessions_seen'],
      )!,
      locationsSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}locations_seen'],
      )!,
      stalkingScore: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stalking_score'],
      )!,
      firstFlagged: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}first_flagged'],
      )!,
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_seen'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      whitelisted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}whitelisted'],
      )!,
    );
  }

  @override
  $StalkingSuspectsTable createAlias(String alias) {
    return $StalkingSuspectsTable(attachedDatabase, alias);
  }
}

class StalkingSuspect extends DataClass implements Insertable<StalkingSuspect> {
  final int id;
  final String macAddress;
  final int sessionsSeen;
  final int locationsSeen;
  final double stalkingScore;
  final int firstFlagged;
  final int lastSeen;
  final String status;
  final bool whitelisted;
  const StalkingSuspect({
    required this.id,
    required this.macAddress,
    required this.sessionsSeen,
    required this.locationsSeen,
    required this.stalkingScore,
    required this.firstFlagged,
    required this.lastSeen,
    required this.status,
    required this.whitelisted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['mac_address'] = Variable<String>(macAddress);
    map['sessions_seen'] = Variable<int>(sessionsSeen);
    map['locations_seen'] = Variable<int>(locationsSeen);
    map['stalking_score'] = Variable<double>(stalkingScore);
    map['first_flagged'] = Variable<int>(firstFlagged);
    map['last_seen'] = Variable<int>(lastSeen);
    map['status'] = Variable<String>(status);
    map['whitelisted'] = Variable<bool>(whitelisted);
    return map;
  }

  StalkingSuspectsCompanion toCompanion(bool nullToAbsent) {
    return StalkingSuspectsCompanion(
      id: Value(id),
      macAddress: Value(macAddress),
      sessionsSeen: Value(sessionsSeen),
      locationsSeen: Value(locationsSeen),
      stalkingScore: Value(stalkingScore),
      firstFlagged: Value(firstFlagged),
      lastSeen: Value(lastSeen),
      status: Value(status),
      whitelisted: Value(whitelisted),
    );
  }

  factory StalkingSuspect.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StalkingSuspect(
      id: serializer.fromJson<int>(json['id']),
      macAddress: serializer.fromJson<String>(json['macAddress']),
      sessionsSeen: serializer.fromJson<int>(json['sessionsSeen']),
      locationsSeen: serializer.fromJson<int>(json['locationsSeen']),
      stalkingScore: serializer.fromJson<double>(json['stalkingScore']),
      firstFlagged: serializer.fromJson<int>(json['firstFlagged']),
      lastSeen: serializer.fromJson<int>(json['lastSeen']),
      status: serializer.fromJson<String>(json['status']),
      whitelisted: serializer.fromJson<bool>(json['whitelisted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'macAddress': serializer.toJson<String>(macAddress),
      'sessionsSeen': serializer.toJson<int>(sessionsSeen),
      'locationsSeen': serializer.toJson<int>(locationsSeen),
      'stalkingScore': serializer.toJson<double>(stalkingScore),
      'firstFlagged': serializer.toJson<int>(firstFlagged),
      'lastSeen': serializer.toJson<int>(lastSeen),
      'status': serializer.toJson<String>(status),
      'whitelisted': serializer.toJson<bool>(whitelisted),
    };
  }

  StalkingSuspect copyWith({
    int? id,
    String? macAddress,
    int? sessionsSeen,
    int? locationsSeen,
    double? stalkingScore,
    int? firstFlagged,
    int? lastSeen,
    String? status,
    bool? whitelisted,
  }) => StalkingSuspect(
    id: id ?? this.id,
    macAddress: macAddress ?? this.macAddress,
    sessionsSeen: sessionsSeen ?? this.sessionsSeen,
    locationsSeen: locationsSeen ?? this.locationsSeen,
    stalkingScore: stalkingScore ?? this.stalkingScore,
    firstFlagged: firstFlagged ?? this.firstFlagged,
    lastSeen: lastSeen ?? this.lastSeen,
    status: status ?? this.status,
    whitelisted: whitelisted ?? this.whitelisted,
  );
  StalkingSuspect copyWithCompanion(StalkingSuspectsCompanion data) {
    return StalkingSuspect(
      id: data.id.present ? data.id.value : this.id,
      macAddress: data.macAddress.present
          ? data.macAddress.value
          : this.macAddress,
      sessionsSeen: data.sessionsSeen.present
          ? data.sessionsSeen.value
          : this.sessionsSeen,
      locationsSeen: data.locationsSeen.present
          ? data.locationsSeen.value
          : this.locationsSeen,
      stalkingScore: data.stalkingScore.present
          ? data.stalkingScore.value
          : this.stalkingScore,
      firstFlagged: data.firstFlagged.present
          ? data.firstFlagged.value
          : this.firstFlagged,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      status: data.status.present ? data.status.value : this.status,
      whitelisted: data.whitelisted.present
          ? data.whitelisted.value
          : this.whitelisted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StalkingSuspect(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('sessionsSeen: $sessionsSeen, ')
          ..write('locationsSeen: $locationsSeen, ')
          ..write('stalkingScore: $stalkingScore, ')
          ..write('firstFlagged: $firstFlagged, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('status: $status, ')
          ..write('whitelisted: $whitelisted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    macAddress,
    sessionsSeen,
    locationsSeen,
    stalkingScore,
    firstFlagged,
    lastSeen,
    status,
    whitelisted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StalkingSuspect &&
          other.id == this.id &&
          other.macAddress == this.macAddress &&
          other.sessionsSeen == this.sessionsSeen &&
          other.locationsSeen == this.locationsSeen &&
          other.stalkingScore == this.stalkingScore &&
          other.firstFlagged == this.firstFlagged &&
          other.lastSeen == this.lastSeen &&
          other.status == this.status &&
          other.whitelisted == this.whitelisted);
}

class StalkingSuspectsCompanion extends UpdateCompanion<StalkingSuspect> {
  final Value<int> id;
  final Value<String> macAddress;
  final Value<int> sessionsSeen;
  final Value<int> locationsSeen;
  final Value<double> stalkingScore;
  final Value<int> firstFlagged;
  final Value<int> lastSeen;
  final Value<String> status;
  final Value<bool> whitelisted;
  const StalkingSuspectsCompanion({
    this.id = const Value.absent(),
    this.macAddress = const Value.absent(),
    this.sessionsSeen = const Value.absent(),
    this.locationsSeen = const Value.absent(),
    this.stalkingScore = const Value.absent(),
    this.firstFlagged = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.status = const Value.absent(),
    this.whitelisted = const Value.absent(),
  });
  StalkingSuspectsCompanion.insert({
    this.id = const Value.absent(),
    required String macAddress,
    required int sessionsSeen,
    required int locationsSeen,
    required double stalkingScore,
    required int firstFlagged,
    required int lastSeen,
    this.status = const Value.absent(),
    this.whitelisted = const Value.absent(),
  }) : macAddress = Value(macAddress),
       sessionsSeen = Value(sessionsSeen),
       locationsSeen = Value(locationsSeen),
       stalkingScore = Value(stalkingScore),
       firstFlagged = Value(firstFlagged),
       lastSeen = Value(lastSeen);
  static Insertable<StalkingSuspect> custom({
    Expression<int>? id,
    Expression<String>? macAddress,
    Expression<int>? sessionsSeen,
    Expression<int>? locationsSeen,
    Expression<double>? stalkingScore,
    Expression<int>? firstFlagged,
    Expression<int>? lastSeen,
    Expression<String>? status,
    Expression<bool>? whitelisted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (macAddress != null) 'mac_address': macAddress,
      if (sessionsSeen != null) 'sessions_seen': sessionsSeen,
      if (locationsSeen != null) 'locations_seen': locationsSeen,
      if (stalkingScore != null) 'stalking_score': stalkingScore,
      if (firstFlagged != null) 'first_flagged': firstFlagged,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (status != null) 'status': status,
      if (whitelisted != null) 'whitelisted': whitelisted,
    });
  }

  StalkingSuspectsCompanion copyWith({
    Value<int>? id,
    Value<String>? macAddress,
    Value<int>? sessionsSeen,
    Value<int>? locationsSeen,
    Value<double>? stalkingScore,
    Value<int>? firstFlagged,
    Value<int>? lastSeen,
    Value<String>? status,
    Value<bool>? whitelisted,
  }) {
    return StalkingSuspectsCompanion(
      id: id ?? this.id,
      macAddress: macAddress ?? this.macAddress,
      sessionsSeen: sessionsSeen ?? this.sessionsSeen,
      locationsSeen: locationsSeen ?? this.locationsSeen,
      stalkingScore: stalkingScore ?? this.stalkingScore,
      firstFlagged: firstFlagged ?? this.firstFlagged,
      lastSeen: lastSeen ?? this.lastSeen,
      status: status ?? this.status,
      whitelisted: whitelisted ?? this.whitelisted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (macAddress.present) {
      map['mac_address'] = Variable<String>(macAddress.value);
    }
    if (sessionsSeen.present) {
      map['sessions_seen'] = Variable<int>(sessionsSeen.value);
    }
    if (locationsSeen.present) {
      map['locations_seen'] = Variable<int>(locationsSeen.value);
    }
    if (stalkingScore.present) {
      map['stalking_score'] = Variable<double>(stalkingScore.value);
    }
    if (firstFlagged.present) {
      map['first_flagged'] = Variable<int>(firstFlagged.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<int>(lastSeen.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (whitelisted.present) {
      map['whitelisted'] = Variable<bool>(whitelisted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StalkingSuspectsCompanion(')
          ..write('id: $id, ')
          ..write('macAddress: $macAddress, ')
          ..write('sessionsSeen: $sessionsSeen, ')
          ..write('locationsSeen: $locationsSeen, ')
          ..write('stalkingScore: $stalkingScore, ')
          ..write('firstFlagged: $firstFlagged, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('status: $status, ')
          ..write('whitelisted: $whitelisted')
          ..write(')'))
        .toString();
  }
}

class $WigleUploadsTable extends WigleUploads
    with TableInfo<$WigleUploadsTable, WigleUpload> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WigleUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES sessions (id)',
    ),
  );
  static const VerificationMeta _uploadedAtMeta = const VerificationMeta(
    'uploadedAt',
  );
  @override
  late final GeneratedColumn<int> uploadedAt = GeneratedColumn<int>(
    'uploaded_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transactionIdMeta = const VerificationMeta(
    'transactionId',
  );
  @override
  late final GeneratedColumn<String> transactionId = GeneratedColumn<String>(
    'transaction_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _networksAcceptedMeta = const VerificationMeta(
    'networksAccepted',
  );
  @override
  late final GeneratedColumn<int> networksAccepted = GeneratedColumn<int>(
    'networks_accepted',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _networksNewMeta = const VerificationMeta(
    'networksNew',
  );
  @override
  late final GeneratedColumn<int> networksNew = GeneratedColumn<int>(
    'networks_new',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    uploadedAt,
    transactionId,
    networksAccepted,
    networksNew,
    status,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wigle_uploads';
  @override
  VerificationContext validateIntegrity(
    Insertable<WigleUpload> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('uploaded_at')) {
      context.handle(
        _uploadedAtMeta,
        uploadedAt.isAcceptableOrUnknown(data['uploaded_at']!, _uploadedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_uploadedAtMeta);
    }
    if (data.containsKey('transaction_id')) {
      context.handle(
        _transactionIdMeta,
        transactionId.isAcceptableOrUnknown(
          data['transaction_id']!,
          _transactionIdMeta,
        ),
      );
    }
    if (data.containsKey('networks_accepted')) {
      context.handle(
        _networksAcceptedMeta,
        networksAccepted.isAcceptableOrUnknown(
          data['networks_accepted']!,
          _networksAcceptedMeta,
        ),
      );
    }
    if (data.containsKey('networks_new')) {
      context.handle(
        _networksNewMeta,
        networksNew.isAcceptableOrUnknown(
          data['networks_new']!,
          _networksNewMeta,
        ),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  WigleUpload map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WigleUpload(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      uploadedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}uploaded_at'],
      )!,
      transactionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transaction_id'],
      ),
      networksAccepted: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}networks_accepted'],
      ),
      networksNew: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}networks_new'],
      ),
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
    );
  }

  @override
  $WigleUploadsTable createAlias(String alias) {
    return $WigleUploadsTable(attachedDatabase, alias);
  }
}

class WigleUpload extends DataClass implements Insertable<WigleUpload> {
  final int id;
  final String? sessionId;
  final int uploadedAt;
  final String? transactionId;
  final int? networksAccepted;
  final int? networksNew;
  final String status;
  const WigleUpload({
    required this.id,
    this.sessionId,
    required this.uploadedAt,
    this.transactionId,
    this.networksAccepted,
    this.networksNew,
    required this.status,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    map['uploaded_at'] = Variable<int>(uploadedAt);
    if (!nullToAbsent || transactionId != null) {
      map['transaction_id'] = Variable<String>(transactionId);
    }
    if (!nullToAbsent || networksAccepted != null) {
      map['networks_accepted'] = Variable<int>(networksAccepted);
    }
    if (!nullToAbsent || networksNew != null) {
      map['networks_new'] = Variable<int>(networksNew);
    }
    map['status'] = Variable<String>(status);
    return map;
  }

  WigleUploadsCompanion toCompanion(bool nullToAbsent) {
    return WigleUploadsCompanion(
      id: Value(id),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      uploadedAt: Value(uploadedAt),
      transactionId: transactionId == null && nullToAbsent
          ? const Value.absent()
          : Value(transactionId),
      networksAccepted: networksAccepted == null && nullToAbsent
          ? const Value.absent()
          : Value(networksAccepted),
      networksNew: networksNew == null && nullToAbsent
          ? const Value.absent()
          : Value(networksNew),
      status: Value(status),
    );
  }

  factory WigleUpload.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WigleUpload(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      uploadedAt: serializer.fromJson<int>(json['uploadedAt']),
      transactionId: serializer.fromJson<String?>(json['transactionId']),
      networksAccepted: serializer.fromJson<int?>(json['networksAccepted']),
      networksNew: serializer.fromJson<int?>(json['networksNew']),
      status: serializer.fromJson<String>(json['status']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String?>(sessionId),
      'uploadedAt': serializer.toJson<int>(uploadedAt),
      'transactionId': serializer.toJson<String?>(transactionId),
      'networksAccepted': serializer.toJson<int?>(networksAccepted),
      'networksNew': serializer.toJson<int?>(networksNew),
      'status': serializer.toJson<String>(status),
    };
  }

  WigleUpload copyWith({
    int? id,
    Value<String?> sessionId = const Value.absent(),
    int? uploadedAt,
    Value<String?> transactionId = const Value.absent(),
    Value<int?> networksAccepted = const Value.absent(),
    Value<int?> networksNew = const Value.absent(),
    String? status,
  }) => WigleUpload(
    id: id ?? this.id,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    uploadedAt: uploadedAt ?? this.uploadedAt,
    transactionId: transactionId.present
        ? transactionId.value
        : this.transactionId,
    networksAccepted: networksAccepted.present
        ? networksAccepted.value
        : this.networksAccepted,
    networksNew: networksNew.present ? networksNew.value : this.networksNew,
    status: status ?? this.status,
  );
  WigleUpload copyWithCompanion(WigleUploadsCompanion data) {
    return WigleUpload(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      uploadedAt: data.uploadedAt.present
          ? data.uploadedAt.value
          : this.uploadedAt,
      transactionId: data.transactionId.present
          ? data.transactionId.value
          : this.transactionId,
      networksAccepted: data.networksAccepted.present
          ? data.networksAccepted.value
          : this.networksAccepted,
      networksNew: data.networksNew.present
          ? data.networksNew.value
          : this.networksNew,
      status: data.status.present ? data.status.value : this.status,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WigleUpload(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('transactionId: $transactionId, ')
          ..write('networksAccepted: $networksAccepted, ')
          ..write('networksNew: $networksNew, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    uploadedAt,
    transactionId,
    networksAccepted,
    networksNew,
    status,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WigleUpload &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.uploadedAt == this.uploadedAt &&
          other.transactionId == this.transactionId &&
          other.networksAccepted == this.networksAccepted &&
          other.networksNew == this.networksNew &&
          other.status == this.status);
}

class WigleUploadsCompanion extends UpdateCompanion<WigleUpload> {
  final Value<int> id;
  final Value<String?> sessionId;
  final Value<int> uploadedAt;
  final Value<String?> transactionId;
  final Value<int?> networksAccepted;
  final Value<int?> networksNew;
  final Value<String> status;
  const WigleUploadsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.uploadedAt = const Value.absent(),
    this.transactionId = const Value.absent(),
    this.networksAccepted = const Value.absent(),
    this.networksNew = const Value.absent(),
    this.status = const Value.absent(),
  });
  WigleUploadsCompanion.insert({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    required int uploadedAt,
    this.transactionId = const Value.absent(),
    this.networksAccepted = const Value.absent(),
    this.networksNew = const Value.absent(),
    required String status,
  }) : uploadedAt = Value(uploadedAt),
       status = Value(status);
  static Insertable<WigleUpload> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<int>? uploadedAt,
    Expression<String>? transactionId,
    Expression<int>? networksAccepted,
    Expression<int>? networksNew,
    Expression<String>? status,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (uploadedAt != null) 'uploaded_at': uploadedAt,
      if (transactionId != null) 'transaction_id': transactionId,
      if (networksAccepted != null) 'networks_accepted': networksAccepted,
      if (networksNew != null) 'networks_new': networksNew,
      if (status != null) 'status': status,
    });
  }

  WigleUploadsCompanion copyWith({
    Value<int>? id,
    Value<String?>? sessionId,
    Value<int>? uploadedAt,
    Value<String?>? transactionId,
    Value<int?>? networksAccepted,
    Value<int?>? networksNew,
    Value<String>? status,
  }) {
    return WigleUploadsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      uploadedAt: uploadedAt ?? this.uploadedAt,
      transactionId: transactionId ?? this.transactionId,
      networksAccepted: networksAccepted ?? this.networksAccepted,
      networksNew: networksNew ?? this.networksNew,
      status: status ?? this.status,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (uploadedAt.present) {
      map['uploaded_at'] = Variable<int>(uploadedAt.value);
    }
    if (transactionId.present) {
      map['transaction_id'] = Variable<String>(transactionId.value);
    }
    if (networksAccepted.present) {
      map['networks_accepted'] = Variable<int>(networksAccepted.value);
    }
    if (networksNew.present) {
      map['networks_new'] = Variable<int>(networksNew.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WigleUploadsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('uploadedAt: $uploadedAt, ')
          ..write('transactionId: $transactionId, ')
          ..write('networksAccepted: $networksAccepted, ')
          ..write('networksNew: $networksNew, ')
          ..write('status: $status')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $NodesTable nodes = $NodesTable(this);
  late final $SessionsTable sessions = $SessionsTable(this);
  late final $DetectionsTable detections = $DetectionsTable(this);
  late final $EngineConfigsTable engineConfigs = $EngineConfigsTable(this);
  late final $BaselinesTable baselines = $BaselinesTable(this);
  late final $BaselineDevicesTable baselineDevices = $BaselineDevicesTable(
    this,
  );
  late final $FingerprintsTable fingerprints = $FingerprintsTable(this);
  late final $FingerprintMacsTable fingerprintMacs = $FingerprintMacsTable(
    this,
  );
  late final $GeofencesTable geofences = $GeofencesTable(this);
  late final $GeofenceAlertsTable geofenceAlerts = $GeofenceAlertsTable(this);
  late final $StalkingSuspectsTable stalkingSuspects = $StalkingSuspectsTable(
    this,
  );
  late final $WigleUploadsTable wigleUploads = $WigleUploadsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    nodes,
    sessions,
    detections,
    engineConfigs,
    baselines,
    baselineDevices,
    fingerprints,
    fingerprintMacs,
    geofences,
    geofenceAlerts,
    stalkingSuspects,
    wigleUploads,
  ];
}

typedef $$NodesTableCreateCompanionBuilder =
    NodesCompanion Function({
      required String id,
      required String name,
      required String macAddress,
      Value<String?> firmwareVersion,
      Value<int?> lastSeen,
      Value<String?> configJson,
      Value<String?> configHash,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$NodesTableUpdateCompanionBuilder =
    NodesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> macAddress,
      Value<String?> firmwareVersion,
      Value<int?> lastSeen,
      Value<String?> configJson,
      Value<String?> configHash,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$NodesTableReferences
    extends BaseReferences<_$AppDatabase, $NodesTable, Node> {
  $$NodesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SessionsTable, List<Session>> _sessionsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.sessions,
    aliasName: $_aliasNameGenerator(db.nodes.id, db.sessions.nodeId),
  );

  $$SessionsTableProcessedTableManager get sessionsRefs {
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sessionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$DetectionsTable, List<Detection>>
  _detectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.detections,
    aliasName: $_aliasNameGenerator(db.nodes.id, db.detections.nodeId),
  );

  $$DetectionsTableProcessedTableManager get detectionsRefs {
    final manager = $$DetectionsTableTableManager(
      $_db,
      $_db.detections,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_detectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$EngineConfigsTable, List<EngineConfig>>
  _engineConfigsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.engineConfigs,
    aliasName: $_aliasNameGenerator(db.nodes.id, db.engineConfigs.nodeId),
  );

  $$EngineConfigsTableProcessedTableManager get engineConfigsRefs {
    final manager = $$EngineConfigsTableTableManager(
      $_db,
      $_db.engineConfigs,
    ).filter((f) => f.nodeId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_engineConfigsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NodesTableFilterComposer extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configHash => $composableBuilder(
    column: $table.configHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> sessionsRefs(
    Expression<bool> Function($$SessionsTableFilterComposer f) f,
  ) {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> detectionsRefs(
    Expression<bool> Function($$DetectionsTableFilterComposer f) f,
  ) {
    final $$DetectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.detections,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DetectionsTableFilterComposer(
            $db: $db,
            $table: $db.detections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> engineConfigsRefs(
    Expression<bool> Function($$EngineConfigsTableFilterComposer f) f,
  ) {
    final $$EngineConfigsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.engineConfigs,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EngineConfigsTableFilterComposer(
            $db: $db,
            $table: $db.engineConfigs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableOrderingComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configHash => $composableBuilder(
    column: $table.configHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NodesTableAnnotationComposer
    extends Composer<_$AppDatabase, $NodesTable> {
  $$NodesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get firmwareVersion => $composableBuilder(
    column: $table.firmwareVersion,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get configHash => $composableBuilder(
    column: $table.configHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> sessionsRefs<T extends Object>(
    Expression<T> Function($$SessionsTableAnnotationComposer a) f,
  ) {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> detectionsRefs<T extends Object>(
    Expression<T> Function($$DetectionsTableAnnotationComposer a) f,
  ) {
    final $$DetectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.detections,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DetectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.detections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> engineConfigsRefs<T extends Object>(
    Expression<T> Function($$EngineConfigsTableAnnotationComposer a) f,
  ) {
    final $$EngineConfigsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.engineConfigs,
      getReferencedColumn: (t) => t.nodeId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$EngineConfigsTableAnnotationComposer(
            $db: $db,
            $table: $db.engineConfigs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NodesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $NodesTable,
          Node,
          $$NodesTableFilterComposer,
          $$NodesTableOrderingComposer,
          $$NodesTableAnnotationComposer,
          $$NodesTableCreateCompanionBuilder,
          $$NodesTableUpdateCompanionBuilder,
          (Node, $$NodesTableReferences),
          Node,
          PrefetchHooks Function({
            bool sessionsRefs,
            bool detectionsRefs,
            bool engineConfigsRefs,
          })
        > {
  $$NodesTableTableManager(_$AppDatabase db, $NodesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NodesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NodesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NodesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<String?> firmwareVersion = const Value.absent(),
                Value<int?> lastSeen = const Value.absent(),
                Value<String?> configJson = const Value.absent(),
                Value<String?> configHash = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion(
                id: id,
                name: name,
                macAddress: macAddress,
                firmwareVersion: firmwareVersion,
                lastSeen: lastSeen,
                configJson: configJson,
                configHash: configHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String macAddress,
                Value<String?> firmwareVersion = const Value.absent(),
                Value<int?> lastSeen = const Value.absent(),
                Value<String?> configJson = const Value.absent(),
                Value<String?> configHash = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => NodesCompanion.insert(
                id: id,
                name: name,
                macAddress: macAddress,
                firmwareVersion: firmwareVersion,
                lastSeen: lastSeen,
                configJson: configJson,
                configHash: configHash,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$NodesTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                sessionsRefs = false,
                detectionsRefs = false,
                engineConfigsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (sessionsRefs) db.sessions,
                    if (detectionsRefs) db.detections,
                    if (engineConfigsRefs) db.engineConfigs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (sessionsRefs)
                        await $_getPrefetchedData<Node, $NodesTable, Session>(
                          currentTable: table,
                          referencedTable: $$NodesTableReferences
                              ._sessionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$NodesTableReferences(
                                db,
                                table,
                                p0,
                              ).sessionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.nodeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (detectionsRefs)
                        await $_getPrefetchedData<Node, $NodesTable, Detection>(
                          currentTable: table,
                          referencedTable: $$NodesTableReferences
                              ._detectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$NodesTableReferences(
                                db,
                                table,
                                p0,
                              ).detectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.nodeId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (engineConfigsRefs)
                        await $_getPrefetchedData<
                          Node,
                          $NodesTable,
                          EngineConfig
                        >(
                          currentTable: table,
                          referencedTable: $$NodesTableReferences
                              ._engineConfigsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$NodesTableReferences(
                                db,
                                table,
                                p0,
                              ).engineConfigsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.nodeId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$NodesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $NodesTable,
      Node,
      $$NodesTableFilterComposer,
      $$NodesTableOrderingComposer,
      $$NodesTableAnnotationComposer,
      $$NodesTableCreateCompanionBuilder,
      $$NodesTableUpdateCompanionBuilder,
      (Node, $$NodesTableReferences),
      Node,
      PrefetchHooks Function({
        bool sessionsRefs,
        bool detectionsRefs,
        bool engineConfigsRefs,
      })
    >;
typedef $$SessionsTableCreateCompanionBuilder =
    SessionsCompanion Function({
      required String id,
      required String name,
      required String nodeId,
      required int startedAt,
      Value<int?> endedAt,
      Value<int> enginesActive,
      Value<int> detectionCount,
      Value<int> uniqueMacCount,
      Value<double> distanceKm,
      Value<bool> exported,
      Value<bool> isWardrive,
      Value<int> rowid,
    });
typedef $$SessionsTableUpdateCompanionBuilder =
    SessionsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> nodeId,
      Value<int> startedAt,
      Value<int?> endedAt,
      Value<int> enginesActive,
      Value<int> detectionCount,
      Value<int> uniqueMacCount,
      Value<double> distanceKm,
      Value<bool> exported,
      Value<bool> isWardrive,
      Value<int> rowid,
    });

final class $$SessionsTableReferences
    extends BaseReferences<_$AppDatabase, $SessionsTable, Session> {
  $$SessionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NodesTable _nodeIdTable(_$AppDatabase db) => db.nodes.createAlias(
    $_aliasNameGenerator(db.sessions.nodeId, db.nodes.id),
  );

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<String>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DetectionsTable, List<Detection>>
  _detectionsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.detections,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.detections.sessionId),
  );

  $$DetectionsTableProcessedTableManager get detectionsRefs {
    final manager = $$DetectionsTableTableManager(
      $_db,
      $_db.detections,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_detectionsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$WigleUploadsTable, List<WigleUpload>>
  _wigleUploadsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.wigleUploads,
    aliasName: $_aliasNameGenerator(db.sessions.id, db.wigleUploads.sessionId),
  );

  $$WigleUploadsTableProcessedTableManager get wigleUploadsRefs {
    final manager = $$WigleUploadsTableTableManager(
      $_db,
      $_db.wigleUploads,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_wigleUploadsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SessionsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get enginesActive => $composableBuilder(
    column: $table.enginesActive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uniqueMacCount => $composableBuilder(
    column: $table.uniqueMacCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get exported => $composableBuilder(
    column: $table.exported,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isWardrive => $composableBuilder(
    column: $table.isWardrive,
    builder: (column) => ColumnFilters(column),
  );

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> detectionsRefs(
    Expression<bool> Function($$DetectionsTableFilterComposer f) f,
  ) {
    final $$DetectionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.detections,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DetectionsTableFilterComposer(
            $db: $db,
            $table: $db.detections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> wigleUploadsRefs(
    Expression<bool> Function($$WigleUploadsTableFilterComposer f) f,
  ) {
    final $$WigleUploadsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wigleUploads,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WigleUploadsTableFilterComposer(
            $db: $db,
            $table: $db.wigleUploads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get enginesActive => $composableBuilder(
    column: $table.enginesActive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uniqueMacCount => $composableBuilder(
    column: $table.uniqueMacCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get exported => $composableBuilder(
    column: $table.exported,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isWardrive => $composableBuilder(
    column: $table.isWardrive,
    builder: (column) => ColumnOrderings(column),
  );

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SessionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionsTable> {
  $$SessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<int> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  GeneratedColumn<int> get enginesActive => $composableBuilder(
    column: $table.enginesActive,
    builder: (column) => column,
  );

  GeneratedColumn<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get uniqueMacCount => $composableBuilder(
    column: $table.uniqueMacCount,
    builder: (column) => column,
  );

  GeneratedColumn<double> get distanceKm => $composableBuilder(
    column: $table.distanceKm,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get exported =>
      $composableBuilder(column: $table.exported, builder: (column) => column);

  GeneratedColumn<bool> get isWardrive => $composableBuilder(
    column: $table.isWardrive,
    builder: (column) => column,
  );

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> detectionsRefs<T extends Object>(
    Expression<T> Function($$DetectionsTableAnnotationComposer a) f,
  ) {
    final $$DetectionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.detections,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DetectionsTableAnnotationComposer(
            $db: $db,
            $table: $db.detections,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> wigleUploadsRefs<T extends Object>(
    Expression<T> Function($$WigleUploadsTableAnnotationComposer a) f,
  ) {
    final $$WigleUploadsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.wigleUploads,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$WigleUploadsTableAnnotationComposer(
            $db: $db,
            $table: $db.wigleUploads,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SessionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionsTable,
          Session,
          $$SessionsTableFilterComposer,
          $$SessionsTableOrderingComposer,
          $$SessionsTableAnnotationComposer,
          $$SessionsTableCreateCompanionBuilder,
          $$SessionsTableUpdateCompanionBuilder,
          (Session, $$SessionsTableReferences),
          Session,
          PrefetchHooks Function({
            bool nodeId,
            bool detectionsRefs,
            bool wigleUploadsRefs,
          })
        > {
  $$SessionsTableTableManager(_$AppDatabase db, $SessionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> nodeId = const Value.absent(),
                Value<int> startedAt = const Value.absent(),
                Value<int?> endedAt = const Value.absent(),
                Value<int> enginesActive = const Value.absent(),
                Value<int> detectionCount = const Value.absent(),
                Value<int> uniqueMacCount = const Value.absent(),
                Value<double> distanceKm = const Value.absent(),
                Value<bool> exported = const Value.absent(),
                Value<bool> isWardrive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion(
                id: id,
                name: name,
                nodeId: nodeId,
                startedAt: startedAt,
                endedAt: endedAt,
                enginesActive: enginesActive,
                detectionCount: detectionCount,
                uniqueMacCount: uniqueMacCount,
                distanceKm: distanceKm,
                exported: exported,
                isWardrive: isWardrive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String nodeId,
                required int startedAt,
                Value<int?> endedAt = const Value.absent(),
                Value<int> enginesActive = const Value.absent(),
                Value<int> detectionCount = const Value.absent(),
                Value<int> uniqueMacCount = const Value.absent(),
                Value<double> distanceKm = const Value.absent(),
                Value<bool> exported = const Value.absent(),
                Value<bool> isWardrive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionsCompanion.insert(
                id: id,
                name: name,
                nodeId: nodeId,
                startedAt: startedAt,
                endedAt: endedAt,
                enginesActive: enginesActive,
                detectionCount: detectionCount,
                uniqueMacCount: uniqueMacCount,
                distanceKm: distanceKm,
                exported: exported,
                isWardrive: isWardrive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                nodeId = false,
                detectionsRefs = false,
                wigleUploadsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (detectionsRefs) db.detections,
                    if (wigleUploadsRefs) db.wigleUploads,
                  ],
                  addJoins:
                      <
                        T extends TableManagerState<
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic,
                          dynamic
                        >
                      >(state) {
                        if (nodeId) {
                          state =
                              state.withJoin(
                                    currentTable: table,
                                    currentColumn: table.nodeId,
                                    referencedTable: $$SessionsTableReferences
                                        ._nodeIdTable(db),
                                    referencedColumn: $$SessionsTableReferences
                                        ._nodeIdTable(db)
                                        .id,
                                  )
                                  as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (detectionsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          Detection
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._detectionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).detectionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (wigleUploadsRefs)
                        await $_getPrefetchedData<
                          Session,
                          $SessionsTable,
                          WigleUpload
                        >(
                          currentTable: table,
                          referencedTable: $$SessionsTableReferences
                              ._wigleUploadsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).wigleUploadsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionsTable,
      Session,
      $$SessionsTableFilterComposer,
      $$SessionsTableOrderingComposer,
      $$SessionsTableAnnotationComposer,
      $$SessionsTableCreateCompanionBuilder,
      $$SessionsTableUpdateCompanionBuilder,
      (Session, $$SessionsTableReferences),
      Session,
      PrefetchHooks Function({
        bool nodeId,
        bool detectionsRefs,
        bool wigleUploadsRefs,
      })
    >;
typedef $$DetectionsTableCreateCompanionBuilder =
    DetectionsCompanion Function({
      Value<int> id,
      required String sessionId,
      required String nodeId,
      required String macAddress,
      Value<String> deviceName,
      required String engine,
      required String detectionMethod,
      required int rssi,
      required int channel,
      required int deviceTimestampMs,
      required int appTimestamp,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> altitude,
      Value<double?> speed,
      Value<double?> heading,
      Value<double?> accuracy,
      Value<int?> satelliteCount,
      Value<String> ssid,
      Value<int> authMode,
      Value<int> count,
      Value<bool?> isRaven,
      Value<String?> ravenFirmware,
      Value<String?> uavId,
      Value<String?> operatorId,
      Value<double?> droneLat,
      Value<double?> droneLon,
      Value<int?> altitudeMsl,
      Value<int?> heightAgl,
      Value<int?> droneSpeed,
      Value<int?> droneHeading,
      Value<double?> pilotLat,
      Value<double?> pilotLon,
      Value<String?> robotType,
      Value<bool?> exploited,
      Value<String?> robotSerial,
      Value<String?> filterDescription,
      Value<bool?> isFullMac,
    });
typedef $$DetectionsTableUpdateCompanionBuilder =
    DetectionsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<String> nodeId,
      Value<String> macAddress,
      Value<String> deviceName,
      Value<String> engine,
      Value<String> detectionMethod,
      Value<int> rssi,
      Value<int> channel,
      Value<int> deviceTimestampMs,
      Value<int> appTimestamp,
      Value<double?> latitude,
      Value<double?> longitude,
      Value<double?> altitude,
      Value<double?> speed,
      Value<double?> heading,
      Value<double?> accuracy,
      Value<int?> satelliteCount,
      Value<String> ssid,
      Value<int> authMode,
      Value<int> count,
      Value<bool?> isRaven,
      Value<String?> ravenFirmware,
      Value<String?> uavId,
      Value<String?> operatorId,
      Value<double?> droneLat,
      Value<double?> droneLon,
      Value<int?> altitudeMsl,
      Value<int?> heightAgl,
      Value<int?> droneSpeed,
      Value<int?> droneHeading,
      Value<double?> pilotLat,
      Value<double?> pilotLon,
      Value<String?> robotType,
      Value<bool?> exploited,
      Value<String?> robotSerial,
      Value<String?> filterDescription,
      Value<bool?> isFullMac,
    });

final class $$DetectionsTableReferences
    extends BaseReferences<_$AppDatabase, $DetectionsTable, Detection> {
  $$DetectionsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.detections.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $NodesTable _nodeIdTable(_$AppDatabase db) => db.nodes.createAlias(
    $_aliasNameGenerator(db.detections.nodeId, db.nodes.id),
  );

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<String>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DetectionsTableFilterComposer
    extends Composer<_$AppDatabase, $DetectionsTable> {
  $$DetectionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detectionMethod => $composableBuilder(
    column: $table.detectionMethod,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get deviceTimestampMs => $composableBuilder(
    column: $table.deviceTimestampMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get appTimestamp => $composableBuilder(
    column: $table.appTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get satelliteCount => $composableBuilder(
    column: $table.satelliteCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ssid => $composableBuilder(
    column: $table.ssid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get authMode => $composableBuilder(
    column: $table.authMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isRaven => $composableBuilder(
    column: $table.isRaven,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ravenFirmware => $composableBuilder(
    column: $table.ravenFirmware,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get uavId => $composableBuilder(
    column: $table.uavId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get droneLat => $composableBuilder(
    column: $table.droneLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get droneLon => $composableBuilder(
    column: $table.droneLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get altitudeMsl => $composableBuilder(
    column: $table.altitudeMsl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get heightAgl => $composableBuilder(
    column: $table.heightAgl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get droneSpeed => $composableBuilder(
    column: $table.droneSpeed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get droneHeading => $composableBuilder(
    column: $table.droneHeading,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pilotLat => $composableBuilder(
    column: $table.pilotLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get pilotLon => $composableBuilder(
    column: $table.pilotLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get robotType => $composableBuilder(
    column: $table.robotType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get exploited => $composableBuilder(
    column: $table.exploited,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get robotSerial => $composableBuilder(
    column: $table.robotSerial,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filterDescription => $composableBuilder(
    column: $table.filterDescription,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isFullMac => $composableBuilder(
    column: $table.isFullMac,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DetectionsTableOrderingComposer
    extends Composer<_$AppDatabase, $DetectionsTable> {
  $$DetectionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detectionMethod => $composableBuilder(
    column: $table.detectionMethod,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssi => $composableBuilder(
    column: $table.rssi,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get channel => $composableBuilder(
    column: $table.channel,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get deviceTimestampMs => $composableBuilder(
    column: $table.deviceTimestampMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get appTimestamp => $composableBuilder(
    column: $table.appTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get altitude => $composableBuilder(
    column: $table.altitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speed => $composableBuilder(
    column: $table.speed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get heading => $composableBuilder(
    column: $table.heading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracy => $composableBuilder(
    column: $table.accuracy,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get satelliteCount => $composableBuilder(
    column: $table.satelliteCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ssid => $composableBuilder(
    column: $table.ssid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get authMode => $composableBuilder(
    column: $table.authMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get count => $composableBuilder(
    column: $table.count,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isRaven => $composableBuilder(
    column: $table.isRaven,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ravenFirmware => $composableBuilder(
    column: $table.ravenFirmware,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get uavId => $composableBuilder(
    column: $table.uavId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get droneLat => $composableBuilder(
    column: $table.droneLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get droneLon => $composableBuilder(
    column: $table.droneLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get altitudeMsl => $composableBuilder(
    column: $table.altitudeMsl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get heightAgl => $composableBuilder(
    column: $table.heightAgl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get droneSpeed => $composableBuilder(
    column: $table.droneSpeed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get droneHeading => $composableBuilder(
    column: $table.droneHeading,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pilotLat => $composableBuilder(
    column: $table.pilotLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get pilotLon => $composableBuilder(
    column: $table.pilotLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get robotType => $composableBuilder(
    column: $table.robotType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get exploited => $composableBuilder(
    column: $table.exploited,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get robotSerial => $composableBuilder(
    column: $table.robotSerial,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filterDescription => $composableBuilder(
    column: $table.filterDescription,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isFullMac => $composableBuilder(
    column: $table.isFullMac,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DetectionsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DetectionsTable> {
  $$DetectionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get engine =>
      $composableBuilder(column: $table.engine, builder: (column) => column);

  GeneratedColumn<String> get detectionMethod => $composableBuilder(
    column: $table.detectionMethod,
    builder: (column) => column,
  );

  GeneratedColumn<int> get rssi =>
      $composableBuilder(column: $table.rssi, builder: (column) => column);

  GeneratedColumn<int> get channel =>
      $composableBuilder(column: $table.channel, builder: (column) => column);

  GeneratedColumn<int> get deviceTimestampMs => $composableBuilder(
    column: $table.deviceTimestampMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get appTimestamp => $composableBuilder(
    column: $table.appTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<double> get altitude =>
      $composableBuilder(column: $table.altitude, builder: (column) => column);

  GeneratedColumn<double> get speed =>
      $composableBuilder(column: $table.speed, builder: (column) => column);

  GeneratedColumn<double> get heading =>
      $composableBuilder(column: $table.heading, builder: (column) => column);

  GeneratedColumn<double> get accuracy =>
      $composableBuilder(column: $table.accuracy, builder: (column) => column);

  GeneratedColumn<int> get satelliteCount => $composableBuilder(
    column: $table.satelliteCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ssid =>
      $composableBuilder(column: $table.ssid, builder: (column) => column);

  GeneratedColumn<int> get authMode =>
      $composableBuilder(column: $table.authMode, builder: (column) => column);

  GeneratedColumn<int> get count =>
      $composableBuilder(column: $table.count, builder: (column) => column);

  GeneratedColumn<bool> get isRaven =>
      $composableBuilder(column: $table.isRaven, builder: (column) => column);

  GeneratedColumn<String> get ravenFirmware => $composableBuilder(
    column: $table.ravenFirmware,
    builder: (column) => column,
  );

  GeneratedColumn<String> get uavId =>
      $composableBuilder(column: $table.uavId, builder: (column) => column);

  GeneratedColumn<String> get operatorId => $composableBuilder(
    column: $table.operatorId,
    builder: (column) => column,
  );

  GeneratedColumn<double> get droneLat =>
      $composableBuilder(column: $table.droneLat, builder: (column) => column);

  GeneratedColumn<double> get droneLon =>
      $composableBuilder(column: $table.droneLon, builder: (column) => column);

  GeneratedColumn<int> get altitudeMsl => $composableBuilder(
    column: $table.altitudeMsl,
    builder: (column) => column,
  );

  GeneratedColumn<int> get heightAgl =>
      $composableBuilder(column: $table.heightAgl, builder: (column) => column);

  GeneratedColumn<int> get droneSpeed => $composableBuilder(
    column: $table.droneSpeed,
    builder: (column) => column,
  );

  GeneratedColumn<int> get droneHeading => $composableBuilder(
    column: $table.droneHeading,
    builder: (column) => column,
  );

  GeneratedColumn<double> get pilotLat =>
      $composableBuilder(column: $table.pilotLat, builder: (column) => column);

  GeneratedColumn<double> get pilotLon =>
      $composableBuilder(column: $table.pilotLon, builder: (column) => column);

  GeneratedColumn<String> get robotType =>
      $composableBuilder(column: $table.robotType, builder: (column) => column);

  GeneratedColumn<bool> get exploited =>
      $composableBuilder(column: $table.exploited, builder: (column) => column);

  GeneratedColumn<String> get robotSerial => $composableBuilder(
    column: $table.robotSerial,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filterDescription => $composableBuilder(
    column: $table.filterDescription,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isFullMac =>
      $composableBuilder(column: $table.isFullMac, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DetectionsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DetectionsTable,
          Detection,
          $$DetectionsTableFilterComposer,
          $$DetectionsTableOrderingComposer,
          $$DetectionsTableAnnotationComposer,
          $$DetectionsTableCreateCompanionBuilder,
          $$DetectionsTableUpdateCompanionBuilder,
          (Detection, $$DetectionsTableReferences),
          Detection,
          PrefetchHooks Function({bool sessionId, bool nodeId})
        > {
  $$DetectionsTableTableManager(_$AppDatabase db, $DetectionsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DetectionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DetectionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DetectionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> nodeId = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<String> detectionMethod = const Value.absent(),
                Value<int> rssi = const Value.absent(),
                Value<int> channel = const Value.absent(),
                Value<int> deviceTimestampMs = const Value.absent(),
                Value<int> appTimestamp = const Value.absent(),
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> altitude = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<double?> heading = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<int?> satelliteCount = const Value.absent(),
                Value<String> ssid = const Value.absent(),
                Value<int> authMode = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<bool?> isRaven = const Value.absent(),
                Value<String?> ravenFirmware = const Value.absent(),
                Value<String?> uavId = const Value.absent(),
                Value<String?> operatorId = const Value.absent(),
                Value<double?> droneLat = const Value.absent(),
                Value<double?> droneLon = const Value.absent(),
                Value<int?> altitudeMsl = const Value.absent(),
                Value<int?> heightAgl = const Value.absent(),
                Value<int?> droneSpeed = const Value.absent(),
                Value<int?> droneHeading = const Value.absent(),
                Value<double?> pilotLat = const Value.absent(),
                Value<double?> pilotLon = const Value.absent(),
                Value<String?> robotType = const Value.absent(),
                Value<bool?> exploited = const Value.absent(),
                Value<String?> robotSerial = const Value.absent(),
                Value<String?> filterDescription = const Value.absent(),
                Value<bool?> isFullMac = const Value.absent(),
              }) => DetectionsCompanion(
                id: id,
                sessionId: sessionId,
                nodeId: nodeId,
                macAddress: macAddress,
                deviceName: deviceName,
                engine: engine,
                detectionMethod: detectionMethod,
                rssi: rssi,
                channel: channel,
                deviceTimestampMs: deviceTimestampMs,
                appTimestamp: appTimestamp,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speed: speed,
                heading: heading,
                accuracy: accuracy,
                satelliteCount: satelliteCount,
                ssid: ssid,
                authMode: authMode,
                count: count,
                isRaven: isRaven,
                ravenFirmware: ravenFirmware,
                uavId: uavId,
                operatorId: operatorId,
                droneLat: droneLat,
                droneLon: droneLon,
                altitudeMsl: altitudeMsl,
                heightAgl: heightAgl,
                droneSpeed: droneSpeed,
                droneHeading: droneHeading,
                pilotLat: pilotLat,
                pilotLon: pilotLon,
                robotType: robotType,
                exploited: exploited,
                robotSerial: robotSerial,
                filterDescription: filterDescription,
                isFullMac: isFullMac,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required String nodeId,
                required String macAddress,
                Value<String> deviceName = const Value.absent(),
                required String engine,
                required String detectionMethod,
                required int rssi,
                required int channel,
                required int deviceTimestampMs,
                required int appTimestamp,
                Value<double?> latitude = const Value.absent(),
                Value<double?> longitude = const Value.absent(),
                Value<double?> altitude = const Value.absent(),
                Value<double?> speed = const Value.absent(),
                Value<double?> heading = const Value.absent(),
                Value<double?> accuracy = const Value.absent(),
                Value<int?> satelliteCount = const Value.absent(),
                Value<String> ssid = const Value.absent(),
                Value<int> authMode = const Value.absent(),
                Value<int> count = const Value.absent(),
                Value<bool?> isRaven = const Value.absent(),
                Value<String?> ravenFirmware = const Value.absent(),
                Value<String?> uavId = const Value.absent(),
                Value<String?> operatorId = const Value.absent(),
                Value<double?> droneLat = const Value.absent(),
                Value<double?> droneLon = const Value.absent(),
                Value<int?> altitudeMsl = const Value.absent(),
                Value<int?> heightAgl = const Value.absent(),
                Value<int?> droneSpeed = const Value.absent(),
                Value<int?> droneHeading = const Value.absent(),
                Value<double?> pilotLat = const Value.absent(),
                Value<double?> pilotLon = const Value.absent(),
                Value<String?> robotType = const Value.absent(),
                Value<bool?> exploited = const Value.absent(),
                Value<String?> robotSerial = const Value.absent(),
                Value<String?> filterDescription = const Value.absent(),
                Value<bool?> isFullMac = const Value.absent(),
              }) => DetectionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                nodeId: nodeId,
                macAddress: macAddress,
                deviceName: deviceName,
                engine: engine,
                detectionMethod: detectionMethod,
                rssi: rssi,
                channel: channel,
                deviceTimestampMs: deviceTimestampMs,
                appTimestamp: appTimestamp,
                latitude: latitude,
                longitude: longitude,
                altitude: altitude,
                speed: speed,
                heading: heading,
                accuracy: accuracy,
                satelliteCount: satelliteCount,
                ssid: ssid,
                authMode: authMode,
                count: count,
                isRaven: isRaven,
                ravenFirmware: ravenFirmware,
                uavId: uavId,
                operatorId: operatorId,
                droneLat: droneLat,
                droneLon: droneLon,
                altitudeMsl: altitudeMsl,
                heightAgl: heightAgl,
                droneSpeed: droneSpeed,
                droneHeading: droneHeading,
                pilotLat: pilotLat,
                pilotLon: pilotLon,
                robotType: robotType,
                exploited: exploited,
                robotSerial: robotSerial,
                filterDescription: filterDescription,
                isFullMac: isFullMac,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$DetectionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false, nodeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$DetectionsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$DetectionsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (nodeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.nodeId,
                                referencedTable: $$DetectionsTableReferences
                                    ._nodeIdTable(db),
                                referencedColumn: $$DetectionsTableReferences
                                    ._nodeIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DetectionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DetectionsTable,
      Detection,
      $$DetectionsTableFilterComposer,
      $$DetectionsTableOrderingComposer,
      $$DetectionsTableAnnotationComposer,
      $$DetectionsTableCreateCompanionBuilder,
      $$DetectionsTableUpdateCompanionBuilder,
      (Detection, $$DetectionsTableReferences),
      Detection,
      PrefetchHooks Function({bool sessionId, bool nodeId})
    >;
typedef $$EngineConfigsTableCreateCompanionBuilder =
    EngineConfigsCompanion Function({
      Value<int> id,
      required String nodeId,
      required String engine,
      required String configJson,
      required int updatedAt,
    });
typedef $$EngineConfigsTableUpdateCompanionBuilder =
    EngineConfigsCompanion Function({
      Value<int> id,
      Value<String> nodeId,
      Value<String> engine,
      Value<String> configJson,
      Value<int> updatedAt,
    });

final class $$EngineConfigsTableReferences
    extends BaseReferences<_$AppDatabase, $EngineConfigsTable, EngineConfig> {
  $$EngineConfigsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $NodesTable _nodeIdTable(_$AppDatabase db) => db.nodes.createAlias(
    $_aliasNameGenerator(db.engineConfigs.nodeId, db.nodes.id),
  );

  $$NodesTableProcessedTableManager get nodeId {
    final $_column = $_itemColumn<String>('node_id')!;

    final manager = $$NodesTableTableManager(
      $_db,
      $_db.nodes,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_nodeIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$EngineConfigsTableFilterComposer
    extends Composer<_$AppDatabase, $EngineConfigsTable> {
  $$EngineConfigsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$NodesTableFilterComposer get nodeId {
    final $$NodesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableFilterComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EngineConfigsTableOrderingComposer
    extends Composer<_$AppDatabase, $EngineConfigsTable> {
  $$EngineConfigsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$NodesTableOrderingComposer get nodeId {
    final $$NodesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableOrderingComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EngineConfigsTableAnnotationComposer
    extends Composer<_$AppDatabase, $EngineConfigsTable> {
  $$EngineConfigsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get engine =>
      $composableBuilder(column: $table.engine, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$NodesTableAnnotationComposer get nodeId {
    final $$NodesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.nodeId,
      referencedTable: $db.nodes,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NodesTableAnnotationComposer(
            $db: $db,
            $table: $db.nodes,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$EngineConfigsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $EngineConfigsTable,
          EngineConfig,
          $$EngineConfigsTableFilterComposer,
          $$EngineConfigsTableOrderingComposer,
          $$EngineConfigsTableAnnotationComposer,
          $$EngineConfigsTableCreateCompanionBuilder,
          $$EngineConfigsTableUpdateCompanionBuilder,
          (EngineConfig, $$EngineConfigsTableReferences),
          EngineConfig,
          PrefetchHooks Function({bool nodeId})
        > {
  $$EngineConfigsTableTableManager(_$AppDatabase db, $EngineConfigsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$EngineConfigsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$EngineConfigsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$EngineConfigsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> nodeId = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
              }) => EngineConfigsCompanion(
                id: id,
                nodeId: nodeId,
                engine: engine,
                configJson: configJson,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String nodeId,
                required String engine,
                required String configJson,
                required int updatedAt,
              }) => EngineConfigsCompanion.insert(
                id: id,
                nodeId: nodeId,
                engine: engine,
                configJson: configJson,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$EngineConfigsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({nodeId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (nodeId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.nodeId,
                                referencedTable: $$EngineConfigsTableReferences
                                    ._nodeIdTable(db),
                                referencedColumn: $$EngineConfigsTableReferences
                                    ._nodeIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$EngineConfigsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $EngineConfigsTable,
      EngineConfig,
      $$EngineConfigsTableFilterComposer,
      $$EngineConfigsTableOrderingComposer,
      $$EngineConfigsTableAnnotationComposer,
      $$EngineConfigsTableCreateCompanionBuilder,
      $$EngineConfigsTableUpdateCompanionBuilder,
      (EngineConfig, $$EngineConfigsTableReferences),
      EngineConfig,
      PrefetchHooks Function({bool nodeId})
    >;
typedef $$BaselinesTableCreateCompanionBuilder =
    BaselinesCompanion Function({
      required String id,
      required String name,
      Value<String?> locationName,
      required double centerLat,
      required double centerLon,
      required double radiusM,
      Value<String?> polygonJson,
      required int createdAt,
      Value<int> detectionCount,
      Value<int> rowid,
    });
typedef $$BaselinesTableUpdateCompanionBuilder =
    BaselinesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String?> locationName,
      Value<double> centerLat,
      Value<double> centerLon,
      Value<double> radiusM,
      Value<String?> polygonJson,
      Value<int> createdAt,
      Value<int> detectionCount,
      Value<int> rowid,
    });

final class $$BaselinesTableReferences
    extends BaseReferences<_$AppDatabase, $BaselinesTable, Baseline> {
  $$BaselinesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$BaselineDevicesTable, List<BaselineDevice>>
  _baselineDevicesRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.baselineDevices,
    aliasName: $_aliasNameGenerator(
      db.baselines.id,
      db.baselineDevices.baselineId,
    ),
  );

  $$BaselineDevicesTableProcessedTableManager get baselineDevicesRefs {
    final manager = $$BaselineDevicesTableTableManager(
      $_db,
      $_db.baselineDevices,
    ).filter((f) => f.baselineId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _baselineDevicesRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$BaselinesTableFilterComposer
    extends Composer<_$AppDatabase, $BaselinesTable> {
  $$BaselinesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get radiusM => $composableBuilder(
    column: $table.radiusM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> baselineDevicesRefs(
    Expression<bool> Function($$BaselineDevicesTableFilterComposer f) f,
  ) {
    final $$BaselineDevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.baselineDevices,
      getReferencedColumn: (t) => t.baselineId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BaselineDevicesTableFilterComposer(
            $db: $db,
            $table: $db.baselineDevices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BaselinesTableOrderingComposer
    extends Composer<_$AppDatabase, $BaselinesTable> {
  $$BaselinesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get radiusM => $composableBuilder(
    column: $table.radiusM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BaselinesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BaselinesTable> {
  $$BaselinesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get locationName => $composableBuilder(
    column: $table.locationName,
    builder: (column) => column,
  );

  GeneratedColumn<double> get centerLat =>
      $composableBuilder(column: $table.centerLat, builder: (column) => column);

  GeneratedColumn<double> get centerLon =>
      $composableBuilder(column: $table.centerLon, builder: (column) => column);

  GeneratedColumn<double> get radiusM =>
      $composableBuilder(column: $table.radiusM, builder: (column) => column);

  GeneratedColumn<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get detectionCount => $composableBuilder(
    column: $table.detectionCount,
    builder: (column) => column,
  );

  Expression<T> baselineDevicesRefs<T extends Object>(
    Expression<T> Function($$BaselineDevicesTableAnnotationComposer a) f,
  ) {
    final $$BaselineDevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.baselineDevices,
      getReferencedColumn: (t) => t.baselineId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BaselineDevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.baselineDevices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$BaselinesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BaselinesTable,
          Baseline,
          $$BaselinesTableFilterComposer,
          $$BaselinesTableOrderingComposer,
          $$BaselinesTableAnnotationComposer,
          $$BaselinesTableCreateCompanionBuilder,
          $$BaselinesTableUpdateCompanionBuilder,
          (Baseline, $$BaselinesTableReferences),
          Baseline,
          PrefetchHooks Function({bool baselineDevicesRefs})
        > {
  $$BaselinesTableTableManager(_$AppDatabase db, $BaselinesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BaselinesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BaselinesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BaselinesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String?> locationName = const Value.absent(),
                Value<double> centerLat = const Value.absent(),
                Value<double> centerLon = const Value.absent(),
                Value<double> radiusM = const Value.absent(),
                Value<String?> polygonJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> detectionCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BaselinesCompanion(
                id: id,
                name: name,
                locationName: locationName,
                centerLat: centerLat,
                centerLon: centerLon,
                radiusM: radiusM,
                polygonJson: polygonJson,
                createdAt: createdAt,
                detectionCount: detectionCount,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String?> locationName = const Value.absent(),
                required double centerLat,
                required double centerLon,
                required double radiusM,
                Value<String?> polygonJson = const Value.absent(),
                required int createdAt,
                Value<int> detectionCount = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BaselinesCompanion.insert(
                id: id,
                name: name,
                locationName: locationName,
                centerLat: centerLat,
                centerLon: centerLon,
                radiusM: radiusM,
                polygonJson: polygonJson,
                createdAt: createdAt,
                detectionCount: detectionCount,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BaselinesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({baselineDevicesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (baselineDevicesRefs) db.baselineDevices,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (baselineDevicesRefs)
                    await $_getPrefetchedData<
                      Baseline,
                      $BaselinesTable,
                      BaselineDevice
                    >(
                      currentTable: table,
                      referencedTable: $$BaselinesTableReferences
                          ._baselineDevicesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$BaselinesTableReferences(
                            db,
                            table,
                            p0,
                          ).baselineDevicesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.baselineId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$BaselinesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BaselinesTable,
      Baseline,
      $$BaselinesTableFilterComposer,
      $$BaselinesTableOrderingComposer,
      $$BaselinesTableAnnotationComposer,
      $$BaselinesTableCreateCompanionBuilder,
      $$BaselinesTableUpdateCompanionBuilder,
      (Baseline, $$BaselinesTableReferences),
      Baseline,
      PrefetchHooks Function({bool baselineDevicesRefs})
    >;
typedef $$BaselineDevicesTableCreateCompanionBuilder =
    BaselineDevicesCompanion Function({
      Value<int> id,
      required String baselineId,
      required String macAddress,
      Value<String> deviceName,
      required String engine,
      Value<int?> rssiAvg,
      required int firstSeen,
      Value<String?> fingerprintId,
    });
typedef $$BaselineDevicesTableUpdateCompanionBuilder =
    BaselineDevicesCompanion Function({
      Value<int> id,
      Value<String> baselineId,
      Value<String> macAddress,
      Value<String> deviceName,
      Value<String> engine,
      Value<int?> rssiAvg,
      Value<int> firstSeen,
      Value<String?> fingerprintId,
    });

final class $$BaselineDevicesTableReferences
    extends
        BaseReferences<_$AppDatabase, $BaselineDevicesTable, BaselineDevice> {
  $$BaselineDevicesTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $BaselinesTable _baselineIdTable(_$AppDatabase db) =>
      db.baselines.createAlias(
        $_aliasNameGenerator(db.baselineDevices.baselineId, db.baselines.id),
      );

  $$BaselinesTableProcessedTableManager get baselineId {
    final $_column = $_itemColumn<String>('baseline_id')!;

    final manager = $$BaselinesTableTableManager(
      $_db,
      $_db.baselines,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_baselineIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$BaselineDevicesTableFilterComposer
    extends Composer<_$AppDatabase, $BaselineDevicesTable> {
  $$BaselineDevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rssiAvg => $composableBuilder(
    column: $table.rssiAvg,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fingerprintId => $composableBuilder(
    column: $table.fingerprintId,
    builder: (column) => ColumnFilters(column),
  );

  $$BaselinesTableFilterComposer get baselineId {
    final $$BaselinesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.baselineId,
      referencedTable: $db.baselines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BaselinesTableFilterComposer(
            $db: $db,
            $table: $db.baselines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BaselineDevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $BaselineDevicesTable> {
  $$BaselineDevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get engine => $composableBuilder(
    column: $table.engine,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rssiAvg => $composableBuilder(
    column: $table.rssiAvg,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fingerprintId => $composableBuilder(
    column: $table.fingerprintId,
    builder: (column) => ColumnOrderings(column),
  );

  $$BaselinesTableOrderingComposer get baselineId {
    final $$BaselinesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.baselineId,
      referencedTable: $db.baselines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BaselinesTableOrderingComposer(
            $db: $db,
            $table: $db.baselines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BaselineDevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $BaselineDevicesTable> {
  $$BaselineDevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get deviceName => $composableBuilder(
    column: $table.deviceName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get engine =>
      $composableBuilder(column: $table.engine, builder: (column) => column);

  GeneratedColumn<int> get rssiAvg =>
      $composableBuilder(column: $table.rssiAvg, builder: (column) => column);

  GeneratedColumn<int> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<String> get fingerprintId => $composableBuilder(
    column: $table.fingerprintId,
    builder: (column) => column,
  );

  $$BaselinesTableAnnotationComposer get baselineId {
    final $$BaselinesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.baselineId,
      referencedTable: $db.baselines,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$BaselinesTableAnnotationComposer(
            $db: $db,
            $table: $db.baselines,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$BaselineDevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $BaselineDevicesTable,
          BaselineDevice,
          $$BaselineDevicesTableFilterComposer,
          $$BaselineDevicesTableOrderingComposer,
          $$BaselineDevicesTableAnnotationComposer,
          $$BaselineDevicesTableCreateCompanionBuilder,
          $$BaselineDevicesTableUpdateCompanionBuilder,
          (BaselineDevice, $$BaselineDevicesTableReferences),
          BaselineDevice,
          PrefetchHooks Function({bool baselineId})
        > {
  $$BaselineDevicesTableTableManager(
    _$AppDatabase db,
    $BaselineDevicesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BaselineDevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BaselineDevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BaselineDevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> baselineId = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<String> deviceName = const Value.absent(),
                Value<String> engine = const Value.absent(),
                Value<int?> rssiAvg = const Value.absent(),
                Value<int> firstSeen = const Value.absent(),
                Value<String?> fingerprintId = const Value.absent(),
              }) => BaselineDevicesCompanion(
                id: id,
                baselineId: baselineId,
                macAddress: macAddress,
                deviceName: deviceName,
                engine: engine,
                rssiAvg: rssiAvg,
                firstSeen: firstSeen,
                fingerprintId: fingerprintId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String baselineId,
                required String macAddress,
                Value<String> deviceName = const Value.absent(),
                required String engine,
                Value<int?> rssiAvg = const Value.absent(),
                required int firstSeen,
                Value<String?> fingerprintId = const Value.absent(),
              }) => BaselineDevicesCompanion.insert(
                id: id,
                baselineId: baselineId,
                macAddress: macAddress,
                deviceName: deviceName,
                engine: engine,
                rssiAvg: rssiAvg,
                firstSeen: firstSeen,
                fingerprintId: fingerprintId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$BaselineDevicesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({baselineId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (baselineId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.baselineId,
                                referencedTable:
                                    $$BaselineDevicesTableReferences
                                        ._baselineIdTable(db),
                                referencedColumn:
                                    $$BaselineDevicesTableReferences
                                        ._baselineIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$BaselineDevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $BaselineDevicesTable,
      BaselineDevice,
      $$BaselineDevicesTableFilterComposer,
      $$BaselineDevicesTableOrderingComposer,
      $$BaselineDevicesTableAnnotationComposer,
      $$BaselineDevicesTableCreateCompanionBuilder,
      $$BaselineDevicesTableUpdateCompanionBuilder,
      (BaselineDevice, $$BaselineDevicesTableReferences),
      BaselineDevice,
      PrefetchHooks Function({bool baselineId})
    >;
typedef $$FingerprintsTableCreateCompanionBuilder =
    FingerprintsCompanion Function({
      required String id,
      required String primaryMac,
      Value<double?> advIntervalMs,
      Value<int?> txPower,
      Value<String?> serviceUuids,
      Value<String?> mfgDataStructure,
      Value<String?> rssiEnvelope,
      Value<double?> probeIntervalMs,
      Value<String?> ieOrder,
      required int createdAt,
      required int updatedAt,
      Value<int> rowid,
    });
typedef $$FingerprintsTableUpdateCompanionBuilder =
    FingerprintsCompanion Function({
      Value<String> id,
      Value<String> primaryMac,
      Value<double?> advIntervalMs,
      Value<int?> txPower,
      Value<String?> serviceUuids,
      Value<String?> mfgDataStructure,
      Value<String?> rssiEnvelope,
      Value<double?> probeIntervalMs,
      Value<String?> ieOrder,
      Value<int> createdAt,
      Value<int> updatedAt,
      Value<int> rowid,
    });

final class $$FingerprintsTableReferences
    extends BaseReferences<_$AppDatabase, $FingerprintsTable, Fingerprint> {
  $$FingerprintsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$FingerprintMacsTable, List<FingerprintMac>>
  _fingerprintMacsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.fingerprintMacs,
    aliasName: $_aliasNameGenerator(
      db.fingerprints.id,
      db.fingerprintMacs.fingerprintId,
    ),
  );

  $$FingerprintMacsTableProcessedTableManager get fingerprintMacsRefs {
    final manager = $$FingerprintMacsTableTableManager(
      $_db,
      $_db.fingerprintMacs,
    ).filter((f) => f.fingerprintId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _fingerprintMacsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$FingerprintsTableFilterComposer
    extends Composer<_$AppDatabase, $FingerprintsTable> {
  $$FingerprintsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get primaryMac => $composableBuilder(
    column: $table.primaryMac,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get advIntervalMs => $composableBuilder(
    column: $table.advIntervalMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get txPower => $composableBuilder(
    column: $table.txPower,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serviceUuids => $composableBuilder(
    column: $table.serviceUuids,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mfgDataStructure => $composableBuilder(
    column: $table.mfgDataStructure,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rssiEnvelope => $composableBuilder(
    column: $table.rssiEnvelope,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get probeIntervalMs => $composableBuilder(
    column: $table.probeIntervalMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ieOrder => $composableBuilder(
    column: $table.ieOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> fingerprintMacsRefs(
    Expression<bool> Function($$FingerprintMacsTableFilterComposer f) f,
  ) {
    final $$FingerprintMacsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fingerprintMacs,
      getReferencedColumn: (t) => t.fingerprintId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FingerprintMacsTableFilterComposer(
            $db: $db,
            $table: $db.fingerprintMacs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FingerprintsTableOrderingComposer
    extends Composer<_$AppDatabase, $FingerprintsTable> {
  $$FingerprintsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get primaryMac => $composableBuilder(
    column: $table.primaryMac,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get advIntervalMs => $composableBuilder(
    column: $table.advIntervalMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get txPower => $composableBuilder(
    column: $table.txPower,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serviceUuids => $composableBuilder(
    column: $table.serviceUuids,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mfgDataStructure => $composableBuilder(
    column: $table.mfgDataStructure,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rssiEnvelope => $composableBuilder(
    column: $table.rssiEnvelope,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get probeIntervalMs => $composableBuilder(
    column: $table.probeIntervalMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ieOrder => $composableBuilder(
    column: $table.ieOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FingerprintsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FingerprintsTable> {
  $$FingerprintsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get primaryMac => $composableBuilder(
    column: $table.primaryMac,
    builder: (column) => column,
  );

  GeneratedColumn<double> get advIntervalMs => $composableBuilder(
    column: $table.advIntervalMs,
    builder: (column) => column,
  );

  GeneratedColumn<int> get txPower =>
      $composableBuilder(column: $table.txPower, builder: (column) => column);

  GeneratedColumn<String> get serviceUuids => $composableBuilder(
    column: $table.serviceUuids,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mfgDataStructure => $composableBuilder(
    column: $table.mfgDataStructure,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rssiEnvelope => $composableBuilder(
    column: $table.rssiEnvelope,
    builder: (column) => column,
  );

  GeneratedColumn<double> get probeIntervalMs => $composableBuilder(
    column: $table.probeIntervalMs,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ieOrder =>
      $composableBuilder(column: $table.ieOrder, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> fingerprintMacsRefs<T extends Object>(
    Expression<T> Function($$FingerprintMacsTableAnnotationComposer a) f,
  ) {
    final $$FingerprintMacsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.fingerprintMacs,
      getReferencedColumn: (t) => t.fingerprintId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FingerprintMacsTableAnnotationComposer(
            $db: $db,
            $table: $db.fingerprintMacs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$FingerprintsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FingerprintsTable,
          Fingerprint,
          $$FingerprintsTableFilterComposer,
          $$FingerprintsTableOrderingComposer,
          $$FingerprintsTableAnnotationComposer,
          $$FingerprintsTableCreateCompanionBuilder,
          $$FingerprintsTableUpdateCompanionBuilder,
          (Fingerprint, $$FingerprintsTableReferences),
          Fingerprint,
          PrefetchHooks Function({bool fingerprintMacsRefs})
        > {
  $$FingerprintsTableTableManager(_$AppDatabase db, $FingerprintsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FingerprintsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FingerprintsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FingerprintsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> primaryMac = const Value.absent(),
                Value<double?> advIntervalMs = const Value.absent(),
                Value<int?> txPower = const Value.absent(),
                Value<String?> serviceUuids = const Value.absent(),
                Value<String?> mfgDataStructure = const Value.absent(),
                Value<String?> rssiEnvelope = const Value.absent(),
                Value<double?> probeIntervalMs = const Value.absent(),
                Value<String?> ieOrder = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FingerprintsCompanion(
                id: id,
                primaryMac: primaryMac,
                advIntervalMs: advIntervalMs,
                txPower: txPower,
                serviceUuids: serviceUuids,
                mfgDataStructure: mfgDataStructure,
                rssiEnvelope: rssiEnvelope,
                probeIntervalMs: probeIntervalMs,
                ieOrder: ieOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String primaryMac,
                Value<double?> advIntervalMs = const Value.absent(),
                Value<int?> txPower = const Value.absent(),
                Value<String?> serviceUuids = const Value.absent(),
                Value<String?> mfgDataStructure = const Value.absent(),
                Value<String?> rssiEnvelope = const Value.absent(),
                Value<double?> probeIntervalMs = const Value.absent(),
                Value<String?> ieOrder = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => FingerprintsCompanion.insert(
                id: id,
                primaryMac: primaryMac,
                advIntervalMs: advIntervalMs,
                txPower: txPower,
                serviceUuids: serviceUuids,
                mfgDataStructure: mfgDataStructure,
                rssiEnvelope: rssiEnvelope,
                probeIntervalMs: probeIntervalMs,
                ieOrder: ieOrder,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FingerprintsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fingerprintMacsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (fingerprintMacsRefs) db.fingerprintMacs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (fingerprintMacsRefs)
                    await $_getPrefetchedData<
                      Fingerprint,
                      $FingerprintsTable,
                      FingerprintMac
                    >(
                      currentTable: table,
                      referencedTable: $$FingerprintsTableReferences
                          ._fingerprintMacsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$FingerprintsTableReferences(
                            db,
                            table,
                            p0,
                          ).fingerprintMacsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.fingerprintId == item.id,
                          ),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$FingerprintsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FingerprintsTable,
      Fingerprint,
      $$FingerprintsTableFilterComposer,
      $$FingerprintsTableOrderingComposer,
      $$FingerprintsTableAnnotationComposer,
      $$FingerprintsTableCreateCompanionBuilder,
      $$FingerprintsTableUpdateCompanionBuilder,
      (Fingerprint, $$FingerprintsTableReferences),
      Fingerprint,
      PrefetchHooks Function({bool fingerprintMacsRefs})
    >;
typedef $$FingerprintMacsTableCreateCompanionBuilder =
    FingerprintMacsCompanion Function({
      Value<int> id,
      required String fingerprintId,
      required String macAddress,
      required int firstSeen,
      required int lastSeen,
    });
typedef $$FingerprintMacsTableUpdateCompanionBuilder =
    FingerprintMacsCompanion Function({
      Value<int> id,
      Value<String> fingerprintId,
      Value<String> macAddress,
      Value<int> firstSeen,
      Value<int> lastSeen,
    });

final class $$FingerprintMacsTableReferences
    extends
        BaseReferences<_$AppDatabase, $FingerprintMacsTable, FingerprintMac> {
  $$FingerprintMacsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $FingerprintsTable _fingerprintIdTable(_$AppDatabase db) =>
      db.fingerprints.createAlias(
        $_aliasNameGenerator(
          db.fingerprintMacs.fingerprintId,
          db.fingerprints.id,
        ),
      );

  $$FingerprintsTableProcessedTableManager get fingerprintId {
    final $_column = $_itemColumn<String>('fingerprint_id')!;

    final manager = $$FingerprintsTableTableManager(
      $_db,
      $_db.fingerprints,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_fingerprintIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$FingerprintMacsTableFilterComposer
    extends Composer<_$AppDatabase, $FingerprintMacsTable> {
  $$FingerprintMacsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  $$FingerprintsTableFilterComposer get fingerprintId {
    final $$FingerprintsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fingerprintId,
      referencedTable: $db.fingerprints,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FingerprintsTableFilterComposer(
            $db: $db,
            $table: $db.fingerprints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FingerprintMacsTableOrderingComposer
    extends Composer<_$AppDatabase, $FingerprintMacsTable> {
  $$FingerprintMacsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  $$FingerprintsTableOrderingComposer get fingerprintId {
    final $$FingerprintsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fingerprintId,
      referencedTable: $db.fingerprints,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FingerprintsTableOrderingComposer(
            $db: $db,
            $table: $db.fingerprints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FingerprintMacsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FingerprintMacsTable> {
  $$FingerprintMacsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  $$FingerprintsTableAnnotationComposer get fingerprintId {
    final $$FingerprintsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.fingerprintId,
      referencedTable: $db.fingerprints,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$FingerprintsTableAnnotationComposer(
            $db: $db,
            $table: $db.fingerprints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$FingerprintMacsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FingerprintMacsTable,
          FingerprintMac,
          $$FingerprintMacsTableFilterComposer,
          $$FingerprintMacsTableOrderingComposer,
          $$FingerprintMacsTableAnnotationComposer,
          $$FingerprintMacsTableCreateCompanionBuilder,
          $$FingerprintMacsTableUpdateCompanionBuilder,
          (FingerprintMac, $$FingerprintMacsTableReferences),
          FingerprintMac,
          PrefetchHooks Function({bool fingerprintId})
        > {
  $$FingerprintMacsTableTableManager(
    _$AppDatabase db,
    $FingerprintMacsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FingerprintMacsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FingerprintMacsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FingerprintMacsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> fingerprintId = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<int> firstSeen = const Value.absent(),
                Value<int> lastSeen = const Value.absent(),
              }) => FingerprintMacsCompanion(
                id: id,
                fingerprintId: fingerprintId,
                macAddress: macAddress,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String fingerprintId,
                required String macAddress,
                required int firstSeen,
                required int lastSeen,
              }) => FingerprintMacsCompanion.insert(
                id: id,
                fingerprintId: fingerprintId,
                macAddress: macAddress,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$FingerprintMacsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({fingerprintId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (fingerprintId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.fingerprintId,
                                referencedTable:
                                    $$FingerprintMacsTableReferences
                                        ._fingerprintIdTable(db),
                                referencedColumn:
                                    $$FingerprintMacsTableReferences
                                        ._fingerprintIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$FingerprintMacsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FingerprintMacsTable,
      FingerprintMac,
      $$FingerprintMacsTableFilterComposer,
      $$FingerprintMacsTableOrderingComposer,
      $$FingerprintMacsTableAnnotationComposer,
      $$FingerprintMacsTableCreateCompanionBuilder,
      $$FingerprintMacsTableUpdateCompanionBuilder,
      (FingerprintMac, $$FingerprintMacsTableReferences),
      FingerprintMac,
      PrefetchHooks Function({bool fingerprintId})
    >;
typedef $$GeofencesTableCreateCompanionBuilder =
    GeofencesCompanion Function({
      required String id,
      required String name,
      required String zoneType,
      Value<double?> centerLat,
      Value<double?> centerLon,
      Value<double?> radiusM,
      Value<String?> polygonJson,
      Value<String?> corridorJson,
      Value<bool> alertOnFlock,
      Value<bool> alertOnDrone,
      Value<bool> alertOnNew,
      Value<bool> alertOnStalking,
      Value<String> alertMode,
      Value<bool> enabled,
      Value<bool> excludeFromWardrive,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$GeofencesTableUpdateCompanionBuilder =
    GeofencesCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> zoneType,
      Value<double?> centerLat,
      Value<double?> centerLon,
      Value<double?> radiusM,
      Value<String?> polygonJson,
      Value<String?> corridorJson,
      Value<bool> alertOnFlock,
      Value<bool> alertOnDrone,
      Value<bool> alertOnNew,
      Value<bool> alertOnStalking,
      Value<String> alertMode,
      Value<bool> enabled,
      Value<bool> excludeFromWardrive,
      Value<int> createdAt,
      Value<int> rowid,
    });

final class $$GeofencesTableReferences
    extends BaseReferences<_$AppDatabase, $GeofencesTable, Geofence> {
  $$GeofencesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$GeofenceAlertsTable, List<GeofenceAlert>>
  _geofenceAlertsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.geofenceAlerts,
    aliasName: $_aliasNameGenerator(
      db.geofences.id,
      db.geofenceAlerts.geofenceId,
    ),
  );

  $$GeofenceAlertsTableProcessedTableManager get geofenceAlertsRefs {
    final manager = $$GeofenceAlertsTableTableManager(
      $_db,
      $_db.geofenceAlerts,
    ).filter((f) => f.geofenceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_geofenceAlertsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$GeofencesTableFilterComposer
    extends Composer<_$AppDatabase, $GeofencesTable> {
  $$GeofencesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get zoneType => $composableBuilder(
    column: $table.zoneType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get radiusM => $composableBuilder(
    column: $table.radiusM,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get corridorJson => $composableBuilder(
    column: $table.corridorJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get alertOnFlock => $composableBuilder(
    column: $table.alertOnFlock,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get alertOnDrone => $composableBuilder(
    column: $table.alertOnDrone,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get alertOnNew => $composableBuilder(
    column: $table.alertOnNew,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get alertOnStalking => $composableBuilder(
    column: $table.alertOnStalking,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alertMode => $composableBuilder(
    column: $table.alertMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get excludeFromWardrive => $composableBuilder(
    column: $table.excludeFromWardrive,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> geofenceAlertsRefs(
    Expression<bool> Function($$GeofenceAlertsTableFilterComposer f) f,
  ) {
    final $$GeofenceAlertsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.geofenceAlerts,
      getReferencedColumn: (t) => t.geofenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GeofenceAlertsTableFilterComposer(
            $db: $db,
            $table: $db.geofenceAlerts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GeofencesTableOrderingComposer
    extends Composer<_$AppDatabase, $GeofencesTable> {
  $$GeofencesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get zoneType => $composableBuilder(
    column: $table.zoneType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLat => $composableBuilder(
    column: $table.centerLat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get centerLon => $composableBuilder(
    column: $table.centerLon,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get radiusM => $composableBuilder(
    column: $table.radiusM,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get corridorJson => $composableBuilder(
    column: $table.corridorJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get alertOnFlock => $composableBuilder(
    column: $table.alertOnFlock,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get alertOnDrone => $composableBuilder(
    column: $table.alertOnDrone,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get alertOnNew => $composableBuilder(
    column: $table.alertOnNew,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get alertOnStalking => $composableBuilder(
    column: $table.alertOnStalking,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alertMode => $composableBuilder(
    column: $table.alertMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get enabled => $composableBuilder(
    column: $table.enabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get excludeFromWardrive => $composableBuilder(
    column: $table.excludeFromWardrive,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GeofencesTableAnnotationComposer
    extends Composer<_$AppDatabase, $GeofencesTable> {
  $$GeofencesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get zoneType =>
      $composableBuilder(column: $table.zoneType, builder: (column) => column);

  GeneratedColumn<double> get centerLat =>
      $composableBuilder(column: $table.centerLat, builder: (column) => column);

  GeneratedColumn<double> get centerLon =>
      $composableBuilder(column: $table.centerLon, builder: (column) => column);

  GeneratedColumn<double> get radiusM =>
      $composableBuilder(column: $table.radiusM, builder: (column) => column);

  GeneratedColumn<String> get polygonJson => $composableBuilder(
    column: $table.polygonJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get corridorJson => $composableBuilder(
    column: $table.corridorJson,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get alertOnFlock => $composableBuilder(
    column: $table.alertOnFlock,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get alertOnDrone => $composableBuilder(
    column: $table.alertOnDrone,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get alertOnNew => $composableBuilder(
    column: $table.alertOnNew,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get alertOnStalking => $composableBuilder(
    column: $table.alertOnStalking,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alertMode =>
      $composableBuilder(column: $table.alertMode, builder: (column) => column);

  GeneratedColumn<bool> get enabled =>
      $composableBuilder(column: $table.enabled, builder: (column) => column);

  GeneratedColumn<bool> get excludeFromWardrive => $composableBuilder(
    column: $table.excludeFromWardrive,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> geofenceAlertsRefs<T extends Object>(
    Expression<T> Function($$GeofenceAlertsTableAnnotationComposer a) f,
  ) {
    final $$GeofenceAlertsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.geofenceAlerts,
      getReferencedColumn: (t) => t.geofenceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GeofenceAlertsTableAnnotationComposer(
            $db: $db,
            $table: $db.geofenceAlerts,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$GeofencesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GeofencesTable,
          Geofence,
          $$GeofencesTableFilterComposer,
          $$GeofencesTableOrderingComposer,
          $$GeofencesTableAnnotationComposer,
          $$GeofencesTableCreateCompanionBuilder,
          $$GeofencesTableUpdateCompanionBuilder,
          (Geofence, $$GeofencesTableReferences),
          Geofence,
          PrefetchHooks Function({bool geofenceAlertsRefs})
        > {
  $$GeofencesTableTableManager(_$AppDatabase db, $GeofencesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GeofencesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GeofencesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GeofencesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> zoneType = const Value.absent(),
                Value<double?> centerLat = const Value.absent(),
                Value<double?> centerLon = const Value.absent(),
                Value<double?> radiusM = const Value.absent(),
                Value<String?> polygonJson = const Value.absent(),
                Value<String?> corridorJson = const Value.absent(),
                Value<bool> alertOnFlock = const Value.absent(),
                Value<bool> alertOnDrone = const Value.absent(),
                Value<bool> alertOnNew = const Value.absent(),
                Value<bool> alertOnStalking = const Value.absent(),
                Value<String> alertMode = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> excludeFromWardrive = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GeofencesCompanion(
                id: id,
                name: name,
                zoneType: zoneType,
                centerLat: centerLat,
                centerLon: centerLon,
                radiusM: radiusM,
                polygonJson: polygonJson,
                corridorJson: corridorJson,
                alertOnFlock: alertOnFlock,
                alertOnDrone: alertOnDrone,
                alertOnNew: alertOnNew,
                alertOnStalking: alertOnStalking,
                alertMode: alertMode,
                enabled: enabled,
                excludeFromWardrive: excludeFromWardrive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String zoneType,
                Value<double?> centerLat = const Value.absent(),
                Value<double?> centerLon = const Value.absent(),
                Value<double?> radiusM = const Value.absent(),
                Value<String?> polygonJson = const Value.absent(),
                Value<String?> corridorJson = const Value.absent(),
                Value<bool> alertOnFlock = const Value.absent(),
                Value<bool> alertOnDrone = const Value.absent(),
                Value<bool> alertOnNew = const Value.absent(),
                Value<bool> alertOnStalking = const Value.absent(),
                Value<String> alertMode = const Value.absent(),
                Value<bool> enabled = const Value.absent(),
                Value<bool> excludeFromWardrive = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => GeofencesCompanion.insert(
                id: id,
                name: name,
                zoneType: zoneType,
                centerLat: centerLat,
                centerLon: centerLon,
                radiusM: radiusM,
                polygonJson: polygonJson,
                corridorJson: corridorJson,
                alertOnFlock: alertOnFlock,
                alertOnDrone: alertOnDrone,
                alertOnNew: alertOnNew,
                alertOnStalking: alertOnStalking,
                alertMode: alertMode,
                enabled: enabled,
                excludeFromWardrive: excludeFromWardrive,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GeofencesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({geofenceAlertsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (geofenceAlertsRefs) db.geofenceAlerts,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (geofenceAlertsRefs)
                    await $_getPrefetchedData<
                      Geofence,
                      $GeofencesTable,
                      GeofenceAlert
                    >(
                      currentTable: table,
                      referencedTable: $$GeofencesTableReferences
                          ._geofenceAlertsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$GeofencesTableReferences(
                            db,
                            table,
                            p0,
                          ).geofenceAlertsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.geofenceId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$GeofencesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GeofencesTable,
      Geofence,
      $$GeofencesTableFilterComposer,
      $$GeofencesTableOrderingComposer,
      $$GeofencesTableAnnotationComposer,
      $$GeofencesTableCreateCompanionBuilder,
      $$GeofencesTableUpdateCompanionBuilder,
      (Geofence, $$GeofencesTableReferences),
      Geofence,
      PrefetchHooks Function({bool geofenceAlertsRefs})
    >;
typedef $$GeofenceAlertsTableCreateCompanionBuilder =
    GeofenceAlertsCompanion Function({
      Value<int> id,
      required String geofenceId,
      Value<int?> detectionId,
      required String alertType,
      required String macAddress,
      required int triggeredAt,
      Value<bool> acknowledged,
    });
typedef $$GeofenceAlertsTableUpdateCompanionBuilder =
    GeofenceAlertsCompanion Function({
      Value<int> id,
      Value<String> geofenceId,
      Value<int?> detectionId,
      Value<String> alertType,
      Value<String> macAddress,
      Value<int> triggeredAt,
      Value<bool> acknowledged,
    });

final class $$GeofenceAlertsTableReferences
    extends BaseReferences<_$AppDatabase, $GeofenceAlertsTable, GeofenceAlert> {
  $$GeofenceAlertsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $GeofencesTable _geofenceIdTable(_$AppDatabase db) =>
      db.geofences.createAlias(
        $_aliasNameGenerator(db.geofenceAlerts.geofenceId, db.geofences.id),
      );

  $$GeofencesTableProcessedTableManager get geofenceId {
    final $_column = $_itemColumn<String>('geofence_id')!;

    final manager = $$GeofencesTableTableManager(
      $_db,
      $_db.geofences,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_geofenceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GeofenceAlertsTableFilterComposer
    extends Composer<_$AppDatabase, $GeofenceAlertsTable> {
  $$GeofenceAlertsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get detectionId => $composableBuilder(
    column: $table.detectionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get alertType => $composableBuilder(
    column: $table.alertType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnFilters(column),
  );

  $$GeofencesTableFilterComposer get geofenceId {
    final $$GeofencesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.geofenceId,
      referencedTable: $db.geofences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GeofencesTableFilterComposer(
            $db: $db,
            $table: $db.geofences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GeofenceAlertsTableOrderingComposer
    extends Composer<_$AppDatabase, $GeofenceAlertsTable> {
  $$GeofenceAlertsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get detectionId => $composableBuilder(
    column: $table.detectionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get alertType => $composableBuilder(
    column: $table.alertType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => ColumnOrderings(column),
  );

  $$GeofencesTableOrderingComposer get geofenceId {
    final $$GeofencesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.geofenceId,
      referencedTable: $db.geofences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GeofencesTableOrderingComposer(
            $db: $db,
            $table: $db.geofences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GeofenceAlertsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GeofenceAlertsTable> {
  $$GeofenceAlertsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get detectionId => $composableBuilder(
    column: $table.detectionId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get alertType =>
      $composableBuilder(column: $table.alertType, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get triggeredAt => $composableBuilder(
    column: $table.triggeredAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get acknowledged => $composableBuilder(
    column: $table.acknowledged,
    builder: (column) => column,
  );

  $$GeofencesTableAnnotationComposer get geofenceId {
    final $$GeofencesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.geofenceId,
      referencedTable: $db.geofences,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GeofencesTableAnnotationComposer(
            $db: $db,
            $table: $db.geofences,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GeofenceAlertsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GeofenceAlertsTable,
          GeofenceAlert,
          $$GeofenceAlertsTableFilterComposer,
          $$GeofenceAlertsTableOrderingComposer,
          $$GeofenceAlertsTableAnnotationComposer,
          $$GeofenceAlertsTableCreateCompanionBuilder,
          $$GeofenceAlertsTableUpdateCompanionBuilder,
          (GeofenceAlert, $$GeofenceAlertsTableReferences),
          GeofenceAlert,
          PrefetchHooks Function({bool geofenceId})
        > {
  $$GeofenceAlertsTableTableManager(
    _$AppDatabase db,
    $GeofenceAlertsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GeofenceAlertsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GeofenceAlertsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GeofenceAlertsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> geofenceId = const Value.absent(),
                Value<int?> detectionId = const Value.absent(),
                Value<String> alertType = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<int> triggeredAt = const Value.absent(),
                Value<bool> acknowledged = const Value.absent(),
              }) => GeofenceAlertsCompanion(
                id: id,
                geofenceId: geofenceId,
                detectionId: detectionId,
                alertType: alertType,
                macAddress: macAddress,
                triggeredAt: triggeredAt,
                acknowledged: acknowledged,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String geofenceId,
                Value<int?> detectionId = const Value.absent(),
                required String alertType,
                required String macAddress,
                required int triggeredAt,
                Value<bool> acknowledged = const Value.absent(),
              }) => GeofenceAlertsCompanion.insert(
                id: id,
                geofenceId: geofenceId,
                detectionId: detectionId,
                alertType: alertType,
                macAddress: macAddress,
                triggeredAt: triggeredAt,
                acknowledged: acknowledged,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GeofenceAlertsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({geofenceId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (geofenceId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.geofenceId,
                                referencedTable: $$GeofenceAlertsTableReferences
                                    ._geofenceIdTable(db),
                                referencedColumn:
                                    $$GeofenceAlertsTableReferences
                                        ._geofenceIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GeofenceAlertsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GeofenceAlertsTable,
      GeofenceAlert,
      $$GeofenceAlertsTableFilterComposer,
      $$GeofenceAlertsTableOrderingComposer,
      $$GeofenceAlertsTableAnnotationComposer,
      $$GeofenceAlertsTableCreateCompanionBuilder,
      $$GeofenceAlertsTableUpdateCompanionBuilder,
      (GeofenceAlert, $$GeofenceAlertsTableReferences),
      GeofenceAlert,
      PrefetchHooks Function({bool geofenceId})
    >;
typedef $$StalkingSuspectsTableCreateCompanionBuilder =
    StalkingSuspectsCompanion Function({
      Value<int> id,
      required String macAddress,
      required int sessionsSeen,
      required int locationsSeen,
      required double stalkingScore,
      required int firstFlagged,
      required int lastSeen,
      Value<String> status,
      Value<bool> whitelisted,
    });
typedef $$StalkingSuspectsTableUpdateCompanionBuilder =
    StalkingSuspectsCompanion Function({
      Value<int> id,
      Value<String> macAddress,
      Value<int> sessionsSeen,
      Value<int> locationsSeen,
      Value<double> stalkingScore,
      Value<int> firstFlagged,
      Value<int> lastSeen,
      Value<String> status,
      Value<bool> whitelisted,
    });

class $$StalkingSuspectsTableFilterComposer
    extends Composer<_$AppDatabase, $StalkingSuspectsTable> {
  $$StalkingSuspectsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sessionsSeen => $composableBuilder(
    column: $table.sessionsSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get locationsSeen => $composableBuilder(
    column: $table.locationsSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stalkingScore => $composableBuilder(
    column: $table.stalkingScore,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get firstFlagged => $composableBuilder(
    column: $table.firstFlagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get whitelisted => $composableBuilder(
    column: $table.whitelisted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$StalkingSuspectsTableOrderingComposer
    extends Composer<_$AppDatabase, $StalkingSuspectsTable> {
  $$StalkingSuspectsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sessionsSeen => $composableBuilder(
    column: $table.sessionsSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get locationsSeen => $composableBuilder(
    column: $table.locationsSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stalkingScore => $composableBuilder(
    column: $table.stalkingScore,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get firstFlagged => $composableBuilder(
    column: $table.firstFlagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get whitelisted => $composableBuilder(
    column: $table.whitelisted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$StalkingSuspectsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StalkingSuspectsTable> {
  $$StalkingSuspectsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get macAddress => $composableBuilder(
    column: $table.macAddress,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sessionsSeen => $composableBuilder(
    column: $table.sessionsSeen,
    builder: (column) => column,
  );

  GeneratedColumn<int> get locationsSeen => $composableBuilder(
    column: $table.locationsSeen,
    builder: (column) => column,
  );

  GeneratedColumn<double> get stalkingScore => $composableBuilder(
    column: $table.stalkingScore,
    builder: (column) => column,
  );

  GeneratedColumn<int> get firstFlagged => $composableBuilder(
    column: $table.firstFlagged,
    builder: (column) => column,
  );

  GeneratedColumn<int> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<bool> get whitelisted => $composableBuilder(
    column: $table.whitelisted,
    builder: (column) => column,
  );
}

class $$StalkingSuspectsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StalkingSuspectsTable,
          StalkingSuspect,
          $$StalkingSuspectsTableFilterComposer,
          $$StalkingSuspectsTableOrderingComposer,
          $$StalkingSuspectsTableAnnotationComposer,
          $$StalkingSuspectsTableCreateCompanionBuilder,
          $$StalkingSuspectsTableUpdateCompanionBuilder,
          (
            StalkingSuspect,
            BaseReferences<
              _$AppDatabase,
              $StalkingSuspectsTable,
              StalkingSuspect
            >,
          ),
          StalkingSuspect,
          PrefetchHooks Function()
        > {
  $$StalkingSuspectsTableTableManager(
    _$AppDatabase db,
    $StalkingSuspectsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StalkingSuspectsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StalkingSuspectsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StalkingSuspectsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> macAddress = const Value.absent(),
                Value<int> sessionsSeen = const Value.absent(),
                Value<int> locationsSeen = const Value.absent(),
                Value<double> stalkingScore = const Value.absent(),
                Value<int> firstFlagged = const Value.absent(),
                Value<int> lastSeen = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<bool> whitelisted = const Value.absent(),
              }) => StalkingSuspectsCompanion(
                id: id,
                macAddress: macAddress,
                sessionsSeen: sessionsSeen,
                locationsSeen: locationsSeen,
                stalkingScore: stalkingScore,
                firstFlagged: firstFlagged,
                lastSeen: lastSeen,
                status: status,
                whitelisted: whitelisted,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String macAddress,
                required int sessionsSeen,
                required int locationsSeen,
                required double stalkingScore,
                required int firstFlagged,
                required int lastSeen,
                Value<String> status = const Value.absent(),
                Value<bool> whitelisted = const Value.absent(),
              }) => StalkingSuspectsCompanion.insert(
                id: id,
                macAddress: macAddress,
                sessionsSeen: sessionsSeen,
                locationsSeen: locationsSeen,
                stalkingScore: stalkingScore,
                firstFlagged: firstFlagged,
                lastSeen: lastSeen,
                status: status,
                whitelisted: whitelisted,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$StalkingSuspectsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StalkingSuspectsTable,
      StalkingSuspect,
      $$StalkingSuspectsTableFilterComposer,
      $$StalkingSuspectsTableOrderingComposer,
      $$StalkingSuspectsTableAnnotationComposer,
      $$StalkingSuspectsTableCreateCompanionBuilder,
      $$StalkingSuspectsTableUpdateCompanionBuilder,
      (
        StalkingSuspect,
        BaseReferences<_$AppDatabase, $StalkingSuspectsTable, StalkingSuspect>,
      ),
      StalkingSuspect,
      PrefetchHooks Function()
    >;
typedef $$WigleUploadsTableCreateCompanionBuilder =
    WigleUploadsCompanion Function({
      Value<int> id,
      Value<String?> sessionId,
      required int uploadedAt,
      Value<String?> transactionId,
      Value<int?> networksAccepted,
      Value<int?> networksNew,
      required String status,
    });
typedef $$WigleUploadsTableUpdateCompanionBuilder =
    WigleUploadsCompanion Function({
      Value<int> id,
      Value<String?> sessionId,
      Value<int> uploadedAt,
      Value<String?> transactionId,
      Value<int?> networksAccepted,
      Value<int?> networksNew,
      Value<String> status,
    });

final class $$WigleUploadsTableReferences
    extends BaseReferences<_$AppDatabase, $WigleUploadsTable, WigleUpload> {
  $$WigleUploadsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SessionsTable _sessionIdTable(_$AppDatabase db) =>
      db.sessions.createAlias(
        $_aliasNameGenerator(db.wigleUploads.sessionId, db.sessions.id),
      );

  $$SessionsTableProcessedTableManager? get sessionId {
    final $_column = $_itemColumn<String>('session_id');
    if ($_column == null) return null;
    final manager = $$SessionsTableTableManager(
      $_db,
      $_db.sessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$WigleUploadsTableFilterComposer
    extends Composer<_$AppDatabase, $WigleUploadsTable> {
  $$WigleUploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get networksAccepted => $composableBuilder(
    column: $table.networksAccepted,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get networksNew => $composableBuilder(
    column: $table.networksNew,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  $$SessionsTableFilterComposer get sessionId {
    final $$SessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableFilterComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WigleUploadsTableOrderingComposer
    extends Composer<_$AppDatabase, $WigleUploadsTable> {
  $$WigleUploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get networksAccepted => $composableBuilder(
    column: $table.networksAccepted,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get networksNew => $composableBuilder(
    column: $table.networksNew,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  $$SessionsTableOrderingComposer get sessionId {
    final $$SessionsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableOrderingComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WigleUploadsTableAnnotationComposer
    extends Composer<_$AppDatabase, $WigleUploadsTable> {
  $$WigleUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get uploadedAt => $composableBuilder(
    column: $table.uploadedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get transactionId => $composableBuilder(
    column: $table.transactionId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get networksAccepted => $composableBuilder(
    column: $table.networksAccepted,
    builder: (column) => column,
  );

  GeneratedColumn<int> get networksNew => $composableBuilder(
    column: $table.networksNew,
    builder: (column) => column,
  );

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  $$SessionsTableAnnotationComposer get sessionId {
    final $$SessionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.sessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SessionsTableAnnotationComposer(
            $db: $db,
            $table: $db.sessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$WigleUploadsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WigleUploadsTable,
          WigleUpload,
          $$WigleUploadsTableFilterComposer,
          $$WigleUploadsTableOrderingComposer,
          $$WigleUploadsTableAnnotationComposer,
          $$WigleUploadsTableCreateCompanionBuilder,
          $$WigleUploadsTableUpdateCompanionBuilder,
          (WigleUpload, $$WigleUploadsTableReferences),
          WigleUpload,
          PrefetchHooks Function({bool sessionId})
        > {
  $$WigleUploadsTableTableManager(_$AppDatabase db, $WigleUploadsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WigleUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WigleUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WigleUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<int> uploadedAt = const Value.absent(),
                Value<String?> transactionId = const Value.absent(),
                Value<int?> networksAccepted = const Value.absent(),
                Value<int?> networksNew = const Value.absent(),
                Value<String> status = const Value.absent(),
              }) => WigleUploadsCompanion(
                id: id,
                sessionId: sessionId,
                uploadedAt: uploadedAt,
                transactionId: transactionId,
                networksAccepted: networksAccepted,
                networksNew: networksNew,
                status: status,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                required int uploadedAt,
                Value<String?> transactionId = const Value.absent(),
                Value<int?> networksAccepted = const Value.absent(),
                Value<int?> networksNew = const Value.absent(),
                required String status,
              }) => WigleUploadsCompanion.insert(
                id: id,
                sessionId: sessionId,
                uploadedAt: uploadedAt,
                transactionId: transactionId,
                networksAccepted: networksAccepted,
                networksNew: networksNew,
                status: status,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$WigleUploadsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$WigleUploadsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$WigleUploadsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$WigleUploadsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WigleUploadsTable,
      WigleUpload,
      $$WigleUploadsTableFilterComposer,
      $$WigleUploadsTableOrderingComposer,
      $$WigleUploadsTableAnnotationComposer,
      $$WigleUploadsTableCreateCompanionBuilder,
      $$WigleUploadsTableUpdateCompanionBuilder,
      (WigleUpload, $$WigleUploadsTableReferences),
      WigleUpload,
      PrefetchHooks Function({bool sessionId})
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$NodesTableTableManager get nodes =>
      $$NodesTableTableManager(_db, _db.nodes);
  $$SessionsTableTableManager get sessions =>
      $$SessionsTableTableManager(_db, _db.sessions);
  $$DetectionsTableTableManager get detections =>
      $$DetectionsTableTableManager(_db, _db.detections);
  $$EngineConfigsTableTableManager get engineConfigs =>
      $$EngineConfigsTableTableManager(_db, _db.engineConfigs);
  $$BaselinesTableTableManager get baselines =>
      $$BaselinesTableTableManager(_db, _db.baselines);
  $$BaselineDevicesTableTableManager get baselineDevices =>
      $$BaselineDevicesTableTableManager(_db, _db.baselineDevices);
  $$FingerprintsTableTableManager get fingerprints =>
      $$FingerprintsTableTableManager(_db, _db.fingerprints);
  $$FingerprintMacsTableTableManager get fingerprintMacs =>
      $$FingerprintMacsTableTableManager(_db, _db.fingerprintMacs);
  $$GeofencesTableTableManager get geofences =>
      $$GeofencesTableTableManager(_db, _db.geofences);
  $$GeofenceAlertsTableTableManager get geofenceAlerts =>
      $$GeofenceAlertsTableTableManager(_db, _db.geofenceAlerts);
  $$StalkingSuspectsTableTableManager get stalkingSuspects =>
      $$StalkingSuspectsTableTableManager(_db, _db.stalkingSuspects);
  $$WigleUploadsTableTableManager get wigleUploads =>
      $$WigleUploadsTableTableManager(_db, _db.wigleUploads);
}
