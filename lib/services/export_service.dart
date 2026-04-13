import 'package:intl/intl.dart';

import '../models/activity_observation.dart';
import '../models/observation.dart';
import '../models/session.dart';
import '../models/taxon.dart';
import 'app_settings.dart';

/// Builds a semicolon-separated CSV string matching the Artportalen
/// "Fåglar" import preset (ap2_template_sv.xls, version 4.17).
///
/// Column order is fixed — 47 columns, last one intentionally empty —
/// as required by Artportalen's Excel import template.
class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  static const _sep = ';';

  static const _headers = [
    'Artnamn',
    'Antal',
    'Ålder-Stadium',
    'Kön',
    'Aktivitet',
    'Metod',
    'Lokalnamn',
    'Huvudlokal',
    'Ost',
    'Nord',
    'Noggrannhet',
    'Diffusion',
    'Startdatum',
    'Starttid',
    'Slutdatum',
    'Sluttid',
    'Publik kommentar',
    'Intressant kommentar',
    'Privat kommentar',
    'Ej återfunnen',
    'Andrahand',
    'Osäker artbestämning',
    'Ospontan',
    'Biotop',
    'Biotop-beskrivning',
    'Artbestämd av',
    'Artbestämd av (fritext)',
    'Bestämningsår',
    'Beskrivning artbestämning',
    'Bekräftad av',
    'Bekräftad av (fritext)',
    'Bekräftelseår',
    'Länk till BOLD/GenBank',
    'Dölj fyndet t.o.m.',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Med-observatör',
    'Externid',
    'Ej funnen',
    '', // column 47 — intentionally blank per template
  ];

  static final _dateFormat = DateFormat('yyyy-MM-dd');
  static final _timeFormat = DateFormat('HH:mm');

  /// Sanitises a string for use as a filename, keeping Swedish characters.
  static String sanitizeFilename(String name) =>
      name.replaceAll(RegExp(r'[/\\:*?"<>|]'), '').trim();

  /// Generates the CSV string for [session] and its [observations].
  ///
  /// [taxa] must contain every taxon referenced by [observations].
  /// [activityObservations] is optional; each activity sub-row is exported
  /// as its own CSV row with the Aktivitet column filled.
  /// [siteName] is the Lokal name; falls back to session name if null.
  String buildCsv({
    required Session session,
    required List<Observation> observations,
    required Map<int, Taxon> taxa,
    Map<int, List<ActivityObservation>> activityObservations = const {},
    String? siteName,
    String? folderName,
  }) {
    final buffer = StringBuffer();
    buffer.write('\uFEFF'); // UTF-8 BOM — tells Excel/Artportalen to use UTF-8
    buffer.writeln(_headers.join(_sep));

    final startDate = _dateFormat.format(session.date);
    final startTime = _timeFormat.format(session.date);
    final endDate =
        session.endTime != null ? _dateFormat.format(session.endTime!) : '';
    final endTime =
        session.endTime != null ? _timeFormat.format(session.endTime!) : '';
    final lokalnamn = _escape(siteName ?? session.name);
    final huvudlokal = folderName != null ? _escape(folderName) : '';
    final noggrannhet = session.radiusMeters?.toString() ?? '';

    final useWgs84 = AppSettings.instance.coordSystem == CoordSystem.wgs84;
    final ost = useWgs84
        ? (session.wgs84Lon?.toStringAsFixed(6) ?? '')
        : (session.sweref99Easting?.round().toString() ?? '');
    final nord = useWgs84
        ? (session.wgs84Lat?.toStringAsFixed(6) ?? '')
        : (session.sweref99Northing?.round().toString() ?? '');

    for (final obs in observations) {
      final taxon = taxa[obs.taxonId];
      if (taxon == null) continue;

      final activities = activityObservations[obs.taxonId] ?? [];

      // Main observation row — only if count > 0.
      if (obs.count > 0) {
        buffer.writeln(_buildRow(
          taxon: taxon,
          count: obs.count,
          activity: '',
          stage: '',
          gender: '',
          lokalnamn: lokalnamn,
          huvudlokal: huvudlokal,
          ost: ost,
          nord: nord,
          noggrannhet: noggrannhet,
          startDate: startDate,
          startTime: startTime,
          endDate: endDate,
          endTime: endTime,
        ).join(_sep));
      }

      // One row per activity/stage/gender sub-record.
      for (final ao in activities) {
        if (ao.count == 0) continue;
        buffer.writeln(_buildRow(
          taxon: taxon,
          count: ao.count,
          activity: ao.activity,
          stage: ao.stage,
          gender: ao.gender,
          lokalnamn: lokalnamn,
          huvudlokal: huvudlokal,
          ost: ost,
          nord: nord,
          noggrannhet: noggrannhet,
          startDate: startDate,
          startTime: startTime,
          endDate: endDate,
          endTime: endTime,
        ).join(_sep));
      }
    }

    return buffer.toString();
  }

  List<String> _buildRow({
    required Taxon taxon,
    required int count,
    required String activity,
    required String stage,
    required String gender,
    required String lokalnamn,
    required String huvudlokal,
    required String ost,
    required String nord,
    required String noggrannhet,
    required String startDate,
    required String startTime,
    required String endDate,
    required String endTime,
  }) {
    final row = List<String>.filled(47, '');
    row[0] = _escape(taxon.swedishName); // Artnamn
    row[1] = count.toString();           // Antal
    row[2] = _escape(stage);             // Ålder-Stadium
    row[3] = _escape(gender);            // Kön
    row[4] = _escape(activity);          // Aktivitet
    // [5] Metod — empty
    row[6] = lokalnamn;                  // Lokalnamn
    row[7] = huvudlokal;                 // Huvudlokal
    row[8] = ost;                        // Ost
    row[9] = nord;                       // Nord
    row[10] = noggrannhet;               // Noggrannhet
    // [11] Diffusion — empty
    row[12] = startDate;                 // Startdatum
    row[13] = startTime;                 // Starttid
    row[14] = endDate;                   // Slutdatum
    row[15] = endTime;                   // Sluttid
    return row;
  }

  /// Wraps [value] in double-quotes if it contains the separator or a quote.
  String _escape(String value) {
    if (value.contains(_sep) || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
