import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../db/session_dao.dart';
import '../models/folder.dart';
import '../models/session.dart';
import '../models/site.dart';
import '../providers/home_provider.dart';

/// Shows a dialog to move [session] to a different site (or make it loose).
Future<void> showMoveSessionDialog(BuildContext context, Session session) async {
  final provider = context.read<HomeProvider>();
  final sites = await provider.getAllSites();

  if (!context.mounted) return;

  final destination = await showDialog<_MoveTarget>(
    context: context,
    builder: (ctx) => _MoveSitePickerDialog(
      sites: sites,
      currentSiteId: session.siteId,
    ),
  );

  if (destination == null || !context.mounted) return;
  await provider.moveSession(session, destination.id);
}

/// Shows a dialog to move [folder] to a different parent folder (or make it root).
/// Excludes the folder itself and all its descendants to prevent circular moves.
Future<void> showMoveFolderDialog(BuildContext context, Folder folder) async {
  final provider = context.read<HomeProvider>();
  final allFolders = await provider.getAllFolders();
  final descendants = await SessionDao.instance.getDescendantFolderIds(folder.id!);

  if (!context.mounted) return;

  // Exclude the folder itself and its descendants from choices.
  final eligible = allFolders
      .where((f) => f.id != folder.id && !descendants.contains(f.id))
      .toList();

  final destination = await showDialog<_MoveTarget>(
    context: context,
    builder: (ctx) => _MoveFolderPickerDialog(
      folders: eligible,
      currentFolderId: folder.parentFolderId,
      title: 'Flytta mapp till',
      looseLabelText: 'Ingen överordnad mapp (rot)',
    ),
  );

  if (destination == null || !context.mounted) return;
  await provider.moveFolder(folder, destination.id);
}

/// Shows a dialog to move [site] to a different folder (or make it loose).
Future<void> showMoveSiteDialog(BuildContext context, Site site) async {
  final provider = context.read<HomeProvider>();
  final folders = await provider.getAllFolders();

  if (!context.mounted) return;

  final destination = await showDialog<_MoveTarget>(
    context: context,
    builder: (ctx) => _MoveFolderPickerDialog(
      folders: folders,
      currentFolderId: site.folderId,
    ),
  );

  if (destination == null || !context.mounted) return;
  await provider.moveSite(site, destination.id);
}

// ---------------------------------------------------------------------------
// Internal types and dialogs
// ---------------------------------------------------------------------------

/// Wraps the selected destination id (null = loose/no parent).
class _MoveTarget {
  final int? id;
  const _MoveTarget(this.id);
}

class _MoveSitePickerDialog extends StatelessWidget {
  final List<Site> sites;
  final int? currentSiteId;

  const _MoveSitePickerDialog({required this.sites, required this.currentSiteId});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Flytta till lokal'),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Löst besök (ingen lokal)'),
              selected: currentSiteId == null,
              onTap: () => Navigator.pop(context, const _MoveTarget(null)),
            ),
            const Divider(height: 1),
            ...sites.map((s) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(s.name),
                  selected: s.id == currentSiteId,
                  onTap: () => Navigator.pop(context, _MoveTarget(s.id)),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
      ],
    );
  }
}

class _MoveFolderPickerDialog extends StatelessWidget {
  final List<Folder> folders;
  final int? currentFolderId;
  final String title;
  final String looseLabelText;

  const _MoveFolderPickerDialog({
    required this.folders,
    required this.currentFolderId,
    this.title = 'Flytta till mapp',
    this.looseLabelText = 'Lös lokal (ingen mapp)',
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: Text(looseLabelText),
              selected: currentFolderId == null,
              onTap: () => Navigator.pop(context, const _MoveTarget(null)),
            ),
            const Divider(height: 1),
            ...folders.map((f) => ListTile(
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(f.name),
                  selected: f.id == currentFolderId,
                  onTap: () => Navigator.pop(context, _MoveTarget(f.id)),
                )),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Avbryt'),
        ),
      ],
    );
  }
}
