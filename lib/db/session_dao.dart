import 'package:sqflite/sqflite.dart';

import '../models/activity_observation.dart';
import '../models/folder.dart';
import '../models/observation.dart';
import '../models/session.dart';
import '../models/site.dart';
import 'app_database.dart';

/// Data access for user-created folders, sites, sessions, and observations.
class SessionDao {
  SessionDao._();
  static final SessionDao instance = SessionDao._();

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  /// Returns root folders (no parent) when [parentFolderId] is not provided,
  /// or sub-folders of [parentFolderId].
  Future<List<Folder>> getFolders({int? parentFolderId, bool rootOnly = false}) async {
    final db = await AppDatabase.instance.appDb;
    if (rootOnly) {
      final rows = await db.query('folders',
          where: 'parent_folder_id IS NULL', orderBy: 'created_at ASC');
      return rows.map(Folder.fromMap).toList();
    }
    if (parentFolderId != null) {
      final rows = await db.query('folders',
          where: 'parent_folder_id = ?',
          whereArgs: [parentFolderId],
          orderBy: 'created_at ASC');
      return rows.map(Folder.fromMap).toList();
    }
    final rows = await db.query('folders', orderBy: 'created_at ASC');
    return rows.map(Folder.fromMap).toList();
  }

  Future<void> moveFolder(int folderId, int? newParentFolderId) async {
    final db = await AppDatabase.instance.appDb;
    await db.update(
      'folders',
      {'parent_folder_id': newParentFolderId},
      where: 'id = ?',
      whereArgs: [folderId],
    );
  }

  /// Returns all descendant folder ids of [folderId] (to prevent circular moves).
  Future<Set<int>> getDescendantFolderIds(int folderId) async {
    final db = await AppDatabase.instance.appDb;
    final all = await db.query('folders');
    final allFolders = all.map(Folder.fromMap).toList();
    final result = <int>{};
    void collect(int id) {
      for (final f in allFolders) {
        if (f.parentFolderId == id && f.id != null) {
          result.add(f.id!);
          collect(f.id!);
        }
      }
    }
    collect(folderId);
    return result;
  }

  Future<Folder> insertFolder(Folder folder) async {
    final db = await AppDatabase.instance.appDb;
    final id = await db.insert('folders', folder.toMap());
    return folder.copyWith(id: id);
  }

  Future<void> updateFolder(Folder folder) async {
    final db = await AppDatabase.instance.appDb;
    await db.update('folders', folder.toMap(), where: 'id = ?', whereArgs: [folder.id]);
  }

  Future<void> deleteFolder(int folderId) async {
    final db = await AppDatabase.instance.appDb;
    await db.delete('folders', where: 'id = ?', whereArgs: [folderId]);
    // Sites lose their folder_id (SET NULL via FK), but are not deleted.
  }

  // ---------------------------------------------------------------------------
  // Sites
  // ---------------------------------------------------------------------------

  Future<List<Site>> getSites({int? folderId, bool loose = false}) async {
    final db = await AppDatabase.instance.appDb;
    if (loose) {
      // Lösa lokaler — sites with no folder
      final rows = await db.query('sites',
          where: 'folder_id IS NULL', orderBy: 'created_at ASC');
      return rows.map(Site.fromMap).toList();
    }
    if (folderId != null) {
      final rows = await db.query('sites',
          where: 'folder_id = ?', whereArgs: [folderId], orderBy: 'created_at ASC');
      return rows.map(Site.fromMap).toList();
    }
    final rows = await db.query('sites', orderBy: 'created_at ASC');
    return rows.map(Site.fromMap).toList();
  }

  Future<Site> insertSite(Site site) async {
    final db = await AppDatabase.instance.appDb;
    final id = await db.insert('sites', site.toMap());
    return site.copyWith(id: id);
  }

  Future<void> updateSite(Site site) async {
    final db = await AppDatabase.instance.appDb;
    await db.update('sites', site.toMap(), where: 'id = ?', whereArgs: [site.id]);
  }

