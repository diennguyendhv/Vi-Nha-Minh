// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CategoryRowsTable extends CategoryRows
    with TableInfo<$CategoryRowsTable, CategoryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CategoryRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statsEnabledMeta = const VerificationMeta(
    'statsEnabled',
  );
  @override
  late final GeneratedColumn<bool> statsEnabled = GeneratedColumn<bool>(
    'stats_enabled',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("stats_enabled" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _excludeFromTotalsMeta = const VerificationMeta(
    'excludeFromTotals',
  );
  @override
  late final GeneratedColumn<bool> excludeFromTotals = GeneratedColumn<bool>(
    'exclude_from_totals',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("exclude_from_totals" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _linkedExpenseCategoryIdMeta =
      const VerificationMeta('linkedExpenseCategoryId');
  @override
  late final GeneratedColumn<String> linkedExpenseCategoryId =
      GeneratedColumn<String>(
        'linked_expense_category_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _groupKeyMeta = const VerificationMeta(
    'groupKey',
  );
  @override
  late final GeneratedColumn<String> groupKey = GeneratedColumn<String>(
    'group_key',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _isDefaultMeta = const VerificationMeta(
    'isDefault',
  );
  @override
  late final GeneratedColumn<bool> isDefault = GeneratedColumn<bool>(
    'is_default',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_default" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    colorValue,
    type,
    statsEnabled,
    excludeFromTotals,
    linkedExpenseCategoryId,
    groupKey,
    isDefault,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'category_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CategoryRow> instance, {
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
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('stats_enabled')) {
      context.handle(
        _statsEnabledMeta,
        statsEnabled.isAcceptableOrUnknown(
          data['stats_enabled']!,
          _statsEnabledMeta,
        ),
      );
    }
    if (data.containsKey('exclude_from_totals')) {
      context.handle(
        _excludeFromTotalsMeta,
        excludeFromTotals.isAcceptableOrUnknown(
          data['exclude_from_totals']!,
          _excludeFromTotalsMeta,
        ),
      );
    }
    if (data.containsKey('linked_expense_category_id')) {
      context.handle(
        _linkedExpenseCategoryIdMeta,
        linkedExpenseCategoryId.isAcceptableOrUnknown(
          data['linked_expense_category_id']!,
          _linkedExpenseCategoryIdMeta,
        ),
      );
    }
    if (data.containsKey('group_key')) {
      context.handle(
        _groupKeyMeta,
        groupKey.isAcceptableOrUnknown(data['group_key']!, _groupKeyMeta),
      );
    }
    if (data.containsKey('is_default')) {
      context.handle(
        _isDefaultMeta,
        isDefault.isAcceptableOrUnknown(data['is_default']!, _isDefaultMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CategoryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CategoryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      statsEnabled: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}stats_enabled'],
      )!,
      excludeFromTotals: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}exclude_from_totals'],
      )!,
      linkedExpenseCategoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}linked_expense_category_id'],
      ),
      groupKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}group_key'],
      ),
      isDefault: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_default'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $CategoryRowsTable createAlias(String alias) {
    return $CategoryRowsTable(attachedDatabase, alias);
  }
}

class CategoryRow extends DataClass implements Insertable<CategoryRow> {
  final String id;
  final String name;
  final int colorValue;
  final String type;
  final bool statsEnabled;
  final bool excludeFromTotals;
  final String? linkedExpenseCategoryId;

  /// v7: phân loại báo cáo cho danh mục Chi (`business_expense` hoặc NULL =
  /// Chi tiêu). Thêm bằng `ADD COLUMN` — không đụng dữ liệu cũ.
  final String? groupKey;
  final bool isDefault;
  final bool isActive;
  const CategoryRow({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.type,
    required this.statsEnabled,
    required this.excludeFromTotals,
    this.linkedExpenseCategoryId,
    this.groupKey,
    required this.isDefault,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['type'] = Variable<String>(type);
    map['stats_enabled'] = Variable<bool>(statsEnabled);
    map['exclude_from_totals'] = Variable<bool>(excludeFromTotals);
    if (!nullToAbsent || linkedExpenseCategoryId != null) {
      map['linked_expense_category_id'] = Variable<String>(
        linkedExpenseCategoryId,
      );
    }
    if (!nullToAbsent || groupKey != null) {
      map['group_key'] = Variable<String>(groupKey);
    }
    map['is_default'] = Variable<bool>(isDefault);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  CategoryRowsCompanion toCompanion(bool nullToAbsent) {
    return CategoryRowsCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
      type: Value(type),
      statsEnabled: Value(statsEnabled),
      excludeFromTotals: Value(excludeFromTotals),
      linkedExpenseCategoryId: linkedExpenseCategoryId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedExpenseCategoryId),
      groupKey: groupKey == null && nullToAbsent
          ? const Value.absent()
          : Value(groupKey),
      isDefault: Value(isDefault),
      isActive: Value(isActive),
    );
  }

