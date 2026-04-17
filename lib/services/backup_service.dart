import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

/// Handles full-database backup (export) and restore (import) via the
/// Android Storage Access Framework (SAF).
class BackupService {
  BackupService._();
  static final BackupService instance = BackupService._();

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  /// Exports a copy of the app database via the system share sheet.
  /// The user picks a destination (Downloads, Google Drive, etc.).
  /// Returns `true` if the share sheet was shown successfully.
  Future<bool> export() async {
    // Ensure WAL is flushed before copying.
    final db = await AppDatabase.instance.appDb;
    await db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');

    final docDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docDir.path, 'birdtally.db');

    final tmpDir = await getTemporaryDirectory();
    final stamp = _dateFmt.format(DateTime.now());
    final backupName = 'BirdTally-backup-$stamp.db';
    final tmpFile = File(p.join(tmpDir.path, backupName));

    await File(dbPath).copy(tmpFile.path);

    await Share.shareXFiles(
      [XFile(tmpFile.path, mimeType: 'application/x-sqlite3')],
      subject: backupName,
    );

    return true;
  }

  /// Lets the user pick a `.db` file and restores it as the app database.
  /// Returns a [BackupRestoreResult] describing what happened.
  Future<BackupRestoreResult> restore() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) {
      return BackupRestoreResult.cancelled;
    }

    final pickedPath = result.files.single.path;
    if (pickedPath == null) {
      return BackupRestoreResult.cancelled;
    }

    // Validate the picked file is a usable SQLite database.
    final valid = await _validate(pickedPath);
    if (!valid) {
      return BackupRestoreResult.invalid;
    }

    // Close current database before overwriting.
    await AppDatabase.instance.close();

    final docDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docDir.path, 'birdtally.db');

    // Keep a safety copy of the current DB in case something goes wrong.
    final safetyPath = '$dbPath.pre-restore';
    if (File(dbPath).existsSync()) {
      await File(dbPath).copy(safetyPath);
    }

    // Also remove WAL/SHM files so the new DB starts clean.
    for (final suffix in ['-wal', '-shm']) {
      final f = File('$dbPath$suffix');
      if (f.existsSync()) await f.delete();
    }

    try {
      await File(pickedPath).copy(dbPath);
      return BackupRestoreResult.success;
    } catch (_) {
      // Attempt to roll back.
      if (File(safetyPath).existsSync()) {
        await File(safetyPath).copy(dbPath);
      }
      return BackupRestoreResult.error;
    }
  }

  /// Quick validation: open as SQLite and check that the `sessions` table
  /// exists (strong indicator this is a BirdTally database).
  Future<bool> _validate(String path) async {
    Database? testDb;
    try {
      testDb = await openDatabase(path, readOnly: true);
      final tables = await testDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sessions'",
      );
      return tables.isNotEmpty;
    } catch (_) {
      return false;
    } finally {
      await testDb?.close();
    }
  }
}

enum BackupRestoreResult {
  success,
  cancelled,
  invalid,
  error,
}
