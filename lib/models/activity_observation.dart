/// A species count with optional activity, ålder-stadium, and kön — sub-record under an Observation.
class ActivityObservation {
  final int? id;
  final int sessionId;
  final int taxonId;
  final String activity;
  final String stage;
  final String gender;
  final int count;

  const ActivityObservation({
    this.id,
    required this.sessionId,
    required this.taxonId,
    this.activity = '',
    this.stage = '',
    this.gender = '',
    required this.count,
  });

  factory ActivityObservation.fromMap(Map<String, dynamic> map) {
    return ActivityObservation(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      taxonId: map['taxon_id'] as int,
      activity: map['activity'] as String? ?? '',
      stage: map['stage'] as String? ?? '',
      gender: map['gender'] as String? ?? '',
      count: map['count'] as int,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'taxon_id': taxonId,
        'activity': activity,
        'stage': stage,
        'gender': gender,
        'count': count,
      };

  ActivityObservation copyWith({
    int? id,
    String? activity,
    String? stage,
    String? gender,
    int? count,
  }) =>
      ActivityObservation(
        id: id ?? this.id,
        sessionId: sessionId,
        taxonId: taxonId,
        activity: activity ?? this.activity,
        stage: stage ?? this.stage,
        gender: gender ?? this.gender,
        count: count ?? this.count,
      );

  /// Label shown in the tally list, combining non-empty fields.
  String get label {
    final parts = [activity, stage, gender].where((s) => s.isNotEmpty).toList();
    return parts.join('  ');
  }
}
