import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db/session_dao.dart';
import '../../models/session.dart';
import '../../models/site.dart';
import '../../widgets/location_dialog.dart';
import '../../widgets/move_dialog.dart';
import '../session/tally_screen.dart';

/// Shows all sessions (Besök) for a site. Allows creating new sessions.
class SiteScreen extends StatefulWidget {
  final Site site;

  const SiteScreen({super.key, required this.site});

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  static final _dateFmt = DateFormat('d MMM yyyy', 'sv_SE');
  static final _timeFmt = DateFormat('HH:mm', 'sv_SE');

  List<Session> _sessions = [];
  bool _loading = true;
  late Site _site;

  @override
  void initState() {
    super.initState();
    _site = widget.site;
    _load();
  }

  Future<void> _load() async {
    final sessions = await SessionDao.instance.getSessions(siteId: _site.id);
    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_site.name),
        actions: [
          IconButton(
            icon: Icon(
              _site.hasLocation ? Icons.location_on_outlined : Icons.location_off_outlined,
              color: _site.hasLocation
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Redigera plats',
            onPressed: _editLocation,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sessions.isEmpty
              ? Center(
                  child: Text(
                    'Tryck på + för att starta ett nytt besök.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                )
              : ListView.builder(
                  itemCount: _sessions.length,
                  itemBuilder: (_, i) => _SessionTile(
                    session: _sessions[i],
                    dateFmt: _dateFmt,
                    timeFmt: _timeFmt,
                    onTap: () => _openSession(_sessions[i]),
                    onDelete: () => _confirmDelete(_sessions[i]),
                  ),
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createSession,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _openSession(Session session) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => TallyScreen(session: session)))
        .then((_) => _load());
  }

  Future<void> _editLocation() async {
    final location = await showLocationDialog(context);
    if (location == null || !mounted) return;
    final updated = _site.copyWith(
      sweref99Northing: location.northing,
      sweref99Easting: location.easting,
      radiusMeters: location.radiusMeters,
      wgs84Lat: location.wgs84Lat,
      wgs84Lon: location.wgs84Lon,
    );
    await SessionDao.instance.updateSite(updated);
    if (mounted) setState(() => _site = updated);
  }

  Future<void> _createSession() async {
    final name = await _showNameDialog();
    if (name == null || !mounted) return;
    final now = DateTime.now();
    final session = await SessionDao.instance.insertSession(
      Session(
        siteId: _site.id,
        name: name,
        date: now,
        sweref99Northing: _site.sweref99Northing,
        sweref99Easting: _site.sweref99Easting,
        radiusMeters: _site.radiusMeters,
        wgs84Lat: _site.wgs84Lat,
        wgs84Lon: _site.wgs84Lon,
        createdAt: now,
        updatedAt: now,
      ),
    );
    if (!mounted) return;
    setState(() => _sessions = [session, ..._sessions]);
    _openSession(session);
  }

  Future<void> _confirmDelete(Session session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ta bort besök?'),
        content: Text('Tar bort "${session.name}".'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Avbryt')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ta bort')),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await SessionDao.instance.deleteSession(session.id!);
      setState(() => _sessions = _sessions.where((s) => s.id != session.id).toList());
    }
  }

  Future<String?> _showNameDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nytt besök'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Namn på besöket'),
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (v) {
            if (v.trim().isNotEmpty) Navigator.pop(ctx, v.trim());
          },
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Avbryt')),
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

class _SessionTile extends StatelessWidget {
  final Session session;
  final DateFormat dateFmt;
  final DateFormat timeFmt;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _SessionTile({
    required this.session,
    required this.dateFmt,
    required this.timeFmt,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr = dateFmt.format(session.date);
    final timeStr = timeFmt.format(session.date);

    return ListTile(
      leading: const Icon(Icons.list_alt_outlined),
      title: Text(session.name),
      subtitle: Text('$dateStr  $timeStr'),
      trailing: PopupMenuButton<String>(
        onSelected: (v) {
          if (v == 'move') showMoveSessionDialog(context, session);
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