  factory CategoryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CategoryRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      type: serializer.fromJson<String>(json['type']),
      statsEnabled: serializer.fromJson<bool>(json['statsEnabled']),
      excludeFromTotals: serializer.fromJson<bool>(json['excludeFromTotals']),
      linkedExpenseCategoryId: serializer.fromJson<String?>(
        json['linkedExpenseCategoryId'],
      ),
      groupKey: serializer.fromJson<String?>(json['groupKey']),
      isDefault: serializer.fromJson<bool>(json['isDefault']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'type': serializer.toJson<String>(type),
      'statsEnabled': serializer.toJson<bool>(statsEnabled),
      'excludeFromTotals': serializer.toJson<bool>(excludeFromTotals),
      'linkedExpenseCategoryId': serializer.toJson<String?>(
        linkedExpenseCategoryId,
      ),
      'groupKey': serializer.toJson<String?>(groupKey),
      'isDefault': serializer.toJson<bool>(isDefault),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  CategoryRow copyWith({
    String? id,
    String? name,
    int? colorValue,
    String? type,
    bool? statsEnabled,
    bool? excludeFromTotals,
    Value<String?> linkedExpenseCategoryId = const Value.absent(),
    Value<String?> groupKey = const Value.absent(),
    bool? isDefault,
    bool? isActive,
  }) => CategoryRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    type: type ?? this.type,
    statsEnabled: statsEnabled ?? this.statsEnabled,
    excludeFromTotals: excludeFromTotals ?? this.excludeFromTotals,
    linkedExpenseCategoryId: linkedExpenseCategoryId.present
        ? linkedExpenseCategoryId.value
        : this.linkedExpenseCategoryId,
    groupKey: groupKey.present ? groupKey.value : this.groupKey,
    isDefault: isDefault ?? this.isDefault,
    isActive: isActive ?? this.isActive,
  );
  CategoryRow copyWithCompanion(CategoryRowsCompanion data) {
    return CategoryRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      type: data.type.present ? data.type.value : this.type,
      statsEnabled: data.statsEnabled.present
          ? data.statsEnabled.value
          : this.statsEnabled,
      excludeFromTotals: data.excludeFromTotals.present
          ? data.excludeFromTotals.value
          : this.excludeFromTotals,
      linkedExpenseCategoryId: data.linkedExpenseCategoryId.present
          ? data.linkedExpenseCategoryId.value
          : this.linkedExpenseCategoryId,
      groupKey: data.groupKey.present ? data.groupKey.value : this.groupKey,
      isDefault: data.isDefault.present ? data.isDefault.value : this.isDefault,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('type: $type, ')
          ..write('statsEnabled: $statsEnabled, ')
          ..write('excludeFromTotals: $excludeFromTotals, ')
          ..write('linkedExpenseCategoryId: $linkedExpenseCategoryId, ')
          ..write('groupKey: $groupKey, ')
          ..write('isDefault: $isDefault, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    colorValue,
    type,
    statsEnabled,
    excludeFromTotals,
    linkedExpenseCategoryId,
    groupKey,
    isDefault,
    isActive,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CategoryRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.type == this.type &&
          other.statsEnabled == this.statsEnabled &&
          other.excludeFromTotals == this.excludeFromTotals &&
          other.linkedExpenseCategoryId == this.linkedExpenseCategoryId &&
          other.groupKey == this.groupKey &&
          other.isDefault == this.isDefault &&
          other.isActive == this.isActive);
}

class CategoryRowsCompanion extends UpdateCompanion<CategoryRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<String> type;
  final Value<bool> statsEnabled;
  final Value<bool> excludeFromTotals;
  final Value<String?> linkedExpenseCategoryId;
  final Value<String?> groupKey;
  final Value<bool> isDefault;
  final Value<bool> isActive;
  final Value<int> rowid;
  const CategoryRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.type = const Value.absent(),
    this.statsEnabled = const Value.absent(),
    this.excludeFromTotals = const Value.absent(),
    this.linkedExpenseCategoryId = const Value.absent(),
    this.groupKey = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CategoryRowsCompanion.insert({
    required String id,
    required String name,
    required int colorValue,
    required String type,
    this.statsEnabled = const Value.absent(),
    this.excludeFromTotals = const Value.absent(),
    this.linkedExpenseCategoryId = const Value.absent(),
    this.groupKey = const Value.absent(),
    this.isDefault = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       colorValue = Value(colorValue),
       type = Value(type);
  static Insertable<CategoryRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<String>? type,
    Expression<bool>? statsEnabled,
    Expression<bool>? excludeFromTotals,
    Expression<String>? linkedExpenseCategoryId,
    Expression<String>? groupKey,
    Expression<bool>? isDefault,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (type != null) 'type': type,
      if (statsEnabled != null) 'stats_enabled': statsEnabled,
      if (excludeFromTotals != null) 'exclude_from_totals': excludeFromTotals,
      if (linkedExpenseCategoryId != null)
        'linked_expense_category_id': linkedExpenseCategoryId,
      if (groupKey != null) 'group_key': groupKey,
      if (isDefault != null) 'is_default': isDefault,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CategoryRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? colorValue,
    Value<String>? type,
    Value<bool>? statsEnabled,
    Value<bool>? excludeFromTotals,
    Value<String?>? linkedExpenseCategoryId,
    Value<String?>? groupKey,
    Value<bool>? isDefault,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return CategoryRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      type: type ?? this.type,
      statsEnabled: statsEnabled ?? this.statsEnabled,
      excludeFromTotals: excludeFromTotals ?? this.excludeFromTotals,
      linkedExpenseCategoryId:
          linkedExpenseCategoryId ?? this.linkedExpenseCategoryId,
      groupKey: groupKey ?? this.groupKey,
      isDefault: isDefault ?? this.isDefault,
      isActive: isActive ?? this.isActive,
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
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (statsEnabled.present) {
      map['stats_enabled'] = Variable<bool>(statsEnabled.value);
    }
    if (excludeFromTotals.present) {
      map['exclude_from_totals'] = Variable<bool>(excludeFromTotals.value);
    }
    if (linkedExpenseCategoryId.present) {
      map['linked_expense_category_id'] = Variable<String>(
        linkedExpenseCategoryId.value,
      );
    }
    if (groupKey.present) {
      map['group_key'] = Variable<String>(groupKey.value);
    }
    if (isDefault.present) {
      map['is_default'] = Variable<bool>(isDefault.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CategoryRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('type: $type, ')
          ..write('statsEnabled: $statsEnabled, ')
          ..write('excludeFromTotals: $excludeFromTotals, ')
          ..write('linkedExpenseCategoryId: $linkedExpenseCategoryId, ')
          ..write('groupKey: $groupKey, ')
          ..write('isDefault: $isDefault, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StatusRowsTable extends StatusRows
    with TableInfo<$StatusRowsTable, StatusRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StatusRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES category_rows (id)',
    ),
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
  static const VerificationMeta _sortOrderMeta = const VerificationMeta(
    'sortOrder',
  );
  @override
  late final GeneratedColumn<int> sortOrder = GeneratedColumn<int>(
    'sort_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    name,
    sortOrder,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'status_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<StatusRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
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
    } else if (isInserting) {
      context.missing(_sortOrderMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StatusRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StatusRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      sortOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sort_order'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $StatusRowsTable createAlias(String alias) {
    return $StatusRowsTable(attachedDatabase, alias);
  }
}

class StatusRow extends DataClass implements Insertable<StatusRow> {
  final String id;
  final String categoryId;
  final String name;
  final int sortOrder;
  final bool isActive;
  const StatusRow({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category_id'] = Variable<String>(categoryId);
    map['name'] = Variable<String>(name);
    map['sort_order'] = Variable<int>(sortOrder);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  StatusRowsCompanion toCompanion(bool nullToAbsent) {
    return StatusRowsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      name: Value(name),
      sortOrder: Value(sortOrder),
      isActive: Value(isActive),
    );
  }

  factory StatusRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StatusRow(
      id: serializer.fromJson<String>(json['id']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      name: serializer.fromJson<String>(json['name']),
      sortOrder: serializer.fromJson<int>(json['sortOrder']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'categoryId': serializer.toJson<String>(categoryId),
      'name': serializer.toJson<String>(name),
      'sortOrder': serializer.toJson<int>(sortOrder),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  StatusRow copyWith({
    String? id,
    String? categoryId,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) => StatusRow(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    name: name ?? this.name,
    sortOrder: sortOrder ?? this.sortOrder,
    isActive: isActive ?? this.isActive,
  );
  StatusRow copyWithCompanion(StatusRowsCompanion data) {
    return StatusRow(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      name: data.name.present ? data.name.value : this.name,
      sortOrder: data.sortOrder.present ? data.sortOrder.value : this.sortOrder,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StatusRow(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, categoryId, name, sortOrder, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StatusRow &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.name == this.name &&
          other.sortOrder == this.sortOrder &&
          other.isActive == this.isActive);
}

class StatusRowsCompanion extends UpdateCompanion<StatusRow> {
  final Value<String> id;
  final Value<String> categoryId;
  final Value<String> name;
  final Value<int> sortOrder;
  final Value<bool> isActive;
  final Value<int> rowid;
  const StatusRowsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.name = const Value.absent(),
    this.sortOrder = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  StatusRowsCompanion.insert({
    required String id,
    required String categoryId,
    required String name,
    required int sortOrder,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       categoryId = Value(categoryId),
       name = Value(name),
       sortOrder = Value(sortOrder);
  static Insertable<StatusRow> custom({
    Expression<String>? id,
    Expression<String>? categoryId,
    Expression<String>? name,
    Expression<int>? sortOrder,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (name != null) 'name': name,
      if (sortOrder != null) 'sort_order': sortOrder,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  StatusRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? categoryId,
    Value<String>? name,
    Value<int>? sortOrder,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return StatusRowsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (sortOrder.present) {
      map['sort_order'] = Variable<int>(sortOrder.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StatusRowsCompanion(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('name: $name, ')
          ..write('sortOrder: $sortOrder, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $TransactionRowsTable extends TransactionRows
    with TableInfo<$TransactionRowsTable, TransactionRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $TransactionRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _typeMeta = const VerificationMeta('type');
  @override
  late final GeneratedColumn<String> type = GeneratedColumn<String>(
    'type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _transferKindMeta = const VerificationMeta(
    'transferKind',
  );
  @override
  late final GeneratedColumn<String> transferKind = GeneratedColumn<String>(
    'transfer_kind',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _categoryIdMeta = const VerificationMeta(
    'categoryId',
  );
  @override
  late final GeneratedColumn<String> categoryId = GeneratedColumn<String>(
    'category_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES category_rows (id)',
    ),
  );
  static const VerificationMeta _sourceKindMeta = const VerificationMeta(
    'sourceKind',
  );
  @override
  late final GeneratedColumn<String> sourceKind = GeneratedColumn<String>(
    'source_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceRefIdMeta = const VerificationMeta(
    'sourceRefId',
  );
  @override
  late final GeneratedColumn<String> sourceRefId = GeneratedColumn<String>(
    'source_ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _destinationKindMeta = const VerificationMeta(
    'destinationKind',
  );
  @override
  late final GeneratedColumn<String> destinationKind = GeneratedColumn<String>(
    'destination_kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _destinationRefIdMeta = const VerificationMeta(
    'destinationRefId',
  );
  @override
  late final GeneratedColumn<String> destinationRefId = GeneratedColumn<String>(
    'destination_ref_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyMeta = const VerificationMeta(
    'currency',
  );
  @override
  late final GeneratedColumn<String> currency = GeneratedColumn<String>(
    'currency',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('VND'),
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _statusIdMeta = const VerificationMeta(
    'statusId',
  );
  @override
  late final GeneratedColumn<String> statusId = GeneratedColumn<String>(
    'status_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES status_rows (id)',
    ),
  );
  static const VerificationMeta _statusUpdatedAtMeta = const VerificationMeta(
    'statusUpdatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> statusUpdatedAt =
      GeneratedColumn<DateTime>(
        'status_updated_at',
        aliasedName,
        true,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _transactionDateMeta = const VerificationMeta(
    'transactionDate',
  );
  @override
  late final GeneratedColumn<DateTime> transactionDate =
      GeneratedColumn<DateTime>(
        'transaction_date',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
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
  static const VerificationMeta _reversalOfTxIdMeta = const VerificationMeta(
    'reversalOfTxId',
  );
  @override
  late final GeneratedColumn<String> reversalOfTxId = GeneratedColumn<String>(
    'reversal_of_tx_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _correctsTxIdMeta = const VerificationMeta(
    'correctsTxId',
  );
  @override
  late final GeneratedColumn<String> correctsTxId = GeneratedColumn<String>(
    'corrects_tx_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _reversedByTxIdMeta = const VerificationMeta(
    'reversedByTxId',
  );
  @override
  late final GeneratedColumn<String> reversedByTxId = GeneratedColumn<String>(
    'reversed_by_tx_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _recoveryOfTxIdMeta = const VerificationMeta(
    'recoveryOfTxId',
  );
  @override
  late final GeneratedColumn<String> recoveryOfTxId = GeneratedColumn<String>(
    'recovery_of_tx_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _obligationIdMeta = const VerificationMeta(
    'obligationId',
  );
  @override
  late final GeneratedColumn<String> obligationId = GeneratedColumn<String>(
    'obligation_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _settlementGroupIdMeta = const VerificationMeta(
    'settlementGroupId',
  );
  @override
  late final GeneratedColumn<String> settlementGroupId =
      GeneratedColumn<String>(
        'settlement_group_id',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _actorMemberIdMeta = const VerificationMeta(
    'actorMemberId',
  );
  @override
  late final GeneratedColumn<String> actorMemberId = GeneratedColumn<String>(
    'actor_member_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _clientTxIdMeta = const VerificationMeta(
    'clientTxId',
  );
  @override
  late final GeneratedColumn<String> clientTxId = GeneratedColumn<String>(
    'client_tx_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _versionMeta = const VerificationMeta(
    'version',
  );
  @override
  late final GeneratedColumn<int> version = GeneratedColumn<int>(
    'version',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    type,
    transferKind,
    categoryId,
    sourceKind,
    sourceRefId,
    destinationKind,
    destinationRefId,
    amountMinor,
    currency,
    note,
    statusId,
    statusUpdatedAt,
    transactionDate,
    createdAt,
    reversalOfTxId,
    correctsTxId,
    reversedByTxId,
    recoveryOfTxId,
    obligationId,
    settlementGroupId,
    actorMemberId,
    clientTxId,
    version,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'transaction_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<TransactionRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('type')) {
      context.handle(
        _typeMeta,
        type.isAcceptableOrUnknown(data['type']!, _typeMeta),
      );
    } else if (isInserting) {
      context.missing(_typeMeta);
    }
    if (data.containsKey('transfer_kind')) {
      context.handle(
        _transferKindMeta,
        transferKind.isAcceptableOrUnknown(
          data['transfer_kind']!,
          _transferKindMeta,
        ),
      );
    }
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('source_kind')) {
      context.handle(
        _sourceKindMeta,
        sourceKind.isAcceptableOrUnknown(data['source_kind']!, _sourceKindMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceKindMeta);
    }
    if (data.containsKey('source_ref_id')) {
      context.handle(
        _sourceRefIdMeta,
        sourceRefId.isAcceptableOrUnknown(
          data['source_ref_id']!,
          _sourceRefIdMeta,
        ),
      );
    }
    if (data.containsKey('destination_kind')) {
      context.handle(
        _destinationKindMeta,
        destinationKind.isAcceptableOrUnknown(
          data['destination_kind']!,
          _destinationKindMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_destinationKindMeta);
    }
    if (data.containsKey('destination_ref_id')) {
      context.handle(
        _destinationRefIdMeta,
        destinationRefId.isAcceptableOrUnknown(
          data['destination_ref_id']!,
          _destinationRefIdMeta,
        ),
      );
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('currency')) {
      context.handle(
        _currencyMeta,
        currency.isAcceptableOrUnknown(data['currency']!, _currencyMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('status_id')) {
      context.handle(
        _statusIdMeta,
        statusId.isAcceptableOrUnknown(data['status_id']!, _statusIdMeta),
      );
    }
    if (data.containsKey('status_updated_at')) {
      context.handle(
        _statusUpdatedAtMeta,
        statusUpdatedAt.isAcceptableOrUnknown(
          data['status_updated_at']!,
          _statusUpdatedAtMeta,
        ),
      );
    }
    if (data.containsKey('transaction_date')) {
      context.handle(
        _transactionDateMeta,
        transactionDate.isAcceptableOrUnknown(
          data['transaction_date']!,
          _transactionDateMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_transactionDateMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('reversal_of_tx_id')) {
      context.handle(
        _reversalOfTxIdMeta,
        reversalOfTxId.isAcceptableOrUnknown(
          data['reversal_of_tx_id']!,
          _reversalOfTxIdMeta,
        ),
      );
    }
    if (data.containsKey('corrects_tx_id')) {
      context.handle(
        _correctsTxIdMeta,
        correctsTxId.isAcceptableOrUnknown(
          data['corrects_tx_id']!,
          _correctsTxIdMeta,
        ),
      );
    }
    if (data.containsKey('reversed_by_tx_id')) {
      context.handle(
        _reversedByTxIdMeta,
        reversedByTxId.isAcceptableOrUnknown(
          data['reversed_by_tx_id']!,
          _reversedByTxIdMeta,
        ),
      );
    }
    if (data.containsKey('recovery_of_tx_id')) {
      context.handle(
        _recoveryOfTxIdMeta,
        recoveryOfTxId.isAcceptableOrUnknown(
          data['recovery_of_tx_id']!,
          _recoveryOfTxIdMeta,
        ),
      );
    }
    if (data.containsKey('obligation_id')) {
      context.handle(
        _obligationIdMeta,
        obligationId.isAcceptableOrUnknown(
          data['obligation_id']!,
          _obligationIdMeta,
        ),
      );
    }
    if (data.containsKey('settlement_group_id')) {
      context.handle(
        _settlementGroupIdMeta,
        settlementGroupId.isAcceptableOrUnknown(
          data['settlement_group_id']!,
          _settlementGroupIdMeta,
        ),
      );
    }
    if (data.containsKey('actor_member_id')) {
      context.handle(
        _actorMemberIdMeta,
        actorMemberId.isAcceptableOrUnknown(
          data['actor_member_id']!,
          _actorMemberIdMeta,
        ),
      );
    }
    if (data.containsKey('client_tx_id')) {
      context.handle(
        _clientTxIdMeta,
        clientTxId.isAcceptableOrUnknown(
          data['client_tx_id']!,
          _clientTxIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_clientTxIdMeta);
    }
    if (data.containsKey('version')) {
      context.handle(
        _versionMeta,
        version.isAcceptableOrUnknown(data['version']!, _versionMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  TransactionRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return TransactionRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      type: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}type'],
      )!,
      transferKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}transfer_kind'],
      ),
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      sourceKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_kind'],
      )!,
      sourceRefId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_ref_id'],
      ),
      destinationKind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_kind'],
      )!,
      destinationRefId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}destination_ref_id'],
      ),
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      currency: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      statusId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status_id'],
      ),
      statusUpdatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}status_updated_at'],
      ),
      transactionDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}transaction_date'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      reversalOfTxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reversal_of_tx_id'],
      ),
      correctsTxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}corrects_tx_id'],
      ),
      reversedByTxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reversed_by_tx_id'],
      ),
      recoveryOfTxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}recovery_of_tx_id'],
      ),
      obligationId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}obligation_id'],
      ),
      settlementGroupId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settlement_group_id'],
      ),
      actorMemberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}actor_member_id'],
      ),
      clientTxId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}client_tx_id'],
      )!,
      version: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}version'],
      )!,
    );
  }

  @override
  $TransactionRowsTable createAlias(String alias) {
    return $TransactionRowsTable(attachedDatabase, alias);
  }
}

class TransactionRow extends DataClass implements Insertable<TransactionRow> {
  final String id;
  final String type;
  final String? transferKind;
  final String categoryId;
  final String sourceKind;
  final String? sourceRefId;
  final String destinationKind;
  final String? destinationRefId;
  final int amountMinor;
  final String currency;
  final String note;
  final String? statusId;
  final DateTime? statusUpdatedAt;
  final DateTime transactionDate;
  final DateTime createdAt;
  final String? reversalOfTxId;
  final String? correctsTxId;
  final String? reversedByTxId;

  /// Phase 8.6 — giao dịch THU HỒI/HOÀN TIỀN trỏ về `id` của giao dịch Chi
  /// gốc. KHÔNG khai báo FK (giống 3 field self-reference phía trên) — lý
  /// do tương tự: tương thích sync Firestore Giai đoạn B (eventual
  /// consistency, bản ghi con có thể tới trước bản gốc).
  final String? recoveryOfTxId;

  /// Phase 8.7 — giao dịch này thuộc `Obligation.id` nào (Cho vay/Đi vay).
  /// KHÔNG khai báo FK — cùng lý do 3 field self-reference + `recovery_of_tx_id`
  /// ở trên (tương thích sync Firestore Giai đoạn B, eventual consistency).
  final String? obligationId;

  /// Phase 8.7 — ghép cặp 2 leg (gốc + lãi) của CÙNG 1 lần tất toán
  /// Receivable. `null` khi tất toán chỉ có 1 dòng. Xem doc-comment field
  /// tương ứng ở `domain/entities/transaction.dart` — field BẮT BUỘC lưu
  /// riêng (không suy ra được từ `clientTxId`).
  final String? settlementGroupId;

  /// v9 — người thực hiện khoản Chi từ Quỹ (nullable; dòng cũ luôn null, không suy ngược).
  final String? actorMemberId;
  final String clientTxId;
  final int version;
  const TransactionRow({
    required this.id,
    required this.type,
    this.transferKind,
    required this.categoryId,
    required this.sourceKind,
    this.sourceRefId,
    required this.destinationKind,
    this.destinationRefId,
    required this.amountMinor,
    required this.currency,
    required this.note,
    this.statusId,
    this.statusUpdatedAt,
    required this.transactionDate,
    required this.createdAt,
    this.reversalOfTxId,
    this.correctsTxId,
    this.reversedByTxId,
    this.recoveryOfTxId,
    this.obligationId,
    this.settlementGroupId,
    this.actorMemberId,
    required this.clientTxId,
    required this.version,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['type'] = Variable<String>(type);
    if (!nullToAbsent || transferKind != null) {
      map['transfer_kind'] = Variable<String>(transferKind);
    }
    map['category_id'] = Variable<String>(categoryId);
    map['source_kind'] = Variable<String>(sourceKind);
    if (!nullToAbsent || sourceRefId != null) {
      map['source_ref_id'] = Variable<String>(sourceRefId);
    }
    map['destination_kind'] = Variable<String>(destinationKind);
    if (!nullToAbsent || destinationRefId != null) {
      map['destination_ref_id'] = Variable<String>(destinationRefId);
    }
    map['amount_minor'] = Variable<int>(amountMinor);
    map['currency'] = Variable<String>(currency);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || statusId != null) {
      map['status_id'] = Variable<String>(statusId);
    }
    if (!nullToAbsent || statusUpdatedAt != null) {
      map['status_updated_at'] = Variable<DateTime>(statusUpdatedAt);
    }
    map['transaction_date'] = Variable<DateTime>(transactionDate);
    map['created_at'] = Variable<DateTime>(createdAt);
    if (!nullToAbsent || reversalOfTxId != null) {
      map['reversal_of_tx_id'] = Variable<String>(reversalOfTxId);
    }
    if (!nullToAbsent || correctsTxId != null) {
      map['corrects_tx_id'] = Variable<String>(correctsTxId);
    }
    if (!nullToAbsent || reversedByTxId != null) {
      map['reversed_by_tx_id'] = Variable<String>(reversedByTxId);
    }
    if (!nullToAbsent || recoveryOfTxId != null) {
      map['recovery_of_tx_id'] = Variable<String>(recoveryOfTxId);
    }
    if (!nullToAbsent || obligationId != null) {
      map['obligation_id'] = Variable<String>(obligationId);
    }
    if (!nullToAbsent || settlementGroupId != null) {
      map['settlement_group_id'] = Variable<String>(settlementGroupId);
    }
    if (!nullToAbsent || actorMemberId != null) {
      map['actor_member_id'] = Variable<String>(actorMemberId);
    }
    map['client_tx_id'] = Variable<String>(clientTxId);
    map['version'] = Variable<int>(version);
    return map;
  }

  TransactionRowsCompanion toCompanion(bool nullToAbsent) {
    return TransactionRowsCompanion(
      id: Value(id),
      type: Value(type),
      transferKind: transferKind == null && nullToAbsent
          ? const Value.absent()
          : Value(transferKind),
      categoryId: Value(categoryId),
      sourceKind: Value(sourceKind),
      sourceRefId: sourceRefId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceRefId),
      destinationKind: Value(destinationKind),
      destinationRefId: destinationRefId == null && nullToAbsent
          ? const Value.absent()
          : Value(destinationRefId),
      amountMinor: Value(amountMinor),
      currency: Value(currency),
      note: Value(note),
      statusId: statusId == null && nullToAbsent
          ? const Value.absent()
          : Value(statusId),
      statusUpdatedAt: statusUpdatedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(statusUpdatedAt),
      transactionDate: Value(transactionDate),
      createdAt: Value(createdAt),
      reversalOfTxId: reversalOfTxId == null && nullToAbsent
          ? const Value.absent()
          : Value(reversalOfTxId),
      correctsTxId: correctsTxId == null && nullToAbsent
          ? const Value.absent()
          : Value(correctsTxId),
      reversedByTxId: reversedByTxId == null && nullToAbsent
          ? const Value.absent()
          : Value(reversedByTxId),
      recoveryOfTxId: recoveryOfTxId == null && nullToAbsent
          ? const Value.absent()
          : Value(recoveryOfTxId),
      obligationId: obligationId == null && nullToAbsent
          ? const Value.absent()
          : Value(obligationId),
      settlementGroupId: settlementGroupId == null && nullToAbsent
          ? const Value.absent()
          : Value(settlementGroupId),
      actorMemberId: actorMemberId == null && nullToAbsent
          ? const Value.absent()
          : Value(actorMemberId),
      clientTxId: Value(clientTxId),
      version: Value(version),
    );
  }

  factory TransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionRow(
      id: serializer.fromJson<String>(json['id']),
      type: serializer.fromJson<String>(json['type']),
      transferKind: serializer.fromJson<String?>(json['transferKind']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      sourceKind: serializer.fromJson<String>(json['sourceKind']),
      sourceRefId: serializer.fromJson<String?>(json['sourceRefId']),
      destinationKind: serializer.fromJson<String>(json['destinationKind']),
      destinationRefId: serializer.fromJson<String?>(json['destinationRefId']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      currency: serializer.fromJson<String>(json['currency']),
      note: serializer.fromJson<String>(json['note']),
      statusId: serializer.fromJson<String?>(json['statusId']),
      statusUpdatedAt: serializer.fromJson<DateTime?>(json['statusUpdatedAt']),
      transactionDate: serializer.fromJson<DateTime>(json['transactionDate']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      reversalOfTxId: serializer.fromJson<String?>(json['reversalOfTxId']),
      correctsTxId: serializer.fromJson<String?>(json['correctsTxId']),
      reversedByTxId: serializer.fromJson<String?>(json['reversedByTxId']),
      recoveryOfTxId: serializer.fromJson<String?>(json['recoveryOfTxId']),
      obligationId: serializer.fromJson<String?>(json['obligationId']),
      settlementGroupId: serializer.fromJson<String?>(
        json['settlementGroupId'],
      ),
      actorMemberId: serializer.fromJson<String?>(json['actorMemberId']),
      clientTxId: serializer.fromJson<String>(json['clientTxId']),
      version: serializer.fromJson<int>(json['version']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'type': serializer.toJson<String>(type),
      'transferKind': serializer.toJson<String?>(transferKind),
      'categoryId': serializer.toJson<String>(categoryId),
      'sourceKind': serializer.toJson<String>(sourceKind),
      'sourceRefId': serializer.toJson<String?>(sourceRefId),
      'destinationKind': serializer.toJson<String>(destinationKind),
      'destinationRefId': serializer.toJson<String?>(destinationRefId),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'currency': serializer.toJson<String>(currency),
      'note': serializer.toJson<String>(note),
      'statusId': serializer.toJson<String?>(statusId),
      'statusUpdatedAt': serializer.toJson<DateTime?>(statusUpdatedAt),
      'transactionDate': serializer.toJson<DateTime>(transactionDate),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'reversalOfTxId': serializer.toJson<String?>(reversalOfTxId),
      'correctsTxId': serializer.toJson<String?>(correctsTxId),
      'reversedByTxId': serializer.toJson<String?>(reversedByTxId),
      'recoveryOfTxId': serializer.toJson<String?>(recoveryOfTxId),
      'obligationId': serializer.toJson<String?>(obligationId),
      'settlementGroupId': serializer.toJson<String?>(settlementGroupId),
      'actorMemberId': serializer.toJson<String?>(actorMemberId),
      'clientTxId': serializer.toJson<String>(clientTxId),
      'version': serializer.toJson<int>(version),
    };
  }

  TransactionRow copyWith({
    String? id,
    String? type,
    Value<String?> transferKind = const Value.absent(),
    String? categoryId,
    String? sourceKind,
    Value<String?> sourceRefId = const Value.absent(),
    String? destinationKind,
    Value<String?> destinationRefId = const Value.absent(),
    int? amountMinor,
    String? currency,
    String? note,
    Value<String?> statusId = const Value.absent(),
    Value<DateTime?> statusUpdatedAt = const Value.absent(),
    DateTime? transactionDate,
    DateTime? createdAt,
    Value<String?> reversalOfTxId = const Value.absent(),
    Value<String?> correctsTxId = const Value.absent(),
    Value<String?> reversedByTxId = const Value.absent(),
    Value<String?> recoveryOfTxId = const Value.absent(),
    Value<String?> obligationId = const Value.absent(),
    Value<String?> settlementGroupId = const Value.absent(),
    Value<String?> actorMemberId = const Value.absent(),
    String? clientTxId,
    int? version,
  }) => TransactionRow(
    id: id ?? this.id,
    type: type ?? this.type,
    transferKind: transferKind.present ? transferKind.value : this.transferKind,
    categoryId: categoryId ?? this.categoryId,
    sourceKind: sourceKind ?? this.sourceKind,
    sourceRefId: sourceRefId.present ? sourceRefId.value : this.sourceRefId,
    destinationKind: destinationKind ?? this.destinationKind,
    destinationRefId: destinationRefId.present
        ? destinationRefId.value
        : this.destinationRefId,
    amountMinor: amountMinor ?? this.amountMinor,
    currency: currency ?? this.currency,
    note: note ?? this.note,
    statusId: statusId.present ? statusId.value : this.statusId,
    statusUpdatedAt: statusUpdatedAt.present
        ? statusUpdatedAt.value
        : this.statusUpdatedAt,
    transactionDate: transactionDate ?? this.transactionDate,
    createdAt: createdAt ?? this.createdAt,
    reversalOfTxId: reversalOfTxId.present
        ? reversalOfTxId.value
        : this.reversalOfTxId,
    correctsTxId: correctsTxId.present ? correctsTxId.value : this.correctsTxId,
    reversedByTxId: reversedByTxId.present
        ? reversedByTxId.value
        : this.reversedByTxId,
    recoveryOfTxId: recoveryOfTxId.present
        ? recoveryOfTxId.value
        : this.recoveryOfTxId,
    obligationId: obligationId.present ? obligationId.value : this.obligationId,
    settlementGroupId: settlementGroupId.present
        ? settlementGroupId.value
        : this.settlementGroupId,
    actorMemberId: actorMemberId.present
        ? actorMemberId.value
        : this.actorMemberId,
    clientTxId: clientTxId ?? this.clientTxId,
    version: version ?? this.version,
  );
  TransactionRow copyWithCompanion(TransactionRowsCompanion data) {
    return TransactionRow(
      id: data.id.present ? data.id.value : this.id,
      type: data.type.present ? data.type.value : this.type,
      transferKind: data.transferKind.present
          ? data.transferKind.value
          : this.transferKind,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      sourceKind: data.sourceKind.present
          ? data.sourceKind.value
          : this.sourceKind,
      sourceRefId: data.sourceRefId.present
          ? data.sourceRefId.value
          : this.sourceRefId,
      destinationKind: data.destinationKind.present
          ? data.destinationKind.value
          : this.destinationKind,
      destinationRefId: data.destinationRefId.present
          ? data.destinationRefId.value
          : this.destinationRefId,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      currency: data.currency.present ? data.currency.value : this.currency,
      note: data.note.present ? data.note.value : this.note,
      statusId: data.statusId.present ? data.statusId.value : this.statusId,
      statusUpdatedAt: data.statusUpdatedAt.present
          ? data.statusUpdatedAt.value
          : this.statusUpdatedAt,
      transactionDate: data.transactionDate.present
          ? data.transactionDate.value
          : this.transactionDate,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      reversalOfTxId: data.reversalOfTxId.present
          ? data.reversalOfTxId.value
          : this.reversalOfTxId,
      correctsTxId: data.correctsTxId.present
          ? data.correctsTxId.value
          : this.correctsTxId,
      reversedByTxId: data.reversedByTxId.present
          ? data.reversedByTxId.value
          : this.reversedByTxId,
      recoveryOfTxId: data.recoveryOfTxId.present
          ? data.recoveryOfTxId.value
          : this.recoveryOfTxId,
      obligationId: data.obligationId.present
          ? data.obligationId.value
          : this.obligationId,
      settlementGroupId: data.settlementGroupId.present
          ? data.settlementGroupId.value
          : this.settlementGroupId,
      actorMemberId: data.actorMemberId.present
          ? data.actorMemberId.value
          : this.actorMemberId,
      clientTxId: data.clientTxId.present
          ? data.clientTxId.value
          : this.clientTxId,
      version: data.version.present ? data.version.value : this.version,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionRow(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('transferKind: $transferKind, ')
          ..write('categoryId: $categoryId, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceRefId: $sourceRefId, ')
          ..write('destinationKind: $destinationKind, ')
          ..write('destinationRefId: $destinationRefId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('note: $note, ')
          ..write('statusId: $statusId, ')
          ..write('statusUpdatedAt: $statusUpdatedAt, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('reversalOfTxId: $reversalOfTxId, ')
          ..write('correctsTxId: $correctsTxId, ')
          ..write('reversedByTxId: $reversedByTxId, ')
          ..write('recoveryOfTxId: $recoveryOfTxId, ')
          ..write('obligationId: $obligationId, ')
          ..write('settlementGroupId: $settlementGroupId, ')
          ..write('actorMemberId: $actorMemberId, ')
          ..write('clientTxId: $clientTxId, ')
          ..write('version: $version')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    type,
    transferKind,
    categoryId,
    sourceKind,
    sourceRefId,
    destinationKind,
    destinationRefId,
    amountMinor,
    currency,
    note,
    statusId,
    statusUpdatedAt,
    transactionDate,
    createdAt,
    reversalOfTxId,
    correctsTxId,
    reversedByTxId,
    recoveryOfTxId,
    obligationId,
    settlementGroupId,
    actorMemberId,
    clientTxId,
    version,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionRow &&
          other.id == this.id &&
          other.type == this.type &&
          other.transferKind == this.transferKind &&
          other.categoryId == this.categoryId &&
          other.sourceKind == this.sourceKind &&
          other.sourceRefId == this.sourceRefId &&
          other.destinationKind == this.destinationKind &&
          other.destinationRefId == this.destinationRefId &&
          other.amountMinor == this.amountMinor &&
          other.currency == this.currency &&
          other.note == this.note &&
          other.statusId == this.statusId &&
          other.statusUpdatedAt == this.statusUpdatedAt &&
          other.transactionDate == this.transactionDate &&
          other.createdAt == this.createdAt &&
          other.reversalOfTxId == this.reversalOfTxId &&
          other.correctsTxId == this.correctsTxId &&
          other.reversedByTxId == this.reversedByTxId &&
          other.recoveryOfTxId == this.recoveryOfTxId &&
          other.obligationId == this.obligationId &&
          other.settlementGroupId == this.settlementGroupId &&
          other.actorMemberId == this.actorMemberId &&
          other.clientTxId == this.clientTxId &&
          other.version == this.version);
}

class TransactionRowsCompanion extends UpdateCompanion<TransactionRow> {
  final Value<String> id;
  final Value<String> type;
  final Value<String?> transferKind;
  final Value<String> categoryId;
  final Value<String> sourceKind;
  final Value<String?> sourceRefId;
  final Value<String> destinationKind;
  final Value<String?> destinationRefId;
  final Value<int> amountMinor;
  final Value<String> currency;
  final Value<String> note;
  final Value<String?> statusId;
  final Value<DateTime?> statusUpdatedAt;
  final Value<DateTime> transactionDate;
  final Value<DateTime> createdAt;
  final Value<String?> reversalOfTxId;
  final Value<String?> correctsTxId;
  final Value<String?> reversedByTxId;
  final Value<String?> recoveryOfTxId;
  final Value<String?> obligationId;
  final Value<String?> settlementGroupId;
  final Value<String?> actorMemberId;
  final Value<String> clientTxId;
  final Value<int> version;
  final Value<int> rowid;
  const TransactionRowsCompanion({
    this.id = const Value.absent(),
    this.type = const Value.absent(),
    this.transferKind = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.sourceKind = const Value.absent(),
    this.sourceRefId = const Value.absent(),
    this.destinationKind = const Value.absent(),
    this.destinationRefId = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.currency = const Value.absent(),
    this.note = const Value.absent(),
    this.statusId = const Value.absent(),
    this.statusUpdatedAt = const Value.absent(),
    this.transactionDate = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.reversalOfTxId = const Value.absent(),
    this.correctsTxId = const Value.absent(),
    this.reversedByTxId = const Value.absent(),
    this.recoveryOfTxId = const Value.absent(),
    this.obligationId = const Value.absent(),
    this.settlementGroupId = const Value.absent(),
    this.actorMemberId = const Value.absent(),
    this.clientTxId = const Value.absent(),
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionRowsCompanion.insert({
    required String id,
    required String type,
    this.transferKind = const Value.absent(),
    required String categoryId,
    required String sourceKind,
    this.sourceRefId = const Value.absent(),
    required String destinationKind,
    this.destinationRefId = const Value.absent(),
    required int amountMinor,
    this.currency = const Value.absent(),
    this.note = const Value.absent(),
    this.statusId = const Value.absent(),
    this.statusUpdatedAt = const Value.absent(),
    required DateTime transactionDate,
    required DateTime createdAt,
    this.reversalOfTxId = const Value.absent(),
    this.correctsTxId = const Value.absent(),
    this.reversedByTxId = const Value.absent(),
    this.recoveryOfTxId = const Value.absent(),
    this.obligationId = const Value.absent(),
    this.settlementGroupId = const Value.absent(),
    this.actorMemberId = const Value.absent(),
    required String clientTxId,
    this.version = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       type = Value(type),
       categoryId = Value(categoryId),
       sourceKind = Value(sourceKind),
       destinationKind = Value(destinationKind),
       amountMinor = Value(amountMinor),
       transactionDate = Value(transactionDate),
       createdAt = Value(createdAt),
       clientTxId = Value(clientTxId);
  static Insertable<TransactionRow> custom({
    Expression<String>? id,
    Expression<String>? type,
    Expression<String>? transferKind,
    Expression<String>? categoryId,
    Expression<String>? sourceKind,
    Expression<String>? sourceRefId,
    Expression<String>? destinationKind,
    Expression<String>? destinationRefId,
    Expression<int>? amountMinor,
    Expression<String>? currency,
    Expression<String>? note,
    Expression<String>? statusId,
    Expression<DateTime>? statusUpdatedAt,
    Expression<DateTime>? transactionDate,
    Expression<DateTime>? createdAt,
    Expression<String>? reversalOfTxId,
    Expression<String>? correctsTxId,
    Expression<String>? reversedByTxId,
    Expression<String>? recoveryOfTxId,
    Expression<String>? obligationId,
    Expression<String>? settlementGroupId,
    Expression<String>? actorMemberId,
    Expression<String>? clientTxId,
    Expression<int>? version,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (type != null) 'type': type,
      if (transferKind != null) 'transfer_kind': transferKind,
      if (categoryId != null) 'category_id': categoryId,
      if (sourceKind != null) 'source_kind': sourceKind,
      if (sourceRefId != null) 'source_ref_id': sourceRefId,
      if (destinationKind != null) 'destination_kind': destinationKind,
      if (destinationRefId != null) 'destination_ref_id': destinationRefId,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (currency != null) 'currency': currency,
      if (note != null) 'note': note,
      if (statusId != null) 'status_id': statusId,
      if (statusUpdatedAt != null) 'status_updated_at': statusUpdatedAt,
      if (transactionDate != null) 'transaction_date': transactionDate,
      if (createdAt != null) 'created_at': createdAt,
      if (reversalOfTxId != null) 'reversal_of_tx_id': reversalOfTxId,
      if (correctsTxId != null) 'corrects_tx_id': correctsTxId,
      if (reversedByTxId != null) 'reversed_by_tx_id': reversedByTxId,
      if (recoveryOfTxId != null) 'recovery_of_tx_id': recoveryOfTxId,
      if (obligationId != null) 'obligation_id': obligationId,
      if (settlementGroupId != null) 'settlement_group_id': settlementGroupId,
      if (actorMemberId != null) 'actor_member_id': actorMemberId,
      if (clientTxId != null) 'client_tx_id': clientTxId,
      if (version != null) 'version': version,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? type,
    Value<String?>? transferKind,
    Value<String>? categoryId,
    Value<String>? sourceKind,
    Value<String?>? sourceRefId,
    Value<String>? destinationKind,
    Value<String?>? destinationRefId,
    Value<int>? amountMinor,
    Value<String>? currency,
    Value<String>? note,
    Value<String?>? statusId,
    Value<DateTime?>? statusUpdatedAt,
    Value<DateTime>? transactionDate,
    Value<DateTime>? createdAt,
    Value<String?>? reversalOfTxId,
    Value<String?>? correctsTxId,
    Value<String?>? reversedByTxId,
    Value<String?>? recoveryOfTxId,
    Value<String?>? obligationId,
    Value<String?>? settlementGroupId,
    Value<String?>? actorMemberId,
    Value<String>? clientTxId,
    Value<int>? version,
    Value<int>? rowid,
  }) {
    return TransactionRowsCompanion(
      id: id ?? this.id,
      type: type ?? this.type,
      transferKind: transferKind ?? this.transferKind,
      categoryId: categoryId ?? this.categoryId,
      sourceKind: sourceKind ?? this.sourceKind,
      sourceRefId: sourceRefId ?? this.sourceRefId,
      destinationKind: destinationKind ?? this.destinationKind,
      destinationRefId: destinationRefId ?? this.destinationRefId,
      amountMinor: amountMinor ?? this.amountMinor,
      currency: currency ?? this.currency,
      note: note ?? this.note,
      statusId: statusId ?? this.statusId,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      transactionDate: transactionDate ?? this.transactionDate,
      createdAt: createdAt ?? this.createdAt,
      reversalOfTxId: reversalOfTxId ?? this.reversalOfTxId,
      correctsTxId: correctsTxId ?? this.correctsTxId,
      reversedByTxId: reversedByTxId ?? this.reversedByTxId,
      recoveryOfTxId: recoveryOfTxId ?? this.recoveryOfTxId,
      obligationId: obligationId ?? this.obligationId,
      settlementGroupId: settlementGroupId ?? this.settlementGroupId,
      actorMemberId: actorMemberId ?? this.actorMemberId,
      clientTxId: clientTxId ?? this.clientTxId,
      version: version ?? this.version,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (type.present) {
      map['type'] = Variable<String>(type.value);
    }
    if (transferKind.present) {
      map['transfer_kind'] = Variable<String>(transferKind.value);
    }
    if (categoryId.present) {
      map['category_id'] = Variable<String>(categoryId.value);
    }
    if (sourceKind.present) {
      map['source_kind'] = Variable<String>(sourceKind.value);
    }
    if (sourceRefId.present) {
      map['source_ref_id'] = Variable<String>(sourceRefId.value);
    }
    if (destinationKind.present) {
      map['destination_kind'] = Variable<String>(destinationKind.value);
    }
    if (destinationRefId.present) {
      map['destination_ref_id'] = Variable<String>(destinationRefId.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (currency.present) {
      map['currency'] = Variable<String>(currency.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (statusId.present) {
      map['status_id'] = Variable<String>(statusId.value);
    }
    if (statusUpdatedAt.present) {
      map['status_updated_at'] = Variable<DateTime>(statusUpdatedAt.value);
    }
    if (transactionDate.present) {
      map['transaction_date'] = Variable<DateTime>(transactionDate.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (reversalOfTxId.present) {
      map['reversal_of_tx_id'] = Variable<String>(reversalOfTxId.value);
    }
    if (correctsTxId.present) {
      map['corrects_tx_id'] = Variable<String>(correctsTxId.value);
    }
    if (reversedByTxId.present) {
      map['reversed_by_tx_id'] = Variable<String>(reversedByTxId.value);
    }
    if (recoveryOfTxId.present) {
      map['recovery_of_tx_id'] = Variable<String>(recoveryOfTxId.value);
    }
    if (obligationId.present) {
      map['obligation_id'] = Variable<String>(obligationId.value);
    }
    if (settlementGroupId.present) {
      map['settlement_group_id'] = Variable<String>(settlementGroupId.value);
    }
    if (actorMemberId.present) {
      map['actor_member_id'] = Variable<String>(actorMemberId.value);
    }
    if (clientTxId.present) {
      map['client_tx_id'] = Variable<String>(clientTxId.value);
    }
    if (version.present) {
      map['version'] = Variable<int>(version.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('TransactionRowsCompanion(')
          ..write('id: $id, ')
          ..write('type: $type, ')
          ..write('transferKind: $transferKind, ')
          ..write('categoryId: $categoryId, ')
          ..write('sourceKind: $sourceKind, ')
          ..write('sourceRefId: $sourceRefId, ')
          ..write('destinationKind: $destinationKind, ')
          ..write('destinationRefId: $destinationRefId, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('currency: $currency, ')
          ..write('note: $note, ')
          ..write('statusId: $statusId, ')
          ..write('statusUpdatedAt: $statusUpdatedAt, ')
          ..write('transactionDate: $transactionDate, ')
          ..write('createdAt: $createdAt, ')
          ..write('reversalOfTxId: $reversalOfTxId, ')
          ..write('correctsTxId: $correctsTxId, ')
          ..write('reversedByTxId: $reversedByTxId, ')
          ..write('recoveryOfTxId: $recoveryOfTxId, ')
          ..write('obligationId: $obligationId, ')
          ..write('settlementGroupId: $settlementGroupId, ')
          ..write('actorMemberId: $actorMemberId, ')
          ..write('clientTxId: $clientTxId, ')
          ..write('version: $version, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FundRowsTable extends FundRows with TableInfo<$FundRowsTable, FundRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FundRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, colorValue, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fund_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<FundRow> instance, {
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
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FundRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FundRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $FundRowsTable createAlias(String alias) {
    return $FundRowsTable(attachedDatabase, alias);
  }
}

class FundRow extends DataClass implements Insertable<FundRow> {
  final String id;
  final String name;
  final int colorValue;
  final bool isActive;
  const FundRow({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  FundRowsCompanion toCompanion(bool nullToAbsent) {
    return FundRowsCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
      isActive: Value(isActive),
    );
  }

  factory FundRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FundRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  FundRow copyWith({
    String? id,
    String? name,
    int? colorValue,
    bool? isActive,
  }) => FundRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    isActive: isActive ?? this.isActive,
  );
  FundRow copyWithCompanion(FundRowsCompanion data) {
    return FundRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FundRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FundRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.isActive == this.isActive);
}

class FundRowsCompanion extends UpdateCompanion<FundRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<bool> isActive;
  final Value<int> rowid;
  const FundRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FundRowsCompanion.insert({
    required String id,
    required String name,
    required int colorValue,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       colorValue = Value(colorValue);
  static Insertable<FundRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FundRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? colorValue,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return FundRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isActive: isActive ?? this.isActive,
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
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FundRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SavingsAssetTypeRowsTable extends SavingsAssetTypeRows
    with TableInfo<$SavingsAssetTypeRowsTable, SavingsAssetTypeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SavingsAssetTypeRowsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _colorValueMeta = const VerificationMeta(
    'colorValue',
  );
  @override
  late final GeneratedColumn<int> colorValue = GeneratedColumn<int>(
    'color_value',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, colorValue, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'savings_asset_type_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SavingsAssetTypeRow> instance, {
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
    if (data.containsKey('color_value')) {
      context.handle(
        _colorValueMeta,
        colorValue.isAcceptableOrUnknown(data['color_value']!, _colorValueMeta),
      );
    } else if (isInserting) {
      context.missing(_colorValueMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SavingsAssetTypeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SavingsAssetTypeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      colorValue: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}color_value'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $SavingsAssetTypeRowsTable createAlias(String alias) {
    return $SavingsAssetTypeRowsTable(attachedDatabase, alias);
  }
}

class SavingsAssetTypeRow extends DataClass
    implements Insertable<SavingsAssetTypeRow> {
  final String id;
  final String name;
  final int colorValue;
  final bool isActive;
  const SavingsAssetTypeRow({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['color_value'] = Variable<int>(colorValue);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  SavingsAssetTypeRowsCompanion toCompanion(bool nullToAbsent) {
    return SavingsAssetTypeRowsCompanion(
      id: Value(id),
      name: Value(name),
      colorValue: Value(colorValue),
      isActive: Value(isActive),
    );
  }

  factory SavingsAssetTypeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SavingsAssetTypeRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      colorValue: serializer.fromJson<int>(json['colorValue']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'colorValue': serializer.toJson<int>(colorValue),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  SavingsAssetTypeRow copyWith({
    String? id,
    String? name,
    int? colorValue,
    bool? isActive,
  }) => SavingsAssetTypeRow(
    id: id ?? this.id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    isActive: isActive ?? this.isActive,
  );
  SavingsAssetTypeRow copyWithCompanion(SavingsAssetTypeRowsCompanion data) {
    return SavingsAssetTypeRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      colorValue: data.colorValue.present
          ? data.colorValue.value
          : this.colorValue,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SavingsAssetTypeRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, colorValue, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SavingsAssetTypeRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.colorValue == this.colorValue &&
          other.isActive == this.isActive);
}

class SavingsAssetTypeRowsCompanion
    extends UpdateCompanion<SavingsAssetTypeRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<int> colorValue;
  final Value<bool> isActive;
  final Value<int> rowid;
  const SavingsAssetTypeRowsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.colorValue = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SavingsAssetTypeRowsCompanion.insert({
    required String id,
    required String name,
    required int colorValue,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       colorValue = Value(colorValue);
  static Insertable<SavingsAssetTypeRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<int>? colorValue,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (colorValue != null) 'color_value': colorValue,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SavingsAssetTypeRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<int>? colorValue,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return SavingsAssetTypeRowsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      isActive: isActive ?? this.isActive,
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
    if (colorValue.present) {
      map['color_value'] = Variable<int>(colorValue.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SavingsAssetTypeRowsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('colorValue: $colorValue, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CounterpartyRowsTable extends CounterpartyRows
    with TableInfo<$CounterpartyRowsTable, CounterpartyRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CounterpartyRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayNameMeta = const VerificationMeta(
    'displayName',
  );
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
    'display_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [id, displayName, isActive];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'counterparty_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<CounterpartyRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
        _displayNameMeta,
        displayName.isAcceptableOrUnknown(
          data['display_name']!,
          _displayNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CounterpartyRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CounterpartyRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      displayName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}display_name'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $CounterpartyRowsTable createAlias(String alias) {
    return $CounterpartyRowsTable(attachedDatabase, alias);
  }
}

class CounterpartyRow extends DataClass implements Insertable<CounterpartyRow> {
  final String id;
  final String displayName;
  final bool isActive;
  const CounterpartyRow({
    required this.id,
    required this.displayName,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  CounterpartyRowsCompanion toCompanion(bool nullToAbsent) {
    return CounterpartyRowsCompanion(
      id: Value(id),
      displayName: Value(displayName),
      isActive: Value(isActive),
    );
  }

  factory CounterpartyRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CounterpartyRow(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  CounterpartyRow copyWith({String? id, String? displayName, bool? isActive}) =>
      CounterpartyRow(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        isActive: isActive ?? this.isActive,
      );
  CounterpartyRow copyWithCompanion(CounterpartyRowsCompanion data) {
    return CounterpartyRow(
      id: data.id.present ? data.id.value : this.id,
      displayName: data.displayName.present
          ? data.displayName.value
          : this.displayName,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CounterpartyRow(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, displayName, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CounterpartyRow &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.isActive == this.isActive);
}

class CounterpartyRowsCompanion extends UpdateCompanion<CounterpartyRow> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<bool> isActive;
  final Value<int> rowid;
  const CounterpartyRowsCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CounterpartyRowsCompanion.insert({
    required String id,
    required String displayName,
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       displayName = Value(displayName);
  static Insertable<CounterpartyRow> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CounterpartyRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? displayName,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return CounterpartyRowsCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CounterpartyRowsCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ObligationRowsTable extends ObligationRows
    with TableInfo<$ObligationRowsTable, ObligationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ObligationRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _counterpartyIdMeta = const VerificationMeta(
    'counterpartyId',
  );
  @override
  late final GeneratedColumn<String> counterpartyId = GeneratedColumn<String>(
    'counterparty_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES counterparty_rows (id)',
    ),
  );
  static const VerificationMeta _directionMeta = const VerificationMeta(
    'direction',
  );
  @override
  late final GeneratedColumn<String> direction = GeneratedColumn<String>(
    'direction',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueDateMeta = const VerificationMeta(
    'dueDate',
  );
  @override
  late final GeneratedColumn<DateTime> dueDate = GeneratedColumn<DateTime>(
    'due_date',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _isActiveMeta = const VerificationMeta(
    'isActive',
  );
  @override
  late final GeneratedColumn<bool> isActive = GeneratedColumn<bool>(
    'is_active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("is_active" IN (0, 1))',
    ),
    defaultValue: const Constant(true),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    counterpartyId,
    direction,
    dueDate,
    note,
    isActive,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'obligation_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<ObligationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('counterparty_id')) {
      context.handle(
        _counterpartyIdMeta,
        counterpartyId.isAcceptableOrUnknown(
          data['counterparty_id']!,
          _counterpartyIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_counterpartyIdMeta);
    }
    if (data.containsKey('direction')) {
      context.handle(
        _directionMeta,
        direction.isAcceptableOrUnknown(data['direction']!, _directionMeta),
      );
    } else if (isInserting) {
      context.missing(_directionMeta);
    }
    if (data.containsKey('due_date')) {
      context.handle(
        _dueDateMeta,
        dueDate.isAcceptableOrUnknown(data['due_date']!, _dueDateMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('is_active')) {
      context.handle(
        _isActiveMeta,
        isActive.isAcceptableOrUnknown(data['is_active']!, _isActiveMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ObligationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ObligationRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      counterpartyId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}counterparty_id'],
      )!,
      direction: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}direction'],
      )!,
      dueDate: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}due_date'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      isActive: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}is_active'],
      )!,
    );
  }

  @override
  $ObligationRowsTable createAlias(String alias) {
    return $ObligationRowsTable(attachedDatabase, alias);
  }
}

class ObligationRow extends DataClass implements Insertable<ObligationRow> {
  final String id;
  final String counterpartyId;
  final String direction;
  final DateTime? dueDate;
  final String note;
  final bool isActive;
  const ObligationRow({
    required this.id,
    required this.counterpartyId,
    required this.direction,
    this.dueDate,
    required this.note,
    required this.isActive,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['counterparty_id'] = Variable<String>(counterpartyId);
    map['direction'] = Variable<String>(direction);
    if (!nullToAbsent || dueDate != null) {
      map['due_date'] = Variable<DateTime>(dueDate);
    }
    map['note'] = Variable<String>(note);
    map['is_active'] = Variable<bool>(isActive);
    return map;
  }

  ObligationRowsCompanion toCompanion(bool nullToAbsent) {
    return ObligationRowsCompanion(
      id: Value(id),
      counterpartyId: Value(counterpartyId),
      direction: Value(direction),
      dueDate: dueDate == null && nullToAbsent
          ? const Value.absent()
          : Value(dueDate),
      note: Value(note),
      isActive: Value(isActive),
    );
  }

  factory ObligationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ObligationRow(
      id: serializer.fromJson<String>(json['id']),
      counterpartyId: serializer.fromJson<String>(json['counterpartyId']),
      direction: serializer.fromJson<String>(json['direction']),
      dueDate: serializer.fromJson<DateTime?>(json['dueDate']),
      note: serializer.fromJson<String>(json['note']),
      isActive: serializer.fromJson<bool>(json['isActive']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'counterpartyId': serializer.toJson<String>(counterpartyId),
      'direction': serializer.toJson<String>(direction),
      'dueDate': serializer.toJson<DateTime?>(dueDate),
      'note': serializer.toJson<String>(note),
      'isActive': serializer.toJson<bool>(isActive),
    };
  }

  ObligationRow copyWith({
    String? id,
    String? counterpartyId,
    String? direction,
    Value<DateTime?> dueDate = const Value.absent(),
    String? note,
    bool? isActive,
  }) => ObligationRow(
    id: id ?? this.id,
    counterpartyId: counterpartyId ?? this.counterpartyId,
    direction: direction ?? this.direction,
    dueDate: dueDate.present ? dueDate.value : this.dueDate,
    note: note ?? this.note,
    isActive: isActive ?? this.isActive,
  );
  ObligationRow copyWithCompanion(ObligationRowsCompanion data) {
    return ObligationRow(
      id: data.id.present ? data.id.value : this.id,
      counterpartyId: data.counterpartyId.present
          ? data.counterpartyId.value
          : this.counterpartyId,
      direction: data.direction.present ? data.direction.value : this.direction,
      dueDate: data.dueDate.present ? data.dueDate.value : this.dueDate,
      note: data.note.present ? data.note.value : this.note,
      isActive: data.isActive.present ? data.isActive.value : this.isActive,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ObligationRow(')
          ..write('id: $id, ')
          ..write('counterpartyId: $counterpartyId, ')
          ..write('direction: $direction, ')
          ..write('dueDate: $dueDate, ')
          ..write('note: $note, ')
          ..write('isActive: $isActive')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, counterpartyId, direction, dueDate, note, isActive);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ObligationRow &&
          other.id == this.id &&
          other.counterpartyId == this.counterpartyId &&
          other.direction == this.direction &&
          other.dueDate == this.dueDate &&
          other.note == this.note &&
          other.isActive == this.isActive);
}

class ObligationRowsCompanion extends UpdateCompanion<ObligationRow> {
  final Value<String> id;
  final Value<String> counterpartyId;
  final Value<String> direction;
  final Value<DateTime?> dueDate;
  final Value<String> note;
  final Value<bool> isActive;
  final Value<int> rowid;
  const ObligationRowsCompanion({
    this.id = const Value.absent(),
    this.counterpartyId = const Value.absent(),
    this.direction = const Value.absent(),
    this.dueDate = const Value.absent(),
    this.note = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ObligationRowsCompanion.insert({
    required String id,
    required String counterpartyId,
    required String direction,
    this.dueDate = const Value.absent(),
    this.note = const Value.absent(),
    this.isActive = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       counterpartyId = Value(counterpartyId),
       direction = Value(direction);
  static Insertable<ObligationRow> custom({
    Expression<String>? id,
    Expression<String>? counterpartyId,
    Expression<String>? direction,
    Expression<DateTime>? dueDate,
    Expression<String>? note,
    Expression<bool>? isActive,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (counterpartyId != null) 'counterparty_id': counterpartyId,
      if (direction != null) 'direction': direction,
      if (dueDate != null) 'due_date': dueDate,
      if (note != null) 'note': note,
      if (isActive != null) 'is_active': isActive,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ObligationRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? counterpartyId,
    Value<String>? direction,
    Value<DateTime?>? dueDate,
    Value<String>? note,
    Value<bool>? isActive,
    Value<int>? rowid,
  }) {
    return ObligationRowsCompanion(
      id: id ?? this.id,
      counterpartyId: counterpartyId ?? this.counterpartyId,
      direction: direction ?? this.direction,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      isActive: isActive ?? this.isActive,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (counterpartyId.present) {
      map['counterparty_id'] = Variable<String>(counterpartyId.value);
    }
    if (direction.present) {
      map['direction'] = Variable<String>(direction.value);
    }
    if (dueDate.present) {
      map['due_date'] = Variable<DateTime>(dueDate.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (isActive.present) {
      map['is_active'] = Variable<bool>(isActive.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ObligationRowsCompanion(')
          ..write('id: $id, ')
          ..write('counterpartyId: $counterpartyId, ')
          ..write('direction: $direction, ')
          ..write('dueDate: $dueDate, ')
          ..write('note: $note, ')
          ..write('isActive: $isActive, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $WalletMetaTable extends WalletMeta
    with TableInfo<$WalletMetaTable, WalletMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $WalletMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _singletonMeta = const VerificationMeta(
    'singleton',
  );
  @override
  late final GeneratedColumn<int> singleton = GeneratedColumn<int>(
    'singleton',
    aliasedName,
    false,
    check: () => singleton.equals(1),
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(1),
  );
  static const VerificationMeta _walletIdMeta = const VerificationMeta(
    'walletId',
  );
  @override
  late final GeneratedColumn<String> walletId = GeneratedColumn<String>(
    'wallet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
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
  @override
  List<GeneratedColumn> get $columns => [singleton, walletId, kind, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'wallet_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<WalletMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('singleton')) {
      context.handle(
        _singletonMeta,
        singleton.isAcceptableOrUnknown(data['singleton']!, _singletonMeta),
      );
    }
    if (data.containsKey('wallet_id')) {
      context.handle(
        _walletIdMeta,
        walletId.isAcceptableOrUnknown(data['wallet_id']!, _walletIdMeta),
      );
    } else if (isInserting) {
      context.missing(_walletIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
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
  Set<GeneratedColumn> get $primaryKey => {singleton};
  @override
  WalletMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return WalletMetaRow(
      singleton: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}singleton'],
      )!,
      walletId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}wallet_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $WalletMetaTable createAlias(String alias) {
    return $WalletMetaTable(attachedDatabase, alias);
  }
}

class WalletMetaRow extends DataClass implements Insertable<WalletMetaRow> {
  final int singleton;
  final String walletId;
  final String kind;
  final DateTime createdAt;
  const WalletMetaRow({
    required this.singleton,
    required this.walletId,
    required this.kind,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['singleton'] = Variable<int>(singleton);
    map['wallet_id'] = Variable<String>(walletId);
    map['kind'] = Variable<String>(kind);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  WalletMetaCompanion toCompanion(bool nullToAbsent) {
    return WalletMetaCompanion(
      singleton: Value(singleton),
      walletId: Value(walletId),
      kind: Value(kind),
      createdAt: Value(createdAt),
    );
  }

  factory WalletMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return WalletMetaRow(
      singleton: serializer.fromJson<int>(json['singleton']),
      walletId: serializer.fromJson<String>(json['walletId']),
      kind: serializer.fromJson<String>(json['kind']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'singleton': serializer.toJson<int>(singleton),
      'walletId': serializer.toJson<String>(walletId),
      'kind': serializer.toJson<String>(kind),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  WalletMetaRow copyWith({
    int? singleton,
    String? walletId,
    String? kind,
    DateTime? createdAt,
  }) => WalletMetaRow(
    singleton: singleton ?? this.singleton,
    walletId: walletId ?? this.walletId,
    kind: kind ?? this.kind,
    createdAt: createdAt ?? this.createdAt,
  );
  WalletMetaRow copyWithCompanion(WalletMetaCompanion data) {
    return WalletMetaRow(
      singleton: data.singleton.present ? data.singleton.value : this.singleton,
      walletId: data.walletId.present ? data.walletId.value : this.walletId,
      kind: data.kind.present ? data.kind.value : this.kind,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('WalletMetaRow(')
          ..write('singleton: $singleton, ')
          ..write('walletId: $walletId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(singleton, walletId, kind, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WalletMetaRow &&
          other.singleton == this.singleton &&
          other.walletId == this.walletId &&
          other.kind == this.kind &&
          other.createdAt == this.createdAt);
}

class WalletMetaCompanion extends UpdateCompanion<WalletMetaRow> {
  final Value<int> singleton;
  final Value<String> walletId;
  final Value<String> kind;
  final Value<DateTime> createdAt;
  const WalletMetaCompanion({
    this.singleton = const Value.absent(),
    this.walletId = const Value.absent(),
    this.kind = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  WalletMetaCompanion.insert({
    this.singleton = const Value.absent(),
    required String walletId,
    required String kind,
    required DateTime createdAt,
  }) : walletId = Value(walletId),
       kind = Value(kind),
       createdAt = Value(createdAt);
  static Insertable<WalletMetaRow> custom({
    Expression<int>? singleton,
    Expression<String>? walletId,
    Expression<String>? kind,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (singleton != null) 'singleton': singleton,
      if (walletId != null) 'wallet_id': walletId,
      if (kind != null) 'kind': kind,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  WalletMetaCompanion copyWith({
    Value<int>? singleton,
    Value<String>? walletId,
    Value<String>? kind,
    Value<DateTime>? createdAt,
  }) {
    return WalletMetaCompanion(
      singleton: singleton ?? this.singleton,
      walletId: walletId ?? this.walletId,
      kind: kind ?? this.kind,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (singleton.present) {
      map['singleton'] = Variable<int>(singleton.value);
    }
    if (walletId.present) {
      map['wallet_id'] = Variable<String>(walletId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('WalletMetaCompanion(')
          ..write('singleton: $singleton, ')
          ..write('walletId: $walletId, ')
          ..write('kind: $kind, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $FinancialMemberRowsTable extends FinancialMemberRows
    with TableInfo<$FinancialMemberRowsTable, FinancialMemberRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FinancialMemberRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _memberIdMeta = const VerificationMeta(
    'memberId',
  );
  @override
  late final GeneratedColumn<String> memberId = GeneratedColumn<String>(
    'member_id',
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
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _displayOrderMeta = const VerificationMeta(
    'displayOrder',
  );
  @override
  late final GeneratedColumn<int> displayOrder = GeneratedColumn<int>(
    'display_order',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [
    memberId,
    label,
    displayOrder,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'financial_member_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<FinancialMemberRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('member_id')) {
      context.handle(
        _memberIdMeta,
        memberId.isAcceptableOrUnknown(data['member_id']!, _memberIdMeta),
      );
    } else if (isInserting) {
      context.missing(_memberIdMeta);
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    } else if (isInserting) {
      context.missing(_labelMeta);
    }
    if (data.containsKey('display_order')) {
      context.handle(
        _displayOrderMeta,
        displayOrder.isAcceptableOrUnknown(
          data['display_order']!,
          _displayOrderMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_displayOrderMeta);
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
  Set<GeneratedColumn> get $primaryKey => {memberId};
  @override
  FinancialMemberRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FinancialMemberRow(
      memberId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}member_id'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      displayOrder: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}display_order'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $FinancialMemberRowsTable createAlias(String alias) {
    return $FinancialMemberRowsTable(attachedDatabase, alias);
  }
}

class FinancialMemberRow extends DataClass
    implements Insertable<FinancialMemberRow> {
  final String memberId;
  final String label;
  final int displayOrder;
  final DateTime createdAt;
  const FinancialMemberRow({
    required this.memberId,
    required this.label,
    required this.displayOrder,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['member_id'] = Variable<String>(memberId);
    map['label'] = Variable<String>(label);
    map['display_order'] = Variable<int>(displayOrder);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  FinancialMemberRowsCompanion toCompanion(bool nullToAbsent) {
    return FinancialMemberRowsCompanion(
      memberId: Value(memberId),
      label: Value(label),
      displayOrder: Value(displayOrder),
      createdAt: Value(createdAt),
    );
  }

  factory FinancialMemberRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FinancialMemberRow(
      memberId: serializer.fromJson<String>(json['memberId']),
      label: serializer.fromJson<String>(json['label']),
      displayOrder: serializer.fromJson<int>(json['displayOrder']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'memberId': serializer.toJson<String>(memberId),
      'label': serializer.toJson<String>(label),
      'displayOrder': serializer.toJson<int>(displayOrder),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  FinancialMemberRow copyWith({
    String? memberId,
    String? label,
    int? displayOrder,
    DateTime? createdAt,
  }) => FinancialMemberRow(
    memberId: memberId ?? this.memberId,
    label: label ?? this.label,
    displayOrder: displayOrder ?? this.displayOrder,
    createdAt: createdAt ?? this.createdAt,
  );
  FinancialMemberRow copyWithCompanion(FinancialMemberRowsCompanion data) {
    return FinancialMemberRow(
      memberId: data.memberId.present ? data.memberId.value : this.memberId,
      label: data.label.present ? data.label.value : this.label,
      displayOrder: data.displayOrder.present
          ? data.displayOrder.value
          : this.displayOrder,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FinancialMemberRow(')
          ..write('memberId: $memberId, ')
          ..write('label: $label, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(memberId, label, displayOrder, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FinancialMemberRow &&
          other.memberId == this.memberId &&
          other.label == this.label &&
          other.displayOrder == this.displayOrder &&
          other.createdAt == this.createdAt);
}

class FinancialMemberRowsCompanion extends UpdateCompanion<FinancialMemberRow> {
  final Value<String> memberId;
  final Value<String> label;
  final Value<int> displayOrder;
  final Value<DateTime> createdAt;
  final Value<int> rowid;
  const FinancialMemberRowsCompanion({
    this.memberId = const Value.absent(),
    this.label = const Value.absent(),
    this.displayOrder = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FinancialMemberRowsCompanion.insert({
    required String memberId,
    required String label,
    required int displayOrder,
    required DateTime createdAt,
    this.rowid = const Value.absent(),
  }) : memberId = Value(memberId),
       label = Value(label),
       displayOrder = Value(displayOrder),
       createdAt = Value(createdAt);
  static Insertable<FinancialMemberRow> custom({
    Expression<String>? memberId,
    Expression<String>? label,
    Expression<int>? displayOrder,
    Expression<DateTime>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (memberId != null) 'member_id': memberId,
      if (label != null) 'label': label,
      if (displayOrder != null) 'display_order': displayOrder,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FinancialMemberRowsCompanion copyWith({
    Value<String>? memberId,
    Value<String>? label,
    Value<int>? displayOrder,
    Value<DateTime>? createdAt,
    Value<int>? rowid,
  }) {
    return FinancialMemberRowsCompanion(
      memberId: memberId ?? this.memberId,
      label: label ?? this.label,
      displayOrder: displayOrder ?? this.displayOrder,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (memberId.present) {
      map['member_id'] = Variable<String>(memberId.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (displayOrder.present) {
      map['display_order'] = Variable<int>(displayOrder.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FinancialMemberRowsCompanion(')
          ..write('memberId: $memberId, ')
          ..write('label: $label, ')
          ..write('displayOrder: $displayOrder, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CategoryRowsTable categoryRows = $CategoryRowsTable(this);
  late final $StatusRowsTable statusRows = $StatusRowsTable(this);
  late final $TransactionRowsTable transactionRows = $TransactionRowsTable(
    this,
  );
  late final $FundRowsTable fundRows = $FundRowsTable(this);
  late final $SavingsAssetTypeRowsTable savingsAssetTypeRows =
      $SavingsAssetTypeRowsTable(this);
  late final $CounterpartyRowsTable counterpartyRows = $CounterpartyRowsTable(
    this,
  );
  late final $ObligationRowsTable obligationRows = $ObligationRowsTable(this);
  late final $WalletMetaTable walletMeta = $WalletMetaTable(this);
  late final $FinancialMemberRowsTable financialMemberRows =
      $FinancialMemberRowsTable(this);
  late final Index uxTransactionClientTxId = Index(
    'ux_transaction_client_tx_id',
    'CREATE UNIQUE INDEX ux_transaction_client_tx_id ON transaction_rows (client_tx_id)',
  );
  late final Index ixTransactionSource = Index(
    'ix_transaction_source',
    'CREATE INDEX ix_transaction_source ON transaction_rows (source_kind, source_ref_id)',
  );
  late final Index ixTransactionDestination = Index(
    'ix_transaction_destination',
    'CREATE INDEX ix_transaction_destination ON transaction_rows (destination_kind, destination_ref_id)',
  );
  late final Index ixTransactionCategoryStatus = Index(
    'ix_transaction_category_status',
    'CREATE INDEX ix_transaction_category_status ON transaction_rows (category_id, status_id)',
  );
  late final Index ixTransactionRecoveryOf = Index(
    'ix_transaction_recovery_of',
    'CREATE INDEX ix_transaction_recovery_of ON transaction_rows (recovery_of_tx_id)',
  );
  late final Index ixTransactionObligation = Index(
    'ix_transaction_obligation',
    'CREATE INDEX ix_transaction_obligation ON transaction_rows (obligation_id)',
  );
  late final Index ixTransactionSettlementGroup = Index(
    'ix_transaction_settlement_group',
    'CREATE INDEX ix_transaction_settlement_group ON transaction_rows (settlement_group_id)',
  );
  late final Index ixStatusCategory = Index(
    'ix_status_category',
    'CREATE INDEX ix_status_category ON status_rows (category_id)',
  );
  late final Index ixObligationCounterparty = Index(
    'ix_obligation_counterparty',
    'CREATE INDEX ix_obligation_counterparty ON obligation_rows (counterparty_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    categoryRows,
    statusRows,
    transactionRows,
    fundRows,
    savingsAssetTypeRows,
    counterpartyRows,
    obligationRows,
    walletMeta,
    financialMemberRows,
    uxTransactionClientTxId,
    ixTransactionSource,
    ixTransactionDestination,
    ixTransactionCategoryStatus,
    ixTransactionRecoveryOf,
    ixTransactionObligation,
    ixTransactionSettlementGroup,
    ixStatusCategory,
    ixObligationCounterparty,
  ];
}

typedef $$CategoryRowsTableCreateCompanionBuilder =
    CategoryRowsCompanion Function({
      required String id,
      required String name,
      required int colorValue,
      required String type,
      Value<bool> statsEnabled,
      Value<bool> excludeFromTotals,
      Value<String?> linkedExpenseCategoryId,
      Value<String?> groupKey,
      Value<bool> isDefault,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$CategoryRowsTableUpdateCompanionBuilder =
    CategoryRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> colorValue,
      Value<String> type,
      Value<bool> statsEnabled,
      Value<bool> excludeFromTotals,
      Value<String?> linkedExpenseCategoryId,
      Value<String?> groupKey,
      Value<bool> isDefault,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$CategoryRowsTableReferences
    extends BaseReferences<_$AppDatabase, $CategoryRowsTable, CategoryRow> {
  $$CategoryRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$StatusRowsTable, List<StatusRow>>
  _statusRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.statusRows,
    aliasName: 'category_rows__id__status_rows__category_id',
  );

  $$StatusRowsTableProcessedTableManager get statusRowsRefs {
    final manager = $$StatusRowsTableTableManager(
      $_db,
      $_db.statusRows,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_statusRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$TransactionRowsTable, List<TransactionRow>>
  _transactionRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.transactionRows,
    aliasName: 'category_rows__id__transaction_rows__category_id',
  );

  $$TransactionRowsTableProcessedTableManager get transactionRowsRefs {
    final manager = $$TransactionRowsTableTableManager(
      $_db,
      $_db.transactionRows,
    ).filter((f) => f.categoryId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transactionRowsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CategoryRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableFilterComposer({
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

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get statsEnabled => $composableBuilder(
    column: $table.statsEnabled,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get excludeFromTotals => $composableBuilder(
    column: $table.excludeFromTotals,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get linkedExpenseCategoryId => $composableBuilder(
    column: $table.linkedExpenseCategoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get groupKey => $composableBuilder(
    column: $table.groupKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> statusRowsRefs(
    Expression<bool> Function($$StatusRowsTableFilterComposer f) f,
  ) {
    final $$StatusRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.statusRows,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StatusRowsTableFilterComposer(
            $db: $db,
            $table: $db.statusRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> transactionRowsRefs(
    Expression<bool> Function($$TransactionRowsTableFilterComposer f) f,
  ) {
    final $$TransactionRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactionRows,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionRowsTableFilterComposer(
            $db: $db,
            $table: $db.transactionRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoryRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableOrderingComposer({
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

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get statsEnabled => $composableBuilder(
    column: $table.statsEnabled,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get excludeFromTotals => $composableBuilder(
    column: $table.excludeFromTotals,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get linkedExpenseCategoryId => $composableBuilder(
    column: $table.linkedExpenseCategoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get groupKey => $composableBuilder(
    column: $table.groupKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isDefault => $composableBuilder(
    column: $table.isDefault,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CategoryRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CategoryRowsTable> {
  $$CategoryRowsTableAnnotationComposer({
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

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<bool> get statsEnabled => $composableBuilder(
    column: $table.statsEnabled,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get excludeFromTotals => $composableBuilder(
    column: $table.excludeFromTotals,
    builder: (column) => column,
  );

  GeneratedColumn<String> get linkedExpenseCategoryId => $composableBuilder(
    column: $table.linkedExpenseCategoryId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get groupKey =>
      $composableBuilder(column: $table.groupKey, builder: (column) => column);

  GeneratedColumn<bool> get isDefault =>
      $composableBuilder(column: $table.isDefault, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> statusRowsRefs<T extends Object>(
    Expression<T> Function($$StatusRowsTableAnnotationComposer a) f,
  ) {
    final $$StatusRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.statusRows,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StatusRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.statusRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> transactionRowsRefs<T extends Object>(
    Expression<T> Function($$TransactionRowsTableAnnotationComposer a) f,
  ) {
    final $$TransactionRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactionRows,
      getReferencedColumn: (t) => t.categoryId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactionRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CategoryRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CategoryRowsTable,
          CategoryRow,
          $$CategoryRowsTableFilterComposer,
          $$CategoryRowsTableOrderingComposer,
          $$CategoryRowsTableAnnotationComposer,
          $$CategoryRowsTableCreateCompanionBuilder,
          $$CategoryRowsTableUpdateCompanionBuilder,
          (CategoryRow, $$CategoryRowsTableReferences),
          CategoryRow,
          PrefetchHooks Function({
            bool statusRowsRefs,
            bool transactionRowsRefs,
          })
        > {
  $$CategoryRowsTableTableManager(_$AppDatabase db, $CategoryRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CategoryRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CategoryRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CategoryRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<bool> statsEnabled = const Value.absent(),
                Value<bool> excludeFromTotals = const Value.absent(),
                Value<String?> linkedExpenseCategoryId = const Value.absent(),
                Value<String?> groupKey = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoryRowsCompanion(
                id: id,
                name: name,
                colorValue: colorValue,
                type: type,
                statsEnabled: statsEnabled,
                excludeFromTotals: excludeFromTotals,
                linkedExpenseCategoryId: linkedExpenseCategoryId,
                groupKey: groupKey,
                isDefault: isDefault,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int colorValue,
                required String type,
                Value<bool> statsEnabled = const Value.absent(),
                Value<bool> excludeFromTotals = const Value.absent(),
                Value<String?> linkedExpenseCategoryId = const Value.absent(),
                Value<String?> groupKey = const Value.absent(),
                Value<bool> isDefault = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CategoryRowsCompanion.insert(
                id: id,
                name: name,
                colorValue: colorValue,
                type: type,
                statsEnabled: statsEnabled,
                excludeFromTotals: excludeFromTotals,
                linkedExpenseCategoryId: linkedExpenseCategoryId,
                groupKey: groupKey,
                isDefault: isDefault,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CategoryRowsTable, CategoryRow>(table),
                  $$CategoryRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({statusRowsRefs = false, transactionRowsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (statusRowsRefs) db.statusRows,
                    if (transactionRowsRefs) db.transactionRows,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (statusRowsRefs)
                        await $_getPrefetchedData<
                          CategoryRow,
                          $CategoryRowsTable,
                          StatusRow
                        >(
                          currentTable: table,
                          referencedTable: $$CategoryRowsTableReferences
                              ._statusRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoryRowsTableReferences(
                                db,
                                table,
                                p0,
                              ).statusRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (transactionRowsRefs)
                        await $_getPrefetchedData<
                          CategoryRow,
                          $CategoryRowsTable,
                          TransactionRow
                        >(
                          currentTable: table,
                          referencedTable: $$CategoryRowsTableReferences
                              ._transactionRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$CategoryRowsTableReferences(
                                db,
                                table,
                                p0,
                              ).transactionRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.categoryId == item.id,
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

typedef $$CategoryRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CategoryRowsTable,
      CategoryRow,
      $$CategoryRowsTableFilterComposer,
      $$CategoryRowsTableOrderingComposer,
      $$CategoryRowsTableAnnotationComposer,
      $$CategoryRowsTableCreateCompanionBuilder,
      $$CategoryRowsTableUpdateCompanionBuilder,
      (CategoryRow, $$CategoryRowsTableReferences),
      CategoryRow,
      PrefetchHooks Function({bool statusRowsRefs, bool transactionRowsRefs})
    >;
typedef $$StatusRowsTableCreateCompanionBuilder = StatusRowsCompanion Function({
  required String id,
  required String categoryId,
  required String name,
  required int sortOrder,
  Value<bool> isActive,
  Value<int> rowid,
});
typedef $$StatusRowsTableUpdateCompanionBuilder = StatusRowsCompanion Function({
  Value<String> id,
  Value<String> categoryId,
  Value<String> name,
  Value<int> sortOrder,
  Value<bool> isActive,
  Value<int> rowid,
});

final class $$StatusRowsTableReferences
    extends BaseReferences<_$AppDatabase, $StatusRowsTable, StatusRow> {
  $$StatusRowsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $CategoryRowsTable _categoryIdTable(_$AppDatabase db) => db
      .categoryRows
      .createAlias('status_rows__category_id__category_rows__id');

  $$CategoryRowsTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoryRowsTableTableManager(
      $_db,
      $_db.categoryRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static MultiTypedResultKey<$TransactionRowsTable, List<TransactionRow>>
  _transactionRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.transactionRows,
    aliasName: 'status_rows__id__transaction_rows__status_id',
  );

  $$TransactionRowsTableProcessedTableManager get transactionRowsRefs {
    final manager = $$TransactionRowsTableTableManager(
      $_db,
      $_db.transactionRows,
    ).filter((f) => f.statusId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _transactionRowsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$StatusRowsTableFilterComposer
    extends Composer<_$AppDatabase, $StatusRowsTable> {
  $$StatusRowsTableFilterComposer({
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

  ColumnFilters<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoryRowsTableFilterComposer get categoryId {
    final $$CategoryRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableFilterComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<bool> transactionRowsRefs(
    Expression<bool> Function($$TransactionRowsTableFilterComposer f) f,
  ) {
    final $$TransactionRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactionRows,
      getReferencedColumn: (t) => t.statusId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionRowsTableFilterComposer(
            $db: $db,
            $table: $db.transactionRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StatusRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $StatusRowsTable> {
  $$StatusRowsTableOrderingComposer({
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

  ColumnOrderings<int> get sortOrder => $composableBuilder(
    column: $table.sortOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoryRowsTableOrderingComposer get categoryId {
    final $$CategoryRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableOrderingComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StatusRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $StatusRowsTable> {
  $$StatusRowsTableAnnotationComposer({
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

  GeneratedColumn<int> get sortOrder =>
      $composableBuilder(column: $table.sortOrder, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$CategoryRowsTableAnnotationComposer get categoryId {
    final $$CategoryRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  Expression<T> transactionRowsRefs<T extends Object>(
    Expression<T> Function($$TransactionRowsTableAnnotationComposer a) f,
  ) {
    final $$TransactionRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.transactionRows,
      getReferencedColumn: (t) => t.statusId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$TransactionRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.transactionRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$StatusRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $StatusRowsTable,
          StatusRow,
          $$StatusRowsTableFilterComposer,
          $$StatusRowsTableOrderingComposer,
          $$StatusRowsTableAnnotationComposer,
          $$StatusRowsTableCreateCompanionBuilder,
          $$StatusRowsTableUpdateCompanionBuilder,
          (StatusRow, $$StatusRowsTableReferences),
          StatusRow,
          PrefetchHooks Function({bool categoryId, bool transactionRowsRefs})
        > {
  $$StatusRowsTableTableManager(_$AppDatabase db, $StatusRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StatusRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StatusRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StatusRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> sortOrder = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StatusRowsCompanion(
                id: id,
                categoryId: categoryId,
                name: name,
                sortOrder: sortOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String categoryId,
                required String name,
                required int sortOrder,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => StatusRowsCompanion.insert(
                id: id,
                categoryId: categoryId,
                name: name,
                sortOrder: sortOrder,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$StatusRowsTable, StatusRow>(table),
                  $$StatusRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({categoryId = false, transactionRowsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (transactionRowsRefs) db.transactionRows,
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
                        if (categoryId) {
                          state = state.withJoin(
                            currentTable: table,
                            currentColumn: table.categoryId,
                            referencedTable: $$StatusRowsTableReferences
                                ._categoryIdTable(db),
                            referencedColumn: $$StatusRowsTableReferences
                                ._categoryIdTable(db)
                                .id,
                          ) as T;
                        }

                        return state;
                      },
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (transactionRowsRefs)
                        await $_getPrefetchedData<
                          StatusRow,
                          $StatusRowsTable,
                          TransactionRow
                        >(
                          currentTable: table,
                          referencedTable: $$StatusRowsTableReferences
                              ._transactionRowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$StatusRowsTableReferences(
                                db,
                                table,
                                p0,
                              ).transactionRowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.statusId == item.id,
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

typedef $$StatusRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $StatusRowsTable,
      StatusRow,
      $$StatusRowsTableFilterComposer,
      $$StatusRowsTableOrderingComposer,
      $$StatusRowsTableAnnotationComposer,
      $$StatusRowsTableCreateCompanionBuilder,
      $$StatusRowsTableUpdateCompanionBuilder,
      (StatusRow, $$StatusRowsTableReferences),
      StatusRow,
      PrefetchHooks Function({bool categoryId, bool transactionRowsRefs})
    >;
typedef $$TransactionRowsTableCreateCompanionBuilder =
    TransactionRowsCompanion Function({
      required String id,
      required String type,
      Value<String?> transferKind,
      required String categoryId,
      required String sourceKind,
      Value<String?> sourceRefId,
      required String destinationKind,
      Value<String?> destinationRefId,
      required int amountMinor,
      Value<String> currency,
      Value<String> note,
      Value<String?> statusId,
      Value<DateTime?> statusUpdatedAt,
      required DateTime transactionDate,
      required DateTime createdAt,
      Value<String?> reversalOfTxId,
      Value<String?> correctsTxId,
      Value<String?> reversedByTxId,
      Value<String?> recoveryOfTxId,
      Value<String?> obligationId,
      Value<String?> settlementGroupId,
      Value<String?> actorMemberId,
      required String clientTxId,
      Value<int> version,
      Value<int> rowid,
    });
typedef $$TransactionRowsTableUpdateCompanionBuilder =
    TransactionRowsCompanion Function({
      Value<String> id,
      Value<String> type,
      Value<String?> transferKind,
      Value<String> categoryId,
      Value<String> sourceKind,
      Value<String?> sourceRefId,
      Value<String> destinationKind,
      Value<String?> destinationRefId,
      Value<int> amountMinor,
      Value<String> currency,
      Value<String> note,
      Value<String?> statusId,
      Value<DateTime?> statusUpdatedAt,
      Value<DateTime> transactionDate,
      Value<DateTime> createdAt,
      Value<String?> reversalOfTxId,
      Value<String?> correctsTxId,
      Value<String?> reversedByTxId,
      Value<String?> recoveryOfTxId,
      Value<String?> obligationId,
      Value<String?> settlementGroupId,
      Value<String?> actorMemberId,
      Value<String> clientTxId,
      Value<int> version,
      Value<int> rowid,
    });

final class $$TransactionRowsTableReferences
    extends
        BaseReferences<_$AppDatabase, $TransactionRowsTable, TransactionRow> {
  $$TransactionRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CategoryRowsTable _categoryIdTable(_$AppDatabase db) => db
      .categoryRows
      .createAlias('transaction_rows__category_id__category_rows__id');

  $$CategoryRowsTableProcessedTableManager get categoryId {
    final $_column = $_itemColumn<String>('category_id')!;

    final manager = $$CategoryRowsTableTableManager(
      $_db,
      $_db.categoryRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_categoryIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $StatusRowsTable _statusIdTable(_$AppDatabase db) =>
      db.statusRows.createAlias('transaction_rows__status_id__status_rows__id');

  $$StatusRowsTableProcessedTableManager? get statusId {
    final $_column = $_itemColumn<String>('status_id');
    if ($_column == null) return null;
    final manager = $$StatusRowsTableTableManager(
      $_db,
      $_db.statusRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_statusIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$TransactionRowsTableFilterComposer
    extends Composer<_$AppDatabase, $TransactionRowsTable> {
  $$TransactionRowsTableFilterComposer({
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

  ColumnFilters<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get transferKind => $composableBuilder(
    column: $table.transferKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceRefId => $composableBuilder(
    column: $table.sourceRefId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get destinationRefId => $composableBuilder(
    column: $table.destinationRefId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reversalOfTxId => $composableBuilder(
    column: $table.reversalOfTxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get correctsTxId => $composableBuilder(
    column: $table.correctsTxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reversedByTxId => $composableBuilder(
    column: $table.reversedByTxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get recoveryOfTxId => $composableBuilder(
    column: $table.recoveryOfTxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get obligationId => $composableBuilder(
    column: $table.obligationId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settlementGroupId => $composableBuilder(
    column: $table.settlementGroupId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get actorMemberId => $composableBuilder(
    column: $table.actorMemberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get clientTxId => $composableBuilder(
    column: $table.clientTxId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnFilters(column),
  );

  $$CategoryRowsTableFilterComposer get categoryId {
    final $$CategoryRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableFilterComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StatusRowsTableFilterComposer get statusId {
    final $$StatusRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.statusId,
      referencedTable: $db.statusRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StatusRowsTableFilterComposer(
            $db: $db,
            $table: $db.statusRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $TransactionRowsTable> {
  $$TransactionRowsTableOrderingComposer({
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

  ColumnOrderings<String> get type => $composableBuilder(
    column: $table.type,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get transferKind => $composableBuilder(
    column: $table.transferKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceRefId => $composableBuilder(
    column: $table.sourceRefId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get destinationRefId => $composableBuilder(
    column: $table.destinationRefId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currency => $composableBuilder(
    column: $table.currency,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reversalOfTxId => $composableBuilder(
    column: $table.reversalOfTxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get correctsTxId => $composableBuilder(
    column: $table.correctsTxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reversedByTxId => $composableBuilder(
    column: $table.reversedByTxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get recoveryOfTxId => $composableBuilder(
    column: $table.recoveryOfTxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get obligationId => $composableBuilder(
    column: $table.obligationId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settlementGroupId => $composableBuilder(
    column: $table.settlementGroupId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get actorMemberId => $composableBuilder(
    column: $table.actorMemberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get clientTxId => $composableBuilder(
    column: $table.clientTxId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get version => $composableBuilder(
    column: $table.version,
    builder: (column) => ColumnOrderings(column),
  );

  $$CategoryRowsTableOrderingComposer get categoryId {
    final $$CategoryRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableOrderingComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StatusRowsTableOrderingComposer get statusId {
    final $$StatusRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.statusId,
      referencedTable: $db.statusRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StatusRowsTableOrderingComposer(
            $db: $db,
            $table: $db.statusRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $TransactionRowsTable> {
  $$TransactionRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get type =>
      $composableBuilder(column: $table.type, builder: (column) => column);

  GeneratedColumn<String> get transferKind => $composableBuilder(
    column: $table.transferKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceKind => $composableBuilder(
    column: $table.sourceKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceRefId => $composableBuilder(
    column: $table.sourceRefId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationKind => $composableBuilder(
    column: $table.destinationKind,
    builder: (column) => column,
  );

  GeneratedColumn<String> get destinationRefId => $composableBuilder(
    column: $table.destinationRefId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<String> get currency =>
      $composableBuilder(column: $table.currency, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<DateTime> get statusUpdatedAt => $composableBuilder(
    column: $table.statusUpdatedAt,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get transactionDate => $composableBuilder(
    column: $table.transactionDate,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get reversalOfTxId => $composableBuilder(
    column: $table.reversalOfTxId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get correctsTxId => $composableBuilder(
    column: $table.correctsTxId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get reversedByTxId => $composableBuilder(
    column: $table.reversedByTxId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get recoveryOfTxId => $composableBuilder(
    column: $table.recoveryOfTxId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get obligationId => $composableBuilder(
    column: $table.obligationId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get settlementGroupId => $composableBuilder(
    column: $table.settlementGroupId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get actorMemberId => $composableBuilder(
    column: $table.actorMemberId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get clientTxId => $composableBuilder(
    column: $table.clientTxId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get version =>
      $composableBuilder(column: $table.version, builder: (column) => column);

  $$CategoryRowsTableAnnotationComposer get categoryId {
    final $$CategoryRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.categoryId,
      referencedTable: $db.categoryRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CategoryRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.categoryRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$StatusRowsTableAnnotationComposer get statusId {
    final $$StatusRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.statusId,
      referencedTable: $db.statusRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StatusRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.statusRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$TransactionRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $TransactionRowsTable,
          TransactionRow,
          $$TransactionRowsTableFilterComposer,
          $$TransactionRowsTableOrderingComposer,
          $$TransactionRowsTableAnnotationComposer,
          $$TransactionRowsTableCreateCompanionBuilder,
          $$TransactionRowsTableUpdateCompanionBuilder,
          (TransactionRow, $$TransactionRowsTableReferences),
          TransactionRow,
          PrefetchHooks Function({bool categoryId, bool statusId})
        > {
  $$TransactionRowsTableTableManager(
    _$AppDatabase db,
    $TransactionRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$TransactionRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$TransactionRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$TransactionRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> type = const Value.absent(),
                Value<String?> transferKind = const Value.absent(),
                Value<String> categoryId = const Value.absent(),
                Value<String> sourceKind = const Value.absent(),
                Value<String?> sourceRefId = const Value.absent(),
                Value<String> destinationKind = const Value.absent(),
                Value<String?> destinationRefId = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<String> currency = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> statusId = const Value.absent(),
                Value<DateTime?> statusUpdatedAt = const Value.absent(),
                Value<DateTime> transactionDate = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<String?> reversalOfTxId = const Value.absent(),
                Value<String?> correctsTxId = const Value.absent(),
                Value<String?> reversedByTxId = const Value.absent(),
                Value<String?> recoveryOfTxId = const Value.absent(),
                Value<String?> obligationId = const Value.absent(),
                Value<String?> settlementGroupId = const Value.absent(),
                Value<String?> actorMemberId = const Value.absent(),
                Value<String> clientTxId = const Value.absent(),
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionRowsCompanion(
                id: id,
                type: type,
                transferKind: transferKind,
                categoryId: categoryId,
                sourceKind: sourceKind,
                sourceRefId: sourceRefId,
                destinationKind: destinationKind,
                destinationRefId: destinationRefId,
                amountMinor: amountMinor,
                currency: currency,
                note: note,
                statusId: statusId,
                statusUpdatedAt: statusUpdatedAt,
                transactionDate: transactionDate,
                createdAt: createdAt,
                reversalOfTxId: reversalOfTxId,
                correctsTxId: correctsTxId,
                reversedByTxId: reversedByTxId,
                recoveryOfTxId: recoveryOfTxId,
                obligationId: obligationId,
                settlementGroupId: settlementGroupId,
                actorMemberId: actorMemberId,
                clientTxId: clientTxId,
                version: version,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String type,
                Value<String?> transferKind = const Value.absent(),
                required String categoryId,
                required String sourceKind,
                Value<String?> sourceRefId = const Value.absent(),
                required String destinationKind,
                Value<String?> destinationRefId = const Value.absent(),
                required int amountMinor,
                Value<String> currency = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> statusId = const Value.absent(),
                Value<DateTime?> statusUpdatedAt = const Value.absent(),
                required DateTime transactionDate,
                required DateTime createdAt,
                Value<String?> reversalOfTxId = const Value.absent(),
                Value<String?> correctsTxId = const Value.absent(),
                Value<String?> reversedByTxId = const Value.absent(),
                Value<String?> recoveryOfTxId = const Value.absent(),
                Value<String?> obligationId = const Value.absent(),
                Value<String?> settlementGroupId = const Value.absent(),
                Value<String?> actorMemberId = const Value.absent(),
                required String clientTxId,
                Value<int> version = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionRowsCompanion.insert(
                id: id,
                type: type,
                transferKind: transferKind,
                categoryId: categoryId,
                sourceKind: sourceKind,
                sourceRefId: sourceRefId,
                destinationKind: destinationKind,
                destinationRefId: destinationRefId,
                amountMinor: amountMinor,
                currency: currency,
                note: note,
                statusId: statusId,
                statusUpdatedAt: statusUpdatedAt,
                transactionDate: transactionDate,
                createdAt: createdAt,
                reversalOfTxId: reversalOfTxId,
                correctsTxId: correctsTxId,
                reversedByTxId: reversedByTxId,
                recoveryOfTxId: recoveryOfTxId,
                obligationId: obligationId,
                settlementGroupId: settlementGroupId,
                actorMemberId: actorMemberId,
                clientTxId: clientTxId,
                version: version,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransactionRowsTable, TransactionRow>(table),
                  $$TransactionRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({categoryId = false, statusId = false}) {
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
                    if (categoryId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.categoryId,
                        referencedTable: $$TransactionRowsTableReferences
                            ._categoryIdTable(db),
                        referencedColumn: $$TransactionRowsTableReferences
                            ._categoryIdTable(db)
                            .id,
                      ) as T;
                    }
                    if (statusId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.statusId,
                        referencedTable: $$TransactionRowsTableReferences
                            ._statusIdTable(db),
                        referencedColumn: $$TransactionRowsTableReferences
                            ._statusIdTable(db)
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

typedef $$TransactionRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $TransactionRowsTable,
      TransactionRow,
      $$TransactionRowsTableFilterComposer,
      $$TransactionRowsTableOrderingComposer,
      $$TransactionRowsTableAnnotationComposer,
      $$TransactionRowsTableCreateCompanionBuilder,
      $$TransactionRowsTableUpdateCompanionBuilder,
      (TransactionRow, $$TransactionRowsTableReferences),
      TransactionRow,
      PrefetchHooks Function({bool categoryId, bool statusId})
    >;
typedef $$FundRowsTableCreateCompanionBuilder = FundRowsCompanion Function({
  required String id,
  required String name,
  required int colorValue,
  Value<bool> isActive,
  Value<int> rowid,
});
typedef $$FundRowsTableUpdateCompanionBuilder = FundRowsCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<int> colorValue,
  Value<bool> isActive,
  Value<int> rowid,
});

class $$FundRowsTableFilterComposer
    extends Composer<_$AppDatabase, $FundRowsTable> {
  $$FundRowsTableFilterComposer({
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

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FundRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $FundRowsTable> {
  $$FundRowsTableOrderingComposer({
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

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FundRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FundRowsTable> {
  $$FundRowsTableAnnotationComposer({
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

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$FundRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FundRowsTable,
          FundRow,
          $$FundRowsTableFilterComposer,
          $$FundRowsTableOrderingComposer,
          $$FundRowsTableAnnotationComposer,
          $$FundRowsTableCreateCompanionBuilder,
          $$FundRowsTableUpdateCompanionBuilder,
          (FundRow, BaseReferences<_$AppDatabase, $FundRowsTable, FundRow>),
          FundRow,
          PrefetchHooks Function()
        > {
  $$FundRowsTableTableManager(_$AppDatabase db, $FundRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FundRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FundRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FundRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FundRowsCompanion(
                id: id,
                name: name,
                colorValue: colorValue,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int colorValue,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FundRowsCompanion.insert(
                id: id,
                name: name,
                colorValue: colorValue,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FundRowsTable, FundRow>(table),
                  BaseReferences<_$AppDatabase, $FundRowsTable, FundRow>(
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

typedef $$FundRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FundRowsTable,
      FundRow,
      $$FundRowsTableFilterComposer,
      $$FundRowsTableOrderingComposer,
      $$FundRowsTableAnnotationComposer,
      $$FundRowsTableCreateCompanionBuilder,
      $$FundRowsTableUpdateCompanionBuilder,
      (FundRow, BaseReferences<_$AppDatabase, $FundRowsTable, FundRow>),
      FundRow,
      PrefetchHooks Function()
    >;
typedef $$SavingsAssetTypeRowsTableCreateCompanionBuilder =
    SavingsAssetTypeRowsCompanion Function({
      required String id,
      required String name,
      required int colorValue,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$SavingsAssetTypeRowsTableUpdateCompanionBuilder =
    SavingsAssetTypeRowsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<int> colorValue,
      Value<bool> isActive,
      Value<int> rowid,
    });

class $$SavingsAssetTypeRowsTableFilterComposer
    extends Composer<_$AppDatabase, $SavingsAssetTypeRowsTable> {
  $$SavingsAssetTypeRowsTableFilterComposer({
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

  ColumnFilters<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SavingsAssetTypeRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $SavingsAssetTypeRowsTable> {
  $$SavingsAssetTypeRowsTableOrderingComposer({
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

  ColumnOrderings<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SavingsAssetTypeRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SavingsAssetTypeRowsTable> {
  $$SavingsAssetTypeRowsTableAnnotationComposer({
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

  GeneratedColumn<int> get colorValue => $composableBuilder(
    column: $table.colorValue,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);
}

class $$SavingsAssetTypeRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SavingsAssetTypeRowsTable,
          SavingsAssetTypeRow,
          $$SavingsAssetTypeRowsTableFilterComposer,
          $$SavingsAssetTypeRowsTableOrderingComposer,
          $$SavingsAssetTypeRowsTableAnnotationComposer,
          $$SavingsAssetTypeRowsTableCreateCompanionBuilder,
          $$SavingsAssetTypeRowsTableUpdateCompanionBuilder,
          (
            SavingsAssetTypeRow,
            BaseReferences<
              _$AppDatabase,
              $SavingsAssetTypeRowsTable,
              SavingsAssetTypeRow
            >,
          ),
          SavingsAssetTypeRow,
          PrefetchHooks Function()
        > {
  $$SavingsAssetTypeRowsTableTableManager(
    _$AppDatabase db,
    $SavingsAssetTypeRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SavingsAssetTypeRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SavingsAssetTypeRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$SavingsAssetTypeRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<int> colorValue = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavingsAssetTypeRowsCompanion(
                id: id,
                name: name,
                colorValue: colorValue,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required int colorValue,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SavingsAssetTypeRowsCompanion.insert(
                id: id,
                name: name,
                colorValue: colorValue,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SavingsAssetTypeRowsTable, SavingsAssetTypeRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $SavingsAssetTypeRowsTable,
                    SavingsAssetTypeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SavingsAssetTypeRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SavingsAssetTypeRowsTable,
      SavingsAssetTypeRow,
      $$SavingsAssetTypeRowsTableFilterComposer,
      $$SavingsAssetTypeRowsTableOrderingComposer,
      $$SavingsAssetTypeRowsTableAnnotationComposer,
      $$SavingsAssetTypeRowsTableCreateCompanionBuilder,
      $$SavingsAssetTypeRowsTableUpdateCompanionBuilder,
      (
        SavingsAssetTypeRow,
        BaseReferences<
          _$AppDatabase,
          $SavingsAssetTypeRowsTable,
          SavingsAssetTypeRow
        >,
      ),
      SavingsAssetTypeRow,
      PrefetchHooks Function()
    >;
typedef $$CounterpartyRowsTableCreateCompanionBuilder =
    CounterpartyRowsCompanion Function({
      required String id,
      required String displayName,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$CounterpartyRowsTableUpdateCompanionBuilder =
    CounterpartyRowsCompanion Function({
      Value<String> id,
      Value<String> displayName,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$CounterpartyRowsTableReferences
    extends
        BaseReferences<_$AppDatabase, $CounterpartyRowsTable, CounterpartyRow> {
  $$CounterpartyRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$ObligationRowsTable, List<ObligationRow>>
  _obligationRowsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.obligationRows,
    aliasName: 'counterparty_rows__id__obligation_rows__counterparty_id',
  );

  $$ObligationRowsTableProcessedTableManager get obligationRowsRefs {
    final manager = $$ObligationRowsTableTableManager(
      $_db,
      $_db.obligationRows,
    ).filter((f) => f.counterpartyId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_obligationRowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$CounterpartyRowsTableFilterComposer
    extends Composer<_$AppDatabase, $CounterpartyRowsTable> {
  $$CounterpartyRowsTableFilterComposer({
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

  ColumnFilters<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> obligationRowsRefs(
    Expression<bool> Function($$ObligationRowsTableFilterComposer f) f,
  ) {
    final $$ObligationRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.obligationRows,
      getReferencedColumn: (t) => t.counterpartyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObligationRowsTableFilterComposer(
            $db: $db,
            $table: $db.obligationRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CounterpartyRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $CounterpartyRowsTable> {
  $$CounterpartyRowsTableOrderingComposer({
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

  ColumnOrderings<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CounterpartyRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CounterpartyRowsTable> {
  $$CounterpartyRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
    column: $table.displayName,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  Expression<T> obligationRowsRefs<T extends Object>(
    Expression<T> Function($$ObligationRowsTableAnnotationComposer a) f,
  ) {
    final $$ObligationRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.obligationRows,
      getReferencedColumn: (t) => t.counterpartyId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$ObligationRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.obligationRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$CounterpartyRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CounterpartyRowsTable,
          CounterpartyRow,
          $$CounterpartyRowsTableFilterComposer,
          $$CounterpartyRowsTableOrderingComposer,
          $$CounterpartyRowsTableAnnotationComposer,
          $$CounterpartyRowsTableCreateCompanionBuilder,
          $$CounterpartyRowsTableUpdateCompanionBuilder,
          (CounterpartyRow, $$CounterpartyRowsTableReferences),
          CounterpartyRow,
          PrefetchHooks Function({bool obligationRowsRefs})
        > {
  $$CounterpartyRowsTableTableManager(
    _$AppDatabase db,
    $CounterpartyRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CounterpartyRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CounterpartyRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CounterpartyRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> displayName = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CounterpartyRowsCompanion(
                id: id,
                displayName: displayName,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String displayName,
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CounterpartyRowsCompanion.insert(
                id: id,
                displayName: displayName,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CounterpartyRowsTable, CounterpartyRow>(table),
                  $$CounterpartyRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({obligationRowsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (obligationRowsRefs) db.obligationRows,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (obligationRowsRefs)
                    await $_getPrefetchedData<
                      CounterpartyRow,
                      $CounterpartyRowsTable,
                      ObligationRow
                    >(
                      currentTable: table,
                      referencedTable: $$CounterpartyRowsTableReferences
                          ._obligationRowsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$CounterpartyRowsTableReferences(
                            db,
                            table,
                            p0,
                          ).obligationRowsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where(
                            (e) => e.counterpartyId == item.id,
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

typedef $$CounterpartyRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CounterpartyRowsTable,
      CounterpartyRow,
      $$CounterpartyRowsTableFilterComposer,
      $$CounterpartyRowsTableOrderingComposer,
      $$CounterpartyRowsTableAnnotationComposer,
      $$CounterpartyRowsTableCreateCompanionBuilder,
      $$CounterpartyRowsTableUpdateCompanionBuilder,
      (CounterpartyRow, $$CounterpartyRowsTableReferences),
      CounterpartyRow,
      PrefetchHooks Function({bool obligationRowsRefs})
    >;
typedef $$ObligationRowsTableCreateCompanionBuilder =
    ObligationRowsCompanion Function({
      required String id,
      required String counterpartyId,
      required String direction,
      Value<DateTime?> dueDate,
      Value<String> note,
      Value<bool> isActive,
      Value<int> rowid,
    });
typedef $$ObligationRowsTableUpdateCompanionBuilder =
    ObligationRowsCompanion Function({
      Value<String> id,
      Value<String> counterpartyId,
      Value<String> direction,
      Value<DateTime?> dueDate,
      Value<String> note,
      Value<bool> isActive,
      Value<int> rowid,
    });

final class $$ObligationRowsTableReferences
    extends BaseReferences<_$AppDatabase, $ObligationRowsTable, ObligationRow> {
  $$ObligationRowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $CounterpartyRowsTable _counterpartyIdTable(_$AppDatabase db) => db
      .counterpartyRows
      .createAlias('obligation_rows__counterparty_id__counterparty_rows__id');

  $$CounterpartyRowsTableProcessedTableManager get counterpartyId {
    final $_column = $_itemColumn<String>('counterparty_id')!;

    final manager = $$CounterpartyRowsTableTableManager(
      $_db,
      $_db.counterpartyRows,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_counterpartyIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$ObligationRowsTableFilterComposer
    extends Composer<_$AppDatabase, $ObligationRowsTable> {
  $$ObligationRowsTableFilterComposer({
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

  ColumnFilters<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnFilters(column),
  );

  $$CounterpartyRowsTableFilterComposer get counterpartyId {
    final $$CounterpartyRowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.counterpartyId,
      referencedTable: $db.counterpartyRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CounterpartyRowsTableFilterComposer(
            $db: $db,
            $table: $db.counterpartyRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObligationRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $ObligationRowsTable> {
  $$ObligationRowsTableOrderingComposer({
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

  ColumnOrderings<String> get direction => $composableBuilder(
    column: $table.direction,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get dueDate => $composableBuilder(
    column: $table.dueDate,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get isActive => $composableBuilder(
    column: $table.isActive,
    builder: (column) => ColumnOrderings(column),
  );

  $$CounterpartyRowsTableOrderingComposer get counterpartyId {
    final $$CounterpartyRowsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.counterpartyId,
      referencedTable: $db.counterpartyRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CounterpartyRowsTableOrderingComposer(
            $db: $db,
            $table: $db.counterpartyRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObligationRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ObligationRowsTable> {
  $$ObligationRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get direction =>
      $composableBuilder(column: $table.direction, builder: (column) => column);

  GeneratedColumn<DateTime> get dueDate =>
      $composableBuilder(column: $table.dueDate, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<bool> get isActive =>
      $composableBuilder(column: $table.isActive, builder: (column) => column);

  $$CounterpartyRowsTableAnnotationComposer get counterpartyId {
    final $$CounterpartyRowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.counterpartyId,
      referencedTable: $db.counterpartyRows,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CounterpartyRowsTableAnnotationComposer(
            $db: $db,
            $table: $db.counterpartyRows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$ObligationRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ObligationRowsTable,
          ObligationRow,
          $$ObligationRowsTableFilterComposer,
          $$ObligationRowsTableOrderingComposer,
          $$ObligationRowsTableAnnotationComposer,
          $$ObligationRowsTableCreateCompanionBuilder,
          $$ObligationRowsTableUpdateCompanionBuilder,
          (ObligationRow, $$ObligationRowsTableReferences),
          ObligationRow,
          PrefetchHooks Function({bool counterpartyId})
        > {
  $$ObligationRowsTableTableManager(
    _$AppDatabase db,
    $ObligationRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ObligationRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ObligationRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ObligationRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> counterpartyId = const Value.absent(),
                Value<String> direction = const Value.absent(),
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObligationRowsCompanion(
                id: id,
                counterpartyId: counterpartyId,
                direction: direction,
                dueDate: dueDate,
                note: note,
                isActive: isActive,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String counterpartyId,
                required String direction,
                Value<DateTime?> dueDate = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<bool> isActive = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ObligationRowsCompanion.insert(
                id: id,
                counterpartyId: counterpartyId,
                direction: direction,
                dueDate: dueDate,
                note: note,
                isActive: isActive,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ObligationRowsTable, ObligationRow>(table),
                  $$ObligationRowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({counterpartyId = false}) {
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
                    if (counterpartyId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.counterpartyId,
                        referencedTable: $$ObligationRowsTableReferences
                            ._counterpartyIdTable(db),
                        referencedColumn: $$ObligationRowsTableReferences
                            ._counterpartyIdTable(db)
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

typedef $$ObligationRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ObligationRowsTable,
      ObligationRow,
      $$ObligationRowsTableFilterComposer,
      $$ObligationRowsTableOrderingComposer,
      $$ObligationRowsTableAnnotationComposer,
      $$ObligationRowsTableCreateCompanionBuilder,
      $$ObligationRowsTableUpdateCompanionBuilder,
      (ObligationRow, $$ObligationRowsTableReferences),
      ObligationRow,
      PrefetchHooks Function({bool counterpartyId})
    >;
typedef $$WalletMetaTableCreateCompanionBuilder = WalletMetaCompanion Function({
  Value<int> singleton,
  required String walletId,
  required String kind,
  required DateTime createdAt,
});
typedef $$WalletMetaTableUpdateCompanionBuilder = WalletMetaCompanion Function({
  Value<int> singleton,
  Value<String> walletId,
  Value<String> kind,
  Value<DateTime> createdAt,
});

class $$WalletMetaTableFilterComposer
    extends Composer<_$AppDatabase, $WalletMetaTable> {
  $$WalletMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$WalletMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $WalletMetaTable> {
  $$WalletMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get singleton => $composableBuilder(
    column: $table.singleton,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get walletId => $composableBuilder(
    column: $table.walletId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$WalletMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $WalletMetaTable> {
  $$WalletMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get singleton =>
      $composableBuilder(column: $table.singleton, builder: (column) => column);

  GeneratedColumn<String> get walletId =>
      $composableBuilder(column: $table.walletId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$WalletMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $WalletMetaTable,
          WalletMetaRow,
          $$WalletMetaTableFilterComposer,
          $$WalletMetaTableOrderingComposer,
          $$WalletMetaTableAnnotationComposer,
          $$WalletMetaTableCreateCompanionBuilder,
          $$WalletMetaTableUpdateCompanionBuilder,
          (
            WalletMetaRow,
            BaseReferences<_$AppDatabase, $WalletMetaTable, WalletMetaRow>,
          ),
          WalletMetaRow,
          PrefetchHooks Function()
        > {
  $$WalletMetaTableTableManager(_$AppDatabase db, $WalletMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$WalletMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$WalletMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$WalletMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                Value<String> walletId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) => WalletMetaCompanion(
                singleton: singleton,
                walletId: walletId,
                kind: kind,
                createdAt: createdAt,
              ),
          createCompanionCallback:
              ({
                Value<int> singleton = const Value.absent(),
                required String walletId,
                required String kind,
                required DateTime createdAt,
              }) => WalletMetaCompanion.insert(
                singleton: singleton,
                walletId: walletId,
                kind: kind,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$WalletMetaTable, WalletMetaRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $WalletMetaTable,
                    WalletMetaRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$WalletMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $WalletMetaTable,
      WalletMetaRow,
      $$WalletMetaTableFilterComposer,
      $$WalletMetaTableOrderingComposer,
      $$WalletMetaTableAnnotationComposer,
      $$WalletMetaTableCreateCompanionBuilder,
      $$WalletMetaTableUpdateCompanionBuilder,
      (
        WalletMetaRow,
        BaseReferences<_$AppDatabase, $WalletMetaTable, WalletMetaRow>,
      ),
      WalletMetaRow,
      PrefetchHooks Function()
    >;
typedef $$FinancialMemberRowsTableCreateCompanionBuilder =
    FinancialMemberRowsCompanion Function({
      required String memberId,
      required String label,
      required int displayOrder,
      required DateTime createdAt,
      Value<int> rowid,
    });
typedef $$FinancialMemberRowsTableUpdateCompanionBuilder =
    FinancialMemberRowsCompanion Function({
      Value<String> memberId,
      Value<String> label,
      Value<int> displayOrder,
      Value<DateTime> createdAt,
      Value<int> rowid,
    });

class $$FinancialMemberRowsTableFilterComposer
    extends Composer<_$AppDatabase, $FinancialMemberRowsTable> {
  $$FinancialMemberRowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FinancialMemberRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $FinancialMemberRowsTable> {
  $$FinancialMemberRowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get memberId => $composableBuilder(
    column: $table.memberId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FinancialMemberRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FinancialMemberRowsTable> {
  $$FinancialMemberRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get memberId =>
      $composableBuilder(column: $table.memberId, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<int> get displayOrder => $composableBuilder(
    column: $table.displayOrder,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$FinancialMemberRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FinancialMemberRowsTable,
          FinancialMemberRow,
          $$FinancialMemberRowsTableFilterComposer,
          $$FinancialMemberRowsTableOrderingComposer,
          $$FinancialMemberRowsTableAnnotationComposer,
          $$FinancialMemberRowsTableCreateCompanionBuilder,
          $$FinancialMemberRowsTableUpdateCompanionBuilder,
          (
            FinancialMemberRow,
            BaseReferences<
              _$AppDatabase,
              $FinancialMemberRowsTable,
              FinancialMemberRow
            >,
          ),
          FinancialMemberRow,
          PrefetchHooks Function()
        > {
  $$FinancialMemberRowsTableTableManager(
    _$AppDatabase db,
    $FinancialMemberRowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FinancialMemberRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FinancialMemberRowsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$FinancialMemberRowsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> memberId = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<int> displayOrder = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FinancialMemberRowsCompanion(
                memberId: memberId,
                label: label,
                displayOrder: displayOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String memberId,
                required String label,
                required int displayOrder,
                required DateTime createdAt,
                Value<int> rowid = const Value.absent(),
              }) => FinancialMemberRowsCompanion.insert(
                memberId: memberId,
                label: label,
                displayOrder: displayOrder,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FinancialMemberRowsTable, FinancialMemberRow>(
                    table,
                  ),
                  BaseReferences<
                    _$AppDatabase,
                    $FinancialMemberRowsTable,
                    FinancialMemberRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FinancialMemberRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FinancialMemberRowsTable,
      FinancialMemberRow,
      $$FinancialMemberRowsTableFilterComposer,
      $$FinancialMemberRowsTableOrderingComposer,
      $$FinancialMemberRowsTableAnnotationComposer,
      $$FinancialMemberRowsTableCreateCompanionBuilder,
      $$FinancialMemberRowsTableUpdateCompanionBuilder,
      (
        FinancialMemberRow,
        BaseReferences<
          _$AppDatabase,
          $FinancialMemberRowsTable,
          FinancialMemberRow
        >,
      ),
      FinancialMemberRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CategoryRowsTableTableManager get categoryRows =>
      $$CategoryRowsTableTableManager(_db, _db.categoryRows);
  $$StatusRowsTableTableManager get statusRows =>
      $$StatusRowsTableTableManager(_db, _db.statusRows);
  $$TransactionRowsTableTableManager get transactionRows =>
      $$TransactionRowsTableTableManager(_db, _db.transactionRows);
  $$FundRowsTableTableManager get fundRows =>
      $$FundRowsTableTableManager(_db, _db.fundRows);
  $$SavingsAssetTypeRowsTableTableManager get savingsAssetTypeRows =>
      $$SavingsAssetTypeRowsTableTableManager(_db, _db.savingsAssetTypeRows);
  $$CounterpartyRowsTableTableManager get counterpartyRows =>
      $$CounterpartyRowsTableTableManager(_db, _db.counterpartyRows);
  $$ObligationRowsTableTableManager get obligationRows =>
      $$ObligationRowsTableTableManager(_db, _db.obligationRows);
  $$WalletMetaTableTableManager get walletMeta =>
      $$WalletMetaTableTableManager(_db, _db.walletMeta);
  $$FinancialMemberRowsTableTableManager get financialMemberRows =>
      $$FinancialMemberRowsTableTableManager(_db, _db.financialMemberRows);
}
