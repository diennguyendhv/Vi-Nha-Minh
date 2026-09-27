import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';
import 'package:drift/native.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../../core/crypto/backup_crypto.dart';
import '../../../domain/engine/financial_engine.dart';
import '../../repositories/local_transaction_repository.dart';
import '../app_database.dart';
import 'sqlcipher_wallet.dart';

/// Thay đổi schema THUẦN CỘNG THÊM được phép giữa phiên bản nguồn và đích: bảng mới
/// (phải rỗng sau di trú) và bảng được ALTER ADD COLUMN (digest dòng đổi vì có thêm ô
/// NULL, số dòng phải giữ nguyên). Mọi bảng khác phải trùng tuyệt đối (số dòng +
/// digest). Nguồn không có trong bảng này ⇒ diễn tập từ chối (không đoán).
const rehearsalAllowedChanges =
    <int, ({Set<String> added, Set<String> altered})>{
      // v10 → v11 (P8.3): `sync_state.backup_state` + bảng `sync_conflicts`.
      10: (added: {'sync_conflicts'}, altered: {'sync_state'}),
      11: (added: <String>{}, altered: <String>{}),
    };

class MigrationRehearsalResult {
  const MigrationRehearsalResult(this.mismatches, this.report);

  /// Rỗng = PASS. Chỉ mã lý do/tên bảng — không nội dung dòng.
  final List<String> mismatches;

  /// Chỉ số đếm/digest/id mờ — an toàn để in ra logcat.
  final Map<String, Object?> report;
  bool get pass => mismatches.isEmpty;
}

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

String _sha(String s) =>
    _hex(const DartSha256().hashSync(utf8.encode(s)).bytes);

Future<String> _fileSha(File f) async =>
    _hex(const DartSha256().hashSync(await f.readAsBytes()).bytes);

/// Phần ngữ nghĩa so sánh được giữa trước/sau: id → clientTxId, id thành viên, số dư
/// mọi pool (Financial Engine thật trên dòng thô).
({
  Map<String, String> clientTxIds,
  List<String> memberIds,
  Map<String, int> balances,
})
_semantic(Database db, AppDatabase mapper) {
  final rows = db.select('SELECT * FROM transaction_rows');
  final txs = [
    for (final r in rows)
      LocalTransactionRepository.rowToDomain(
        mapper.transactionRows.map(Map<String, dynamic>.from(r)),
      ),
  ];
  final balances = {
    for (final e in computeAllPoolBalances(txs).entries)
      e.key.toString(): e.value,
  };
  return (
    clientTxIds: {
      for (final r in rows) r['id'] as String: r['client_tx_id'] as String,
    },
    memberIds: [
      for (final r in db.select(
        'SELECT member_id FROM financial_member_rows ORDER BY member_id',
      ))
        r['member_id'] as String,
    ],
    balances: balances,
  );
}

String _canon(Object v) => jsonEncode(switch (v) {
  final Map<String, Object?> m => Map.fromEntries(
    m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
  ),
  _ => v,
});

void _deleteWithSidecars(File f) {
  for (final suffix in ['', '-journal', '-wal', '-shm']) {
    final x = File('${f.path}$suffix');
    if (x.existsSync()) x.deleteSync();
  }
}

