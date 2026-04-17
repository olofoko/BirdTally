import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Manages both databases:
///   - taxa.db  (read-only, copied from assets on first run)
///   - app.db   (read-write, user data: folders, sites, sessions, observations)
class AppDatabase {
  AppDatabase._();
  static final AppDatabase instance = AppDatabase._();

  Database? _taxaDb;
  Database? _appDb;

  // ---------------------------------------------------------------------------
  // Taxa DB (read-only, bundled)
  // ---------------------------------------------------------------------------

  Future<Database> get taxaDb async {
    _taxaDb ??= await _openTaxaDb();
    return _taxaDb!;
  }

  Future<Database> _openTaxaDb() async {
    final dir = await getApplicationSupportDirectory();
    final path = join(dir.path, 'taxa.db');

    // Copy from assets if not present or outdated.
    if (!File(path).existsSync()) {
      final data = await rootBundle.load('assets/data/taxa.db');
      final bytes = data.buffer.asUint8List();
      await File(path).writeAsBytes(bytes, flush: true);
    }

    return openDatabase(path, readOnly: true);
  }

  // ---------------------------------------------------------------------------
  // App DB (read-write, user data)
  // ---------------------------------------------------------------------------

  Future<Database> get appDb async {
    _appDb ??= await _openAppDb();
    return _appDb!;
  }

  Future<Database> _openAppDb() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = join(dir.path, 'birdtally.db');

