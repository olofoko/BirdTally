import 'package:flutter/foundation.dart';

import '../db/session_dao.dart';
import '../db/taxon_dao.dart';
import '../models/activity_observation.dart';
import '../models/observation.dart';
import '../models/session.dart';
import '../models/taxon.dart';

/// Manages observations and taxa for the currently active session.
///
/// Auto-saves every count change to the database immediately.
class TallyProvider extends ChangeNotifier {
  Session? _session;
  List<Observation> _observations = [];
  // taxon_id → list of activity sub-records
  Map<int, List<ActivityObservation>> _activityObservations = {};
  Map<int, Taxon> _taxa = {};
  bool _loading = true;

  Session? get session => _session;
  bool get loading => _loading;

  /// Observations that are pinned (shown in Aktuell lista), sorted by sort_order.
  List<Observation> get pinnedObservations {
    final pinned = _observations.where((o) => o.isPinned).toList();
    pinned.sort((a, b) {
      final ta = _taxa[a.taxonId];
      final tb = _taxa[b.taxonId];
      return (ta?.sortOrder ?? 0).compareTo(tb?.sortOrder ?? 0);
    });
    return pinned;
  }

  Taxon? taxonFor(int taxonId) => _taxa[taxonId];

  int countFor(int taxonId) {
    return _observations
        .firstWhere(
          (o) => o.taxonId == taxonId,
          orElse: () => Observation(
            sessionId: _session?.id ?? 0,
            taxonId: taxonId,
            count: 0,
          ),
        )
        .count;
  }

  /// Activity sub-records for a taxon, sorted by activity name.
  List<ActivityObservation> activityObservationsFor(int taxonId) {
    final list = List<ActivityObservation>.from(
        _activityObservations[taxonId] ?? []);
    list.sort((a, b) => a.activity.compareTo(b.activity));
    return list;
  }

  bool hasActivityObservations(int taxonId) =>
      (_activityObservations[taxonId]?.isNotEmpty) ?? false;

  /// Sum of own count + all activity sub-counts + all direct taxon children counts.
  int totalCountFor(int taxonId) {
    int total = countFor(taxonId);
    // Add activity sub-counts for this taxon.
    for (final ao in (_activityObservations[taxonId] ?? <ActivityObservation>[])) {
      total += ao.count;
    }
    // Add direct taxon children counts (underart etc.).
    for (final obs in _observations) {
      if (_taxa[obs.taxonId]?.parentTaxonId == taxonId) {
        total += obs.count;
        // Also add activity counts for those children.
        for (final ao in (_activityObservations[obs.taxonId] ?? <ActivityObservation>[])) {
          total += ao.count;
        }
      }
    }
    return total;
  }

  Future<void> load(Session session) async {
    _loading = true;
    _session = session;
    _observations = [];
    _activityObservations = {};
    _taxa = {};
    notifyListeners();

    _observations = await SessionDao.instance.getObservations(session.id!);
    _activityObservations =
        await SessionDao.instance.getActivityObservations(session.id!);

    // Collect all taxon IDs needed (observations + activity observations).
    final taxonIds = {
      ..._observations.map((o) => o.taxonId),
      ..._activityObservations.keys,
    }.toList();

    if (taxonIds.isNotEmpty) {
      final taxa = await TaxonDao.instance.getByIds(taxonIds);
      _taxa = {for (final t in taxa) t.taxonId: t};

      // Load parent taxa so child observations can show their parent row.
      final parentIds = taxa
          .where((t) => t.parentTaxonId != null)
          .map((t) => t.parentTaxonId!)
          .where((id) => !_taxa.containsKey(id))
          .toSet()
          .toList();
      if (parentIds.isNotEmpty) {
        final parents = await TaxonDao.instance.getByIds(parentIds);
        for (final p in parents) {
          _taxa[p.taxonId] = p;
        }
      }
    }

    _loading = false;
    notifyListeners();
  }

  Future<void> increment(int taxonId) => _adjust(taxonId, 1);

  Future<void> decrement(int taxonId) {
    if (countFor(taxonId) <= 0) return Future.value();
    return _adjust(taxonId, -1);
  }

