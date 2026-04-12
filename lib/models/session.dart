/// A single field session (Besök) with location, metadata and species counts.
class Session {
  final int? id;
  final int? siteId;   // null → Lös lista (standalone, no site)
  final String name;
  final DateTime date;
  final String? region;

  // Location — SWEREF 99 TM (EPSG:3006)
  final double? sweref99Northing;
  final double? sweref99Easting;
  final int? radiusMeters;

  // Original WGS84 coordinates (stored to avoid round-trip conversion)
  final double? wgs84Lat;
  final double? wgs84Lon;

  final DateTime? endTime;
  final bool isTemplate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Session({
    this.id,
    this.siteId,
    required this.name,
    required this.date,
    this.region,
    this.sweref99Northing,
    this.sweref99Easting,
    this.radiusMeters,
    this.wgs84Lat,
    this.wgs84Lon,
    this.endTime,
    this.isTemplate = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasLocation =>
      sweref99Northing != null && sweref99Easting != null;

  String get locationString {
    if (!hasLocation) return '';
    final n = sweref99Northing!.round();
    final e = sweref99Easting!.round();
    final r = radiusMeters != null ? ' r ${_formatRadius(radiusMeters!)}' : '';
    return 'N $n E $e$r';
  }

  String _formatRadius(int meters) {
    if (meters >= 1000 && meters % 1000 == 0) return '${meters ~/ 1000} km';
    return '$meters m';
  }

  factory Session.fromMap(Map<String, dynamic> map) {
    return Session(
      id: map['id'] as int?,
      siteId: map['site_id'] as int?,
      name: map['name'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      region: map['region'] as String?,
      sweref99Northing: map['sweref99_northing'] as double?,
      sweref99Easting: map['sweref99_easting'] as double?,
      radiusMeters: map['radius_m'] as int?,
      wgs84Lat: map['wgs84_lat'] as double?,
      wgs84Lon: map['wgs84_lon'] as double?,
      endTime: map['end_time'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['end_time'] as int)
          : null,
      isTemplate: (map['is_template'] as int) == 1,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'site_id': siteId,
        'name': name,
        'date': date.millisecondsSinceEpoch,
        'region': region,
        'sweref99_northing': sweref99Northing,
        'sweref99_easting': sweref99Easting,
        'radius_m': radiusMeters,
        'wgs84_lat': wgs84Lat,
        'wgs84_lon': wgs84Lon,
        'end_time': endTime?.millisecondsSinceEpoch,
        'is_template': isTemplate ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  Session copyWith({
    int? id,
    int? siteId,
    String? name,
    DateTime? date,
    String? region,
    double? sweref99Northing,
    double? sweref99Easting,
    int? radiusMeters,
    double? wgs84Lat,
    double? wgs84Lon,
    DateTime? endTime,
    bool? isTemplate,
    DateTime? updatedAt,
    bool clearSite = false,
    bool clearLocation = false,
    bool clearEndTime = false,
  }) {
    return Session(
      id: id ?? this.id,
      siteId: clearSite ? null : (siteId ?? this.siteId),
      name: name ?? this.name,
      date: date ?? this.date,
      region: region ?? this.region,
      sweref99Northing: clearLocation ? null : (sweref99Northing ?? this.sweref99Northing),
      sweref99Easting: clearLocation ? null : (sweref99Easting ?? this.sweref99Easting),
      radiusMeters: clearLocation ? null : (radiusMeters ?? this.radiusMeters),
      wgs84Lat: clearLocation ? null : (wgs84Lat ?? this.wgs84Lat),
      wgs84Lon: clearLocation ? null : (wgs84Lon ?? this.wgs84Lon),
      endTime: clearEndTime ? null : (endTime ?? this.endTime),
      isTemplate: isTemplate ?? this.isTemplate,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
