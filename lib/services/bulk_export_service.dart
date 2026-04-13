import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../db/session_dao.dart';
import '../db/taxon_dao.dart';
import '../models/folder.dart';
import '../models/session.dart';
import '../models/site.dart';
import 'export_service.dart';

/// Builds zip files containing one CSV per session — used for per-Mapp,
/// per-Lokal, and full-backup exports (W4).
///
/// Zip layout mirrors the app's folder tree:
///   MappName/
///     LokalName/
///       BesökName.csv
class BulkExportService {
  BulkExportService._();
  static final BulkExportService instance = BulkExportService._();

  static final _dateFmt = DateFormat('yyyyMMdd');

  // ─── public API ─────────────────────────────────────────────────────────────

  /// Exports all sessions in [folder] (and sub-folders / sites) as a zip.
  /// Returns the path of the created temporary zip file.
  /// Throws if no non-empty sessions are found.
  Future<String> exportFolder(Folder folder) async {
    final archive = Archive();
    final folderSafe = ExportService.sanitizeFilename(folder.name);
    await _addFolderToArchive(
      archive,
      folder,
      zipParentPath: folderSafe,
      csvFolderName: folder.name,
    );
    return _writeZip(archive, '${_dateFmt.format(DateTime.now())}_$folderSafe');
  }

  /// Exports all sessions in [site] as a zip.
  /// [folderName] is the site's parent folder name, if any.
  Future<String> exportSite(Site site, {String? folderName}) async {
    final archive = Archive();
    final siteSafe = ExportService.sanitizeFilename(site.name);
    final zipPath = folderName != null
        ? '${ExportService.sanitizeFilename(folderName)}/$siteSafe'
        : siteSafe;
    await _addSiteToArchive(
      archive,
      site,
      zipPath: zipPath,
      csvFolderName: folderName,
    );
    final label = folderName != null
        ? '${_dateFmt.format(DateTime.now())}_${ExportService.sanitizeFilename(folderName)}_$siteSafe'
        : '${_dateFmt.format(DateTime.now())}_$siteSafe';
    return _writeZip(archive, label);
  }

  /// Exports every session in the database as a full backup zip.
  Future<String> exportAll() async {
    final archive = Archive();

    // Root folders with their subtrees
    final rootFolders = await SessionDao.instance.getFolders(rootOnly: true);
    for (final folder in rootFolders) {
      final folderSafe = ExportService.sanitizeFilename(folder.name);
      await _addFolderToArchive(
        archive,
        folder,
        zipParentPath: folderSafe,
        csvFolderName: folder.name,
      );
    }

    // Loose sites (folderId == null)
    final looseSites = await SessionDao.instance.getSites(loose: true);
    for (final site in looseSites) {
      final siteSafe = ExportService.sanitizeFilename(site.name);
      await _addSiteToArchive(
        archive,
        site,
        zipPath: 'Lösa lokaler/$siteSafe',
        csvFolderName: null,
      );
    }

    // Loose sessions (siteId == null)
    final looseSessions = await SessionDao.instance.getSessions(loose: true);
    for (final session in looseSessions) {
      await _addSessionEntry(
        archive,
        session,
        zipDir: 'Lösa besök',
        csvSiteName: null,
        csvFolderName: null,
      );
    }

    return _writeZip(
      archive,
      '${_dateFmt.format(DateTime.now())}_BirdTally_Backup',
    );
  }

  // ─── internals ──────────────────────────────────────────────────────────────

  Future<void> _addFolderToArchive(
    Archive archive,
    Folder folder, {
    required String zipParentPath,
    required String? csvFolderName,
  }) async {
    // Sites directly in this folder
    final sites = await SessionDao.instance.getSites(folderId: folder.id);
    for (final site in sites) {
      final siteSafe = ExportService.sanitizeFilename(site.name);
      await _addSiteToArchive(
        archive,
        site,
        zipPath: '$zipParentPath/$siteSafe',
        csvFolderName: csvFolderName,
      );
    }

    // Sub-folders — each sub-folder becomes its own Artportalen Huvudlokal.
    final subs = await SessionDao.instance.getFolders(parentFolderId: folder.id);
    for (final sub in subs) {
      final subSafe = ExportService.sanitizeFilename(sub.name);
      await _addFolderToArchive(
        archive,
        sub,
        zipParentPath: '$zipParentPath/$subSafe',
        csvFolderName: sub.name,
      );
    }
  }

  Future<void> _addSiteToArchive(
    Archive archive,
    Site site, {
    required String zipPath,
    required String? csvFolderName,
  }) async {
    final sessions = await SessionDao.instance.getSessions(siteId: site.id);
    for (final session in sessions) {
      await _addSessionEntry(
        archive,
        session,
        zipDir: zipPath,
        csvSiteName: site.name,
        csvFolderName: csvFolderName,
      );
    }
  }

  Future<void> _addSessionEntry(
    Archive archive,
    Session session, {
    required String zipDir,
    required String? csvSiteName,
    required String? csvFolderName,
  }) async {
    final observations =
        await SessionDao.instance.getObservations(session.id!);
    final actObs =
        await SessionDao.instance.getActivityObservations(session.id!);

    final nonZero = observations
        .where((o) =>
            o.count > 0 ||
            (actObs[o.taxonId]?.any((a) => a.count > 0) ?? false))
        .toList();

    if (nonZero.isEmpty) return; // skip sessions with no observations

    final taxonIds = nonZero.map((o) => o.taxonId).toList();
    final taxaList = await TaxonDao.instance.getByIds(taxonIds);
    final taxa = {for (final t in taxaList) t.taxonId: t};

    final csv = ExportService.instance.buildCsv(
      session: session,
      observations: nonZero,
      taxa: taxa,
      activityObservations: actObs,
      siteName: csvSiteName,
      folderName: csvFolderName,
    );

    final sessionSafe = ExportService.sanitizeFilename(session.name);
    final bytes = utf8.encode(csv);
    archive.addFile(
      ArchiveFile('$zipDir/$sessionSafe.csv', bytes.length, bytes),
    );
  }

  /// Encodes [archive] as a zip and writes it to the temp directory.
  /// Throws a user-visible message if the archive is empty.
  Future<String> _writeZip(Archive archive, String zipName) async {
    if (archive.isEmpty) {
      throw Exception('Inga observationer att exportera.');
    }
    final dir = await getTemporaryDirectory();
    final zipPath = '${dir.path}/$zipName.zip';
    final bytes = ZipEncoder().encode(archive);
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Kunde inte skapa zip-filen.');
    }
    await File(zipPath).writeAsBytes(bytes);
    return zipPath;
  }
}
