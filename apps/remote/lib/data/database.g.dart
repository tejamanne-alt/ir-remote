// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'database.dart';

// ignore_for_file: type=lint
class $RoomsTable extends Rooms with TableInfo<$RoomsTable, RoomRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoomsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, sortOrder];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'rooms';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoomRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoomRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoomRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
    );
  }

  @override
  $RoomsTable createAlias(String alias) {
    return $RoomsTable(attachedDatabase, alias);
  }
}

class RoomRow extends DataClass implements Insertable<RoomRow> {
  final int id;
  final String name;
  final int sortOrder;
  const RoomRow({
    required this.id,
    required this.name,
    required this.sortOrder,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    return map;
  }

  RoomsCompanion toCompanion(bool nullToAbsent) {
    return RoomsCompanion(
      id: Value(id),
      name: Value(name),
      sortOrder: Value(sortOrder),
    );
  }

  factory RoomRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoomRow(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
    };
  }

  RoomRow copyWith({int? id, String? name, int? sortOrder}) => RoomRow(
    id: id ?? this.id,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
  );
  RoomRow copyWithCompanion(RoomsCompanion data) {
    return RoomRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoomRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, sortOrder);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoomRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder);
}

class RoomsCompanion extends UpdateCompanion<RoomRow> {
  final Value<int> id;
  final Value<String> name;
  final Value<int> sortOrder;
  const RoomsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
  });
  RoomsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.sortOrder = const Value.absent(),
  }) : name = Value(name);
  static Insertable<RoomRow> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<int>? sortOrder,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
    });
  }

  RoomsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<int>? sortOrder,
  }) {
    return RoomsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoomsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, DeviceRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 40,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _brandMeta = const VerificationMeta('brand');
  @override
  late final GeneratedColumn<String> brand = GeneratedColumn<String>(
    'brand',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _codeSetIdMeta = const VerificationMeta(
    'codeSetId',
  );
  @override
  late final GeneratedColumn<String> codeSetId = GeneratedColumn<String>(
    'code_set_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _roomIdMeta = const VerificationMeta('roomId');
  @override
  late final GeneratedColumn<int> roomId = GeneratedColumn<int>(
    'room_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES rooms (id) ON DELETE SET NULL',
    ),
  );
  static const VerificationMeta _transportIdMeta = const VerificationMeta(
    'transportId',
  );
  @override
  late final GeneratedColumn<String> transportId = GeneratedColumn<String>(
    'transport_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _favouriteMeta = const VerificationMeta(
    'favourite',
  );
  @override
  late final GeneratedColumn<bool> favourite = GeneratedColumn<bool>(
    'favourite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favourite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acProtocolIdMeta = const VerificationMeta(
    'acProtocolId',
  );
  @override
  late final GeneratedColumn<String> acProtocolId = GeneratedColumn<String>(
    'ac_protocol_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acCapsVersionMeta = const VerificationMeta(
    'acCapsVersion',
  );
  @override
  late final GeneratedColumn<int> acCapsVersion = GeneratedColumn<int>(
    'ac_caps_version',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acLastStateMeta = const VerificationMeta(
    'acLastState',
  );
  @override
  late final GeneratedColumn<String> acLastState = GeneratedColumn<String>(
    'ac_last_state',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _acLastSentAtMeta = const VerificationMeta(
    'acLastSentAt',
  );
  @override
  late final GeneratedColumn<DateTime> acLastSentAt = GeneratedColumn<DateTime>(
    'ac_last_sent_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    category,
    brand,
    codeSetId,
    roomId,
    transportId,
    favourite,
    sortOrder,
    createdAt,
    lastUsedAt,
    acProtocolId,
    acCapsVersion,
    acLastState,
    acLastSentAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceRow> instance, {
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
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('brand')) {
      context.handle(
        _brandMeta,
        brand.isAcceptableOrUnknown(data['brand']!, _brandMeta),
      );
    }
    if (data.containsKey('code_set_id')) {
      context.handle(
        _codeSetIdMeta,
        codeSetId.isAcceptableOrUnknown(data['code_set_id']!, _codeSetIdMeta),
      );
    }
    if (data.containsKey('room_id')) {
      context.handle(
        _roomIdMeta,
        roomId.isAcceptableOrUnknown(data['room_id']!, _roomIdMeta),
      );
    }
    if (data.containsKey('transport_id')) {
      context.handle(
        _transportIdMeta,
        transportId.isAcceptableOrUnknown(
          data['transport_id']!,
          _transportIdMeta,
        ),
      );
    }
    if (data.containsKey('favourite')) {
      context.handle(
        _favouriteMeta,
        favourite.isAcceptableOrUnknown(data['favourite']!, _favouriteMeta),
      );
    }
    if (data.containsKey('sort_order')) {
      context.handle(
        _sortOrderMeta,
        sortOrder.isAcceptableOrUnknown(data['sort_order']!, _sortOrderMeta),
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
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    if (data.containsKey('ac_protocol_id')) {
      context.handle(
        _acProtocolIdMeta,
        acProtocolId.isAcceptableOrUnknown(
          data['ac_protocol_id']!,
          _acProtocolIdMeta,
        ),
      );
    }
    if (data.containsKey('ac_caps_version')) {
      context.handle(
        _acCapsVersionMeta,
        acCapsVersion.isAcceptableOrUnknown(
          data['ac_caps_version']!,
          _acCapsVersionMeta,
        ),
      );
    }
    if (data.containsKey('ac_last_state')) {
      context.handle(
        _acLastStateMeta,
        acLastState.isAcceptableOrUnknown(
          data['ac_last_state']!,
          _acLastStateMeta,
        ),
      );
    }
    if (data.containsKey('ac_last_sent_at')) {
      context.handle(
        _acLastSentAtMeta,
        acLastSentAt.isAcceptableOrUnknown(
          data['ac_last_sent_at']!,
          _acLastSentAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeviceRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      brand: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}brand'],
      ),
      codeSetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}code_set_id'],
      ),
      roomId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}room_id'],
      ),
      transportId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transport_id'],
      ),
      favourite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favourite'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      ),
      acProtocolId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ac_protocol_id'],
      ),
      acCapsVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}ac_caps_version'],
      ),
      acLastState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ac_last_state'],
      ),
      acLastSentAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ac_last_sent_at'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class DeviceRow extends DataClass implements Insertable<DeviceRow> {
  final String id;
  final String name;

  /// `DeviceCategory.name`.
  final String category;
  final String? brand;

  /// Code-set reference (`null` for learned or imported remotes).
  final String? codeSetId;
  final int? roomId;

  /// The user's chosen transport, or `null` for automatic selection.
  final String? transportId;
  final bool favourite;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  /// AC remotes: protocol variant, capability-descriptor version, and the
  /// last state sent (AcState JSON) with its time.
  final String? acProtocolId;
  final int? acCapsVersion;
  final String? acLastState;
  final DateTime? acLastSentAt;
  const DeviceRow({
    required this.id,
    required this.name,
    required this.category,
    this.brand,
    this.codeSetId,
    this.roomId,
    this.transportId,
    required this.favourite,
    required this.sortOrder,
    required this.createdAt,
    this.lastUsedAt,
    this.acProtocolId,
    this.acCapsVersion,
    this.acLastState,
    this.acLastSentAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['category'] = Variable<String>(category);
    if (!nullToAbsent || brand != null) {
      map['brand'] = Variable<String>(brand);
    }
    if (!nullToAbsent || codeSetId != null) {
      map['code_set_id'] = Variable<String>(codeSetId);
    }
    if (!nullToAbsent || roomId != null) {
      map['room_id'] = Variable<int>(roomId);
    }
    if (!nullToAbsent || transportId != null) {
      map['transport_id'] = Variable<String>(transportId);
    }
    map['favourite'] = Variable<bool>(favourite);
    map['sort_order'] = Variable<int>(sortOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || lastUsedAt != null) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    }
    if (!nullToAbsent || acProtocolId != null) {
      map['ac_protocol_id'] = Variable<String>(acProtocolId);
    }
    if (!nullToAbsent || acCapsVersion != null) {
      map['ac_caps_version'] = Variable<int>(acCapsVersion);
    }
    if (!nullToAbsent || acLastState != null) {
      map['ac_last_state'] = Variable<String>(acLastState);
    }
    if (!nullToAbsent || acLastSentAt != null) {
      map['ac_last_sent_at'] = Variable<DateTime>(acLastSentAt);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      id: Value(id),
      name: Value(name),
      category: Value(category),
      brand: brand == null && nullToAbsent
          ? const Value.absent()
          : Value(brand),
      codeSetId: codeSetId == null && nullToAbsent
          ? const Value.absent()
          : Value(codeSetId),
      roomId: roomId == null && nullToAbsent
          ? const Value.absent()
          : Value(roomId),
      transportId: transportId == null && nullToAbsent
          ? const Value.absent()
          : Value(transportId),
      favourite: Value(favourite),
      sortOrder: Value(sortOrder),
      createdAt: Value(createdAt),
      lastUsedAt: lastUsedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastUsedAt),
      acProtocolId: acProtocolId == null && nullToAbsent
          ? const Value.absent()
          : Value(acProtocolId),
      acCapsVersion: acCapsVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(acCapsVersion),
      acLastState: acLastState == null && nullToAbsent
          ? const Value.absent()
          : Value(acLastState),
      acLastSentAt: acLastSentAt == null && nullToAbsent
          ? const Value.absent()
          : Value(acLastSentAt),
    );
  }

  factory DeviceRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      category: serializer.fromJson<String>(json['category']),
      brand: serializer.fromJson<String?>(json['brand']),
      codeSetId: serializer.fromJson<String?>(json['codeSetId']),
      roomId: serializer.fromJson<int?>(json['roomId']),
      transportId: serializer.fromJson<String?>(json['transportId']),
      favourite: serializer.fromJson<bool>(json['favourite']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      lastUsedAt: serializer.fromJson<DateTime?>(json['lastUsedAt']),
      acProtocolId: serializer.fromJson<String?>(json['acProtocolId']),
      acCapsVersion: serializer.fromJson<int?>(json['acCapsVersion']),
      acLastState: serializer.fromJson<String?>(json['acLastState']),
      acLastSentAt: serializer.fromJson<DateTime?>(json['acLastSentAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'category': serializer.toJson<String>(category),
      'brand': serializer.toJson<String?>(brand),
      'codeSetId': serializer.toJson<String?>(codeSetId),
      'roomId': serializer.toJson<int?>(roomId),
      'transportId': serializer.toJson<String?>(transportId),
      'favourite': serializer.toJson<bool>(favourite),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'lastUsedAt': serializer.toJson<DateTime?>(lastUsedAt),
      'acProtocolId': serializer.toJson<String?>(acProtocolId),
      'acCapsVersion': serializer.toJson<int?>(acCapsVersion),
      'acLastState': serializer.toJson<String?>(acLastState),
      'acLastSentAt': serializer.toJson<DateTime?>(acLastSentAt),
    };
  }

  DeviceRow copyWith({
    String? id,
    String? name,
    String? category,
    Value<String?> brand = const Value.absent(),
    Value<String?> codeSetId = const Value.absent(),
    Value<int?> roomId = const Value.absent(),
    Value<String?> transportId = const Value.absent(),
    bool? favourite,
    int? sortOrder,
    DateTime? createdAt,
    Value<DateTime?> lastUsedAt = const Value.absent(),
    Value<String?> acProtocolId = const Value.absent(),
    Value<int?> acCapsVersion = const Value.absent(),
    Value<String?> acLastState = const Value.absent(),
    Value<DateTime?> acLastSentAt = const Value.absent(),
  }) => DeviceRow(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    brand: brand.present ? brand.value : this.brand,
    codeSetId: codeSetId.present ? codeSetId.value : this.codeSetId,
    roomId: roomId.present ? roomId.value : this.roomId,
    transportId: transportId.present ? transportId.value : this.transportId,
    favourite: favourite ?? this.favourite,
    sortOrder: sortOrder ?? this.sortOrder,
    createdAt: createdAt ?? this.createdAt,
    lastUsedAt: lastUsedAt.present ? lastUsedAt.value : this.lastUsedAt,
    acProtocolId: acProtocolId.present ? acProtocolId.value : this.acProtocolId,
    acCapsVersion: acCapsVersion.present
        ? acCapsVersion.value
        : this.acCapsVersion,
    acLastState: acLastState.present ? acLastState.value : this.acLastState,
    acLastSentAt: acLastSentAt.present ? acLastSentAt.value : this.acLastSentAt,
  );
  DeviceRow copyWithCompanion(DevicesCompanion data) {
    return DeviceRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      category: data.category.present ? data.category.value : this.category,
      brand: data.brand.present ? data.brand.value : this.brand,
      codeSetId: data.codeSetId.present ? data.codeSetId.value : this.codeSetId,
      roomId: data.roomId.present ? data.roomId.value : this.roomId,
      transportId: data.transportId.present
          ? data.transportId.value
          : this.transportId,
      favourite: data.favourite.present ? data.favourite.value : this.favourite,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
      acProtocolId: data.acProtocolId.present
          ? data.acProtocolId.value
          : this.acProtocolId,
      acCapsVersion: data.acCapsVersion.present
          ? data.acCapsVersion.value
          : this.acCapsVersion,
      acLastState: data.acLastState.present
          ? data.acLastState.value
          : this.acLastState,
      acLastSentAt: data.acLastSentAt.present
          ? data.acLastSentAt.value
          : this.acLastSentAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('brand: $brand, ')
          ..write('codeSetId: $codeSetId, ')
          ..write('roomId: $roomId, ')
          ..write('transportId: $transportId, ')
          ..write('favourite: $favourite, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('acProtocolId: $acProtocolId, ')
          ..write('acCapsVersion: $acCapsVersion, ')
          ..write('acLastState: $acLastState, ')
          ..write('acLastSentAt: $acLastSentAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    category,
    brand,
    codeSetId,
    roomId,
    transportId,
    favourite,
    sortOrder,
    createdAt,
    lastUsedAt,
    acProtocolId,
    acCapsVersion,
    acLastState,
    acLastSentAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.category == this.category &&
          other.brand == this.brand &&
          other.codeSetId == this.codeSetId &&
          other.roomId == this.roomId &&
          other.transportId == this.transportId &&
          other.favourite == this.favourite &&
          other.sortOrder == this.sortOrder &&
          other.createdAt == this.createdAt &&
          other.lastUsedAt == this.lastUsedAt &&
          other.acProtocolId == this.acProtocolId &&
          other.acCapsVersion == this.acCapsVersion &&
          other.acLastState == this.acLastState &&
          other.acLastSentAt == this.acLastSentAt);
}

class DevicesCompanion extends UpdateCompanion<DeviceRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> category;
  final Value<String?> brand;
  final Value<String?> codeSetId;
  final Value<int?> roomId;
  final Value<String?> transportId;
  final Value<bool> favourite;
  final Value<int> sortOrder;
  final Value<DateTime> createdAt;
  final Value<DateTime?> lastUsedAt;
  final Value<String?> acProtocolId;
  final Value<int?> acCapsVersion;
  final Value<String?> acLastState;
  final Value<DateTime?> acLastSentAt;
  final Value<int> rowid;
  const DevicesCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.category = const Value.absent(),
    this.brand = const Value.absent(),
    this.codeSetId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.transportId = const Value.absent(),
    this.favourite = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
    this.acProtocolId = const Value.absent(),
    this.acCapsVersion = const Value.absent(),
    this.acLastState = const Value.absent(),
    this.acLastSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required String id,
    required String name,
    required String category,
    this.brand = const Value.absent(),
    this.codeSetId = const Value.absent(),
    this.roomId = const Value.absent(),
    this.transportId = const Value.absent(),
    this.favourite = const Value.absent(),
    this.sortOrder = const Value.absent(),
    required DateTime createdAt,
    this.lastUsedAt = const Value.absent(),
    this.acProtocolId = const Value.absent(),
    this.acCapsVersion = const Value.absent(),
    this.acLastState = const Value.absent(),
    this.acLastSentAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       category = Value(category),
       createdAt = Value(createdAt);
  static Insertable<DeviceRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? category,
    Expression<String>? brand,
    Expression<String>? codeSetId,
    Expression<int>? roomId,
    Expression<String>? transportId,
    Expression<bool>? favourite,
    Expression<int>? sortOrder,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? lastUsedAt,
    Expression<String>? acProtocolId,
    Expression<int>? acCapsVersion,
    Expression<String>? acLastState,
    Expression<DateTime>? acLastSentAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (category != null) 'category': category,
      if (brand != null) 'brand': brand,
      if (codeSetId != null) 'code_set_id': codeSetId,
      if (roomId != null) 'room_id': roomId,
      if (transportId != null) 'transport_id': transportId,
      if (favourite != null) 'favourite': favourite,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
      if (acProtocolId != null) 'ac_protocol_id': acProtocolId,
      if (acCapsVersion != null) 'ac_caps_version': acCapsVersion,
      if (acLastState != null) 'ac_last_state': acLastState,
      if (acLastSentAt != null) 'ac_last_sent_at': acLastSentAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? category,
    Value<String?>? brand,
    Value<String?>? codeSetId,
    Value<int?>? roomId,
    Value<String?>? transportId,
    Value<bool>? favourite,
    Value<int>? sortOrder,
    Value<DateTime>? createdAt,
    Value<DateTime?>? lastUsedAt,
    Value<String?>? acProtocolId,
    Value<int?>? acCapsVersion,
    Value<String?>? acLastState,
    Value<DateTime?>? acLastSentAt,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      category: category ?? this.category,
      brand: brand ?? this.brand,
      codeSetId: codeSetId ?? this.codeSetId,
      roomId: roomId ?? this.roomId,
      transportId: transportId ?? this.transportId,
      favourite: favourite ?? this.favourite,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      acProtocolId: acProtocolId ?? this.acProtocolId,
      acCapsVersion: acCapsVersion ?? this.acCapsVersion,
      acLastState: acLastState ?? this.acLastState,
      acLastSentAt: acLastSentAt ?? this.acLastSentAt,
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
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (brand.present) {
      map['brand'] = Variable<String>(brand.value);
    }
    if (codeSetId.present) {
      map['code_set_id'] = Variable<String>(codeSetId.value);
    }
    if (roomId.present) {
      map['room_id'] = Variable<int>(roomId.value);
    }
    if (transportId.present) {
      map['transport_id'] = Variable<String>(transportId.value);
    }
    if (favourite.present) {
      map['favourite'] = Variable<bool>(favourite.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    if (acProtocolId.present) {
      map['ac_protocol_id'] = Variable<String>(acProtocolId.value);
    }
    if (acCapsVersion.present) {
      map['ac_caps_version'] = Variable<int>(acCapsVersion.value);
    }
    if (acLastState.present) {
      map['ac_last_state'] = Variable<String>(acLastState.value);
    }
    if (acLastSentAt.present) {
      map['ac_last_sent_at'] = Variable<DateTime>(acLastSentAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('category: $category, ')
          ..write('brand: $brand, ')
          ..write('codeSetId: $codeSetId, ')
          ..write('roomId: $roomId, ')
          ..write('transportId: $transportId, ')
          ..write('favourite: $favourite, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('lastUsedAt: $lastUsedAt, ')
          ..write('acProtocolId: $acProtocolId, ')
          ..write('acCapsVersion: $acCapsVersion, ')
          ..write('acLastState: $acLastState, ')
          ..write('acLastSentAt: $acLastSentAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DeviceKeysTable extends DeviceKeys
    with TableInfo<$DeviceKeysTable, DeviceKeyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DeviceKeysTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES devices (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _keyNameMeta = const VerificationMeta(
    'keyName',
  );
  @override
  late final GeneratedColumn<String> keyName = GeneratedColumn<String>(
    'key_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _signalMeta = const VerificationMeta('signal');
  @override
  late final GeneratedColumn<String> signal = GeneratedColumn<String>(
    'signal',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _signalToggledMeta = const VerificationMeta(
    'signalToggled',
  );
  @override
  late final GeneratedColumn<String> signalToggled = GeneratedColumn<String>(
    'signal_toggled',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _protocolMeta = const VerificationMeta(
    'protocol',
  );
  @override
  late final GeneratedColumn<String> protocol = GeneratedColumn<String>(
    'protocol',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _paramsMeta = const VerificationMeta('params');
  @override
  late final GeneratedColumn<String> params = GeneratedColumn<String>(
    'params',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    deviceId,
    keyName,
    label,
    signal,
    signalToggled,
    source,
    protocol,
    params,
    position,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'device_keys';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeviceKeyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('key_name')) {
      context.handle(
        _keyNameMeta,
        keyName.isAcceptableOrUnknown(data['key_name']!, _keyNameMeta),
      );
    } else if (isInserting) {
      context.missing(_keyNameMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('signal')) {
      context.handle(
        _signalMeta,
        signal.isAcceptableOrUnknown(data['signal']!, _signalMeta),
      );
    } else if (isInserting) {
      context.missing(_signalMeta);
    }
    if (data.containsKey('signal_toggled')) {
      context.handle(
        _signalToggledMeta,
        signalToggled.isAcceptableOrUnknown(
          data['signal_toggled']!,
          _signalToggledMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('protocol')) {
      context.handle(
        _protocolMeta,
        protocol.isAcceptableOrUnknown(data['protocol']!, _protocolMeta),
      );
    }
    if (data.containsKey('params')) {
      context.handle(
        _paramsMeta,
        params.isAcceptableOrUnknown(data['params']!, _paramsMeta),
      );
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {deviceId, keyName};
  @override
  DeviceKeyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeviceKeyRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      keyName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key_name'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      ),
      signal: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signal'],
      )!,
      signalToggled: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}signal_toggled'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      protocol: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}protocol'],
      ),
      params: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}params'],
      ),
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $DeviceKeysTable createAlias(String alias) {
    return $DeviceKeysTable(attachedDatabase, alias);
  }
}

class DeviceKeyRow extends DataClass implements Insertable<DeviceKeyRow> {
  final String deviceId;

  /// Normalized key name (`Keys`), or `custom:<label>`.
  final String keyName;

  /// User label for custom keys.
  final String? label;

  /// IrSignal JSON snapshot. Database updates never change it silently.
  final String signal;

  /// For toggle protocols (RC5, RC6): the snapshot with the toggle bit set.
  final String? signalToggled;

  /// Where the key came from: `database`, `learned` or `imported`.
  final String source;

  /// Protocol and parameters when known (informational, for the inspector
  /// and "Update codes" diffs).
  final String? protocol;
  final String? params;
  final int position;
  const DeviceKeyRow({
    required this.deviceId,
    required this.keyName,
    this.label,
    required this.signal,
    this.signalToggled,
    required this.source,
    this.protocol,
    this.params,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['device_id'] = Variable<String>(deviceId);
    map['key_name'] = Variable<String>(keyName);
    if (!nullToAbsent || label != null) {
      map['label'] = Variable<String>(label);
    }
    map['signal'] = Variable<String>(signal);
    if (!nullToAbsent || signalToggled != null) {
      map['signal_toggled'] = Variable<String>(signalToggled);
    }
    map['source'] = Variable<String>(source);
    if (!nullToAbsent || protocol != null) {
      map['protocol'] = Variable<String>(protocol);
    }
    if (!nullToAbsent || params != null) {
      map['params'] = Variable<String>(params);
    }
    map['position'] = Variable<int>(position);
    return map;
  }

  DeviceKeysCompanion toCompanion(bool nullToAbsent) {
    return DeviceKeysCompanion(
      deviceId: Value(deviceId),
      keyName: Value(keyName),
      label: label == null && nullToAbsent
          ? const Value.absent()
          : Value(label),
      signal: Value(signal),
      signalToggled: signalToggled == null && nullToAbsent
          ? const Value.absent()
          : Value(signalToggled),
      source: Value(source),
      protocol: protocol == null && nullToAbsent
          ? const Value.absent()
          : Value(protocol),
      params: params == null && nullToAbsent
          ? const Value.absent()
          : Value(params),
      position: Value(position),
    );
  }

  factory DeviceKeyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeviceKeyRow(
      deviceId: serializer.fromJson<String>(json['deviceId']),
      keyName: serializer.fromJson<String>(json['keyName']),
      label: serializer.fromJson<String?>(json['label']),
      signal: serializer.fromJson<String>(json['signal']),
      signalToggled: serializer.fromJson<String?>(json['signalToggled']),
      source: serializer.fromJson<String>(json['source']),
      protocol: serializer.fromJson<String?>(json['protocol']),
      params: serializer.fromJson<String?>(json['params']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String>(deviceId),
      'keyName': serializer.toJson<String>(keyName),
      'label': serializer.toJson<String?>(label),
      'signal': serializer.toJson<String>(signal),
      'signalToggled': serializer.toJson<String?>(signalToggled),
      'source': serializer.toJson<String>(source),
      'protocol': serializer.toJson<String?>(protocol),
      'params': serializer.toJson<String?>(params),
      'position': serializer.toJson<int>(position),
    };
  }

  DeviceKeyRow copyWith({
    String? deviceId,
    String? keyName,
    Value<String?> label = const Value.absent(),
    String? signal,
    Value<String?> signalToggled = const Value.absent(),
    String? source,
    Value<String?> protocol = const Value.absent(),
    Value<String?> params = const Value.absent(),
    int? position,
  }) => DeviceKeyRow(
    deviceId: deviceId ?? this.deviceId,
    keyName: keyName ?? this.keyName,
    label: label.present ? label.value : this.label,
    signal: signal ?? this.signal,
    signalToggled: signalToggled.present
        ? signalToggled.value
        : this.signalToggled,
    source: source ?? this.source,
    protocol: protocol.present ? protocol.value : this.protocol,
    params: params.present ? params.value : this.params,
    position: position ?? this.position,
  );
  DeviceKeyRow copyWithCompanion(DeviceKeysCompanion data) {
    return DeviceKeyRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      keyName: data.keyName.present ? data.keyName.value : this.keyName,
      label: data.label.present ? data.label.value : this.label,
      signal: data.signal.present ? data.signal.value : this.signal,
      signalToggled: data.signalToggled.present
          ? data.signalToggled.value
          : this.signalToggled,
      source: data.source.present ? data.source.value : this.source,
      protocol: data.protocol.present ? data.protocol.value : this.protocol,
      params: data.params.present ? data.params.value : this.params,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeviceKeyRow(')
          ..write('deviceId: $deviceId, ')
          ..write('keyName: $keyName, ')
          ..write('label: $label, ')
          ..write('signal: $signal, ')
          ..write('signalToggled: $signalToggled, ')
          ..write('source: $source, ')
          ..write('protocol: $protocol, ')
          ..write('params: $params, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    deviceId,
    keyName,
    label,
    signal,
    signalToggled,
    source,
    protocol,
    params,
    position,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeviceKeyRow &&
          other.deviceId == this.deviceId &&
          other.keyName == this.keyName &&
          other.label == this.label &&
          other.signal == this.signal &&
          other.signalToggled == this.signalToggled &&
          other.source == this.source &&
          other.protocol == this.protocol &&
          other.params == this.params &&
          other.position == this.position);
}

class DeviceKeysCompanion extends UpdateCompanion<DeviceKeyRow> {
  final Value<String> deviceId;
  final Value<String> keyName;
  final Value<String?> label;
  final Value<String> signal;
  final Value<String?> signalToggled;
  final Value<String> source;
  final Value<String?> protocol;
  final Value<String?> params;
  final Value<int> position;
  final Value<int> rowid;
  const DeviceKeysCompanion({
    this.deviceId = const Value.absent(),
    this.keyName = const Value.absent(),
    this.label = const Value.absent(),
    this.signal = const Value.absent(),
    this.signalToggled = const Value.absent(),
    this.source = const Value.absent(),
    this.protocol = const Value.absent(),
    this.params = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DeviceKeysCompanion.insert({
    required String deviceId,
    required String keyName,
    this.label = const Value.absent(),
    required String signal,
    this.signalToggled = const Value.absent(),
    required String source,
    this.protocol = const Value.absent(),
    this.params = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : deviceId = Value(deviceId),
       keyName = Value(keyName),
       signal = Value(signal),
       source = Value(source);
  static Insertable<DeviceKeyRow> custom({
    Expression<String>? deviceId,
    Expression<String>? keyName,
    Expression<String>? label,
    Expression<String>? signal,
    Expression<String>? signalToggled,
    Expression<String>? source,
    Expression<String>? protocol,
    Expression<String>? params,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (keyName != null) 'key_name': keyName,
      if (label != null) 'label': label,
      if (signal != null) 'signal': signal,
      if (signalToggled != null) 'signal_toggled': signalToggled,
      if (source != null) 'source': source,
      if (protocol != null) 'protocol': protocol,
      if (params != null) 'params': params,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DeviceKeysCompanion copyWith({
    Value<String>? deviceId,
    Value<String>? keyName,
    Value<String?>? label,
    Value<String>? signal,
    Value<String?>? signalToggled,
    Value<String>? source,
    Value<String?>? protocol,
    Value<String?>? params,
    Value<int>? position,
    Value<int>? rowid,
  }) {
    return DeviceKeysCompanion(
      deviceId: deviceId ?? this.deviceId,
      keyName: keyName ?? this.keyName,
      label: label ?? this.label,
      signal: signal ?? this.signal,
      signalToggled: signalToggled ?? this.signalToggled,
      source: source ?? this.source,
      protocol: protocol ?? this.protocol,
      params: params ?? this.params,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (keyName.present) {
      map['key_name'] = Variable<String>(keyName.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (signal.present) {
      map['signal'] = Variable<String>(signal.value);
    }
    if (signalToggled.present) {
      map['signal_toggled'] = Variable<String>(signalToggled.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (protocol.present) {
      map['protocol'] = Variable<String>(protocol.value);
    }
    if (params.present) {
      map['params'] = Variable<String>(params.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DeviceKeysCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('keyName: $keyName, ')
          ..write('label: $label, ')
          ..write('signal: $signal, ')
          ..write('signalToggled: $signalToggled, ')
          ..write('source: $source, ')
          ..write('protocol: $protocol, ')
          ..write('params: $params, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $HubsTable extends Hubs with TableInfo<$HubsTable, HubRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $HubsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
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
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 1,
      maxTextLength: 64,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hostMeta = const VerificationMeta('host');
  @override
  late final GeneratedColumn<String> host = GeneratedColumn<String>(
    'host',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _portMeta = const VerificationMeta('port');
  @override
  late final GeneratedColumn<int> port = GeneratedColumn<int>(
    'port',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tokenMeta = const VerificationMeta('token');
  @override
  late final GeneratedColumn<String> token = GeneratedColumn<String>(
    'token',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _extraMeta = const VerificationMeta('extra');
  @override
  late final GeneratedColumn<String> extra = GeneratedColumn<String>(
    'extra',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    kind,
    name,
    host,
    port,
    token,
    extra,
    addedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'hubs';
  @override
  VerificationContext validateIntegrity(
    Insertable<HubRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('host')) {
      context.handle(
        _hostMeta,
        host.isAcceptableOrUnknown(data['host']!, _hostMeta),
      );
    } else if (isInserting) {
      context.missing(_hostMeta);
    }
    if (data.containsKey('port')) {
      context.handle(
        _portMeta,
        port.isAcceptableOrUnknown(data['port']!, _portMeta),
      );
    } else if (isInserting) {
      context.missing(_portMeta);
    }
    if (data.containsKey('token')) {
      context.handle(
        _tokenMeta,
        token.isAcceptableOrUnknown(data['token']!, _tokenMeta),
      );
    }
    if (data.containsKey('extra')) {
      context.handle(
        _extraMeta,
        extra.isAcceptableOrUnknown(data['extra']!, _extraMeta),
      );
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_addedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  HubRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return HubRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      host: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}host'],
      )!,
      port: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}port'],
      )!,
      token: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token'],
      ),
      extra: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}extra'],
      ),
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
    );
  }

  @override
  $HubsTable createAlias(String alias) {
    return $HubsTable(attachedDatabase, alias);
  }
}

class HubRow extends DataClass implements Insertable<HubRow> {
  final String id;

  /// `TransportKind.name` (espBridge or broadlink).
  final String kind;
  final String name;
  final String host;
  final int port;

  /// Pairing token (ESP32 bridge). LAN-only credential.
  final String? token;

  /// Kind-specific JSON (for example the Broadlink device type and MAC).
  final String? extra;
  final DateTime addedAt;
  const HubRow({
    required this.id,
    required this.kind,
    required this.name,
    required this.host,
    required this.port,
    this.token,
    this.extra,
    required this.addedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['kind'] = Variable<String>(kind);
    map['name'] = Variable<String>(name);
    map['host'] = Variable<String>(host);
    map['port'] = Variable<int>(port);
    if (!nullToAbsent || token != null) {
      map['token'] = Variable<String>(token);
    }
    if (!nullToAbsent || extra != null) {
      map['extra'] = Variable<String>(extra);
    }
    map['added_at'] = Variable<DateTime>(addedAt);
    return map;
  }

  HubsCompanion toCompanion(bool nullToAbsent) {
    return HubsCompanion(
      id: Value(id),
      kind: Value(kind),
      name: Value(name),
      host: Value(host),
      port: Value(port),
      token: token == null && nullToAbsent
          ? const Value.absent()
          : Value(token),
      extra: extra == null && nullToAbsent
          ? const Value.absent()
          : Value(extra),
      addedAt: Value(addedAt),
    );
  }

  factory HubRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return HubRow(
      id: serializer.fromJson<String>(json['id']),
      kind: serializer.fromJson<String>(json['kind']),
      name: serializer.fromJson<String>(json['name']),
      host: serializer.fromJson<String>(json['host']),
      port: serializer.fromJson<int>(json['port']),
      token: serializer.fromJson<String?>(json['token']),
      extra: serializer.fromJson<String?>(json['extra']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'kind': serializer.toJson<String>(kind),
      'name': serializer.toJson<String>(name),
      'host': serializer.toJson<String>(host),
      'port': serializer.toJson<int>(port),
      'token': serializer.toJson<String?>(token),
      'extra': serializer.toJson<String?>(extra),
      'addedAt': serializer.toJson<DateTime>(addedAt),
    };
  }

  HubRow copyWith({
    String? id,
    String? kind,
    String? name,
    String? host,
    int? port,
    Value<String?> token = const Value.absent(),
    Value<String?> extra = const Value.absent(),
    DateTime? addedAt,
  }) => HubRow(
    id: id ?? this.id,
    kind: kind ?? this.kind,
    name: name ?? this.name,
    host: host ?? this.host,
    port: port ?? this.port,
    token: token.present ? token.value : this.token,
    extra: extra.present ? extra.value : this.extra,
    addedAt: addedAt ?? this.addedAt,
  );
  HubRow copyWithCompanion(HubsCompanion data) {
    return HubRow(
      id: data.id.present ? data.id.value : this.id,
      kind: data.kind.present ? data.kind.value : this.kind,
      name: data.name.present ? data.name.value : this.name,
      host: data.host.present ? data.host.value : this.host,
      port: data.port.present ? data.port.value : this.port,
      token: data.token.present ? data.token.value : this.token,
      extra: data.extra.present ? data.extra.value : this.extra,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('HubRow(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('token: $token, ')
          ..write('extra: $extra, ')
          ..write('addedAt: $addedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, kind, name, host, port, token, extra, addedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HubRow &&
          other.id == this.id &&
          other.kind == this.kind &&
          other.name == this.name &&
          other.host == this.host &&
          other.port == this.port &&
          other.token == this.token &&
          other.extra == this.extra &&
          other.addedAt == this.addedAt);
}

class HubsCompanion extends UpdateCompanion<HubRow> {
  final Value<String> id;
  final Value<String> kind;
  final Value<String> name;
  final Value<String> host;
  final Value<int> port;
  final Value<String?> token;
  final Value<String?> extra;
  final Value<DateTime> addedAt;
  final Value<int> rowid;
  const HubsCompanion({
    this.id = const Value.absent(),
    this.kind = const Value.absent(),
    this.name = const Value.absent(),
    this.host = const Value.absent(),
    this.port = const Value.absent(),
    this.token = const Value.absent(),
    this.extra = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  HubsCompanion.insert({
    required String id,
    required String kind,
    required String name,
    required String host,
    required int port,
    this.token = const Value.absent(),
    this.extra = const Value.absent(),
    required DateTime addedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       kind = Value(kind),
       name = Value(name),
       host = Value(host),
       port = Value(port),
       addedAt = Value(addedAt);
  static Insertable<HubRow> custom({
    Expression<String>? id,
    Expression<String>? kind,
    Expression<String>? name,
    Expression<String>? host,
    Expression<int>? port,
    Expression<String>? token,
    Expression<String>? extra,
    Expression<DateTime>? addedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (kind != null) 'kind': kind,
      if (name != null) 'name': name,
      if (host != null) 'host': host,
      if (port != null) 'port': port,
      if (token != null) 'token': token,
      if (extra != null) 'extra': extra,
      if (addedAt != null) 'added_at': addedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  HubsCompanion copyWith({
    Value<String>? id,
    Value<String>? kind,
    Value<String>? name,
    Value<String>? host,
    Value<int>? port,
    Value<String?>? token,
    Value<String?>? extra,
    Value<DateTime>? addedAt,
    Value<int>? rowid,
  }) {
    return HubsCompanion(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      token: token ?? this.token,
      extra: extra ?? this.extra,
      addedAt: addedAt ?? this.addedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (host.present) {
      map['host'] = Variable<String>(host.value);
    }
    if (port.present) {
      map['port'] = Variable<int>(port.value);
    }
    if (token.present) {
      map['token'] = Variable<String>(token.value);
    }
    if (extra.present) {
      map['extra'] = Variable<String>(extra.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('HubsCompanion(')
          ..write('id: $id, ')
          ..write('kind: $kind, ')
          ..write('name: $name, ')
          ..write('host: $host, ')
          ..write('port: $port, ')
          ..write('token: $token, ')
          ..write('extra: $extra, ')
          ..write('addedAt: $addedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $RoomsTable rooms = $RoomsTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $DeviceKeysTable deviceKeys = $DeviceKeysTable(this);
  late final $HubsTable hubs = $HubsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    rooms,
    devices,
    deviceKeys,
    hubs,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'rooms',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('devices', kind: UpdateKind.update)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'devices',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('device_keys', kind: UpdateKind.delete)],
    ),
  ]);
  @override
  DriftDatabaseOptions get options =>
      const DriftDatabaseOptions(storeDateTimeAsText: true);
}

typedef $$RoomsTableCreateCompanionBuilder = RoomsCompanion Function({
  Value<int> id,
  required String name,
  Value<int> sortOrder,
});
typedef $$RoomsTableUpdateCompanionBuilder = RoomsCompanion Function({
  Value<int> id,
  Value<String> name,
  Value<int> sortOrder,
});

final class $$RoomsTableReferences
    extends BaseReferences<_$AppDatabase, $RoomsTable, RoomRow> {
  $$RoomsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DevicesTable, List<DeviceRow>> _devicesRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.devices,
    aliasName: 'rooms__id__devices__room_id',
  );

  $$DevicesTableProcessedTableManager get devicesRefs {
    final manager = $$DevicesTableTableManager(
      $_db,
      $_db.devices,
    ).filter((f) => f.roomId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_devicesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$RoomsTableFilterComposer extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableFilterComposer({
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

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> devicesRefs(
    Expression<bool> Function($$DevicesTableFilterComposer f) f,
  ) {
    final $$DevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.roomId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableFilterComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoomsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableOrderingComposer({
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

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoomsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoomsTable> {
  $$RoomsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  Expression<T> devicesRefs<T extends Object>(
    Expression<T> Function($$DevicesTableAnnotationComposer a) f,
  ) {
    final $$DevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.roomId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$RoomsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoomsTable,
          RoomRow,
          $$RoomsTableFilterComposer,
          $$RoomsTableOrderingComposer,
          $$RoomsTableAnnotationComposer,
          $$RoomsTableCreateCompanionBuilder,
          $$RoomsTableUpdateCompanionBuilder,
          (RoomRow, $$RoomsTableReferences),
          RoomRow,
          PrefetchHooks Function({bool devicesRefs})
        > {
  $$RoomsTableTableManager(_$AppDatabase db, $RoomsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoomsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoomsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoomsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> sortOrder = const Value.absent(),
          }) => RoomsCompanion(id: id, name: name, sortOrder: sortOrder),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String name,
            Value<int> sortOrder = const Value.absent(),
          }) => RoomsCompanion.insert(id: id, name: name, sortOrder: sortOrder),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RoomsTable, RoomRow>(table),
                  $$RoomsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({devicesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (devicesRefs) db.devices],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (devicesRefs)
                    await $_getPrefetchedDataByColumns<
                      RoomRow,
                      $RoomsTable,
                      DeviceRow,
                      $DevicesTable
                    >(
                      currentTable: table,
                      referencedTable: $$RoomsTableReferences._devicesRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$RoomsTableReferences(db, table, p0).devicesRefs,
                      currentColumn: 'id',
                      referencedColumn: 'room_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$RoomsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoomsTable,
      RoomRow,
      $$RoomsTableFilterComposer,
      $$RoomsTableOrderingComposer,
      $$RoomsTableAnnotationComposer,
      $$RoomsTableCreateCompanionBuilder,
      $$RoomsTableUpdateCompanionBuilder,
      (RoomRow, $$RoomsTableReferences),
      RoomRow,
      PrefetchHooks Function({bool devicesRefs})
    >;
typedef $$DevicesTableCreateCompanionBuilder = DevicesCompanion Function({
  required String id,
  required String name,
  required String category,
  Value<String?> brand,
  Value<String?> codeSetId,
  Value<int?> roomId,
  Value<String?> transportId,
  Value<bool> favourite,
  Value<int> sortOrder,
  required DateTime createdAt,
  Value<DateTime?> lastUsedAt,
  Value<String?> acProtocolId,
  Value<int?> acCapsVersion,
  Value<String?> acLastState,
  Value<DateTime?> acLastSentAt,
  Value<int> rowid,
});
typedef $$DevicesTableUpdateCompanionBuilder = DevicesCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> category,
  Value<String?> brand,
  Value<String?> codeSetId,
  Value<int?> roomId,
  Value<String?> transportId,
  Value<bool> favourite,
  Value<int> sortOrder,
  Value<DateTime> createdAt,
  Value<DateTime?> lastUsedAt,
  Value<String?> acProtocolId,
  Value<int?> acCapsVersion,
  Value<String?> acLastState,
  Value<DateTime?> acLastSentAt,
  Value<int> rowid,
});

final class $$DevicesTableReferences
    extends BaseReferences<_$AppDatabase, $DevicesTable, DeviceRow> {
  $$DevicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $RoomsTable _roomIdTable(_$AppDatabase db) =>
      db.rooms.createAlias('devices__room_id__rooms__id');

  $$RoomsTableProcessedTableManager? get roomId {
    final $_column = $_itemColumn<int>('room_id');
    if ($_column == null) return null;
    final manager = $$RoomsTableTableManager(
      $_db,
      $_db.rooms,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_roomIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$DeviceKeysTable, List<DeviceKeyRow>>
  _deviceKeysRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.deviceKeys,
    aliasName: 'devices__id__device_keys__device_id',
  );

  $$DeviceKeysTableProcessedTableManager get deviceKeysRefs {
    final manager = $$DeviceKeysTableTableManager(
      $_db,
      $_db.deviceKeys,
    ).filter((f) => f.deviceId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_deviceKeysRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DevicesTableFilterComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableFilterComposer({
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

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get codeSetId => $composableBuilder(
    column: $table.codeSetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transportId => $composableBuilder(
    column: $table.transportId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acProtocolId => $composableBuilder(
    column: $table.acProtocolId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get acCapsVersion => $composableBuilder(
    column: $table.acCapsVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get acLastState => $composableBuilder(
    column: $table.acLastState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get acLastSentAt => $composableBuilder(
    column: $table.acLastSentAt,
    builder: (column) => ColumnFilters(column),
  );

  $$RoomsTableFilterComposer get roomId {
    final $$RoomsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableFilterComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> deviceKeysRefs(
    Expression<bool> Function($$DeviceKeysTableFilterComposer f) f,
  ) {
    final $$DeviceKeysTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.deviceKeys,
      getReferencedColumn: (t) => t.deviceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceKeysTableFilterComposer(
            $db: $db,
            $table: $db.deviceKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DevicesTableOrderingComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableOrderingComposer({
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

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get brand => $composableBuilder(
    column: $table.brand,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get codeSetId => $composableBuilder(
    column: $table.codeSetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transportId => $composableBuilder(
    column: $table.transportId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favourite => $composableBuilder(
    column: $table.favourite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acProtocolId => $composableBuilder(
    column: $table.acProtocolId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get acCapsVersion => $composableBuilder(
    column: $table.acCapsVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get acLastState => $composableBuilder(
    column: $table.acLastState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get acLastSentAt => $composableBuilder(
    column: $table.acLastSentAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$RoomsTableOrderingComposer get roomId {
    final $$RoomsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableOrderingComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$AppDatabase, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
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

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<String> get brand =>
      $composableBuilder(column: $table.brand, builder: (column) => column);

  GeneratedColumn<String> get codeSetId =>
      $composableBuilder(column: $table.codeSetId, builder: (column) => column);

  GeneratedColumn<String> get transportId => $composableBuilder(
    column: $table.transportId,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get favourite =>
      $composableBuilder(column: $table.favourite, builder: (column) => column);

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acProtocolId => $composableBuilder(
    column: $table.acProtocolId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get acCapsVersion => $composableBuilder(
    column: $table.acCapsVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get acLastState => $composableBuilder(
    column: $table.acLastState,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get acLastSentAt => $composableBuilder(
    column: $table.acLastSentAt,
    builder: (column) => column,
  );

  $$RoomsTableAnnotationComposer get roomId {
    final $$RoomsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.roomId,
      referencedTable: $db.rooms,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$RoomsTableAnnotationComposer(
            $db: $db,
            $table: $db.rooms,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> deviceKeysRefs<T extends Object>(
    Expression<T> Function($$DeviceKeysTableAnnotationComposer a) f,
  ) {
    final $$DeviceKeysTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.deviceKeys,
      getReferencedColumn: (t) => t.deviceId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DeviceKeysTableAnnotationComposer(
            $db: $db,
            $table: $db.deviceKeys,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DevicesTable,
          DeviceRow,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (DeviceRow, $$DevicesTableReferences),
          DeviceRow,
          PrefetchHooks Function({bool roomId, bool deviceKeysRefs})
        > {
  $$DevicesTableTableManager(_$AppDatabase db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<String?> brand = const Value.absent(),
                Value<String?> codeSetId = const Value.absent(),
                Value<int?> roomId = const Value.absent(),
                Value<String?> transportId = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<String?> acProtocolId = const Value.absent(),
                Value<int?> acCapsVersion = const Value.absent(),
                Value<String?> acLastState = const Value.absent(),
                Value<DateTime?> acLastSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                id: id,
                name: name,
                category: category,
                brand: brand,
                codeSetId: codeSetId,
                roomId: roomId,
                transportId: transportId,
                favourite: favourite,
                sortOrder: sortOrder,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                acProtocolId: acProtocolId,
                acCapsVersion: acCapsVersion,
                acLastState: acLastState,
                acLastSentAt: acLastSentAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String category,
                Value<String?> brand = const Value.absent(),
                Value<String?> codeSetId = const Value.absent(),
                Value<int?> roomId = const Value.absent(),
                Value<String?> transportId = const Value.absent(),
                Value<bool> favourite = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                required DateTime createdAt,
                Value<DateTime?> lastUsedAt = const Value.absent(),
                Value<String?> acProtocolId = const Value.absent(),
                Value<int?> acCapsVersion = const Value.absent(),
                Value<String?> acLastState = const Value.absent(),
                Value<DateTime?> acLastSentAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                id: id,
                name: name,
                category: category,
                brand: brand,
                codeSetId: codeSetId,
                roomId: roomId,
                transportId: transportId,
                favourite: favourite,
                sortOrder: sortOrder,
                createdAt: createdAt,
                lastUsedAt: lastUsedAt,
                acProtocolId: acProtocolId,
                acCapsVersion: acCapsVersion,
                acLastState: acLastState,
                acLastSentAt: acLastSentAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DevicesTable, DeviceRow>(table),
                  $$DevicesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({roomId = false, deviceKeysRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (deviceKeysRefs) db.deviceKeys],
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
                    if (roomId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.roomId,
                        referencedTable: $$DevicesTableReferences._roomIdTable(
                          db,
                        ),
                        referencedColumn: $$DevicesTableReferences
                            ._roomIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (deviceKeysRefs)
                    await $_getPrefetchedDataByColumns<
                      DeviceRow,
                      $DevicesTable,
                      DeviceKeyRow,
                      $DeviceKeysTable
                    >(
                      currentTable: table,
                      referencedTable: $$DevicesTableReferences
                          ._deviceKeysRefsTable(db),
                      managerFromTypedResult: (p0) => $$DevicesTableReferences(
                        db,
                        table,
                        p0,
                      ).deviceKeysRefs,
                      currentColumn: 'id',
                      referencedColumn: 'device_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DevicesTable,
      DeviceRow,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (DeviceRow, $$DevicesTableReferences),
      DeviceRow,
      PrefetchHooks Function({bool roomId, bool deviceKeysRefs})
    >;
typedef $$DeviceKeysTableCreateCompanionBuilder = DeviceKeysCompanion Function({
  required String deviceId,
  required String keyName,
  Value<String?> label,
  required String signal,
  Value<String?> signalToggled,
  required String source,
  Value<String?> protocol,
  Value<String?> params,
  Value<int> position,
  Value<int> rowid,
});
typedef $$DeviceKeysTableUpdateCompanionBuilder = DeviceKeysCompanion Function({
  Value<String> deviceId,
  Value<String> keyName,
  Value<String?> label,
  Value<String> signal,
  Value<String?> signalToggled,
  Value<String> source,
  Value<String?> protocol,
  Value<String?> params,
  Value<int> position,
  Value<int> rowid,
});

final class $$DeviceKeysTableReferences
    extends BaseReferences<_$AppDatabase, $DeviceKeysTable, DeviceKeyRow> {
  $$DeviceKeysTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DevicesTable _deviceIdTable(_$AppDatabase db) =>
      db.devices.createAlias('device_keys__device_id__devices__id');

  $$DevicesTableProcessedTableManager get deviceId {
    final $_column = $_itemColumn<String>('device_id')!;

    final manager = $$DevicesTableTableManager(
      $_db,
      $_db.devices,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_deviceIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DeviceKeysTableFilterComposer
    extends Composer<_$AppDatabase, $DeviceKeysTable> {
  $$DeviceKeysTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get keyName => $composableBuilder(
    column: $table.keyName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signal => $composableBuilder(
    column: $table.signal,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get signalToggled => $composableBuilder(
    column: $table.signalToggled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get params => $composableBuilder(
    column: $table.params,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$DevicesTableFilterComposer get deviceId {
    final $$DevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deviceId,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableFilterComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceKeysTableOrderingComposer
    extends Composer<_$AppDatabase, $DeviceKeysTable> {
  $$DeviceKeysTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get keyName => $composableBuilder(
    column: $table.keyName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signal => $composableBuilder(
    column: $table.signal,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get signalToggled => $composableBuilder(
    column: $table.signalToggled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get protocol => $composableBuilder(
    column: $table.protocol,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get params => $composableBuilder(
    column: $table.params,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$DevicesTableOrderingComposer get deviceId {
    final $$DevicesTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deviceId,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableOrderingComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceKeysTableAnnotationComposer
    extends Composer<_$AppDatabase, $DeviceKeysTable> {
  $$DeviceKeysTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get keyName =>
      $composableBuilder(column: $table.keyName, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get signal =>
      $composableBuilder(column: $table.signal, builder: (column) => column);

  GeneratedColumn<String> get signalToggled => $composableBuilder(
    column: $table.signalToggled,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<String> get protocol =>
      $composableBuilder(column: $table.protocol, builder: (column) => column);

  GeneratedColumn<String> get params =>
      $composableBuilder(column: $table.params, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$DevicesTableAnnotationComposer get deviceId {
    final $$DevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deviceId,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DeviceKeysTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DeviceKeysTable,
          DeviceKeyRow,
          $$DeviceKeysTableFilterComposer,
          $$DeviceKeysTableOrderingComposer,
          $$DeviceKeysTableAnnotationComposer,
          $$DeviceKeysTableCreateCompanionBuilder,
          $$DeviceKeysTableUpdateCompanionBuilder,
          (DeviceKeyRow, $$DeviceKeysTableReferences),
          DeviceKeyRow,
          PrefetchHooks Function({bool deviceId})
        > {
  $$DeviceKeysTableTableManager(_$AppDatabase db, $DeviceKeysTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DeviceKeysTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DeviceKeysTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DeviceKeysTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> deviceId = const Value.absent(),
                Value<String> keyName = const Value.absent(),
                Value<String?> label = const Value.absent(),
                Value<String> signal = const Value.absent(),
                Value<String?> signalToggled = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<String?> protocol = const Value.absent(),
                Value<String?> params = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceKeysCompanion(
                deviceId: deviceId,
                keyName: keyName,
                label: label,
                signal: signal,
                signalToggled: signalToggled,
                source: source,
                protocol: protocol,
                params: params,
                position: position,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String deviceId,
                required String keyName,
                Value<String?> label = const Value.absent(),
                required String signal,
                Value<String?> signalToggled = const Value.absent(),
                required String source,
                Value<String?> protocol = const Value.absent(),
                Value<String?> params = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DeviceKeysCompanion.insert(
                deviceId: deviceId,
                keyName: keyName,
                label: label,
                signal: signal,
                signalToggled: signalToggled,
                source: source,
                protocol: protocol,
                params: params,
                position: position,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DeviceKeysTable, DeviceKeyRow>(table),
                  $$DeviceKeysTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({deviceId = false}) {
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
                    if (deviceId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.deviceId,
                        referencedTable: $$DeviceKeysTableReferences
                            ._deviceIdTable(db),
                        referencedColumn: $$DeviceKeysTableReferences
                            ._deviceIdTable(db)
                            .id,
                      ) as T;
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

typedef $$DeviceKeysTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DeviceKeysTable,
      DeviceKeyRow,
      $$DeviceKeysTableFilterComposer,
      $$DeviceKeysTableOrderingComposer,
      $$DeviceKeysTableAnnotationComposer,
      $$DeviceKeysTableCreateCompanionBuilder,
      $$DeviceKeysTableUpdateCompanionBuilder,
      (DeviceKeyRow, $$DeviceKeysTableReferences),
      DeviceKeyRow,
      PrefetchHooks Function({bool deviceId})
    >;
typedef $$HubsTableCreateCompanionBuilder = HubsCompanion Function({
  required String id,
  required String kind,
  required String name,
  required String host,
  required int port,
  Value<String?> token,
  Value<String?> extra,
  required DateTime addedAt,
  Value<int> rowid,
});
typedef $$HubsTableUpdateCompanionBuilder = HubsCompanion Function({
  Value<String> id,
  Value<String> kind,
  Value<String> name,
  Value<String> host,
  Value<int> port,
  Value<String?> token,
  Value<String?> extra,
  Value<DateTime> addedAt,
  Value<int> rowid,
});

class $$HubsTableFilterComposer extends Composer<_$AppDatabase, $HubsTable> {
  $$HubsTableFilterComposer({
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

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$HubsTableOrderingComposer extends Composer<_$AppDatabase, $HubsTable> {
  $$HubsTableOrderingComposer({
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

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get host => $composableBuilder(
    column: $table.host,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get port => $composableBuilder(
    column: $table.port,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get token => $composableBuilder(
    column: $table.token,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get extra => $composableBuilder(
    column: $table.extra,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$HubsTableAnnotationComposer
    extends Composer<_$AppDatabase, $HubsTable> {
  $$HubsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get host =>
      $composableBuilder(column: $table.host, builder: (column) => column);

  GeneratedColumn<int> get port =>
      $composableBuilder(column: $table.port, builder: (column) => column);

  GeneratedColumn<String> get token =>
      $composableBuilder(column: $table.token, builder: (column) => column);

  GeneratedColumn<String> get extra =>
      $composableBuilder(column: $table.extra, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);
}

class $$HubsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $HubsTable,
          HubRow,
          $$HubsTableFilterComposer,
          $$HubsTableOrderingComposer,
          $$HubsTableAnnotationComposer,
          $$HubsTableCreateCompanionBuilder,
          $$HubsTableUpdateCompanionBuilder,
          (HubRow, BaseReferences<_$AppDatabase, $HubsTable, HubRow>),
          HubRow,
          PrefetchHooks Function()
        > {
  $$HubsTableTableManager(_$AppDatabase db, $HubsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$HubsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$HubsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$HubsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> host = const Value.absent(),
                Value<int> port = const Value.absent(),
                Value<String?> token = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => HubsCompanion(
                id: id,
                kind: kind,
                name: name,
                host: host,
                port: port,
                token: token,
                extra: extra,
                addedAt: addedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String kind,
                required String name,
                required String host,
                required int port,
                Value<String?> token = const Value.absent(),
                Value<String?> extra = const Value.absent(),
                required DateTime addedAt,
                Value<int> rowid = const Value.absent(),
              }) => HubsCompanion.insert(
                id: id,
                kind: kind,
                name: name,
                host: host,
                port: port,
                token: token,
                extra: extra,
                addedAt: addedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$HubsTable, HubRow>(table),
                  BaseReferences<_$AppDatabase, $HubsTable, HubRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$HubsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $HubsTable,
      HubRow,
      $$HubsTableFilterComposer,
      $$HubsTableOrderingComposer,
      $$HubsTableAnnotationComposer,
      $$HubsTableCreateCompanionBuilder,
      $$HubsTableUpdateCompanionBuilder,
      (HubRow, BaseReferences<_$AppDatabase, $HubsTable, HubRow>),
      HubRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$AppDatabase, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$RoomsTableTableManager get rooms =>
      $$RoomsTableTableManager(_db, _db.rooms);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$DeviceKeysTableTableManager get deviceKeys =>
      $$DeviceKeysTableTableManager(_db, _db.deviceKeys);
  $$HubsTableTableManager get hubs => $$HubsTableTableManager(_db, _db.hubs);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
