import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/local_status_repository.dart';
import '../../domain/entities/status.dart';
import '../../domain/repositories/status_repository.dart';
import 'database_provider.dart';

final statusRepositoryProvider = Provider<StatusRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return LocalStatusRepository(db);
});

final statusesStreamProvider = StreamProvider.family<List<Status>, String>((
  ref,
  categoryId,
) {
  final repository = ref.watch(statusRepositoryProvider);
  return repository.watchStatuses(categoryId);
});
