import 'package:flutter/foundation.dart';

import '../db/session_dao.dart';
import '../models/folder.dart';
import '../models/session.dart';
import '../models/site.dart';

/// Manages the data visible on the home (Listor) screen:
/// folders, loose sites (Lösa lokaler), and loose sessions (Lösa listor).
class HomeProvider extends ChangeNotifier {
  List<Folder> _folders = [];
  List<Site> _looseSites = [];
  List<Session> _looseSessions = [];
  bool _loading = false;

  List<Folder> get folders => List.unmodifiable(_folders);
  List<Site> get looseSites => List.unmodifiable(_looseSites);
  List<Session> get looseSessions => List.unmodifiable(_looseSessions);
  bool get loading => _loading;

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    final results = await Future.wait([
      SessionDao.instance.getFolders(rootOnly: true),
      SessionDao.instance.getSites(loose: true),
      SessionDao.instance.getSessions(loose: true),
    ]);
    _folders = results[0] as List<Folder>;
    _looseSites = results[1] as List<Site>;
    _looseSessions = results[2] as List<Session>;
    _loading = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  Future<Folder> createFolder(String name) async {
    final folder = await SessionDao.instance.insertFolder(
      Folder(name: name, createdAt: DateTime.now()),
    );
    _folders = [..._folders, folder];
    notifyListeners();
    return folder;
  }

  Future<void> renameFolder(Folder folder, String name) async {
    final updated = folder.copyWith(name: name);
    await SessionDao.instance.updateFolder(updated);
    _folders = [for (final f in _folders) f.id == folder.id ? updated : f];
    notifyListeners();
  }

  Future<void> deleteFolder(int folderId) async {
    await SessionDao.instance.deleteFolder(folderId);
    _folders = _folders.where((f) => f.id != folderId).toList();
    // Reload loose sites — some may have been orphaned from the deleted folder.
    _looseSites = await SessionDao.instance.getSites(loose: true);
    notifyListeners();
  }

  Future<Folder> createSubFolder(int parentFolderId, String name) async {
    return SessionDao.instance.insertFolder(
      Folder(name: name, parentFolderId: parentFolderId, createdAt: DateTime.now()),
    );
  }

  Future<void> moveFolder(Folder folder, int? newParentFolderId) async {
    await SessionDao.instance.moveFolder(folder.id!, newParentFolderId);
    // Reload root folders — moved folder may have left or joined the root list.
    _folders = await SessionDao.instance.getFolders(rootOnly: true);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Loose sites (Lösa lokaler)
  // ---------------------------------------------------------------------------

  Future<Site> createLooseSite(String name) async {
    final site = await SessionDao.instance.insertSite(
      Site(name: name, createdAt: DateTime.now()),
    );
    _looseSites = [..._looseSites, site];
    notifyListeners();
    return site;
  }

  Future<void> deleteLooseSite(int siteId) async {
    await SessionDao.instance.deleteSite(siteId);
    _looseSites = _looseSites.where((s) => s.id != siteId).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Loose sessions (Lösa listor)
  // ---------------------------------------------------------------------------

  Future<Session> createLooseSession(String name) async {
    final now = DateTime.now();
    final session = await SessionDao.instance.insertSession(
      Session(name: name, date: now, createdAt: now, updatedAt: now),
    );
    _looseSessions = [..._looseSessions, session];
    notifyListeners();
    return session;
  }

  Future<void> deleteLooseSession(int sessionId) async {
    await SessionDao.instance.deleteSession(sessionId);
    _looseSessions = _looseSessions.where((s) => s.id != sessionId).toList();
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Move helpers
  // ---------------------------------------------------------------------------

  /// All folders — used by move pickers in child screens.
  Future<List<Folder>> getAllFolders() => SessionDao.instance.getFolders();

  /// All sites — used by move pickers in child screens.
  Future<List<Site>> getAllSites() => SessionDao.instance.getSites();

  /// Moves [session] to [newSiteId] (null = loose lista).
  Future<void> moveSession(Session session, int? newSiteId) async {
    await SessionDao.instance.moveSession(session.id!, newSiteId);
    // Refresh loose sessions list.
    _looseSessions = await SessionDao.instance.getSessions(loose: true);
    notifyListeners();
  }

  /// Moves [site] to [newFolderId] (null = lösa lokaler).
  Future<void> moveSite(Site site, int? newFolderId) async {
    await SessionDao.instance.moveSite(site.id!, newFolderId);
    // Refresh loose sites list.
    _looseSites = await SessionDao.instance.getSites(loose: true);
    notifyListeners();
  }
}
