import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../db/session_dao.dart';
import '../../models/session.dart';
import '../../models/taxon.dart';
import '../../providers/search_provider.dart';
import '../../providers/tally_provider.dart';
import '../../services/export_service.dart';
import '../../models/activity_observation.dart';
import '../../utils/activities.dart';
import '../../utils/stages.dart';
import '../../utils/string_utils.dart';
import '../../widgets/badge_chips.dart';
import '../../widgets/observation_row.dart' show ObservationRow, TallyCounter;

/// Entry point: scopes TallyProvider and SearchProvider to this screen.
class TallyScreen extends StatelessWidget {
  final Session session;

  const TallyScreen({super.key, required this.session});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => TallyProvider()..load(session)),
        ChangeNotifierProvider(create: (_) => SearchProvider()..init()),
      ],
      child: _TallyBody(session: session),
    );
  }
}

// ---------------------------------------------------------------------------
// Body
// ---------------------------------------------------------------------------

class _TallyBody extends StatefulWidget {
  final Session session;
  const _TallyBody({required this.session});

  @override
  State<_TallyBody> createState() => _TallyBodyState();
}

class _TallyBodyState extends State<_TallyBody> {
  static final _dateFmt = DateFormat('d MMM yyyy', 'sv_SE');
  static final _timeFmt = DateFormat('HH:mm', 'sv_SE');

