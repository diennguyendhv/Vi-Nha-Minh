import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/backup/backup_service.dart';
import '../../domain/auth/cloud_session.dart';

final cloudSessionProvider = Provider<CloudSession?>((ref) => null);

/// DEV-only zero-knowledge backup (fixture data; SQLCipher gate still closed).
final backupServiceProvider = Provider<BackupService?>((ref) => null);
