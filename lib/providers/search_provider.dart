import 'package:flutter/foundation.dart';

import '../db/taxon_dao.dart';
import '../models/taxon.dart';

/// Manages search query, category toggles, and result list for the tally
/// screen's search/browse panel.
///
/// Toggles (Underarter, Komplex, Hybrider) persist for the lifetime of this
/// provider (i.e. for the current session screen).
class SearchProvider extends ChangeNotifier {
  String _query = '';
  bool includeUnderart = false;
  bool includeKomplex = false;
  bool includeHybrider = false;

  List<Taxon> _browseList = [];
  List<Taxon> _searchResults = [];
  bool _searching = false;

  String get query => _query;
  bool get hasQuery => _query.isNotEmpty;
  bool get searching => _searching;

  /// When query is empty: returns the 248-species browse list.
  /// When query is non-empty: returns search results.
  List<Taxon> get results => hasQuery ? _searchResults : _browseList;

  Future<void> init() async {
    _browseList = await TaxonDao.instance.getBrowseList();
    notifyListeners();
  }

  Future<void> setQuery(String q) async {
    _query = q;
    if (q.isEmpty) {
      _searchResults = [];
      _searching = false;
      notifyListeners();
      return;
    }
    _searching = true;
    notifyListeners();
    _searchResults = await TaxonDao.instance.search(
      q,
      includeUnderart: includeUnderart,
      includeKomplex: includeKomplex,
      includeHybrider: includeHybrider,
    );
    _searching = false;
    notifyListeners();
  }

  void setToggle(String toggle, bool value) {
    switch (toggle) {
      case 'underart':
        includeUnderart = value;
      case 'komplex':
        includeKomplex = value;
      case 'hybrid':
        includeHybrider = value;
    }
    notifyListeners();
    if (hasQuery) setQuery(_query); // re-run search with new toggles
  }

  void clear() {
    _query = '';
    _searchResults = [];
    _searching = false;
    notifyListeners();
  }
}