  void _openSearchSheet() {
    final searchProvider = context.read<SearchProvider>();
    final tallyProvider = context.read<TallyProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: searchProvider),
          ChangeNotifierProvider.value(value: tallyProvider),
        ],
        child: _SearchSheet(
          onTap: (taxon) async {
            await tallyProvider.addFromSearch(taxon);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TallyProvider>();
    final session = provider.session ?? widget.session;
    final dateStr = _dateFmt.format(session.date);
    final startStr = _timeFmt.format(session.date);
    final endStr = session.endTime != null ? _timeFmt.format(session.endTime!) : null;
    final finished = session.endTime != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => _renameSession(context, provider),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(session.name),
              ),
            ),
            GestureDetector(
              onTap: () => _editTimes(context, provider, session),
              child: Text(
                endStr != null
                    ? '$dateStr  $startStr – $endStr'
                    : '$dateStr  $startStr',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<SortMode>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sortering',
            onSelected: (mode) => provider.setSortMode(mode),
            itemBuilder: (_) => [
              _sortMenuItem(SortMode.taxonomic, 'Taxonomisk ordning', provider),
              _sortMenuItem(SortMode.alphabetic, 'Alfabetisk', provider),
              _sortMenuItem(SortMode.byCount, 'Antal (mest först)', provider),
              _sortMenuItem(SortMode.added, 'Tillagd ordning', provider),
            ],
          ),
          if (!finished)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: 'Avsluta besök',
              onPressed: () => provider.setEndTime(DateTime.now()),
            ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Exportera',
            onPressed: _share,
          ),
        ],
      ),
      body: _TallyList(onAddSpecies: _openSearchSheet),
    );
  }

  PopupMenuItem<SortMode> _sortMenuItem(
      SortMode mode, String label, TallyProvider provider) {
    return PopupMenuItem(
      value: mode,
      child: Row(
        children: [
          if (provider.sortMode == mode)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.check, size: 18),
            )
          else
            const SizedBox(width: 26),
          Text(label),
        ],
      ),
    );
  }

  Future<void> _renameSession(
      BuildContext context, TallyProvider provider) async {
    final current = provider.session?.name ?? '';
    final controller = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ändra namn'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Avbryt')),
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
    if (name == null) return;
    await provider.rename(name);
  }

  Future<void> _editTimes(
      BuildContext context, TallyProvider provider, Session session) async {
    final date = session.date;
    final picked = await showDatePicker(
      context: context,
      initialDate: date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null || !context.mounted) return;

    final startTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(date),
      helpText: 'Starttid',
    );
    if (startTime == null || !context.mounted) return;

    final newStart = DateTime(
        picked.year, picked.month, picked.day, startTime.hour, startTime.minute);
    await provider.setStartTime(newStart);

    if (!context.mounted) return;

    final wantEnd = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sluttid'),
        content: const Text('Vill du ange en sluttid?'),
        actions: [
          if (session.endTime != null)
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Ta bort sluttid'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Nej')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Ja')),
        ],
      ),
    );

    if (wantEnd == null && context.mounted) {
      provider.clearEndTime();
    } else if (wantEnd == true && context.mounted) {
      final endDate = await showDatePicker(
        context: context,
        initialDate: session.endTime ?? picked,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Slutdatum',
      );
      if (endDate == null || !context.mounted) return;

      final endTime = await showTimePicker(
        context: context,
        initialTime: session.endTime != null
            ? TimeOfDay.fromDateTime(session.endTime!)
            : TimeOfDay.now(),
        helpText: 'Sluttid',
      );
      if (endTime != null && context.mounted) {
        final newEnd = DateTime(
            endDate.year, endDate.month, endDate.day, endTime.hour, endTime.minute);
        provider.setEndTime(newEnd);
      }
    }
  }

  Future<void> _share() async {
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
    if (mode == null || !mounted) return;

    final provider = context.read<TallyProvider>();
    final session = provider.session ?? widget.session;

    final actObs =
        await SessionDao.instance.getActivityObservations(session.id!);

    // Include species with a main count OR with any sub-rows (stage/gender/activity).
    final observations = provider.pinnedObservations.where((o) =>
        o.count > 0 || (actObs[o.taxonId]?.any((a) => a.count > 0) ?? false),
    ).toList();
    final taxa = {
      for (final o in observations)
        if (provider.taxonFor(o.taxonId) != null) o.taxonId: provider.taxonFor(o.taxonId)!,
    };

    // Look up site name and folder name if session belongs to a site.
    String? siteName;
    String? folderName;
    if (session.siteId != null) {
      final sites = await SessionDao.instance.getSites();
      final match = sites.where((s) => s.id == session.siteId).firstOrNull;
      siteName = match?.name;
      if (match?.folderId != null) {
        final folders = await SessionDao.instance.getFolders();
        folderName = folders.firstWhere((f) => f.id == match!.folderId).name;
      }
    }

    if (!mounted) return;

    final name = ExportService.sanitizeFilename(session.name);

    if (mode == _ExportMode.clipboard) {
      final csv = ExportService.instance.buildCsv(
        session: session,
        observations: observations,
        taxa: taxa,
        activityObservations: actObs,
        siteName: siteName,
        folderName: folderName,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kopierat till urklipp')),
        );
      }
    } else {
      final csv = ExportService.instance.buildCsv(
        session: session,
        observations: observations,
        taxa: taxa,
        activityObservations: actObs,
        siteName: siteName,
        folderName: folderName,
      );
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$name.csv');
      await file.writeAsString(csv);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/csv')],
        subject: 'BirdTally – $name',
      );
    }
  }
}

enum _ExportMode { full, clipboard }

// ---------------------------------------------------------------------------
// Aktuell lista
// ---------------------------------------------------------------------------

class _TallyList extends StatefulWidget {
  final VoidCallback onAddSpecies;
  const _TallyList({required this.onAddSpecies});

  @override
  State<_TallyList> createState() => _TallyListState();
}

class _TallyListState extends State<_TallyList> {
  final Set<int> _collapsed = {};

