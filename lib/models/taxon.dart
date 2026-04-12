/// A single taxon from the Dyntaxa/Artdatabanken database.
class Taxon {
  final int taxonId;
  final int? sortOrder;
  final String scientificName;
  final String swedishName;
  final TaxonCategory category;
  final String? redListCategory;
  final String? redListCriteria;
  final bool isBirdsDirective;
  final bool isForestryPriority;
  final bool inBrowseList;
  final int? parentTaxonId;

  const Taxon({
    required this.taxonId,
    this.sortOrder,
    required this.scientificName,
    required this.swedishName,
    required this.category,
    this.redListCategory,
    this.redListCriteria,
    required this.isBirdsDirective,
    required this.isForestryPriority,
    required this.inBrowseList,
    this.parentTaxonId,
  });

  factory Taxon.fromMap(Map<String, dynamic> map) {
    return Taxon(
      taxonId: map['taxon_id'] as int,
      sortOrder: map['sort_order'] as int?,
      scientificName: map['scientific_name'] as String,
      swedishName: map['swedish_name'] as String,
      category: TaxonCategory.fromString(map['category'] as String),
      redListCategory: map['red_list_category'] as String?,
      redListCriteria: map['red_list_criteria'] as String?,
      isBirdsDirective: (map['is_birds_directive'] as int) == 1,
      isForestryPriority: (map['is_forestry_priority'] as int) == 1,
      inBrowseList: (map['in_browse_list'] as int) == 1,
      parentTaxonId: map['parent_taxon_id'] as int?,
    );
  }

  /// Whether this taxon has a meaningful red list badge to display.
  bool get hasRedListBadge {
    if (redListCategory == null) return false;
    const badged = {'LC', 'CR', 'CR°', 'EN', 'NT', 'NT°', 'VU', 'DD', 'RE', 'NE', 'NA'};
    return badged.contains(redListCategory);
  }
}

enum TaxonCategory {
  art,
  underart,
  hybrid,
  artkomplex,
  kollektivtaxon,
  pseudotaxon;

  static TaxonCategory fromString(String s) {
    return switch (s) {
      'Art' => art,
      'Underart' => underart,
      'Hybrid' => hybrid,
      'Artkomplex' => artkomplex,
      'Kollektivtaxon' => kollektivtaxon,
      'Pseudotaxon' => pseudotaxon,
      _ => throw ArgumentError('Unknown TaxonCategory: $s'),
    };
  }

  String get label => switch (this) {
        art => 'Art',
        underart => 'Underart',
        hybrid => 'Hybrid',
        artkomplex => 'Artkomplex',
        kollektivtaxon => 'Kollektivtaxon',
        pseudotaxon => 'Grupp',
      };

  /// True if this category is indented under a parent in the tally list.
  bool get isChild =>
      this == underart || this == artkomplex || this == kollektivtaxon;
}
