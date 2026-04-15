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
  bool _subRowHintShown = false;

  Session? get session => _session;
  bool get loading => _loading;
  bool get subRowHintShown => _subRowHintShown;

  void markSubRowHintShown() {
    _subRowHintShown = true;
  }

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
    for (final ao in (_activityObservations[taxonId] ?? <ActivityObservation>[])) {
      total += ao.count;
    }
    for (final obs in _observations) {
      if (_taxa[obs.taxonId]?.parentTaxonId == taxonId) {
        total += obs.count;
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
    _subRowHintShown = false;
    notifyListeners();

    _observations = await SessionDao.instance.getObservations(session.id!);
    _activityObservations =
        await SessionDao.instance.getActivityObservations(session.id!);

    final taxonIds = {
      ..._observations.map((o) => o.taxonId),
      ..._activityObservations.keys,
    }.toList();

    if (taxonIds.isNotEmpty) {
      final taxa = await TaxonDao.instance.getByIds(taxonIds);
      _taxa = {for (final t in taxa) t.taxonId: t};

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

  Future<void> addActivity(int taxonId, String activity) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, activity: activity, count: 0),
        1);
  }

  Future<void> addStage(int taxonId, String stage) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, stage: stage, count: 0),
        1);
  }

  Future<void> addGender(int taxonId, String gender) async {
    await _ensurePinned(taxonId);
    await _adjustActivity(
        ActivityObservation(
            sessionId: _session!.id!, taxonId: taxonId, gender: gender, count: 0),
        1);
  }

  Future<void> setActivityOnSubRow(ActivityObservation ao, String activity) async {
    final fresh = _freshSubRow(ao);
    final updated =
        await SessionDao.instance.setSubRowProperties(fresh, activity: activity);
    _replaceSubRow(fresh, updated);
    notifyListeners();
  }

  Future<void> setStageOnSubRow(ActivityObservation ao, String stage) async {
    final fresh = _freshSubRow(ao);
    final updated =
        await SessionDao.instance.setSubRowProperties(fresh, stage: stage);
    _replaceSubRow(fresh, updated);
    notifyListeners();
  }

  Future<void> setGenderOnSubRow(ActivityObservation ao, String gender) async {
    final fresh = _freshSubRow(ao);
    final updated =
        await SessionDao.instance.setSubRowProperties(fresh, gender: gender);
    _replaceSubRow(fresh, updated);
    notifyListeners();
  }

  /// Looks up the current in-memory version of [ao] so callers that hold a
  /// stale closure reference (possibly with id=null) always operate on the
  /// row that has the real DB id.
  ActivityObservation _freshSubRow(ActivityObservation ao) {
    final list = _activityObservations[ao.taxonId] ?? [];
    if (ao.id != null) {
      final byId = list.firstWhere((a) => a.id == ao.id, orElse: () => ao);
      return byId;
    }
    return list.firstWhere(
      (a) => a.activity == ao.activity && a.stage == ao.stage && a.gender == ao.gender,
      orElse: () => ao,
    );
  }

  void _replaceSubRow(ActivityObservation old, ActivityObservation updated) {
    final list =
        List<ActivityObservation>.from(_activityObservations[old.taxonId] ?? []);
    list.removeWhere((a) => a.id == old.id || a.id == updated.id);
    list.add(updated);
    _activityObservations[old.taxonId] = list;
  }

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

  Future<void> deleteObservation(int taxonId) async {
    final idx = _observations.indexWhere((o) => o.taxonId == taxonId);
    if (idx >= 0 && _observations[idx].id != null) {
      await SessionDao.instance.deleteObservation(_observations[idx].id!);
      _observations = List.of(_observations)..removeAt(idx);
    }
    _activityObservations.remove(taxonId);
    notifyListeners();
  }

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
    int savedIdx = saved.id != null
        ? savedList.indexWhere((a) => a.id == saved.id)
        : -1;
    if (savedIdx < 0) {
      savedIdx = savedList.indexWhere((a) =>
          a.activity == saved.activity &&
          a.stage == saved.stage &&
          a.gender == saved.gender);
    }
    if (savedIdx >= 0) {
      savedList[savedIdx] = saved;
      _activityObservations[taxonId] = savedList;
      notifyListeners();
    }
  }
}