/// DIỄN TẬP di trú schema trên BẢN SAO của ví thật đã mã hoá — không bao giờ ghi vào
/// [live]:
/// 1. mở [live] CHỈ ĐỌC (`?mode=ro`) bằng [liveKey], chụp snapshot + ngữ nghĩa;
/// 2. `sqlcipher_export` sang file tạm trong [scratch], mã hoá bằng khoá TẠM ngẫu nhiên
///    (chỉ trong bộ nhớ, không vào Keystore/prefs), kiểm bản sao trùng nguồn;
/// 3. mở bản sao bằng `AppDatabase` của source hiện tại ⇒ chạy đúng `onUpgrade`/
///    `beforeOpen` thật;
/// 4. so sánh walletId, số dòng/digest từng bảng (chỉ cho phép thay đổi cộng thêm
///    khai báo trong [rehearsalAllowedChanges]), id/clientTxId, id thành viên, số dư,
///    integrity, FK; kiểm file [live] không đổi (SHA-256 + độ dài);
/// 5. xoá bản sao (kể cả khi lỗi).
Future<MigrationRehearsalResult> rehearseWalletMigration({
  required File live,
  required Uint8List liveKey,
  required Directory scratch,
}) async {
  final mismatches = <String>[];
  final report = <String, Object?>{};
  MigrationRehearsalResult done() {
    report['pass'] = mismatches.isEmpty;
    report['mismatches'] = mismatches;
    return MigrationRehearsalResult(mismatches, report);
  }

  if (probeDbFile(live) != DbFileState.encrypted) {
    mismatches.add('source-not-encrypted');
    return done();
  }
  // Journal/WAL nóng: khôi phục nó là một lần GHI ⇒ không làm, chỉ báo.
  for (final side in ['-journal', '-wal']) {
    if (File('${live.path}$side').existsSync()) {
      mismatches.add('source-has$side');
      return done();
    }
  }
  final liveShaBefore = await _fileSha(live);
  final liveLenBefore = live.lengthSync();
  final liveUri = Uri.file(live.path).replace(queryParameters: {'mode': 'ro'});

  // Chỉ để ánh xạ dòng thô → TransactionRow (không mở, không file).
  final mapper = AppDatabase.forTesting(NativeDatabase.memory());
  scratch.createSync(recursive: true);
  final temp = File(
    '${scratch.path}/rehearsal_${DateTime.now().microsecondsSinceEpoch}.sqlite',
  );
  final tempKey = BackupCrypto.randomBytes(32);
  try {
    // 1. Nguồn, chỉ đọc.
    final src = sqlite3.open('$liveUri', uri: true);
    late final DbSnapshot before;
    late final ({
      Map<String, String> clientTxIds,
      List<String> memberIds,
      Map<String, int> balances,
    })
    semBefore;
    try {
      applySqlcipherKey(src, liveKey);
      before = captureSnapshot(src);
      semBefore = _semantic(src, mapper);
    } finally {
      src.close();
    }
    final targetVersion = mapper.schemaVersion;
    report
      ..['walletId'] = before.walletId
      ..['fromVersion'] = before.userVersion
      ..['toVersion'] = targetVersion
      ..['sourceIntegrity'] = before.integrity
      ..['sourceFk'] = before.foreignKeyViolations;
    if (!before.healthy) mismatches.add('source-unhealthy');
    final allowed = rehearsalAllowedChanges[before.userVersion];
    if (allowed == null) {
      mismatches.add('unsupported-source-version:${before.userVersion}');
      return done();
    }

    // 2. Bản sao mã hoá bằng khoá tạm.
    final target = sqlite3.open(temp.path, uri: true);
    try {
      applySqlcipherKey(target, tempKey);
      target.execute('ATTACH DATABASE ? AS live KEY ?', [
        '$liveUri',
        "x'${_hex(liveKey)}'",
      ]);
      target.select("SELECT sqlcipher_export('main', 'live')");
      target.execute('DETACH DATABASE live');
      target.userVersion = before.userVersion;
    } finally {
      target.close();
    }
    final copy = sqlite3.open(temp.path, mode: OpenMode.readOnly);
    try {
      applySqlcipherKey(copy, tempKey);
      if (!captureSnapshot(copy).sameDataAs(before)) {
        mismatches.add('copy-differs-from-source');
        return done();
      }
    } finally {
      copy.close();
    }

    // 3. Di trú THẬT của source hiện tại, trên bản sao.
    final app = AppDatabase.forTesting(
      NativeDatabase(temp, setup: (db) => applySqlcipherKey(db, tempKey)),
    );
    final Map<String, int> balancesViaApp;
    try {
      await app.select(app.walletMeta).get();
      balancesViaApp = {
        for (final e in computeAllPoolBalances(
          await LocalTransactionRepository(app).allTransactions(),
        ).entries)
          e.key.toString(): e.value,
      };
    } finally {
      await app.close();
    }

    // 4. So sánh.
    final migrated = sqlite3.open(temp.path, mode: OpenMode.readOnly);
    late final DbSnapshot after;
    late final ({
      Map<String, String> clientTxIds,
      List<String> memberIds,
      Map<String, int> balances,
    })
    semAfter;
    try {
      applySqlcipherKey(migrated, tempKey);
      after = captureSnapshot(migrated);
      semAfter = _semantic(migrated, mapper);
    } finally {
      migrated.close();
    }

    if (after.userVersion != targetVersion) {
      mismatches.add('target-version:${after.userVersion}');
    }
    if (after.walletId != before.walletId) mismatches.add('walletId');
    if (after.integrity != 'ok') mismatches.add('integrity');
    if (after.foreignKeyViolations != 0) mismatches.add('foreign-keys');
    final tables = <String, Object>{};
    for (final name in {...before.tables.keys, ...after.tables.keys}) {
      final b = before.tables[name];
      final a = after.tables[name];
      tables[name] = [b?.count ?? -1, a?.count ?? -1, b?.digest == a?.digest];
      if (a == null) {
        mismatches.add('table-dropped:$name');
      } else if (b == null) {
        if (!allowed.added.contains(name)) mismatches.add('table-new:$name');
        if (a.count != 0) mismatches.add('table-new-not-empty:$name');
      } else if (a.count != b.count) {
        mismatches.add('table-count:$name');
      } else if (a.digest != b.digest && !allowed.altered.contains(name)) {
        mismatches.add('table-digest:$name');
      }
    }
    report['tables'] = tables;
    if (_canon(semAfter.clientTxIds) != _canon(semBefore.clientTxIds)) {
      mismatches.add('transaction-ids-or-clientTxIds');
    }
    if (_canon(semAfter.memberIds) != _canon(semBefore.memberIds)) {
      mismatches.add('financial-member-ids');
    }
    if (_canon(semAfter.balances) != _canon(semBefore.balances)) {
      mismatches.add('balances-raw');
    }
    if (_canon(balancesViaApp) != _canon(semBefore.balances)) {
      mismatches.add('balances-via-app');
    }
    report
      ..['transactions'] = semBefore.clientTxIds.length
      ..['txIdsDigest'] = _sha(_canon(semBefore.clientTxIds))
      ..['memberIds'] = semBefore.memberIds
      ..['pools'] = semBefore.balances.length
      ..['balancesDigest'] = _sha(_canon(semBefore.balances))
      ..['targetIntegrity'] = after.integrity
      ..['targetFk'] = after.foreignKeyViolations;
    return done();
  } on Object catch (e) {
    mismatches.add('error:${e.runtimeType}');
    return done();
  } finally {
    await mapper.close();
    _deleteWithSidecars(temp);
    report['rehearsalFileDeleted'] = !temp.existsSync();
    if (!(report['rehearsalFileDeleted']! as bool)) {
      mismatches.add('rehearsal-file-not-deleted');
    }
    // File thật không được đổi dù chỉ 1 byte.
    final unchanged =
        live.existsSync() &&
        live.lengthSync() == liveLenBefore &&
        await _fileSha(live) == liveShaBefore;
    report['liveUnchanged'] = unchanged;
    if (!unchanged) mismatches.add('LIVE-FILE-CHANGED');
    report['pass'] = mismatches.isEmpty;
  }
}