  Future<void> incrementActivity(ActivityObservation ao) =>
      _adjustActivity(ao, 1);

  Future<void> decrementActivity(ActivityObservation ao) {
    if (ao.count <= 0) return Future.value();
    return _adjustActivity(ao, -1);
  }

  /// Adds an activity sub-record for a taxon (creates it with count 1).
  /// Also ensures the parent taxon is pinned.
  Future<void> addActivity(int taxonId, String activity) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, activity: activity, count: 0),
        1);
  }

  /// Adds a standalone ålder-stadium sub-row for a taxon.
  Future<void> addStage(int taxonId, String stage) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, stage: stage, count: 0),
        1);
  }

  /// Adds a standalone kön sub-row for a taxon.
  Future<void> addGender(int taxonId, String gender) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, gender: gender, count: 0),
        1);
  }

  /// Sets activity on an existing sub-row (merges if duplicate created).
  Future<void> setActivityOnSubRow(ActivityObservation ao, String activity) async {
    final updated =
        await SessionDao.instance.setSubRowProperties(ao, activity: activity);
    _replaceSubRow(ao, updated);
    notifyListeners();
  }

  /// Sets ålder-stadium on an existing sub-row (merges if duplicate created).
  Future<void> setStageOnSubRow(ActivityObservation ao, String stage) async {
    final updated =
        await SessionDao.instance.setSubRowProperties(ao, stage: stage);
    _replaceSubRow(ao, updated);
    notifyListeners();
  }

  /// Sets kön on an existing sub-row (merges if duplicate created).
  Future<void> setGenderOnSubRow(ActivityObservation ao, String gender) async {
    final updated =
        await SessionDao.instance.setSubRowProperties(ao, gender: gender);
    _replaceSubRow(ao, updated);
    notifyListeners();
  }

  void _replaceSubRow(ActivityObservation old, ActivityObservation updated) {
    final list =
        List<ActivityObservation>.from(_activityObservations[old.taxonId] ?? []);
    // Remove the old row (and any that now match the updated id, in case of merge).
    list.removeWhere((a) => a.id == old.id || a.id == updated.id);
    list.add(updated);
    _activityObservations[old.taxonId] = list;
  }

  /// Deletes a specific activity observation.
  Future<void> deleteActivityObservation(ActivityObservation obs) async {
    if (obs.id == null) return;
    await SessionDao.instance.deleteActivityObservation(obs.id!);
    final list = List<ActivityObservation>.from(
        _activityObservations[obs.taxonId] ?? []);
    list.removeWhere((a) => a.id == obs.id);
    _activityObservations[obs.taxonId] = list;
    if (list.isEmpty) _activityObservations.remove(obs.taxonId);
    notifyListeners();
  }

  Future<void> rename(String name) async {
    final updated = _session!.copyWith(name: name, updatedAt: DateTime.now());
    await SessionDao.instance.updateSession(updated);
    _session = updated;
    notifyListeners();
  }

  Future<void> setStartTime(DateTime dt) async {
    final updated = _session!.copyWith(date: dt, updatedAt: DateTime.now());
    await SessionDao.instance.updateSession(updated);
    _session = updated;
    notifyListeners();
  }

  Future<void> setEndTime(DateTime dt) async {
    final updated = _session!.copyWith(endTime: dt, updatedAt: DateTime.now());
    await SessionDao.instance.updateSession(updated);
    _session = updated;
    notifyListeners();
  }

  Future<void> clearEndTime() async {
    final updated = _session!.copyWith(clearEndTime: true, updatedAt: DateTime.now());
    await SessionDao.instance.updateSession(updated);
    _session = updated;
    notifyListeners();
  }

  /// Deletes a taxon's main observation and all its activity sub-records.
  Future<void> deleteObservation(int taxonId) async {
    final idx = _observations.indexWhere((o) => o.taxonId == taxonId);
    if (idx >= 0 && _observations[idx].id != null) {
      await SessionDao.instance.deleteObservation(_observations[idx].id!);
      _observations = List.of(_observations)..removeAt(idx);
    }
    // Activity observations are deleted via DB cascade, clear locally too.
    _activityObservations.remove(taxonId);
    notifyListeners();
  }

  /// Adds a taxon from the search panel: pins it and increments by 1.
  Future<void> addFromSearch(Taxon taxon) async {
    if (!_taxa.containsKey(taxon.taxonId)) {
      _taxa[taxon.taxonId] = taxon;
    }
    if (taxon.parentTaxonId != null &&
        !_taxa.containsKey(taxon.parentTaxonId)) {
      final parent = await TaxonDao.instance.getById(taxon.parentTaxonId!);
      if (parent != null) _taxa[parent.taxonId] = parent;
    }
    await _ensurePinned(taxon.taxonId);
  }

  Future<void> _ensurePinned(int taxonId) async {
    final idx = _observations.indexWhere((o) => o.taxonId == taxonId);
    if (idx < 0) {
      // No main observation yet — create a pinned one with count 0.
      final obs = Observation(
        sessionId: _session!.id!,
        taxonId: taxonId,
        count: 0,
        isPinned: true,
      );
      _observations = [..._observations, obs];
      notifyListeners();
      final saved = await SessionDao.instance.upsertObservation(obs);
      final i = _observations.indexWhere((o) => o.taxonId == taxonId);
      if (i >= 0) _observations = List.of(_observations)..[i] = saved;
    } else if (!_observations[idx].isPinned) {
      final obs = _observations[idx].copyWith(isPinned: true);
      _observations = List.of(_observations)..[idx] = obs;
      notifyListeners();
      await SessionDao.instance.upsertObservation(obs);
    }
  }

  Future<void> _adjust(int taxonId, int delta, {bool pin = false}) async {
    final idx = _observations.indexWhere((o) => o.taxonId == taxonId);
    Observation obs;

    if (idx >= 0) {
      final existing = _observations[idx];
      final newCount = (existing.count + delta).clamp(0, 9999).toInt();
      obs = existing.copyWith(
        count: newCount,
        isPinned: pin || existing.isPinned,
      );
      _observations = List.of(_observations)..[idx] = obs;
    } else {
      if (delta < 0) return;
      obs = Observation(
        sessionId: _session!.id!,
        taxonId: taxonId,
        count: delta,
        isPinned: true,
      );
      _observations = [..._observations, obs];
    }

    notifyListeners();

    final saved = await SessionDao.instance.upsertObservation(obs);
    final savedIdx = _observations.indexWhere((o) => o.taxonId == taxonId);
    if (savedIdx >= 0) {
      _observations = List.of(_observations)..[savedIdx] = saved;
    }
  }

  Future<void> _adjustActivity(ActivityObservation template, int delta) async {
    final taxonId = template.taxonId;
    final list = List<ActivityObservation>.from(
        _activityObservations[taxonId] ?? []);

    // Find by id if known, otherwise by composite key.
    final idx = template.id != null
        ? list.indexWhere((a) => a.id == template.id)
        : list.indexWhere((a) =>
            a.activity == template.activity &&
            a.stage == template.stage &&
            a.gender == template.gender);

    ActivityObservation obs;
    if (idx >= 0) {
      final newCount = (list[idx].count + delta).clamp(0, 9999).toInt();
      obs = list[idx].copyWith(count: newCount);
      list[idx] = obs;
    } else {
      if (delta < 0) return;
      obs = ActivityObservation(
        sessionId: _session!.id!,
        taxonId: taxonId,
        activity: template.activity,
        stage: template.stage,
        gender: template.gender,
        count: delta,
      );
      list.add(obs);
    }

    _activityObservations[taxonId] = list;
    notifyListeners();

    final saved = await SessionDao.instance.upsertActivityObservation(obs);
    final savedList = List<ActivityObservation>.from(
        _activityObservations[taxonId] ?? []);
    final savedIdx = saved.id != null
        ? savedList.indexWhere((a) => a.id == saved.id)
        : savedList.indexWhere((a) =>
            a.activity == saved.activity &&
            a.stage == saved.stage &&
            a.gender == saved.gender);
    if (savedIdx >= 0) {
      savedList[savedIdx] = saved;
      _activityObservations[taxonId] = savedList;
    }
  }
}