  Future<void> deleteSite(int siteId) async {
    final db = await AppDatabase.instance.appDb;
    await db.delete('sites', where: 'id = ?', whereArgs: [siteId]);
  }

  // ---------------------------------------------------------------------------
  // Sessions
  // ---------------------------------------------------------------------------

  Future<List<Session>> getSessions({int? siteId, bool loose = false}) async {
    final db = await AppDatabase.instance.appDb;
    if (loose) {
      final rows = await db.query('sessions',
          where: 'site_id IS NULL AND is_template = 0',
          orderBy: 'date DESC');
      return rows.map(Session.fromMap).toList();
    }
    if (siteId != null) {
      final rows = await db.query('sessions',
          where: 'site_id = ? AND is_template = 0',
          whereArgs: [siteId],
          orderBy: 'date DESC');
      return rows.map(Session.fromMap).toList();
    }
    final rows = await db.query('sessions',
        where: 'is_template = 0', orderBy: 'date DESC');
    return rows.map(Session.fromMap).toList();
  }

  Future<Session?> getTemplate(int siteId) async {
    final db = await AppDatabase.instance.appDb;
    final rows = await db.query('sessions',
        where: 'site_id = ? AND is_template = 1',
        whereArgs: [siteId],
        limit: 1);
    if (rows.isEmpty) return null;
    return Session.fromMap(rows.first);
  }

  Future<Session> insertSession(Session session) async {
    final db = await AppDatabase.instance.appDb;
    final id = await db.insert('sessions', session.toMap());
    return session.copyWith(id: id);
  }

  Future<void> updateSession(Session session) async {
    final db = await AppDatabase.instance.appDb;
    await db.update('sessions', session.toMap(),
        where: 'id = ?', whereArgs: [session.id]);
  }

  Future<void> deleteSession(int sessionId) async {
    final db = await AppDatabase.instance.appDb;
    await db.delete('sessions', where: 'id = ?', whereArgs: [sessionId]);
    // Observations deleted via ON DELETE CASCADE.
  }

  // ---------------------------------------------------------------------------
  // Observations
  // ---------------------------------------------------------------------------

  Future<List<Observation>> getObservations(int sessionId) async {
    final db = await AppDatabase.instance.appDb;
    final rows = await db.query('observations',
        where: 'session_id = ?', whereArgs: [sessionId]);
    return rows.map(Observation.fromMap).toList();
  }