    return openDatabase(
      path,
      version: 10,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE folders (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        parent_folder_id  INTEGER REFERENCES folders(id) ON DELETE SET NULL,
        name              TEXT NOT NULL,
        created_at        INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sites (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        folder_id           INTEGER REFERENCES folders(id) ON DELETE SET NULL,
        name                TEXT NOT NULL,
        landskap            TEXT,
        sweref99_northing   REAL,
        sweref99_easting    REAL,
        radius_m            INTEGER,
        wgs84_lat           REAL,
        wgs84_lon           REAL,
        created_at          INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE sessions (
        id                  INTEGER PRIMARY KEY AUTOINCREMENT,
        site_id             INTEGER REFERENCES sites(id) ON DELETE SET NULL,
        name                TEXT NOT NULL,
        date                INTEGER NOT NULL,
        region              TEXT,
        sweref99_northing   REAL,
        sweref99_easting    REAL,
        radius_m            INTEGER,
        wgs84_lat           REAL,
        wgs84_lon           REAL,
        end_time            INTEGER,
        is_template         INTEGER NOT NULL DEFAULT 0,
        created_at          INTEGER NOT NULL,
        updated_at          INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE observations (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        taxon_id    INTEGER NOT NULL,
        count       INTEGER NOT NULL DEFAULT 0,
        is_pinned   INTEGER NOT NULL DEFAULT 0,
        UNIQUE (session_id, taxon_id)
      )
    ''');

    await db.execute('CREATE INDEX idx_obs_session ON observations(session_id)');
    await db.execute('CREATE INDEX idx_sessions_site ON sessions(site_id)');
    await db.execute('CREATE INDEX idx_sites_folder ON sites(folder_id)');
    await _createActivityObservations(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _createActivityObservations(db);
    }
    if (oldVersion < 3) {
      await db.execute('ALTER TABLE sessions ADD COLUMN end_time INTEGER');
    }
    if (oldVersion < 4) {
      await db.execute(
          'ALTER TABLE folders ADD COLUMN parent_folder_id INTEGER REFERENCES folders(id) ON DELETE SET NULL');
    }
    if (oldVersion < 5) {
      await db.execute('ALTER TABLE sites ADD COLUMN sweref99_northing REAL');
      await db.execute('ALTER TABLE sites ADD COLUMN sweref99_easting REAL');
      await db.execute('ALTER TABLE sites ADD COLUMN radius_m INTEGER');
    }
    if (oldVersion < 6) {
      await db.execute('ALTER TABLE sites ADD COLUMN wgs84_lat REAL');
      await db.execute('ALTER TABLE sites ADD COLUMN wgs84_lon REAL');
      await db.execute('ALTER TABLE sessions ADD COLUMN wgs84_lat REAL');
      await db.execute('ALTER TABLE sessions ADD COLUMN wgs84_lon REAL');
    }
    if (oldVersion < 7) {
      // Recreate activity_observations with stage/gender columns and updated
      // unique constraint (session_id, taxon_id, activity, stage, gender).
      await db.execute('''
        CREATE TABLE activity_observations_new (
          id          INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id  INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          taxon_id    INTEGER NOT NULL,
          activity    TEXT NOT NULL DEFAULT '',
          stage       TEXT NOT NULL DEFAULT '',
          gender      TEXT NOT NULL DEFAULT '',
          count       INTEGER NOT NULL DEFAULT 0,
          UNIQUE (session_id, taxon_id, activity, stage, gender)
        )
      ''');
      await db.execute('''
        INSERT INTO activity_observations_new
          (id, session_id, taxon_id, activity, stage, gender, count)
        SELECT id, session_id, taxon_id, activity, '', '', count
        FROM activity_observations
      ''');
      await db.execute('DROP TABLE activity_observations');
      await db.execute(
          'ALTER TABLE activity_observations_new RENAME TO activity_observations');
      await db.execute(
          'CREATE INDEX idx_act_obs_session ON activity_observations(session_id)');
    }
    if (oldVersion < 8) {
      await db.execute('ALTER TABLE sites ADD COLUMN landskap TEXT');
    }
    if (oldVersion < 9) {
      // Recreate activity_observations with comment_public/comment_private
      // columns. (Later replaced by v10 which drops the UNIQUE constraint —
      // we still run the v9 step for DBs upgrading from v8 so comment columns
      // exist before v10 restructures the table.)
      await db.execute('''
        CREATE TABLE activity_observations_new (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id       INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          taxon_id         INTEGER NOT NULL,
          activity         TEXT NOT NULL DEFAULT '',
          stage            TEXT NOT NULL DEFAULT '',
          gender           TEXT NOT NULL DEFAULT '',
          comment_public   TEXT NOT NULL DEFAULT '',
          comment_private  TEXT NOT NULL DEFAULT '',
          count            INTEGER NOT NULL DEFAULT 0,
          UNIQUE (session_id, taxon_id, activity, stage, gender, comment_public, comment_private)
        )
      ''');
      await db.execute('''
        INSERT INTO activity_observations_new
          (id, session_id, taxon_id, activity, stage, gender, comment_public, comment_private, count)
        SELECT id, session_id, taxon_id, activity, stage, gender, '', '', count
        FROM activity_observations
      ''');
      await db.execute('DROP TABLE activity_observations');
      await db.execute(
          'ALTER TABLE activity_observations_new RENAME TO activity_observations');
      await db.execute(
          'CREATE INDEX idx_act_obs_session ON activity_observations(session_id)');
    }
    if (oldVersion < 10) {
      // Drop the UNIQUE constraint so the user can create multiple sub-rows
      // with identical attributes (e.g. two "sträckande N" rows filled in
      // with different comments afterwards).
      await db.execute('''
        CREATE TABLE activity_observations_new (
          id               INTEGER PRIMARY KEY AUTOINCREMENT,
          session_id       INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
          taxon_id         INTEGER NOT NULL,
          activity         TEXT NOT NULL DEFAULT '',
          stage            TEXT NOT NULL DEFAULT '',
          gender           TEXT NOT NULL DEFAULT '',
          comment_public   TEXT NOT NULL DEFAULT '',
          comment_private  TEXT NOT NULL DEFAULT '',
          count            INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.execute('''
        INSERT INTO activity_observations_new
          (id, session_id, taxon_id, activity, stage, gender, comment_public, comment_private, count)
        SELECT id, session_id, taxon_id, activity, stage, gender, comment_public, comment_private, count
        FROM activity_observations
      ''');
      await db.execute('DROP TABLE activity_observations');
      await db.execute(
          'ALTER TABLE activity_observations_new RENAME TO activity_observations');
      await db.execute(
          'CREATE INDEX idx_act_obs_session ON activity_observations(session_id)');
    }
  }

  Future<void> _createActivityObservations(Database db) async {
    await db.execute('''
      CREATE TABLE activity_observations (
        id               INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id       INTEGER NOT NULL REFERENCES sessions(id) ON DELETE CASCADE,
        taxon_id         INTEGER NOT NULL,
        activity         TEXT NOT NULL DEFAULT '',
        stage            TEXT NOT NULL DEFAULT '',
        gender           TEXT NOT NULL DEFAULT '',
        comment_public   TEXT NOT NULL DEFAULT '',
        comment_private  TEXT NOT NULL DEFAULT '',
        count            INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_act_obs_session ON activity_observations(session_id)',
    );
  }

  Future<void> close() async {
    await _taxaDb?.close();
    await _appDb?.close();
    _taxaDb = null;
    _appDb = null;
  }
}
