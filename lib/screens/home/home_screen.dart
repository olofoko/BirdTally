import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/app_database.dart';
import '../../db/session_dao.dart';
import '../../db/taxon_dao.dart';
import '../../models/folder.dart';
import '../../models/observation.dart';
import '../../models/session.dart';
import '../../models/site.dart';
import '../../providers/home_provider.dart';
import '../../services/app_settings.dart';
import '../../services/backup_service.dart';
import '../../services/bulk_export_service.dart';
import '../../services/export_service.dart';
import '../../widgets/location_dialog.dart';
import '../../widgets/move_dialog.dart';
import '../session/tally_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _HomeViewMode { tree, date }

class _HomeScreenState extends State<HomeScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy', 'sv_SE');
  static final _timeFmt = DateFormat('HH:mm', 'sv_SE');
  static final _dayHeaderFmt =
      DateFormat("EEEE 'den' d MMMM yyyy", 'sv_SE');

  // Lazy-loaded children, keyed by parent id.
  final Map<int, List<Folder>> _subFoldersByFolder = {};
  final Map<int, List<Site>> _sitesByFolder = {};
  final Map<int, List<Session>> _sessionsBySite = {};
  final Map<int, SiteSummary> _siteSummaries = {};
  final Set<String> _loadingNodes = {};

  /// Returns the center of the screen as a Rect — required by iOS share sheet.
  Rect get _shareOrigin {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return Rect.zero;
    final size = box.size;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  _HomeViewMode _viewMode = _HomeViewMode.tree;
  List<SessionWithContext>? _dateViewData;
  bool _loadingDateView = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeProvider>().load();
    });
  }

  // ---------------------------------------------------------------------------
  // Lazy loading
  // ---------------------------------------------------------------------------

  Future<void> _loadFolderChildren(int folderId) async {
    if (_loadingNodes.contains('f$folderId')) return;
    setState(() => _loadingNodes.add('f$folderId'));
    final results = await Future.wait([
      SessionDao.instance.getFolders(parentFolderId: folderId),
      SessionDao.instance.getSites(folderId: folderId),
    ]);
    if (!mounted) return;
    final sites = results[1] as List<Site>;
    // Load summaries for all sites in parallel.
    await _loadSiteSummaries(sites);
    if (!mounted) return;
    setState(() {
      _subFoldersByFolder[folderId] = results[0] as List<Folder>;
      _sitesByFolder[folderId] = sites;
      _loadingNodes.remove('f$folderId');
    });
  }

  Future<void> _reloadFolderChildren(int folderId) async {
    _subFoldersByFolder.remove(folderId);
    _sitesByFolder.remove(folderId);
    await _loadFolderChildren(folderId);
  }

  Future<void> _loadSiteChildren(int siteId) async {
    if (_loadingNodes.contains('s$siteId')) return;
    setState(() => _loadingNodes.add('s$siteId'));
    final sessions = await SessionDao.instance.getSessions(siteId: siteId);
    if (!mounted) return;
    setState(() {
      _sessionsBySite[siteId] = sessions;
      _loadingNodes.remove('s$siteId');
    });
  }

  Future<void> _reloadSiteChildren(int siteId) async {
    _sessionsBySite.remove(siteId);
    await _loadSiteChildren(siteId);
  }

  Future<void> _loadSiteSummaries(List<Site> sites) async {
    final futures = sites
        .where((s) => s.id != null && !_siteSummaries.containsKey(s.id))
        .map((s) async {
      final summary = await SessionDao.instance.getSiteSummary(s.id!);
      _siteSummaries[s.id!] = summary;
    });
    await Future.wait(futures);
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Besök'),
        actions: [
          IconButton(
            icon: Icon(_viewMode == _HomeViewMode.tree
                ? Icons.calendar_month_outlined
                : Icons.account_tree_outlined),
            tooltip: _viewMode == _HomeViewMode.tree
                ? 'Visa per datum'
                : 'Visa mappträd',
            onPressed: _toggleViewMode,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Inställningar',
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : (_viewMode == _HomeViewMode.tree
              ? _buildBody(provider)
              : _buildDateView()),
    );
  }

  Widget _inlineFab() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: FloatingActionButton(
          onPressed: () => _showAddSheet(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _toggleViewMode() {
    setState(() {
      _viewMode = _viewMode == _HomeViewMode.tree
          ? _HomeViewMode.date
          : _HomeViewMode.tree;
    });
    if (_viewMode == _HomeViewMode.date) {
      _loadDateView();
    }
  }

  Future<void> _loadDateView({bool force = false}) async {
    if (_loadingDateView) return;
    if (!force && _dateViewData != null) return;
    setState(() => _loadingDateView = true);
    final data = await SessionDao.instance.getAllSessionsForDateView();
    if (!mounted) return;
    setState(() {
      _dateViewData = data;
      _loadingDateView = false;
    });
  }

  Widget _buildDateView() {
    if (_loadingDateView || _dateViewData == null) {
      if (!_loadingDateView) _loadDateView();
      return const Center(child: CircularProgressIndicator());
    }
    final entries = _dateViewData!;
    if (entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Inga besök än.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                onPressed: () => _showAddSheet(context),
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      );
    }

    // Group by local date (YYYY-MM-DD).
    final groups = <DateTime, List<SessionWithContext>>{};
    for (final e in entries) {
      final d = e.session.date;
      final key = DateTime(d.year, d.month, d.day);
      groups.putIfAbsent(key, () => []).add(e);
    }
    final sortedKeys = groups.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return ListView(
      children: [
        for (final dayKey in sortedKeys) ...[
          _buildDayHeader(dayKey, groups[dayKey]!),
          for (final e in groups[dayKey]!) _buildDateSessionTile(e),
          const SizedBox(height: 8),
        ],
        _inlineFab(),
      ],
    );
  }

  Widget _buildDayHeader(
      DateTime day, List<SessionWithContext> sessionsThatDay) {
    final label = _dayHeaderFmt.format(day);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 4, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Alternativ för dagen',
            onSelected: (v) {
              if (v == 'exportDay') {
                _exportDay(day, sessionsThatDay);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'exportDay',
                child: Text('Exportera dagens besök (kombinerad CSV)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateSessionTile(SessionWithContext e) {
    final session = e.session;
    final startStr = _timeFmt.format(session.date);
    final endStr = session.endTime != null
        ? ' – ${_timeFmt.format(session.endTime!)}'
        : '';
    final crumbs = <String>[
      ...e.breadcrumbFolders.map((f) => f.name),
      if (e.site != null) e.site!.name,
    ];
    final breadcrumb = crumbs.isEmpty ? 'Lösa besök' : crumbs.join(' › ');

    return ListTile(
      leading: const Icon(Icons.list_alt_outlined),
      title: Text(session.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$startStr$endStr'),
          Text(
            breadcrumb,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (v) => _handleSessionMenu(v, session, e.site),
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'export', child: Text('Exportera')),
          PopupMenuItem(value: 'rename', child: Text('Ändra namn')),
          PopupMenuItem(value: 'useAsTemplate', child: Text('Använd som mall')),
          PopupMenuItem(value: 'move', child: Text('Flytta')),
          PopupMenuItem(value: 'delete', child: Text('Ta bort')),
        ],
      ),
      onTap: () => _openSession(session, e.site),
    );
  }

  // ---------------------------------------------------------------------------
  // Combined CSV export helpers
  // ---------------------------------------------------------------------------

  /// Loads one session's observations and builds a [CombinedCsvEntry].
  /// Returns null if the session has no non-zero observations.
  Future<CombinedCsvEntry?> _buildCsvEntry(
      Session session, {String? siteName, String? folderName}) async {
    final observations =
        await SessionDao.instance.getObservations(session.id!);
    final actObs =
        await SessionDao.instance.getActivityObservations(session.id!);
    final nonZero = observations
        .where((o) =>
            o.count > 0 ||
            (actObs[o.taxonId]?.any((a) => a.count > 0) ?? false))
        .toList();
    if (nonZero.isEmpty) return null;
    final taxa = {
      for (final t in await TaxonDao.instance
          .getByIds(nonZero.map((o) => o.taxonId).toList()))
        t.taxonId: t,
    };
    return CombinedCsvEntry(
      session: session,
      observations: nonZero,
      taxa: taxa,
      activityObservations: actObs,
      siteName: siteName,
      folderName: folderName,
    );
  }

  /// Recursively collects [CombinedCsvEntry] for every session under [folder].
  Future<void> _gatherFolderEntries(
      Folder folder, List<CombinedCsvEntry> out) async {
    final sites = await SessionDao.instance.getSites(folderId: folder.id);
    for (final site in sites) {
      final sessions = await SessionDao.instance.getSessions(siteId: site.id);
      for (final session in sessions) {
        final entry = await _buildCsvEntry(session,
            siteName: site.name, folderName: folder.name);
        if (entry != null) out.add(entry);
      }
    }
    final subs =
        await SessionDao.instance.getFolders(parentFolderId: folder.id);
    for (final sub in subs) {
      await _gatherFolderEntries(sub, out);
    }
  }

  Future<void> _exportDay(
      DateTime day, List<SessionWithContext> entries) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Förbereder export…'),
      duration: Duration(seconds: 30),
    ));
    try {
      final csvEntries = <CombinedCsvEntry>[];
      for (final e in entries) {
        final folderName = e.breadcrumbFolders.isNotEmpty
            ? e.breadcrumbFolders.last.name
            : null;
        final entry = await _buildCsvEntry(e.session,
            siteName: e.site?.name, folderName: folderName);
        if (entry != null) csvEntries.add(entry);
      }
      await _shareCombinedCsv(
        messenger,
        csvEntries,
        filename: 'BirdTally_${DateFormat('yyyy-MM-dd').format(day)}.csv',
        subject: 'BirdTally – ${DateFormat('yyyy-MM-dd').format(day)}',
      );
    } catch (err) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(err.toString())));
      }
    }
  }

  Future<void> _exportSiteCombined(Site site, Folder? parentFolder) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Förbereder export…'),
      duration: Duration(seconds: 30),
    ));
    try {
      final sessions = await SessionDao.instance.getSessions(siteId: site.id);
      final csvEntries = <CombinedCsvEntry>[];
      for (final session in sessions) {
        final entry = await _buildCsvEntry(session,
            siteName: site.name, folderName: parentFolder?.name);
        if (entry != null) csvEntries.add(entry);
      }
      final safe = ExportService.sanitizeFilename(site.name);
      await _shareCombinedCsv(
        messenger,
        csvEntries,
        filename: 'BirdTally_$safe.csv',
        subject: 'BirdTally – ${site.name}',
      );
    } catch (err) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(err.toString())));
      }
    }
  }

  Future<void> _exportFolderCombined(Folder folder) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Förbereder export…'),
      duration: Duration(seconds: 30),
    ));
    try {
      final csvEntries = <CombinedCsvEntry>[];
      await _gatherFolderEntries(folder, csvEntries);
      final safe = ExportService.sanitizeFilename(folder.name);
      await _shareCombinedCsv(
        messenger,
        csvEntries,
        filename: 'BirdTally_$safe.csv',
        subject: 'BirdTally – ${folder.name}',
      );
    } catch (err) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(err.toString())));
      }
    }
  }

  Future<void> _shareCombinedCsv(
    ScaffoldMessengerState messenger,
    List<CombinedCsvEntry> entries, {
    required String filename,
    required String subject,
  }) async {
    messenger.removeCurrentSnackBar();
    if (entries.isEmpty) {
      if (mounted) {
        messenger.showSnackBar(const SnackBar(
          content: Text('Inga besök med observationer att exportera.'),
        ));
      }
      return;
    }
    final csv = ExportService.instance.buildCombinedCsv(entries);
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(csv);
    if (mounted) {
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: subject,
        sharePositionOrigin: _shareOrigin,
      );
    }
  }

  Widget _buildBody(HomeProvider provider) {
    // Eagerly load summaries for loose sites visible on the home screen.
    if (provider.looseSites.isNotEmpty) {
      final missing = provider.looseSites
          .where((s) => s.id != null && !_siteSummaries.containsKey(s.id))
          .toList();
      if (missing.isNotEmpty) {
        _loadSiteSummaries(missing).then((_) {
          if (mounted) setState(() {});
        });
      }
    }

    final hasContent = provider.folders.isNotEmpty ||
        provider.looseSites.isNotEmpty ||
        provider.looseSessions.isNotEmpty;

    if (!hasContent) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tryck på + för att skapa\nen mapp, lokal eller besök.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                onPressed: () => _showAddSheet(context),
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      children: [
        if (provider.folders.isNotEmpty) ...[
          _sectionHeader('Mappar'),
          for (final folder in provider.folders) _buildFolderTile(folder, 0),
        ],
        if (provider.looseSites.isNotEmpty) ...[
          _sectionHeader('Lösa lokaler'),
          for (final site in provider.looseSites) _buildSiteTile(site, 0, null),
        ],
        if (provider.looseSessions.isNotEmpty) ...[
          _sectionHeader('Besök'),
          for (final session in provider.looseSessions)
            _buildSessionTile(session, 0, null),
        ],
        _inlineFab(),
      ],
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Tree nodes
  // ---------------------------------------------------------------------------

  Widget _buildFolderTile(Folder folder, int depth) {
    final id = folder.id!;
    final isLoading = _loadingNodes.contains('f$id');
    final subFolders = _subFoldersByFolder[id];
    final sites = _sitesByFolder[id];
    final hasLoadedChildren = subFolders != null && sites != null;

    return _IndentedTile(
      depth: depth,
      child: ExpansionTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(folder.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              onSelected: (v) => _handleFolderMenu(v, folder, depth),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'addSite', child: Text('Ny lokal')),
                PopupMenuItem(value: 'addSubFolder', child: Text('Ny undermapp')),
                PopupMenuItem(value: 'exportCombined', child: Text('Exportera mapp (kombinerad CSV)')),
                PopupMenuItem(value: 'export', child: Text('Exportera mapp (zip)')),
                PopupMenuItem(value: 'move', child: Text('Flytta')),
                PopupMenuItem(value: 'rename', child: Text('Byt namn')),
                PopupMenuItem(value: 'delete', child: Text('Ta bort')),
              ],
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        onExpansionChanged: (expanded) {
          if (expanded && !hasLoadedChildren) _loadFolderChildren(id);
        },
        children: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (hasLoadedChildren) ...[
            for (final sub in subFolders) _buildFolderTile(sub, depth + 1),
            for (final site in sites) _buildSiteTile(site, depth + 1, folder),
            if (subFolders.isEmpty && sites.isEmpty)
              _emptyHint(depth + 1, 'Tom mapp'),
          ],
        ],
      ),
    );
  }

  Widget _buildSiteTile(Site site, int depth, Folder? parentFolder) {
    final id = site.id!;
    final isLoading = _loadingNodes.contains('s$id');
    final sessions = _sessionsBySite[id];
    final hasLoadedChildren = sessions != null;
    final summary = _siteSummaries[id];

    String? subtitleText;
    if (summary != null) {
      final parts = <String>[];
      if (summary.lastVisit != null) {
        parts.add('Senast ${_dateFmt.format(summary.lastVisit!)}');
      }
      if (summary.speciesCount > 0) {
        parts.add('${summary.speciesCount} arter');
      }
      if (parts.isNotEmpty) subtitleText = parts.join(' · ');
    }

    return _IndentedTile(
      depth: depth,
      child: ExpansionTile(
        leading: Icon(
          Icons.place_outlined,
          color: site.hasLocation
              ? Theme.of(context).colorScheme.primary
              : null,
        ),
        title: Text(site.name),
        subtitle: subtitleText != null
            ? Text(
                subtitleText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              )
            : null,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              onSelected: (v) =>
                  _handleSiteMenu(v, site, parentFolder),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'addSession', child: Text('Nytt besök')),
                PopupMenuItem(value: 'exportCombined', child: Text('Exportera lokal (kombinerad CSV)')),
                PopupMenuItem(value: 'export', child: Text('Exportera lokal (zip)')),
                PopupMenuItem(value: 'rename', child: Text('Ändra namn')),
                PopupMenuItem(value: 'location', child: Text('Redigera plats')),
                PopupMenuItem(value: 'move', child: Text('Flytta')),
                PopupMenuItem(value: 'delete', child: Text('Ta bort')),
              ],
            ),
            const Icon(Icons.expand_more),
          ],
        ),
        onExpansionChanged: (expanded) {
          if (expanded && !hasLoadedChildren) _loadSiteChildren(id);
        },
        children: [
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (hasLoadedChildren) ...[
            for (final session in sessions)
              _buildSessionTile(session, depth + 1, site),
            if (sessions.isEmpty) _emptyHint(depth + 1, 'Inga besök'),
          ],
        ],
      ),
    );
  }

  Widget _buildSessionTile(Session session, int depth, Site? site) {
    final dateStr = _dateFmt.format(session.date);
    final timeStr = _timeFmt.format(session.date);
    final endStr =
        session.endTime != null ? '–${_timeFmt.format(session.endTime!)}' : '';

    return _IndentedTile(
      depth: depth,
      child: ListTile(
        leading: const Icon(Icons.list_alt_outlined),
        title: Text(session.name),
        subtitle: Text('$dateStr  $timeStr$endStr'),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => _handleSessionMenu(v, session, site),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'export', child: Text('Exportera')),
            PopupMenuItem(value: 'rename', child: Text('Ändra namn')),
            PopupMenuItem(value: 'useAsTemplate', child: Text('Använd som mall')),
            PopupMenuItem(value: 'move', child: Text('Flytta')),
            PopupMenuItem(value: 'delete', child: Text('Ta bort')),
          ],
        ),
        onTap: () => _openSession(session, site),
      ),
    );
  }

  Widget _emptyHint(int depth, String text) {
    return _IndentedTile(
      depth: depth,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Menu handlers
  // ---------------------------------------------------------------------------

  Future<void> _handleFolderMenu(
      String action, Folder folder, int depth) async {
    switch (action) {
      case 'addSite':
        await _createSiteInFolder(folder);
      case 'addSubFolder':
        await _createSubFolder(folder);
      case 'exportCombined':
        await _exportFolderCombined(folder);
      case 'export':
        await _exportFolder(folder);
      case 'move':
        final (folderMoved, newParentId) = await showMoveFolderDialog(context, folder);
        if (!mounted || !folderMoved) return;
        // Reload source parent's sub-folder list (removes the folder from there).
        if (folder.parentFolderId != null &&
            _subFoldersByFolder.containsKey(folder.parentFolderId)) {
          await _reloadFolderChildren(folder.parentFolderId!);
        }
        // Reload destination parent's sub-folder list (adds the folder there).
        if (newParentId != null && _subFoldersByFolder.containsKey(newParentId)) {
          await _reloadFolderChildren(newParentId);
        }
      case 'rename':
        await _renameFolder(folder);
      case 'delete':
        await _confirmDeleteFolder(folder);
    }
  }

  Future<void> _handleSiteMenu(
      String action, Site site, Folder? parentFolder) async {
    switch (action) {
      case 'addSession':
        await _createSessionInSite(site, parentFolder);
      case 'exportCombined':
        await _exportSiteCombined(site, parentFolder);
      case 'export':
        await _exportSite(site, parentFolder);
      case 'rename':
        await _renameSite(site, parentFolder);
      case 'location':
        await _editSiteLocation(site, parentFolder);
      case 'move':
        final (siteMoved, newFolderId) = await showMoveSiteDialog(context, site);
        if (!mounted || !siteMoved) return;
        // Reload source folder's site list (removes the site from there).
        if (parentFolder != null) await _reloadFolderChildren(parentFolder.id!);
        // Reload destination folder's site list (adds the site there).
        if (newFolderId != null && _sitesByFolder.containsKey(newFolderId)) {
          await _reloadFolderChildren(newFolderId);
        }
      case 'delete':
        await _confirmDeleteSite(site, parentFolder);
    }
  }

  Future<void> _handleSessionMenu(
      String action, Session session, Site? site) async {
    switch (action) {
      case 'export':
        await _exportSession(context, session, site);
      case 'rename':
        await _renameSession(session, site);
        _invalidateDateView();
      case 'useAsTemplate':
        await _createSessionFromTemplate(site, session);
        _invalidateDateView();
      case 'move':
        final (sessionMoved, newSiteId) = await showMoveSessionDialog(context, session);
        if (!mounted || !sessionMoved) return;
        // Reload source site's session list (removes the session from there).
        if (site != null) await _reloadSiteChildren(site.id!);
        // Reload destination site's session list (adds the session there).
        if (newSiteId != null && _sessionsBySite.containsKey(newSiteId)) {
          await _reloadSiteChildren(newSiteId);
        }
        _invalidateDateView();
      case 'delete':
        await _confirmDeleteSession(session, site);
        _invalidateDateView();
    }
  }

  Future<void> _createSessionFromTemplate(Site? site, Session template) async {
    final name = await _showNameDialog('Nytt besök', hint: 'Namn på besöket');
    if (name == null || !mounted) return;

    if (site != null) {
      final session = await SessionDao.instance.createSessionFromTemplate(
        template: template,
        name: name,
        site: site,
      );
      if (!mounted) return;
      final existing = _sessionsBySite[site.id!] ?? [];
      setState(() => _sessionsBySite[site.id!] = [session, ...existing]);
      _openSession(session, site);
    } else {
      // Loose session — copy pinned species rows only, no sub-rows.
      final observations = await SessionDao.instance.getObservations(template.id!);
      final now = DateTime.now();
      final session = await SessionDao.instance.insertSession(Session(
        name: name,
        date: now,
        createdAt: now,
        updatedAt: now,
      ));
      for (final obs in observations.where((o) => o.isPinned)) {
        await SessionDao.instance.upsertObservation(
          Observation(sessionId: session.id!, taxonId: obs.taxonId, count: 0, isPinned: true),
        );
      }
      if (!mounted) return;
      context.read<HomeProvider>().load();
      _openSession(session, null);
    }
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _openSession(Session session, Site? site) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TallyScreen(session: session)))
        .then((_) {
      // Invalidate summary so it refreshes with new data.
      if (site != null && mounted) {
        _siteSummaries.remove(site.id);
        _reloadSiteChildren(site.id!);
      }
      if (site == null && mounted) context.read<HomeProvider>().load();
      _invalidateDateView();
    });
  }

  void _invalidateDateView() {
    if (_viewMode == _HomeViewMode.date) {
      _loadDateView(force: true);
    } else {
      _dateViewData = null;
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD — folders
  // ---------------------------------------------------------------------------

  Future<void> _createSubFolder(Folder parent) async {
    final name = await _showNameDialog('Ny undermapp', hint: 'Namn på mappen');
    if (name == null || !mounted) return;
    await context.read<HomeProvider>().createSubFolder(parent.id!, name);
    await _reloadFolderChildren(parent.id!);
  }

  Future<void> _renameFolder(Folder folder) async {
    final name =
        await _showNameDialog('Byt namn', hint: 'Mappnamn', initial: folder.name);
    if (name == null || !mounted) return;
    await context.read<HomeProvider>().renameFolder(folder, name);
    // Root folders are in provider; sub-folders need parent reload.
    if (folder.parentFolderId != null) {
      await _reloadFolderChildren(folder.parentFolderId!);
    }
  }

  Future<void> _renameSite(Site site, Folder? parentFolder) async {
    final name = await _showNameDialog('Ändra namn',
        hint: 'Lokalnamn', initial: site.name);
    if (name == null || !mounted) return;
    if (parentFolder == null) {
      await context.read<HomeProvider>().renameSite(site, name);
    } else {
      await SessionDao.instance.updateSite(site.copyWith(name: name));
      await _reloadFolderChildren(parentFolder.id!);
    }
  }

  Future<void> _renameSession(Session session, Site? site) async {
    final name = await _showNameDialog('Ändra namn',
        hint: 'Namn på besöket', initial: session.name);
    if (name == null || !mounted) return;
    final updated =
        session.copyWith(name: name, updatedAt: DateTime.now());
    await SessionDao.instance.updateSession(updated);
    if (!mounted) return;
    if (site == null) {
      await context.read<HomeProvider>().renameLooseSession(session, name);
    } else {
      setState(() {
        final list = _sessionsBySite[site.id!] ?? [];
        _sessionsBySite[site.id!] = [
          for (final s in list) s.id == session.id ? updated : s
        ];
      });
    }
  }

  Future<void> _confirmDeleteFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort mapp?'),
        content: Text(
            'Tar bort "${folder.name}". Lokaler i mappen förblir som lösa lokaler.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ta bort')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await context.read<HomeProvider>().deleteFolder(folder.id!);
    if (folder.parentFolderId != null && mounted) {
      await _reloadFolderChildren(folder.parentFolderId!);
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD — sites
  // ---------------------------------------------------------------------------

  Future<void> _createLooseSite() async {
    final name = await _showNameDialog('Ny lokal', hint: 'Namn på lokalen');
    if (name == null || !mounted) return;
    var site = await context.read<HomeProvider>().createLooseSite(name);
    if (!mounted) return;
    final location = await showLocationDialog(context);
    if (location != null && mounted) {
      site = site.copyWith(
        sweref99Northing: location.northing,
        sweref99Easting: location.easting,
        radiusMeters: location.radiusMeters,
        wgs84Lat: location.wgs84Lat,
        wgs84Lon: location.wgs84Lon,
      );
      await SessionDao.instance.updateSite(site);
    }
    if (mounted) context.read<HomeProvider>().load();
  }

  Future<void> _createSiteInFolder(Folder folder) async {
    final name = await _showNameDialog('Ny lokal', hint: 'Namn på lokalen');
    if (name == null || !mounted) return;
    var site = await SessionDao.instance.insertSite(
      Site(folderId: folder.id, name: name, createdAt: DateTime.now()),
    );
    if (!mounted) return;
    final location = await showLocationDialog(context);
    if (location != null && mounted) {
      site = site.copyWith(
        sweref99Northing: location.northing,
        sweref99Easting: location.easting,
        radiusMeters: location.radiusMeters,
        wgs84Lat: location.wgs84Lat,
        wgs84Lon: location.wgs84Lon,
      );
      await SessionDao.instance.updateSite(site);
    }
    if (mounted) await _reloadFolderChildren(folder.id!);
  }

  Future<void> _editSiteLocation(Site site, Folder? parentFolder) async {
    final location = await showLocationDialog(context);
    if (location == null || !mounted) return;
    final updated = site.copyWith(
      sweref99Northing: location.northing,
      sweref99Easting: location.easting,
      radiusMeters: location.radiusMeters,
      wgs84Lat: location.wgs84Lat,
      wgs84Lon: location.wgs84Lon,
    );
    await SessionDao.instance.updateSite(updated);
    // Refresh the list so the location indicator updates.
    if (parentFolder != null && mounted) {
      await _reloadFolderChildren(parentFolder.id!);
    } else if (mounted) {
      context.read<HomeProvider>().load();
    }
  }

  Future<void> _confirmDeleteSite(Site site, Folder? parentFolder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort lokal?'),
        content: Text('Tar bort "${site.name}" och alla dess besök.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ta bort')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SessionDao.instance.deleteSite(site.id!);
    if (parentFolder != null && mounted) {
      await _reloadFolderChildren(parentFolder.id!);
    } else if (mounted) {
      context.read<HomeProvider>().load();
    }
  }

  // ---------------------------------------------------------------------------
  // CRUD — sessions
  // ---------------------------------------------------------------------------

  Future<void> _createLooseSession() async {
    final name = await _showNameDialog('Nytt besök', hint: 'Namn på besöket');
    if (name == null || !mounted) return;
    final session =
        await context.read<HomeProvider>().createLooseSession(name);
    if (!mounted) return;
    _openSession(session, null);
  }

  Future<void> _createSessionInSite(Site site, Folder? parentFolder) async {
    // Ask: blank or from template?
    final useTemplate = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Starta nytt tomt besök'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Använd tidigare besök som mall'),
              onTap: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      ),
    );
    if (useTemplate == null || !mounted) return;

    Session? templateSession;
    if (useTemplate) {
      final sessions = _sessionsBySite[site.id!] ??
          await SessionDao.instance.getSessions(siteId: site.id);
      if (!mounted) return;
      if (sessions.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Inga tidigare besök att använda som mall.')),
        );
        return;
      }
      templateSession = await _pickTemplateSession(sessions);
      if (templateSession == null || !mounted) return;
    }

    final name = await _showNameDialog('Nytt besök', hint: 'Namn på besöket');
    if (name == null || !mounted) return;

    final Session session;
    if (templateSession != null) {
      session = await SessionDao.instance.createSessionFromTemplate(
        template: templateSession,
        name: name,
        site: site,
      );
    } else {
      final now = DateTime.now();
      session = await SessionDao.instance.insertSession(Session(
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
      ));
    }
    if (!mounted) return;
    final existing = _sessionsBySite[site.id!] ?? [];
    setState(() => _sessionsBySite[site.id!] = [session, ...existing]);
    _openSession(session, site);
  }

  Future<Session?> _pickTemplateSession(List<Session> sessions) {
    return showModalBottomSheet<Session>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                'Välj mall',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: sessions.length,
                itemBuilder: (_, i) {
                  final s = sessions[i];
                  final dateStr = _dateFmt.format(s.date);
                  return ListTile(
                    leading: const Icon(Icons.list_alt_outlined),
                    title: Text(s.name),
                    subtitle: Text(dateStr),
                    onTap: () => Navigator.pop(ctx, s),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteSession(Session session, Site? site) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort besök?'),
        content: Text('Tar bort "${session.name}".'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Avbryt')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ta bort')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await SessionDao.instance.deleteSession(session.id!);
    if (site != null && mounted) {
      await _reloadSiteChildren(site.id!);
    } else if (mounted) {
      context.read<HomeProvider>().load();
    }
  }

  // ---------------------------------------------------------------------------
  // Export
  // ---------------------------------------------------------------------------

  Future<void> _exportFolder(Folder folder) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Förbereder export…'), duration: Duration(seconds: 30)),
    );
    try {
      final path = await BulkExportService.instance.exportFolder(folder);
      messenger.removeCurrentSnackBar();
      if (mounted) {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/zip')],
          subject: 'BirdTally – ${folder.name}',
          sharePositionOrigin: _shareOrigin,
        );
      }
    } catch (e) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _exportSite(Site site, Folder? parentFolder) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Förbereder export…'), duration: Duration(seconds: 30)),
    );
    try {
      final path = await BulkExportService.instance.exportSite(
        site,
        folderName: parentFolder?.name,
      );
      messenger.removeCurrentSnackBar();
      if (mounted) {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/zip')],
          subject: 'BirdTally – ${site.name}',
          sharePositionOrigin: _shareOrigin,
        );
      }
    } catch (e) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _exportAll() async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Förbereder backup…'), duration: Duration(seconds: 30)),
    );
    try {
      final path = await BulkExportService.instance.exportAll();
      messenger.removeCurrentSnackBar();
      if (mounted) {
        await Share.shareXFiles(
          [XFile(path, mimeType: 'application/zip')],
          subject: 'BirdTally Backup',
          sharePositionOrigin: _shareOrigin,
        );
      }
    } catch (e) {
      messenger.removeCurrentSnackBar();
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _backupExport() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await BackupService.instance.export();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Kunde inte exportera: $e')),
        );
      }
    }
  }

  Future<void> _backupRestore() async {
    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Återställ databas'),
        content: const Text(
          'All nuvarande data ersätts med innehållet i den valda filen. '
          'Appen startas om efter återställning.\n\n'
          'Vill du fortsätta?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Återställ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await BackupService.instance.restore();

    switch (result) {
      case BackupRestoreResult.success:
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Återställd! Appen startas om…')),
          );
          // Reload home data from the restored database.
          await AppDatabase.instance.appDb; // reopen
          if (mounted) context.read<HomeProvider>().load();
        }
      case BackupRestoreResult.cancelled:
        break;
      case BackupRestoreResult.invalid:
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Filen verkar inte vara en giltig BirdTally-databas.'),
            ),
          );
        }
      case BackupRestoreResult.error:
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Något gick fel vid återställning.')),
          );
        }
    }
  }

  Future<void> _exportSession(
      BuildContext context, Session session, Site? site) async {
    final siteName = site?.name;
    final mode = await showModalBottomSheet<_ExportMode>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Exportera som CSV'),
              subtitle: const Text('Komplett CSV-fil'),
              onTap: () => Navigator.pop(ctx, _ExportMode.full),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('Kopiera text'),
              onTap: () => Navigator.pop(ctx, _ExportMode.clipboard),
            ),
          ],
        ),
      ),
    );
    if (mode == null || !context.mounted) return;

    final observations =
        await SessionDao.instance.getObservations(session.id!);
    final actObs =
        await SessionDao.instance.getActivityObservations(session.id!);

    // Include species with a main count OR with any sub-rows (stage/gender/activity).
    final nonZero = observations.where((o) =>
        o.count > 0 || (actObs[o.taxonId]?.any((a) => a.count > 0) ?? false),
    ).toList();

    final taxonIds = nonZero.map((o) => o.taxonId).toList();
    final taxa = taxonIds.isEmpty
        ? <int, dynamic>{}
        : {
            for (final t in await TaxonDao.instance.getByIds(taxonIds))
              t.taxonId: t,
          };

    String? folderName;
    if (site?.folderId != null) {
      final folders = await SessionDao.instance.getFolders();
      folderName = folders.firstWhere((f) => f.id == site!.folderId).name;
    }

    final name = ExportService.sanitizeFilename(session.name);

    if (mode == _ExportMode.clipboard) {
      final csv = ExportService.instance.buildCsv(
        session: session,
        observations: nonZero,
        taxa: Map.from(taxa),
        activityObservations: actObs,
        siteName: siteName,
        folderName: folderName,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopierat till urklipp')),
        );
      }
    } else {
      final csv = ExportService.instance.buildCsv(
        session: session,
        observations: nonZero,
        taxa: Map.from(taxa),
        activityObservations: actObs,
        siteName: siteName,
        folderName: folderName,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name.csv');
      await file.writeAsString(csv);
      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'BirdTally – $name',
          sharePositionOrigin: _shareOrigin,
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Add sheet & settings
  // ---------------------------------------------------------------------------

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Ny mapp'),
              subtitle: const Text('Samla flera lokaler, t.ex. ett område eller ett län.'),
              onTap: () {
                Navigator.pop(ctx);
                _createFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Ny lokal'),
              subtitle: const Text('En plats du återbesöker. Sparar GPS och underlättar mall för nya besök.'),
              onTap: () {
                Navigator.pop(ctx);
                _createLooseSite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Nytt besök'),
              subtitle: const Text('En räkning vid en viss tid. Kan ligga fritt eller under en lokal.'),
              onTap: () {
                Navigator.pop(ctx);
                _createLooseSession();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createFolder() async {
    final name = await _showNameDialog('Ny mapp', hint: 'Namn på mappen');
    if (name == null || !mounted) return;
    context.read<HomeProvider>().createFolder(name);
  }

  void _showSettings(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            final current = AppSettings.instance.coordSystem;
            return SingleChildScrollView(
              child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Koordinatsystem för export',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                RadioGroup<CoordSystem>(
                  groupValue: current,
                  onChanged: (v) async {
                    await AppSettings.instance.setCoordSystem(v!);
                    setModalState(() {});
                  },
                  child: const Column(
                    children: [
                      RadioListTile<CoordSystem>(
                        title: Text('SWEREF 99 TM'),
                        subtitle: Text('Ost / Nord i meter'),
                        value: CoordSystem.sweref99,
                      ),
                      RadioListTile<CoordSystem>(
                        title: Text('WGS84'),
                        subtitle: Text('Latitud / Longitud i decimalgrader'),
                        value: CoordSystem.wgs84,
                      ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.backup_outlined),
                  title: const Text('Backup – exportera all data'),
                  subtitle: const Text('Alla besök som zip-fil'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _exportAll();
                  },
                ),
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    'Säkerhetskopia (databas)',
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.save_outlined),
                  title: const Text('Exportera säkerhetskopia'),
                  subtitle: const Text('Spara hela databasen till valfri plats'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _backupExport();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Återställ från säkerhetskopia'),
                  subtitle: const Text('Välj en .db-fil att återställa från'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _backupRestore();
                  },
                ),
              ],
              ),
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared dialogs
  // ---------------------------------------------------------------------------

  Future<String?> _showNameDialog(String title,
      {required String hint, String? initial}) {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
          TextButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

/// Applies left indentation based on [depth] in the tree.
class _IndentedTile extends StatelessWidget {
  final int depth;
  final Widget child;

  const _IndentedTile({required this.depth, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: depth * 16.0),
      child: child,
    );
  }
}

enum _ExportMode { full, clipboard }
