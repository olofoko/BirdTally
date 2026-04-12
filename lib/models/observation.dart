/// A species count within a session.
///
/// [isPinned] — true when the species has been explicitly added to the tally
/// (count > 0, or pinned via the browse list). Pinned observations appear
/// in Aktuell lista even if the count is later set back to 0.
class Observation {
  final int? id;
  final int sessionId;
  final int taxonId;
  final int count;
  final bool isPinned;

  const Observation({
    this.id,
    required this.sessionId,
    required this.taxonId,
    required this.count,
    this.isPinned = false,
  });

  factory Observation.fromMap(Map<String, dynamic> map) {
    return Observation(
      id: map['id'] as int?,
      sessionId: map['session_id'] as int,
      taxonId: map['taxon_id'] as int,
      count: map['count'] as int,
      isPinned: (map['is_pinned'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'session_id': sessionId,
        'taxon_id': taxonId,
        'count': count,
        'is_pinned': isPinned ? 1 : 0,
      };

  Observation copyWith({int? id, int? count, bool? isPinned}) => Observation(
        id: id ?? this.id,
        sessionId: sessionId,
        taxonId: taxonId,
        count: count ?? this.count,
        isPinned: isPinned ?? this.isPinned,
      );
}