  void _toggleCollapse(int taxonId) {
    setState(() {
      if (_collapsed.contains(taxonId)) {
        _collapsed.remove(taxonId);
      } else {
        _collapsed.add(taxonId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TallyProvider>();

    if (provider.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final items = _buildItems(provider);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Tryck på + för att söka\noch lägga till arter.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 16),
              FloatingActionButton(
                onPressed: widget.onAddSpecies,
                child: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      );
    }

    // Build flat list: species rows + activity sub-rows.
    final rows = <Widget>[];
    for (final item in items) {
      final taxon = item.taxon;
      final ownCount = provider.countFor(taxon.taxonId);
      final displayCount = item.isChild
          ? ownCount
          : provider.totalCountFor(taxon.taxonId);
      final subRows = !item.isChild
          ? provider.activityObservationsFor(taxon.taxonId)
          : <ActivityObservation>[];
      final hasSubRows = subRows.isNotEmpty;
      final isCollapsed = _collapsed.contains(taxon.taxonId);

      if (rows.isNotEmpty) rows.add(const Divider(height: 1));

      rows.add(ObservationRow(
        taxon: taxon,
        displayCount: displayCount,
        ownCount: ownCount,
        isChild: item.isChild,
        onIncrement: () => provider.increment(taxon.taxonId),
        onDecrement: () => provider.decrement(taxon.taxonId),
        onTap: hasSubRows
            ? () => _toggleCollapse(taxon.taxonId)
            : () => _showTaxonOptions(context, provider, taxon),
        onLongPress: () => _showTaxonOptions(context, provider, taxon),
        hasSubRows: hasSubRows,
        collapsed: isCollapsed,
        multiplier: provider.multiplierFor(taxon.taxonId),
      ));

      // Activity/stage/gender sub-rows (only for top-level taxa, hide when collapsed).
      if (!item.isChild && !isCollapsed) {
        for (final ao in subRows) {
          rows.add(const Divider(height: 1));
          rows.add(_ActivityRow(
            ao: ao,
            multiplier: provider.subRowMultiplierFor(ao.id ?? 0),
            onIncrement: () => provider.incrementActivity(ao),
            onDecrement: () => provider.decrementActivity(ao),
            onTap: () => _showSubRowOptions(context, provider, ao),
          ));
        }
      }
    }

    rows.add(Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: FloatingActionButton(
          onPressed: widget.onAddSpecies,
          child: const Icon(Icons.add),
        ),
      ),
    ));

    return ListView(children: rows);
  }

  /// Builds an ordered flat list of display items from pinned observations.
  ///
  /// - Top-level taxa (Art, Hybrid) become group heads.
  /// - Child taxa (Underart, Artkomplex, Kollektivtaxon) appear indented
  ///   below their parent, which is shown even if the parent has count = 0.
  /// - Groups sorted according to the current [SortMode].
  List<_TallyItem> _buildItems(TallyProvider provider) {
    final pinned = provider.pinnedObservations;
    if (pinned.isEmpty) return [];

    // Index for insertion-order sort.
    final insertionOrder = <int, int>{};
    for (var i = 0; i < pinned.length; i++) {
      insertionOrder[pinned[i].taxonId] = i;
    }

    // Separate top-level and child observations.
    final Map<int, List<int>> childrenByParent = {}; // parentId → [taxonIds]
    final List<int> topLevelIds = [];

    for (final obs in pinned) {
      final taxon = provider.taxonFor(obs.taxonId);
      if (taxon == null) continue;

      if (taxon.category.isChild && taxon.parentTaxonId != null) {
        childrenByParent.putIfAbsent(taxon.parentTaxonId!, () => []).add(taxon.taxonId);
      } else {
        topLevelIds.add(taxon.taxonId);
      }
    }

    // Collect all group-head IDs: explicit top-level + implied parents of children.
    final groupHeadIds = <int>{
      ...topLevelIds,
      ...childrenByParent.keys,
    };

    // Sort group heads according to the chosen mode.
    final sortedHeads = groupHeadIds.toList();
    switch (provider.sortMode) {
      case SortMode.taxonomic:
        sortedHeads.sort((a, b) {
          final ta = provider.taxonFor(a);
          final tb = provider.taxonFor(b);
          return (ta?.sortOrder ?? 0).compareTo(tb?.sortOrder ?? 0);
        });
      case SortMode.alphabetic:
        sortedHeads.sort((a, b) {
          final ta = provider.taxonFor(a);
          final tb = provider.taxonFor(b);
          return (ta?.swedishName ?? '').compareTo(tb?.swedishName ?? '');
        });
      case SortMode.byCount:
        sortedHeads.sort((a, b) {
          return provider.totalCountFor(b).compareTo(provider.totalCountFor(a));
        });
      case SortMode.added:
        sortedHeads.sort((a, b) {
          return (insertionOrder[a] ?? 9999).compareTo(insertionOrder[b] ?? 9999);
        });
    }

    final items = <_TallyItem>[];
    for (final headId in sortedHeads) {
      final headTaxon = provider.taxonFor(headId);
      if (headTaxon != null) {
        items.add(_TallyItem(taxon: headTaxon, isChild: false));
      }

      final childIds = childrenByParent[headId] ?? [];
      childIds.sort((a, b) {
        final ta = provider.taxonFor(a);
        final tb = provider.taxonFor(b);
        return (ta?.sortOrder ?? 0).compareTo(tb?.sortOrder ?? 0);
      });
      for (final childId in childIds) {
        final childTaxon = provider.taxonFor(childId);
        if (childTaxon != null) {
          items.add(_TallyItem(taxon: childTaxon, isChild: true));
        }
      }
    }

    return items;
  }

  void _showSubRowInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Om underrader'),
        content: const SingleChildScrollView(
          child: Text(
            'Underrader räknas som separata fynd. Kön, ålder/stadie, '
            'aktivitet och kommentar kan alla läggas in i samma underrad. '
            'Underrader kan alltså ha olika egenskaper kopplade till sig, '
            'eller samma, det väljer du själv. Summan av alla individer '
            'räknas in i totalsiffran på huvudraden.\n\n'
            'Att plussa på direkt i huvudraden räknas endast som notering '
            'av art.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showTaxonOptions(
      BuildContext context, TallyProvider provider, Taxon taxon) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lägg till underrad',
                      style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.help_outline, size: 20),
                    tooltip: 'Om underrader',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _showSubRowInfo(ctx),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Varje underrad räknas som minst en egen individ med valda egenskaper. Huvudraden visar totalsumman.',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.add_task),
              title: const Text('Aktivitet'),
              onTap: () {
                Navigator.pop(ctx);
                _showActivityPicker(context, provider, taxon);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Ålder-Stadium'),
              onTap: () {
                Navigator.pop(ctx);
                _showStagePicker(context, provider, taxon: taxon);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Kön'),
              onTap: () {
                Navigator.pop(ctx);
                _showGenderPicker(context, provider, taxon: taxon);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: const Text('Kommentar'),
              onTap: () {
                Navigator.pop(ctx);
                _showCommentEditor(context, provider, taxon: taxon);
              },
            ),
            const Divider(height: 1),
            _MultiplierPicker(
              current: provider.multiplierFor(taxon.taxonId),
              onChanged: (v) {
                provider.setMultiplier(taxon.taxonId, v);
                Navigator.pop(ctx);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Ta bort från besök'),
              onTap: () {
                Navigator.pop(ctx);
                provider.deleteObservation(taxon.taxonId);
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  void _showSubRowOptions(
      BuildContext context, TallyProvider provider, ActivityObservation ao) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_task),
              title: Text(ao.activity.isEmpty
                  ? 'Lägg till aktivitet'
                  : 'Ändra aktivitet (${ao.activity})'),
              onTap: () {
                Navigator.pop(ctx);
                _showActivityPickerForSubRow(context, provider, ao);
              },
            ),
            ListTile(
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(ao.stage.isEmpty
                  ? 'Lägg till ålder-stadium'
                  : 'Ändra ålder-stadium (${ao.stage})'),
              onTap: () {
                Navigator.pop(ctx);
                _showStagePicker(context, provider, ao: ao);
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: Text(ao.gender.isEmpty
                  ? 'Lägg till kön'
                  : 'Ändra kön (${ao.gender})'),
              onTap: () {
                Navigator.pop(ctx);
                _showGenderPicker(context, provider, ao: ao);
              },
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline),
              title: Text(ao.hasAnyComment
                  ? 'Ändra kommentar'
                  : 'Lägg till kommentar'),
              onTap: () {
                Navigator.pop(ctx);
                _showCommentEditor(context, provider, ao: ao);
              },
            ),
            const Divider(height: 1),
            _MultiplierPicker(
              current: provider.subRowMultiplierFor(ao.id ?? 0),
              onChanged: (v) {
                provider.setSubRowMultiplier(ao.id ?? 0, v);
                Navigator.pop(ctx);
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Ta bort underrad'),
              onTap: () {
                Navigator.pop(ctx);
                provider.deleteActivityObservation(ao);
              },
            ),
          ],
          ),
        ),
      ),
    );
  }

  void _showActivityPicker(
      BuildContext context, TallyProvider provider, Taxon taxon) {
    final existing = provider
        .activityObservationsFor(taxon.taxonId)
        .map((a) => a.activity)
        .toSet();

    _showValuePicker(
      context: context,
      title: 'Välj aktivitet',
      values: kActivities,
      isAlreadyAdded: (v) => existing.contains(v),
      onSelected: (v) async {
        await provider.addActivity(taxon.taxonId, v);
        if (context.mounted) _maybeShowSubRowSnackbar(context, provider);
      },
    );
  }

  void _maybeShowSubRowSnackbar(BuildContext context, TallyProvider provider) {
    if (provider.subRowHintShown) return;
    provider.markSubRowHintShown();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Underraden räknas som 1 individ. Tryck + för fler.'),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showActivityPickerForSubRow(
      BuildContext context, TallyProvider provider, ActivityObservation ao) {
    _showValuePicker(
      context: context,
      title: 'Välj aktivitet',
      values: kActivities,
      isAlreadyAdded: (_) => false,
      onSelected: (v) => provider.setActivityOnSubRow(ao, v),
    );
  }

  void _showStagePicker(BuildContext context, TallyProvider provider,
      {Taxon? taxon, ActivityObservation? ao}) {
    _showValuePicker(
      context: context,
      title: 'Välj ålder-stadium',
      values: kStages,
      isAlreadyAdded: (_) => false,
      onSelected: (v) async {
        if (ao != null) {
          await provider.setStageOnSubRow(ao, v);
        } else {
          await provider.addStage(taxon!.taxonId, v);
          if (context.mounted) _maybeShowSubRowSnackbar(context, provider);
        }
      },
    );
  }

  Future<void> _showCommentEditor(
    BuildContext context,
    TallyProvider provider, {
    Taxon? taxon,
    ActivityObservation? ao,
  }) async {
    final result = await showDialog<_CommentEditorResult>(
      context: context,
      builder: (_) => _CommentEditorDialog(
        initialPublic: ao?.commentPublic ?? '',
        initialPrivate: ao?.commentPrivate ?? '',
      ),
    );
    if (result == null) return;
    if (ao != null) {
      await provider.setCommentsOnSubRow(
          ao, result.commentPublic, result.commentPrivate);
    } else if (taxon != null) {
      if (result.commentPublic.isEmpty && result.commentPrivate.isEmpty) return;
      await provider.addComments(
          taxon.taxonId, result.commentPublic, result.commentPrivate);
      if (context.mounted) _maybeShowSubRowSnackbar(context, provider);
    }
  }

  void _showGenderPicker(BuildContext context, TallyProvider provider,
      {Taxon? taxon, ActivityObservation? ao}) {
    _showValuePicker(
      context: context,
      title: 'Välj kön',
      values: kGenders,
      isAlreadyAdded: (_) => false,
      onSelected: (v) async {
        if (ao != null) {
          await provider.setGenderOnSubRow(ao, v);
        } else {
          await provider.addGender(taxon!.taxonId, v);
          if (context.mounted) _maybeShowSubRowSnackbar(context, provider);
        }
      },
    );
  }

  void _showValuePicker({
    required BuildContext context,
    required String title,
    required List<String> values,
    required bool Function(String) isAlreadyAdded,
    required void Function(String) onSelected,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        expand: false,
        builder: (_, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: values.length,
                itemBuilder: (_, i) {
                  final value = values[i];
                  final alreadyAdded = isAlreadyAdded(value);
                  return ListTile(
                    title: Text(value),
                    trailing: alreadyAdded
                        ? const Icon(Icons.check, size: 18)
                        : null,
                    onTap: alreadyAdded
                        ? null
                        : () {
                            Navigator.pop(ctx);
                            onSelected(value);
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TallyItem {
  final Taxon taxon;
  final bool isChild;
  const _TallyItem({required this.taxon, required this.isChild});
}

// ---------------------------------------------------------------------------
// Comment editor
// ---------------------------------------------------------------------------

class _CommentEditorResult {
  final String commentPublic;
  final String commentPrivate;
  const _CommentEditorResult(this.commentPublic, this.commentPrivate);
}

enum _CommentMode { publik, privat }

class _CommentEditorDialog extends StatefulWidget {
  final String initialPublic;
  final String initialPrivate;

  const _CommentEditorDialog({
    required this.initialPublic,
    required this.initialPrivate,
  });

  @override
  State<_CommentEditorDialog> createState() => _CommentEditorDialogState();
}

class _CommentEditorDialogState extends State<_CommentEditorDialog> {
  static const _maxLen = 1000;

  late String _public = widget.initialPublic;
  late String _private = widget.initialPrivate;
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialPublic);
  _CommentMode _mode = _CommentMode.publik;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _switchMode(_CommentMode mode) {
    if (mode == _mode) return;
    if (_mode == _CommentMode.publik) {
      _public = _controller.text;
    } else {
      _private = _controller.text;
    }
    setState(() {
      _mode = mode;
      _controller.text =
          mode == _CommentMode.publik ? _public : _private;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Kommentar'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_CommentMode>(
              segments: const [
                ButtonSegment(
                  value: _CommentMode.publik,
                  label: Text('Publik'),
                  icon: Icon(Icons.public, size: 18),
                ),
                ButtonSegment(
                  value: _CommentMode.privat,
                  label: Text('Privat'),
                  icon: Icon(Icons.lock_outline, size: 18),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (s) => _switchMode(s.first),
            ),
            const SizedBox(height: 12),
            Text(
              _mode == _CommentMode.publik
                  ? 'Syns för alla på Artportalen.'
                  : 'Syns bara för dig på Artportalen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              autofocus: true,
              maxLength: _maxLen,
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Fritext…',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
        TextButton(
          onPressed: () {
            if (_mode == _CommentMode.publik) {
              _public = _controller.text;
            } else {
              _private = _controller.text;
            }
            Navigator.pop(
              context,
              _CommentEditorResult(_public.trim(), _private.trim()),
            );
          },
          child: const Text('Spara'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Activity sub-row
// ---------------------------------------------------------------------------

class _ActivityRow extends StatefulWidget {
  final ActivityObservation ao;
  final int multiplier;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.ao,
    this.multiplier = 1,
    required this.onIncrement,
    required this.onDecrement,
    required this.onTap,
  });

  @override
  State<_ActivityRow> createState() => _ActivityRowState();
}

class _ActivityRowState extends State<_ActivityRow> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ao = widget.ao;
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
    );
    return Padding(
      padding: const EdgeInsets.only(left: 32, right: 12),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(width: 20),
              Expanded(
                child: GestureDetector(
                  onTap: widget.onTap,
                  onLongPress: () => setState(() => _expanded = !_expanded),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          ao.label.isEmpty ? '—' : ao.label,
                          style: labelStyle,
                          maxLines: _expanded ? null : 1,
                          overflow: _expanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                        ),
                        if (ao.commentPublic.isNotEmpty)
                          _CommentLine(
                            icon: Icons.public,
                            text: ao.commentPublic,
                            expanded: _expanded,
                          ),
                        if (ao.commentPrivate.isNotEmpty)
                          _CommentLine(
                            icon: Icons.lock_outline,
                            text: ao.commentPrivate,
                            expanded: _expanded,
                          ),
                        if (ao.count == 0)
                          Text(
                            'Tryck + för att räkna',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              TallyCounter(
                count: ao.count,
                onIncrement: widget.onIncrement,
                onDecrement: widget.onDecrement,
                small: true,
                multiplier: widget.multiplier,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommentLine extends StatelessWidget {
  final IconData icon;
  final String text;
  final bool expanded;

  const _CommentLine({
    required this.icon,
    required this.text,
    required this.expanded,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75);
    final style = theme.textTheme.bodySmall?.copyWith(color: color);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2, right: 4),
            child: Icon(icon, size: 12, color: color),
          ),
          Expanded(
            child: Text(
              text,
              style: style,
              maxLines: expanded ? null : 1,
              overflow:
                  expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Multiplier picker (used inside taxon & sub-row bottom sheets)
// ---------------------------------------------------------------------------

class _MultiplierPicker extends StatelessWidget {
  final int current;
  final ValueChanged<int> onChanged;

  const _MultiplierPicker({required this.current, required this.onChanged});

  static const _presets = [1, 5, 10, 50];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed,
                  size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Text('Multiplikator', style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final v in _presets)
                ChoiceChip(
                  label: Text('x$v'),
                  selected: current == v,
                  onSelected: (_) => onChanged(v),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ActionChip(
                label: Text(!_presets.contains(current) && current > 1
                    ? 'x$current'
                    : '…'),
                onPressed: () => _pickCustom(context),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _pickCustom(BuildContext context) {
    final controller = TextEditingController(
      text: current > 1 ? '$current' : '',
    );
    showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Anpassad multiplikator'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Antal per tryck',
            prefixText: 'x',
          ),
          onSubmitted: (v) {
            final n = int.tryParse(v);
            if (n != null && n >= 1) Navigator.pop(ctx, n);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Avbryt'),
          ),
          TextButton(
            onPressed: () {
              final n = int.tryParse(controller.text);
              if (n != null && n >= 1) Navigator.pop(ctx, n);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    ).then((v) {
      if (v != null) onChanged(v);
    });
  }
}

// ---------------------------------------------------------------------------
// Search bottom sheet
// ---------------------------------------------------------------------------

class _SearchSheet extends StatefulWidget {
  final void Function(Taxon) onTap;
  const _SearchSheet({required this.onTap});

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final search = context.watch<SearchProvider>();
    final tally = context.watch<TallyProvider>();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Search field
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              onChanged: (q) => context.read<SearchProvider>().setQuery(q),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Sök art…',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: search.hasQuery
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _controller.clear();
                          context.read<SearchProvider>().clear();
                        },
                      )
                    : null,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                filled: true,
              ),
            ),
          ),
          // Toggles
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _Toggle(
                  label: 'Underarter',
                  value: search.includeUnderart,
                  onChanged: (v) => search.setToggle('underart', v),
                ),
                const SizedBox(width: 8),
                _Toggle(
                  label: 'Komplex',
                  value: search.includeKomplex,
                  onChanged: (v) => search.setToggle('komplex', v),
                ),
                const SizedBox(width: 8),
                _Toggle(
                  label: 'Hybrider',
                  value: search.includeHybrider,
                  onChanged: (v) => search.setToggle('hybrid', v),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
            child: Text(
              'LC, NT, VU, EN, CR, RE, DD, NE, NA = Rödlistekategorier\nFD I = Med i fågeldirektivets bilaga 1\nSkog = Prioriterade fågelarter i skogsvårdslagen',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          const Divider(height: 1),
          // Results
          Expanded(
            child: search.searching
                ? const Center(child: CircularProgressIndicator())
                : search.results.isEmpty && search.hasQuery
                    ? Center(
                        child: Text(
                          'Inga träffar för "${search.query}"',
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: search.results.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final taxon = search.results[i];
                          final count = tally.countFor(taxon.taxonId);
                          return _SearchResultTile(
                            taxon: taxon,
                            count: count,
                            query: search.query,
                            onTap: () => widget.onTap(taxon),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final Taxon taxon;
  final int count;
  final String query;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.taxon,
    required this.count,
    required this.query,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      title: _highlightedText(taxon.swedishName.sentenceCase, query, theme.textTheme.bodyLarge),
      subtitle: _highlightedText(
        taxon.scientificName,
        query,
        theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BadgeChips(taxon: taxon),
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Chip(
                label: Text('$count'),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
              ),
            ),
        ],
      ),
      onTap: onTap,
    );
  }

  Widget _highlightedText(String text, String query, TextStyle? base) {
    if (query.isEmpty) return Text(text, style: base);
    final lower = text.toLowerCase();
    final idx = lower.indexOf(query.toLowerCase());
    if (idx < 0) return Text(text, style: base);
    return Text.rich(TextSpan(style: base, children: [
      TextSpan(text: text.substring(0, idx)),
      TextSpan(text: text.substring(idx, idx + query.length),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      TextSpan(text: text.substring(idx + query.length)),
    ]));
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _Toggle({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: value,
      onSelected: onChanged,
      visualDensity: VisualDensity.compact,
    );
  }
}
