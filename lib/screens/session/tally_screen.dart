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
import '../../widgets/observation_row.dart';

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
          children: [
            GestureDetector(
              onTap: () => _renameSession(context, provider),
              child: Text(session.name),
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
      body: _TallyList(),
      floatingActionButton: FloatingActionButton(
        onPressed: _openSearchSheet,
        child: const Icon(Icons.add),
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
          decoration: const InputDecoration(hintText: 'Listnamn'),
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
        clipboardMode: true,
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
        clipboardMode: false,
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

class _TallyList extends StatelessWidget {
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
          child: Text(
            'Tryck på + för att söka\noch lägga till arter.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
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

      if (rows.isNotEmpty) rows.add(const Divider(height: 1));

      rows.add(ObservationRow(
        taxon: taxon,
        displayCount: displayCount,
        ownCount: ownCount,
        isChild: item.isChild,
        onIncrement: () => provider.increment(taxon.taxonId),
        onDecrement: () => provider.decrement(taxon.taxonId),
        onTap: () => _showTaxonOptions(context, provider, taxon),
      ));

      // Activity/stage/gender sub-rows (only for top-level taxa).
      if (!item.isChild) {
        for (final ao in provider.activityObservationsFor(taxon.taxonId)) {
          rows.add(const Divider(height: 1));
          rows.add(_ActivityRow(
            ao: ao,
            onIncrement: () => provider.incrementActivity(ao),
            onDecrement: () => provider.decrementActivity(ao),
            onDelete: () => provider.deleteActivityObservation(ao),
            onTap: () => _showSubRowOptions(context, provider, ao),
          ));
        }
      }
    }

    return ListView(children: rows);
  }

  /// Builds an ordered flat list of display items from pinned observations.
  ///
  /// - Top-level taxa (Art, Hybrid) become group heads.
  /// - Child taxa (Underart, Artkomplex, Kollektivtaxon) appear indented
  ///   below their parent, which is shown even if the parent has count = 0.
  /// - Groups sorted by parent's sort_order; children sorted within group.
  List<_TallyItem> _buildItems(TallyProvider provider) {
    final pinned = provider.pinnedObservations;
    if (pinned.isEmpty) return [];

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

    // Sort group heads by sort_order.
    final sortedHeads = groupHeadIds.toList()
      ..sort((a, b) {
        final ta = provider.taxonFor(a);
        final tb = provider.taxonFor(b);
        return (ta?.sortOrder ?? 0).compareTo(tb?.sortOrder ?? 0);
      });

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

  void _showTaxonOptions(
      BuildContext context, TallyProvider provider, Taxon taxon) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Lägg till underrad',
                  style: Theme.of(ctx).textTheme.labelLarge?.copyWith(
                        color: Theme.of(ctx).colorScheme.primary,
                      ),
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
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Ta bort från lista'),
              onTap: () {
                Navigator.pop(ctx);
                provider.deleteObservation(taxon.taxonId);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showSubRowOptions(
      BuildContext context, TallyProvider provider, ActivityObservation ao) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
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
      onSelected: (v) => provider.addActivity(taxon.taxonId, v),
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
      onSelected: (v) {
        if (ao != null) {
          provider.setStageOnSubRow(ao, v);
        } else {
          provider.addStage(taxon!.taxonId, v);
        }
      },
    );
  }

  void _showGenderPicker(BuildContext context, TallyProvider provider,
      {Taxon? taxon, ActivityObservation? ao}) {
    _showValuePicker(
      context: context,
      title: 'Välj kön',
      values: kGenders,
      isAlreadyAdded: (_) => false,
      onSelected: (v) {
        if (ao != null) {
          provider.setGenderOnSubRow(ao, v);
        } else {
          provider.addGender(taxon!.taxonId, v);
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
// Activity sub-row
// ---------------------------------------------------------------------------

class _ActivityRow extends StatelessWidget {
  final ActivityObservation ao;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  const _ActivityRow({
    required this.ao,
    required this.onIncrement,
    required this.onDecrement,
    required this.onDelete,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 32),
      child: SizedBox(
        height: 48,
        child: Row(
          children: [
            const SizedBox(width: 20),
            Expanded(
              child: GestureDetector(
                onTap: onTap,
                child: Text(
                  ao.label.isEmpty ? '—' : ao.label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 16),
              onPressed: onDelete,
              tooltip: 'Ta bort underrad',
              padding: EdgeInsets.zero,
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                onPressed: ao.count > 0 ? onDecrement : null,
                icon: const Icon(Icons.remove, size: 18),
                padding: EdgeInsets.zero,
              ),
            ),
            SizedBox(
              width: 36,
              child: Text(
                '${ao.count}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: IconButton(
                onPressed: onIncrement,
                icon: const Icon(Icons.add, size: 18),
                padding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
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
