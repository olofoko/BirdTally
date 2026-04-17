/// A species count with optional activity, ålder-stadium, kön, and
/// free-text comments — sub-record under an Observation.
class ActivityObservation {
  final int? id;
  final int sessionId;
  final int taxonId;
  final String activity;
  final String stage;
  final String gender;
  final String commentPublic;
  final String commentPrivate;
  final int count;

  const ActivityObservation({
    this.id,
    required this.sessionId,
    required this.taxonId,
    this.activity = '',
    this.stage = '',
    this.gender = '',
    this.commentPublic = '',
    this.commentPrivate = '',
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
      commentPublic: map['comment_public'] as String? ?? '',
      commentPrivate: map['comment_private'] as String? ?? '',
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
        'comment_public': commentPublic,
        'comment_private': commentPrivate,
        'count': count,
      };

  ActivityObservation copyWith({
    int? id,
    String? activity,
    String? stage,
    String? gender,
    String? commentPublic,
    String? commentPrivate,
    int? count,
  }) =>
      ActivityObservation(
        id: id ?? this.id,
        sessionId: sessionId,
        taxonId: taxonId,
        activity: activity ?? this.activity,
        stage: stage ?? this.stage,
        gender: gender ?? this.gender,
        commentPublic: commentPublic ?? this.commentPublic,
        commentPrivate: commentPrivate ?? this.commentPrivate,
        count: count ?? this.count,
      );

  /// Label shown in the tally list, combining non-empty activity/stage/gender.
  /// Comments are rendered separately by the row widget.
  String get label {
    final parts = [activity, stage, gender].where((s) => s.isNotEmpty).toList();
    return parts.join('  ');
  }

  bool get hasAnyComment =>
      commentPublic.isNotEmpty || commentPrivate.isNotEmpty;
}
