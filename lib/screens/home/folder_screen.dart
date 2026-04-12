import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../db/session_dao.dart';
import '../../models/folder.dart';
import '../../models/site.dart';
import '../../providers/home_provider.dart';
import '../../utils/landsskap.dart';
import '../../widgets/location_dialog.dart';
import '../../widgets/move_dialog.dart';
import 'site_screen.dart';

/// Shows sub-folders and sites belonging to a folder.
class FolderScreen extends StatefulWidget {
  final Folder folder;

  const FolderScreen({super.key, required this.folder});

  @override
  State<FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<FolderScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy', 'sv_SE');

  List<Folder> _subFolders = [];
  List<Site> _sites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final subFolders =
        await SessionDao.instance.getFolders(parentFolderId: widget.folder.id);
    final sites =
        await SessionDao.instance.getSites(folderId: widget.folder.id);
    if (!mounted) return;
    setState(() {
      _subFolders = subFolders;
      _sites = sites;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.folder.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(context),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddSheet,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_subFolders.isEmpty && _sites.isEmpty) {
      return Center(
        child: Text(
          'Tryck på + för att lägga till en undermapp eller lokal.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    final items = <Widget>[];

    if (_subFolders.isNotEmpty) {
      items.add(_sectionHeader(context, 'Undermappar'));
      for (final f in _subFolders) {
        items.add(_SubFolderTile(
          folder: f,
          onTap: () => _openFolder(f),
          onMove: () => _moveSubFolder(f),
          onDelete: () => _confirmDeleteSubFolder(f),
        ));
      }
    }

    if (_sites.isNotEmpty) {
      items.add(_sectionHeader(context, 'Lokaler'));
      for (final s in _sites) {
        items.add(_SiteTile(
          site: s,
          dateFmt: _dateFmt,
          onTap: () => _openSite(s),
          onDelete: () => _confirmDelete(s),
        ));
      }
    }

    return ListView(children: items);
  }

  Widget _sectionHeader(BuildContext context, String title) {
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

  void _openFolder(Folder folder) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => FolderScreen(folder: folder)))
        .then((_) => _load());
  }

  void _openSite(Site site) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SiteScreen(site: site)))
        .then((_) => _load());
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('Ny undermapp'),
              onTap: () {
                Navigator.pop(ctx);
                _createSubFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.place_outlined),
              title: const Text('Ny lokal'),
              onTap: () {
                Navigator.pop(ctx);
                _createSite();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createSubFolder() async {
    final name = await _showNameDialog('Ny undermapp', hint: 'Namn på mappen');
    if (name == null || !mounted) return;
    final folder = await context
        .read<HomeProvider>()
        .createSubFolder(widget.folder.id!, name);
    setState(() => _subFolders = [..._subFolders, folder]);
  }

  Future<void> _createSite() async {
    final name = await _showNameDialog('Ny lokal', hint: 'Namn på lokalen');
    if (name == null || !mounted) return;
    var site = await SessionDao.instance.insertSite(
      Site(folderId: widget.folder.id, name: name, createdAt: DateTime.now()),
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

    if (!mounted) return;
    final landskap = await showLandskapPicker(context);
    if (landskap != null && landskap.isNotEmpty && mounted) {
      site = site.copyWith(landskap: landskap);
      await SessionDao.instance.updateSite(site);
    }

    if (!mounted) return;
    setState(() => _sites = [..._sites, site]);
    _openSite(site);
  }

  Future<void> _moveSubFolder(Folder folder) async {
    await showMoveFolderDialog(context, folder);
    if (mounted) _load();
  }

  Future<void> _confirmDeleteSubFolder(Folder folder) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort mapp?'),
        content:
            Text('Tar bort "${folder.name}". Lokaler i mappen förblir som lösa lokaler.'),
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
    if (confirmed == true && mounted) {
      await SessionDao.instance.deleteFolder(folder.id!);
      setState(() => _subFolders = _subFolders.where((f) => f.id != folder.id).toList());
    }
  }

  Future<void> _confirmDelete(Site site) async {
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
    if (confirmed == true && mounted) {
      await SessionDao.instance.deleteSite(site.id!);
      setState(() => _sites = _sites.where((s) => s.id != site.id).toList());
    }
  }

  Future<String?> _showNameDialog(String title, {required String hint}) {
    final controller = TextEditingController();
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
// Tile widgets
// ---------------------------------------------------------------------------

class _SubFolderTile extends StatelessWidget {
  final Folder folder;
  final VoidCallback onTap;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  const _SubFolderTile({
    required this.folder,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.folder_outlined),
      title: Text(folder.name),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'move') onMove();
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'move', child: Text('Flytta')),
          PopupMenuItem(value: 'delete', child: Text('Ta bort')),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _SiteTile extends StatelessWidget {
  final Site site;
  final DateFormat dateFmt;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SiteTile({
    required this.site,
    required this.dateFmt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.place_outlined),
      title: Text(site.name),
      subtitle: Text(dateFmt.format(site.createdAt)),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'move') showMoveSiteDialog(context, site);
          if (v == 'delete') onDelete();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'move', child: Text('Flytta')),
          PopupMenuItem(value: 'delete', child: Text('Ta bort')),
        ],
      ),
      onTap: onTap,
    );
  }
}
