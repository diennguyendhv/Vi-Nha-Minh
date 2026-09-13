// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
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
  );
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _spenderMeta = const VerificationMeta(
    'spender',
  );
  @override
  late final GeneratedColumn<String> spender = GeneratedColumn<String>(
    'spender',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
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
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _savingsDestinationMeta =
      const VerificationMeta('savingsDestination');
  @override
  late final GeneratedColumn<String> savingsDestination =
      GeneratedColumn<String>(
        'savings_destination',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    categoryId,
    amount,
    date,
    spender,
    note,
    status,
    savingsDestination,
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
    if (data.containsKey('category_id')) {
      context.handle(
        _categoryIdMeta,
        categoryId.isAcceptableOrUnknown(data['category_id']!, _categoryIdMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryIdMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('spender')) {
      context.handle(
        _spenderMeta,
        spender.isAcceptableOrUnknown(data['spender']!, _spenderMeta),
      );
    } else if (isInserting) {
      context.missing(_spenderMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    }
    if (data.containsKey('savings_destination')) {
      context.handle(
        _savingsDestinationMeta,
        savingsDestination.isAcceptableOrUnknown(
          data['savings_destination']!,
          _savingsDestinationMeta,
        ),
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
      categoryId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category_id'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      spender: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}spender'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      ),
      savingsDestination: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}savings_destination'],
      ),
    );
  }

  @override
  $TransactionRowsTable createAlias(String alias) {
    return $TransactionRowsTable(attachedDatabase, alias);
  }
}

class TransactionRow extends DataClass implements Insertable<TransactionRow> {
  final String id;
  final String categoryId;
  final int amount;
  final DateTime date;
  final String spender;
  final String note;
  final String? status;
  final String? savingsDestination;
  const TransactionRow({
    required this.id,
    required this.categoryId,
    required this.amount,
    required this.date,
    required this.spender,
    required this.note,
    this.status,
    this.savingsDestination,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['category_id'] = Variable<String>(categoryId);
    map['amount'] = Variable<int>(amount);
    map['date'] = Variable<DateTime>(date);
    map['spender'] = Variable<String>(spender);
    map['note'] = Variable<String>(note);
    if (!nullToAbsent || status != null) {
      map['status'] = Variable<String>(status);
    }
    if (!nullToAbsent || savingsDestination != null) {
      map['savings_destination'] = Variable<String>(savingsDestination);
    }
    return map;
  }

  TransactionRowsCompanion toCompanion(bool nullToAbsent) {
    return TransactionRowsCompanion(
      id: Value(id),
      categoryId: Value(categoryId),
      amount: Value(amount),
      date: Value(date),
      spender: Value(spender),
      note: Value(note),
      status: status == null && nullToAbsent
          ? const Value.absent()
          : Value(status),
      savingsDestination: savingsDestination == null && nullToAbsent
          ? const Value.absent()
          : Value(savingsDestination),
    );
  }

  factory TransactionRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return TransactionRow(
      id: serializer.fromJson<String>(json['id']),
      categoryId: serializer.fromJson<String>(json['categoryId']),
      amount: serializer.fromJson<int>(json['amount']),
      date: serializer.fromJson<DateTime>(json['date']),
      spender: serializer.fromJson<String>(json['spender']),
      note: serializer.fromJson<String>(json['note']),
      status: serializer.fromJson<String?>(json['status']),
      savingsDestination: serializer.fromJson<String?>(
        json['savingsDestination'],
      ),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'categoryId': serializer.toJson<String>(categoryId),
      'amount': serializer.toJson<int>(amount),
      'date': serializer.toJson<DateTime>(date),
      'spender': serializer.toJson<String>(spender),
      'note': serializer.toJson<String>(note),
      'status': serializer.toJson<String?>(status),
      'savingsDestination': serializer.toJson<String?>(savingsDestination),
    };
  }

  TransactionRow copyWith({
    String? id,
    String? categoryId,
    int? amount,
    DateTime? date,
    String? spender,
    String? note,
    Value<String?> status = const Value.absent(),
    Value<String?> savingsDestination = const Value.absent(),
  }) => TransactionRow(
    id: id ?? this.id,
    categoryId: categoryId ?? this.categoryId,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    spender: spender ?? this.spender,
    note: note ?? this.note,
    status: status.present ? status.value : this.status,
    savingsDestination: savingsDestination.present
        ? savingsDestination.value
        : this.savingsDestination,
  );
  TransactionRow copyWithCompanion(TransactionRowsCompanion data) {
    return TransactionRow(
      id: data.id.present ? data.id.value : this.id,
      categoryId: data.categoryId.present
          ? data.categoryId.value
          : this.categoryId,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      spender: data.spender.present ? data.spender.value : this.spender,
      note: data.note.present ? data.note.value : this.note,
      status: data.status.present ? data.status.value : this.status,
      savingsDestination: data.savingsDestination.present
          ? data.savingsDestination.value
          : this.savingsDestination,
    );
  }

  @override
  String toString() {
    return (StringBuffer('TransactionRow(')
          ..write('id: $id, ')
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('spender: $spender, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('savingsDestination: $savingsDestination')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    categoryId,
    amount,
    date,
    spender,
    note,
    status,
    savingsDestination,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TransactionRow &&
          other.id == this.id &&
          other.categoryId == this.categoryId &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.spender == this.spender &&
          other.note == this.note &&
          other.status == this.status &&
          other.savingsDestination == this.savingsDestination);
}

class TransactionRowsCompanion extends UpdateCompanion<TransactionRow> {
  final Value<String> id;
  final Value<String> categoryId;
  final Value<int> amount;
  final Value<DateTime> date;
  final Value<String> spender;
  final Value<String> note;
  final Value<String?> status;
  final Value<String?> savingsDestination;
  final Value<int> rowid;
  const TransactionRowsCompanion({
    this.id = const Value.absent(),
    this.categoryId = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.spender = const Value.absent(),
    this.note = const Value.absent(),
    this.status = const Value.absent(),
    this.savingsDestination = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  TransactionRowsCompanion.insert({
    required String id,
    required String categoryId,
    required int amount,
    required DateTime date,
    required String spender,
    this.note = const Value.absent(),
    this.status = const Value.absent(),
    this.savingsDestination = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       categoryId = Value(categoryId),
       amount = Value(amount),
       date = Value(date),
       spender = Value(spender);
  static Insertable<TransactionRow> custom({
    Expression<String>? id,
    Expression<String>? categoryId,
    Expression<int>? amount,
    Expression<DateTime>? date,
    Expression<String>? spender,
    Expression<String>? note,
    Expression<String>? status,
    Expression<String>? savingsDestination,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (categoryId != null) 'category_id': categoryId,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (spender != null) 'spender': spender,
      if (note != null) 'note': note,
      if (status != null) 'status': status,
      if (savingsDestination != null) 'savings_destination': savingsDestination,
      if (rowid != null) 'rowid': rowid,
    });
  }

  TransactionRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? categoryId,
    Value<int>? amount,
    Value<DateTime>? date,
    Value<String>? spender,
    Value<String>? note,
    Value<String?>? status,
    Value<String?>? savingsDestination,
    Value<int>? rowid,
  }) {
    return TransactionRowsCompanion(
      id: id ?? this.id,
      categoryId: categoryId ?? this.categoryId,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      spender: spender ?? this.spender,
      note: note ?? this.note,
      status: status ?? this.status,
      savingsDestination: savingsDestination ?? this.savingsDestination,
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
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (spender.present) {
      map['spender'] = Variable<String>(spender.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (savingsDestination.present) {
      map['savings_destination'] = Variable<String>(savingsDestination.value);
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
          ..write('categoryId: $categoryId, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('spender: $spender, ')
          ..write('note: $note, ')
          ..write('status: $status, ')
          ..write('savingsDestination: $savingsDestination, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FundEntryRowsTable extends FundEntryRows
    with TableInfo<$FundEntryRowsTable, FundEntryRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FundEntryRowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fundIdMeta = const VerificationMeta('fundId');
  @override
  late final GeneratedColumn<String> fundId = GeneratedColumn<String>(
    'fund_id',
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
  static const VerificationMeta _amountMeta = const VerificationMeta('amount');
  @override
  late final GeneratedColumn<int> amount = GeneratedColumn<int>(
    'amount',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
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
  @override
  List<GeneratedColumn> get $columns => [id, fundId, kind, amount, date, note];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'fund_entry_rows';
  @override
  VerificationContext validateIntegrity(
    Insertable<FundEntryRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('fund_id')) {
      context.handle(
        _fundIdMeta,
        fundId.isAcceptableOrUnknown(data['fund_id']!, _fundIdMeta),
      );
    } else if (isInserting) {
      context.missing(_fundIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('amount')) {
      context.handle(
        _amountMeta,
        amount.isAcceptableOrUnknown(data['amount']!, _amountMeta),
      );
    } else if (isInserting) {
      context.missing(_amountMeta);
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FundEntryRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FundEntryRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      fundId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fund_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      amount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      )!,
    );
  }

  @override
  $FundEntryRowsTable createAlias(String alias) {
    return $FundEntryRowsTable(attachedDatabase, alias);
  }
}

class FundEntryRow extends DataClass implements Insertable<FundEntryRow> {
  final String id;
  final String fundId;
  final String kind;
  final int amount;
  final DateTime date;
  final String note;
  const FundEntryRow({
    required this.id,
    required this.fundId,
    required this.kind,
    required this.amount,
    required this.date,
    required this.note,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['fund_id'] = Variable<String>(fundId);
    map['kind'] = Variable<String>(kind);
    map['amount'] = Variable<int>(amount);
    map['date'] = Variable<DateTime>(date);
    map['note'] = Variable<String>(note);
    return map;
  }

  FundEntryRowsCompanion toCompanion(bool nullToAbsent) {
    return FundEntryRowsCompanion(
      id: Value(id),
      fundId: Value(fundId),
      kind: Value(kind),
      amount: Value(amount),
      date: Value(date),
      note: Value(note),
    );
  }

  factory FundEntryRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FundEntryRow(
      id: serializer.fromJson<String>(json['id']),
      fundId: serializer.fromJson<String>(json['fundId']),
      kind: serializer.fromJson<String>(json['kind']),
      amount: serializer.fromJson<int>(json['amount']),
      date: serializer.fromJson<DateTime>(json['date']),
      note: serializer.fromJson<String>(json['note']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'fundId': serializer.toJson<String>(fundId),
      'kind': serializer.toJson<String>(kind),
      'amount': serializer.toJson<int>(amount),
      'date': serializer.toJson<DateTime>(date),
      'note': serializer.toJson<String>(note),
    };
  }

  FundEntryRow copyWith({
    String? id,
    String? fundId,
    String? kind,
    int? amount,
    DateTime? date,
    String? note,
  }) => FundEntryRow(
    id: id ?? this.id,
    fundId: fundId ?? this.fundId,
    kind: kind ?? this.kind,
    amount: amount ?? this.amount,
    date: date ?? this.date,
    note: note ?? this.note,
  );
  FundEntryRow copyWithCompanion(FundEntryRowsCompanion data) {
    return FundEntryRow(
      id: data.id.present ? data.id.value : this.id,
      fundId: data.fundId.present ? data.fundId.value : this.fundId,
      kind: data.kind.present ? data.kind.value : this.kind,
      amount: data.amount.present ? data.amount.value : this.amount,
      date: data.date.present ? data.date.value : this.date,
      note: data.note.present ? data.note.value : this.note,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FundEntryRow(')
          ..write('id: $id, ')
          ..write('fundId: $fundId, ')
          ..write('kind: $kind, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, fundId, kind, amount, date, note);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FundEntryRow &&
          other.id == this.id &&
          other.fundId == this.fundId &&
          other.kind == this.kind &&
          other.amount == this.amount &&
          other.date == this.date &&
          other.note == this.note);
}

class FundEntryRowsCompanion extends UpdateCompanion<FundEntryRow> {
  final Value<String> id;
  final Value<String> fundId;
  final Value<String> kind;
  final Value<int> amount;
  final Value<DateTime> date;
  final Value<String> note;
  final Value<int> rowid;
  const FundEntryRowsCompanion({
    this.id = const Value.absent(),
    this.fundId = const Value.absent(),
    this.kind = const Value.absent(),
    this.amount = const Value.absent(),
    this.date = const Value.absent(),
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FundEntryRowsCompanion.insert({
    required String id,
    required String fundId,
    required String kind,
    required int amount,
    required DateTime date,
    this.note = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       fundId = Value(fundId),
       kind = Value(kind),
       amount = Value(amount),
       date = Value(date);
  static Insertable<FundEntryRow> custom({
    Expression<String>? id,
    Expression<String>? fundId,
    Expression<String>? kind,
    Expression<int>? amount,
    Expression<DateTime>? date,
    Expression<String>? note,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (fundId != null) 'fund_id': fundId,
      if (kind != null) 'kind': kind,
      if (amount != null) 'amount': amount,
      if (date != null) 'date': date,
      if (note != null) 'note': note,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FundEntryRowsCompanion copyWith({
    Value<String>? id,
    Value<String>? fundId,
    Value<String>? kind,
    Value<int>? amount,
    Value<DateTime>? date,
    Value<String>? note,
    Value<int>? rowid,
  }) {
    return FundEntryRowsCompanion(
      id: id ?? this.id,
      fundId: fundId ?? this.fundId,
      kind: kind ?? this.kind,
      amount: amount ?? this.amount,
      date: date ?? this.date,
      note: note ?? this.note,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (fundId.present) {
      map['fund_id'] = Variable<String>(fundId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (amount.present) {
      map['amount'] = Variable<int>(amount.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FundEntryRowsCompanion(')
          ..write('id: $id, ')
          ..write('fundId: $fundId, ')
          ..write('kind: $kind, ')
          ..write('amount: $amount, ')
          ..write('date: $date, ')
          ..write('note: $note, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $TransactionRowsTable transactionRows = $TransactionRowsTable(
    this,
  );
  late final $FundEntryRowsTable fundEntryRows = $FundEntryRowsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    transactionRows,
    fundEntryRows,
  ];
}

typedef $$TransactionRowsTableCreateCompanionBuilder =
    TransactionRowsCompanion Function({
      required String id,
      required String categoryId,
      required int amount,
      required DateTime date,
      required String spender,
      Value<String> note,
      Value<String?> status,
      Value<String?> savingsDestination,
      Value<int> rowid,
    });
typedef $$TransactionRowsTableUpdateCompanionBuilder =
    TransactionRowsCompanion Function({
      Value<String> id,
      Value<String> categoryId,
      Value<int> amount,
      Value<DateTime> date,
      Value<String> spender,
      Value<String> note,
      Value<String?> status,
      Value<String?> savingsDestination,
      Value<int> rowid,
    });

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

  ColumnFilters<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get spender => $composableBuilder(
    column: $table.spender,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get savingsDestination => $composableBuilder(
    column: $table.savingsDestination,
    builder: (column) => ColumnFilters(column),
  );
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

  ColumnOrderings<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get spender => $composableBuilder(
    column: $table.spender,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get savingsDestination => $composableBuilder(
    column: $table.savingsDestination,
    builder: (column) => ColumnOrderings(column),
  );
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

  GeneratedColumn<String> get categoryId => $composableBuilder(
    column: $table.categoryId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get spender =>
      $composableBuilder(column: $table.spender, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<String> get savingsDestination => $composableBuilder(
    column: $table.savingsDestination,
    builder: (column) => column,
  );
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
          (
            TransactionRow,
            BaseReferences<
              _$AppDatabase,
              $TransactionRowsTable,
              TransactionRow
            >,
          ),
          TransactionRow,
          PrefetchHooks Function()
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
                Value<String> categoryId = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> spender = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> savingsDestination = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionRowsCompanion(
                id: id,
                categoryId: categoryId,
                amount: amount,
                date: date,
                spender: spender,
                note: note,
                status: status,
                savingsDestination: savingsDestination,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String categoryId,
                required int amount,
                required DateTime date,
                required String spender,
                Value<String> note = const Value.absent(),
                Value<String?> status = const Value.absent(),
                Value<String?> savingsDestination = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => TransactionRowsCompanion.insert(
                id: id,
                categoryId: categoryId,
                amount: amount,
                date: date,
                spender: spender,
                note: note,
                status: status,
                savingsDestination: savingsDestination,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$TransactionRowsTable, TransactionRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $TransactionRowsTable,
                    TransactionRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
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
      (
        TransactionRow,
        BaseReferences<_$AppDatabase, $TransactionRowsTable, TransactionRow>,
      ),
      TransactionRow,
      PrefetchHooks Function()
    >;
typedef $$FundEntryRowsTableCreateCompanionBuilder =
    FundEntryRowsCompanion Function({
      required String id,
      required String fundId,
      required String kind,
      required int amount,
      required DateTime date,
      Value<String> note,
      Value<int> rowid,
    });
typedef $$FundEntryRowsTableUpdateCompanionBuilder =
    FundEntryRowsCompanion Function({
      Value<String> id,
      Value<String> fundId,
      Value<String> kind,
      Value<int> amount,
      Value<DateTime> date,
      Value<String> note,
      Value<int> rowid,
    });

class $$FundEntryRowsTableFilterComposer
    extends Composer<_$AppDatabase, $FundEntryRowsTable> {
  $$FundEntryRowsTableFilterComposer({
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

  ColumnFilters<String> get fundId => $composableBuilder(
    column: $table.fundId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FundEntryRowsTableOrderingComposer
    extends Composer<_$AppDatabase, $FundEntryRowsTable> {
  $$FundEntryRowsTableOrderingComposer({
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

  ColumnOrderings<String> get fundId => $composableBuilder(
    column: $table.fundId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amount => $composableBuilder(
    column: $table.amount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FundEntryRowsTableAnnotationComposer
    extends Composer<_$AppDatabase, $FundEntryRowsTable> {
  $$FundEntryRowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fundId =>
      $composableBuilder(column: $table.fundId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<int> get amount =>
      $composableBuilder(column: $table.amount, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);
}

class $$FundEntryRowsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $FundEntryRowsTable,
          FundEntryRow,
          $$FundEntryRowsTableFilterComposer,
          $$FundEntryRowsTableOrderingComposer,
          $$FundEntryRowsTableAnnotationComposer,
          $$FundEntryRowsTableCreateCompanionBuilder,
          $$FundEntryRowsTableUpdateCompanionBuilder,
          (
            FundEntryRow,
            BaseReferences<_$AppDatabase, $FundEntryRowsTable, FundEntryRow>,
          ),
          FundEntryRow,
          PrefetchHooks Function()
        > {
  $$FundEntryRowsTableTableManager(_$AppDatabase db, $FundEntryRowsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FundEntryRowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FundEntryRowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FundEntryRowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> fundId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<int> amount = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FundEntryRowsCompanion(
                id: id,
                fundId: fundId,
                kind: kind,
                amount: amount,
                date: date,
                note: note,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String fundId,
                required String kind,
                required int amount,
                required DateTime date,
                Value<String> note = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FundEntryRowsCompanion.insert(
                id: id,
                fundId: fundId,
                kind: kind,
                amount: amount,
                date: date,
                note: note,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FundEntryRowsTable, FundEntryRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $FundEntryRowsTable,
                    FundEntryRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FundEntryRowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $FundEntryRowsTable,
      FundEntryRow,
      $$FundEntryRowsTableFilterComposer,
      $$FundEntryRowsTableOrderingComposer,
      $$FundEntryRowsTableAnnotationComposer,
      $$FundEntryRowsTableCreateCompanionBuilder,
      $$FundEntryRowsTableUpdateCompanionBuilder,
      (
        FundEntryRow,
        BaseReferences<_$AppDatabase, $FundEntryRowsTable, FundEntryRow>,
      ),
      FundEntryRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$TransactionRowsTableTableManager get transactionRows =>
      $$TransactionRowsTableTableManager(_db, _db.transactionRows);
  $$FundEntryRowsTableTableManager get fundEntryRows =>
      $$FundEntryRowsTableTableManager(_db, _db.fundEntryRows);
}