  /// Upsert: inserts or replaces an observation row.
  Future<Observation> upsertObservation(Observation obs) async {
    final db = await AppDatabase.instance.appDb;
    final id = await db.insert(
      'observations',
      obs.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return obs.copyWith(id: id);
  }

  Future<void> deleteObservation(int observationId) async {
    final db = await AppDatabase.instance.appDb;
    await db.delete('observations', where: 'id = ?', whereArgs: [observationId]);
  }

  // ---------------------------------------------------------------------------
  // Move helpers
  // ---------------------------------------------------------------------------

  Future<void> moveSession(int sessionId, int? newSiteId) async {
    final db = await AppDatabase.instance.appDb;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.update(
      'sessions',
      {'site_id': newSiteId, 'updated_at': now},
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  Future<void> moveSite(int siteId, int? newFolderId) async {
    final db = await AppDatabase.instance.appDb;
    await db.update(
      'sites',
      {'folder_id': newFolderId},
      where: 'id = ?',
      whereArgs: [siteId],
    );
  }

  // ---------------------------------------------------------------------------
  // Site summaries
  // ---------------------------------------------------------------------------

  /// Returns a summary for the given site: last visit date and total unique
  /// species count across all sessions at the site.
  Future<SiteSummary> getSiteSummary(int siteId) async {
    final db = await AppDatabase.instance.appDb;
    final lastRow = await db.query('sessions',
        where: 'site_id = ? AND is_template = 0',
        whereArgs: [siteId],
        orderBy: 'date DESC',
        limit: 1);
    DateTime? lastVisit;
    if (lastRow.isNotEmpty) {
      lastVisit = DateTime.fromMillisecondsSinceEpoch(lastRow.first['date'] as int);
    }
    final countResult = await db.rawQuery('''
      SELECT COUNT(DISTINCT o.taxon_id) AS cnt
      FROM observations o
      JOIN sessions s ON s.id = o.session_id
      WHERE s.site_id = ? AND s.is_template = 0 AND o.count > 0
    ''', [siteId]);
    final speciesCount = (countResult.first['cnt'] as int?) ?? 0;
    return SiteSummary(lastVisit: lastVisit, speciesCount: speciesCount);
  }

  // ---------------------------------------------------------------------------
  // Activity observations
  // ---------------------------------------------------------------------------

  /// Returns all activity sub-records for a session, keyed by taxon_id.
  Future<Map<int, List<ActivityObservation>>> getActivityObservations(
      int sessionId) async {
    final db = await AppDatabase.instance.appDb;
    final rows = await db.query(
      'activity_observations',
      where: 'session_id = ?',
      whereArgs: [sessionId],
    );
    final result = <int, List<ActivityObservation>>{};
    for (final row in rows) {
      final obs = ActivityObservation.fromMap(row);
      result.putIfAbsent(obs.taxonId, () => []).add(obs);
    }
    return result;
  }

  Future<ActivityObservation> upsertActivityObservation(
      ActivityObservation obs) async {
    final db = await AppDatabase.instance.appDb;
    final id = await db.insert(
      'activity_observations',
      obs.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return obs.copyWith(id: id);
  }

  /// Updates activity/stage/gender/comment fields on an existing sub-row.
  /// Does not merge with other rows, even if attributes end up identical —
  /// the user chose to create separate sub-rows and we keep them distinct.
  Future<ActivityObservation> setSubRowProperties(
    ActivityObservation ao, {
    String? activity,
    String? stage,
    String? gender,
    String? commentPublic,
    String? commentPrivate,
  }) async {
    final db = await AppDatabase.instance.appDb;
    final updated = ao.copyWith(
      activity: activity ?? ao.activity,
      stage: stage ?? ao.stage,
      gender: gender ?? ao.gender,
      commentPublic: commentPublic ?? ao.commentPublic,
      commentPrivate: commentPrivate ?? ao.commentPrivate,
    );
    await db.update('activity_observations', updated.toMap(),
        where: 'id = ?', whereArgs: [ao.id]);
    return updated;
  }

  Future<void> deleteActivityObservation(int id) async {
    final db = await AppDatabase.instance.appDb;
    await db.delete('activity_observations', where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------------------------------
  // Template helpers
  // ---------------------------------------------------------------------------

  /// Creates a new session under [site] using [template] as a blueprint.
  /// All observation counts and activity counts are reset to 0.
  /// Species rows (pinned) and activity sub-rows are copied.
  Future<Session> createSessionFromTemplate({
    required Session template,
    required String name,
    required Site site,
  }) async {
    final db = await AppDatabase.instance.appDb;
    final now = DateTime.now();

    // Fetch template observations and activity observations.
    final observations = await getObservations(template.id!);

    late Session newSession;

    await db.transaction((txn) async {
      final sessionId = await txn.insert('sessions', {
        'site_id': site.id,
        'name': name,
        'date': now.millisecondsSinceEpoch,
        'sweref99_northing': site.sweref99Northing,
        'sweref99_easting': site.sweref99Easting,
        'radius_m': site.radiusMeters,
        'wgs84_lat': site.wgs84Lat,
        'wgs84_lon': site.wgs84Lon,
        'is_template': 0,
        'created_at': now.millisecondsSinceEpoch,
        'updated_at': now.millisecondsSinceEpoch,
      });

      for (final obs in observations.where((o) => o.isPinned)) {
        await txn.insert('observations', {
          'session_id': sessionId,
          'taxon_id': obs.taxonId,
          'count': 0,
          'is_pinned': 1,
        });
        // Activity sub-rows are intentionally not copied — a new session
        // starts clean with only the pinned species list.
      }

      newSession = Session(
        id: sessionId,
        siteId: site.id,
        name: name,
        date: now,
        sweref99Northing: site.sweref99Northing,
        sweref99Easting: site.sweref99Easting,
        radiusMeters: site.radiusMeters,
        wgs84Lat: site.wgs84Lat,
        wgs84Lon: site.wgs84Lon,
        createdAt: now,
        updatedAt: now,
      );
    });

    return newSession;
  }

  /// Saves [source] as the template for its site, replacing any existing one.
  /// Copies pinned taxon IDs with count = 0.
  Future<void> saveAsTemplate(Session source, List<Observation> observations) async {
    final db = await AppDatabase.instance.appDb;
    if (source.siteId == null) return;

    await db.transaction((txn) async {
      // Delete old template for this site.
      final existing = await txn.query('sessions',
          where: 'site_id = ? AND is_template = 1',
          whereArgs: [source.siteId]);
      for (final row in existing) {
        await txn.delete('sessions', where: 'id = ?', whereArgs: [row['id']]);
      }

      // Insert new template session.
      final now = DateTime.now().millisecondsSinceEpoch;
      final templateId = await txn.insert('sessions', {
        'site_id': source.siteId,
        'name': source.name,
        'date': now,
        'region': source.region,
        'sweref99_northing': source.sweref99Northing,
        'sweref99_easting': source.sweref99Easting,
        'radius_m': source.radiusMeters,
        'is_template': 1,
        'created_at': now,
        'updated_at': now,
      });

      // Copy pinned observations with count = 0.
      for (final obs in observations.where((o) => o.isPinned)) {
        await txn.insert('observations', {
          'session_id': templateId,
          'taxon_id': obs.taxonId,
          'count': 0,
          'is_pinned': 1,
        });
      }
    });
  }
}

class SiteSummary {
  final DateTime? lastVisit;
  final int speciesCount;
  const SiteSummary({this.lastVisit, this.speciesCount = 0});
}

/// A session with its site and the chain of folders leading to it.
/// [breadcrumbFolders] is ordered root → leaf.
class SessionWithContext {
  final Session session;
  final Site? site;
  final List<Folder> breadcrumbFolders;
  const SessionWithContext({
    required this.session,
    this.site,
    this.breadcrumbFolders = const [],
  });
}

extension SessionDateView on SessionDao {
  /// Returns every non-template session ordered by date DESC, with its
  /// site and full folder breadcrumb resolved in a single batch of queries.
  Future<List<SessionWithContext>> getAllSessionsForDateView() async {
    final db = await AppDatabase.instance.appDb;
    final sessionRows = await db.query('sessions',
        where: 'is_template = 0', orderBy: 'date DESC');
    final sessions = sessionRows.map(Session.fromMap).toList();
    if (sessions.isEmpty) return [];

    final siteIds = sessions
        .map((s) => s.siteId)
        .whereType<int>()
        .toSet()
        .toList();
    final sitesById = <int, Site>{};
    if (siteIds.isNotEmpty) {
      final placeholders = siteIds.map((_) => '?').join(', ');
      final siteRows = await db.rawQuery(
          'SELECT * FROM sites WHERE id IN ($placeholders)', siteIds);
      for (final row in siteRows.map(Site.fromMap)) {
        if (row.id != null) sitesById[row.id!] = row;
      }
    }

    final folderRows = await db.query('folders');
    final foldersById = <int, Folder>{
      for (final row in folderRows.map(Folder.fromMap))
        if (row.id != null) row.id!: row,
    };

    return sessions.map((session) {
      final site = session.siteId != null ? sitesById[session.siteId] : null;
      final crumbs = <Folder>[];
      int? currentId = site?.folderId;
      while (currentId != null) {
        final folder = foldersById[currentId];
        if (folder == null) break;
        crumbs.insert(0, folder);
        currentId = folder.parentFolderId;
      }
      return SessionWithContext(
          session: session, site: site, breadcrumbFolders: crumbs);
    }).toList();
  }
}
