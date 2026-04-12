import '../models/taxon.dart';
import 'app_database.dart';

/// Data access for the read-only taxa database.
class TaxonDao {
  TaxonDao._();
  static final TaxonDao instance = TaxonDao._();

  Future<List<Taxon>> getBrowseList() async {
    final db = await AppDatabase.instance.taxaDb;
    final rows = await db.query(
      'taxa',
      where: 'in_browse_list = 1',
      orderBy: 'sort_order ASC',
    );
    return rows.map(Taxon.fromMap).toList();
  }

  /// Full-text search across Swedish and scientific names.
  ///
  /// [includeUnderart]    — include Underart in results
  /// [includeKomplex]     — include Artkomplex and Kollektivtaxon
  /// [includeHybrider]    — include Hybrid
  /// Pseudotaxon is always included but sorted to the end.
  Future<List<Taxon>> search(
    String query, {
    bool includeUnderart = false,
    bool includeKomplex = false,
    bool includeHybrider = false,
  }) async {
    final db = await AppDatabase.instance.taxaDb;
    final q = '%${query.toLowerCase()}%';

    final allowedCategories = <String>['Art'];
    if (includeUnderart) allowedCategories.add('Underart');
    if (includeKomplex) {
      allowedCategories.addAll(['Artkomplex', 'Kollektivtaxon']);
    }
    if (includeHybrider) allowedCategories.add('Hybrid');
    // Pseudotaxon always included but added after — we handle ordering below.
    allowedCategories.add('Pseudotaxon');

    final placeholders = allowedCategories.map((_) => '?').join(', ');

    // Two queries: matching taxa first, Pseudotaxon last.
    final rows = await db.rawQuery('''
      SELECT *,
        CASE WHEN category = 'Pseudotaxon' THEN 1 ELSE 0 END AS _is_pseudo,
        CASE
          WHEN LOWER(swedish_name) LIKE ?    THEN 0
          WHEN LOWER(scientific_name) LIKE ? THEN 1
          ELSE 2
        END AS _match_rank
      FROM taxa
      WHERE
        (LOWER(swedish_name) LIKE ? OR LOWER(scientific_name) LIKE ?)
        AND category IN ($placeholders)
      ORDER BY _is_pseudo ASC, _match_rank ASC, sort_order ASC
    ''', [q, q, q, q, ...allowedCategories]);

    return rows.map(Taxon.fromMap).toList();
  }

  Future<Taxon?> getById(int taxonId) async {
    final db = await AppDatabase.instance.taxaDb;
    final rows = await db.query('taxa', where: 'taxon_id = ?', whereArgs: [taxonId]);
    if (rows.isEmpty) return null;
    return Taxon.fromMap(rows.first);
  }

  /// Returns all Underart (and Artkomplex/Kollektivtaxon) children of a parent.
  Future<List<Taxon>> getChildren(int parentTaxonId) async {
    final db = await AppDatabase.instance.taxaDb;
    final rows = await db.query(
      'taxa',
      where: 'parent_taxon_id = ?',
      whereArgs: [parentTaxonId],
      orderBy: 'sort_order ASC',
    );
    return rows.map(Taxon.fromMap).toList();
  }

  Future<List<Taxon>> getByIds(List<int> taxonIds) async {
    if (taxonIds.isEmpty) return [];
    final db = await AppDatabase.instance.taxaDb;
    final placeholders = taxonIds.map((_) => '?').join(', ');
    final rows = await db.rawQuery(
      'SELECT * FROM taxa WHERE taxon_id IN ($placeholders) ORDER BY sort_order ASC',
      taxonIds,
    );
    return rows.map(Taxon.fromMap).toList();
  }
}
