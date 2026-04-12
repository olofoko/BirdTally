import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/session_dao.dart';
import '../../db/taxon_dao.dart';
import '../../models/activity_observation.dart';
import '../../models/folder.dart';
import '../../models/observation.dart';
import '../../models/session.dart';
import '../../models/site.dart';
import '../../providers/home_provider.dart';
import '../../services/app_settings.dart';
import '../../services/export_service.dart';
import '../../widgets/location_dialog.dart';
import '../../widgets/move_dialog.dart';
import '../session/tally_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy', 'sv_SE');
  static final _timeFmt = DateFormat('HH:mm', 'sv_SE');

  // Lazy-loaded children, keyed by parent id.
  final Map<int, List<Folder>> _subFoldersByFolder = {};
  final Map<int, List<Site>> _sitesByFolder = {};
  final Map<int, List<Session>> _sessionsBySite = {};
  final Set<String> _loadingNodes = {};

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
    setState(() {
      _subFoldersByFolder[folderId] = results[0] as List<Folder>;
      _sitesByFolder[folderId] = results[1] as List<Site>;
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

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<HomeProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listor'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Inställningar',
            onPressed: () => _showSettings(context),
          ),
        ],
      ),
      body: provider.loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(provider),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(HomeProvider provider) {
    final hasContent = provider.folders.isNotEmpty ||
        provider.looseSites.isNotEmpty ||
        provider.looseSessions.isNotEmpty;

    if (!hasContent) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            'Tryck på + för att skapa\nen mapp, lokal eller lista.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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
          _sectionHeader('Listor'),
          for (final session in provider.looseSessions)
            _buildSessionTile(session, 0, null),
        ],
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              onSelected: (v) =>
                  _handleSiteMenu(v, site, parentFolder),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'addSession', child: Text('Ny session')),
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
      case 'move':
        await showMoveFolderDialog(context, folder);
        if (mounted) context.read<HomeProvider>().load();
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
      case 'location':
        await _editSiteLocation(site, parentFolder);
      case 'move':
        await showMoveSiteDialog(context, site);
        if (mounted) context.read<HomeProvider>().load();
        if (parentFolder != null && mounted) {
          await _reloadFolderChildren(parentFolder.id!);
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
      case 'useAsTemplate':
        await _createSessionFromTemplate(site, session);
      case 'move':
        await showMoveSessionDialog(context, session);
        if (mounted) context.read<HomeProvider>().load();
        if (site != null && mounted) await _reloadSiteChildren(site.id!);
      case 'delete':
        await _confirmDeleteSession(session, site);
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
      // Loose session — copy species rows but no site
      final observations = await SessionDao.instance.getObservations(template.id!);
      final actObsMap = await SessionDao.instance.getActivityObservations(template.id!);
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
        for (final ao in actObsMap[obs.taxonId] ?? []) {
          await SessionDao.instance.upsertActivityObservation(
            ActivityObservation(sessionId: session.id!, taxonId: ao.taxonId, activity: ao.activity, count: 0),
          );
        }
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
      if (site != null && mounted) _reloadSiteChildren(site.id!);
      if (site == null && mounted) context.read<HomeProvider>().load();
    });
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
      final updated = site.copyWith(
        sweref99Northing: location.northing,
        sweref99Easting: location.easting,
        radiusMeters: location.radiusMeters,
        wgs84Lat: location.wgs84Lat,
        wgs84Lon: location.wgs84Lon,
      );
      await SessionDao.instance.updateSite(updated);
      site = updated;
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
      final updated = site.copyWith(
        sweref99Northing: location.northing,
        sweref99Easting: location.easting,
        radiusMeters: location.radiusMeters,
        wgs84Lat: location.wgs84Lat,
        wgs84Lon: location.wgs84Lon,
      );
      await SessionDao.instance.updateSite(updated);
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
    final name = await _showNameDialog('Ny lista', hint: 'Namn på listan');
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
              title: const Text('Starta ny tom lista'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Använd tidigare lista som mall'),
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
          const SnackBar(content: Text('Inga tidigare listor att använda som mall.')),
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
              title: const Text('Exportera med rubrikrad'),
              subtitle: const Text('Komplett CSV-fil'),
              onTap: () => Navigator.pop(ctx, _ExportMode.full),
            ),
            ListTile(
              leading: const Icon(Icons.content_paste_outlined),
              title: const Text('Kopiera som urklipp'),
              subtitle: const Text('Utan rubrikrad — för import i Artportalen'),
              onTap: () => Navigator.pop(ctx, _ExportMode.clipboard),
            ),
          ],
        ),
      ),
    );
    if (mode == null || !context.mounted) return;

    final observations =
        await SessionDao.instance.getObservations(session.id!);
    final nonZero = observations.where((o) => o.count > 0).toList();

    final taxonIds = nonZero.map((o) => o.taxonId).toList();
    final taxa = taxonIds.isEmpty
        ? <int, dynamic>{}
        : {
            for (final t in await TaxonDao.instance.getByIds(taxonIds))
              t.taxonId: t,
          };

    final actObs =
        await SessionDao.instance.getActivityObservations(session.id!);

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
        clipboardMode: true,
      );
      await Share.share(csv, subject: 'BirdTally – $name');
    } else {
      final csv = ExportService.instance.buildCsv(
        session: session,
        observations: nonZero,
        taxa: Map.from(taxa),
        activityObservations: actObs,
        siteName: siteName,
        folderName: folderName,
        clipboardMode: false,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name.csv');
      await file.writeAsString(csv);
      if (context.mounted) {
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'text/csv')],
          subject: 'BirdTally – $name',
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
              onTap: () {
                Navigator.pop(ctx);
                _createFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Ny lokal'),
              onTap: () {
                Navigator.pop(ctx);
                _createLooseSite();
              },
            ),
            ListTile(
              leading: const Icon(Icons.list_alt_outlined),
              title: const Text('Ny lista'),
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
      builder: (ctx) => SafeArea(
        child: StatefulBuilder(
          builder: (ctx, setModalState) {
            final current = AppSettings.instance.coordSystem;
            return Column(
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
              ],
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
