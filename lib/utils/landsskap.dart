import 'package:flutter/material.dart';

/// Swedish provinces (landskap) used for Artportalen lokalnamn formatting.
/// Each entry has an [abbr] (used in export) and a [name] (shown in UI).
const List<({String abbr, String name})> kLandskap = [
  (abbr: 'Sk', name: 'Skåne'),
  (abbr: 'Bl', name: 'Blekinge'),
  (abbr: 'Ha', name: 'Halland'),
  (abbr: 'Sm', name: 'Småland'),
  (abbr: 'Öl', name: 'Öland'),
  (abbr: 'Go', name: 'Gotland'),
  (abbr: 'Ög', name: 'Östergötland'),
  (abbr: 'Vg', name: 'Västergötland'),
  (abbr: 'Bo', name: 'Bohuslän'),
  (abbr: 'Ds', name: 'Dalsland'),
  (abbr: 'Nä', name: 'Närke'),
  (abbr: 'Sö', name: 'Södermanland'),
  (abbr: 'Up', name: 'Uppland'),
  (abbr: 'Vs', name: 'Västmanland'),
  (abbr: 'Vr', name: 'Värmland'),
  (abbr: 'Dr', name: 'Dalarna'),
  (abbr: 'Gä', name: 'Gästrikland'),
  (abbr: 'Hs', name: 'Hälsingland'),
  (abbr: 'Me', name: 'Medelpad'),
  (abbr: 'Hr', name: 'Härjedalen'),
  (abbr: 'Jä', name: 'Jämtland'),
  (abbr: 'Ån', name: 'Ångermanland'),
  (abbr: 'Vb', name: 'Västerbotten'),
  (abbr: 'Nb', name: 'Norrbotten'),
  (abbr: 'Ås', name: 'Åsele lappmark'),
  (abbr: 'Ly', name: 'Lycksele lappmark'),
  (abbr: 'Pi', name: 'Pite lappmark'),
  (abbr: 'Lu', name: 'Lule lappmark'),
  (abbr: 'To', name: 'Torne lappmark'),
];

/// Shows a bottom-sheet picker for a Swedish province.
///
/// Returns:
/// - The abbreviation string (e.g. `'Sk'`) when the user selects a province.
/// - `''` (empty string) when the user taps "Inget landskap" to clear.
/// - `null` if the sheet is dismissed without a selection.
Future<String?> showLandskapPicker(
  BuildContext context, {
  String? current,
}) {
  return showModalBottomSheet<String>(
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
              'Välj landskap',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                if (current != null && current.isNotEmpty)
                  ListTile(
                    leading: const Icon(Icons.clear),
                    title: const Text('Inget landskap'),
                    onTap: () => Navigator.pop(ctx, ''),
                  ),
                ...kLandskap.map((l) => ListTile(
                      title: Text('${l.name} (${l.abbr})'),
                      trailing: current == l.abbr
                          ? const Icon(Icons.check, size: 18)
                          : null,
                      onTap: () => Navigator.pop(ctx, l.abbr),
                    )),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
