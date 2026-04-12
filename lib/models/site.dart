/// A survey site (Lokal) — a named location that holds one or more Besök.
class Site {
  final int? id;
  final int? folderId; // null → Lösa lokaler
  final String name;
  final String? landskap; // Swedish province abbreviation, e.g. 'Sk'
  final double? sweref99Northing;
  final double? sweref99Easting;
  final int? radiusMeters;
  final double? wgs84Lat;
  final double? wgs84Lon;
  final DateTime createdAt;

  const Site({
    this.id,
    this.folderId,
    required this.name,
    this.landskap,
    this.sweref99Northing,
    this.sweref99Easting,
    this.radiusMeters,
    this.wgs84Lat,
    this.wgs84Lon,
    required this.createdAt,
  });

  bool get hasLocation => sweref99Northing != null && sweref99Easting != null;

  factory Site.fromMap(Map<String, dynamic> map) {
    return Site(
      id: map['id'] as int?,
      folderId: map['folder_id'] as int?,
      name: map['name'] as String,
      landskap: map['landskap'] as String?,
      sweref99Northing: map['sweref99_northing'] as double?,
      sweref99Easting: map['sweref99_easting'] as double?,
      radiusMeters: map['radius_m'] as int?,
      wgs84Lat: map['wgs84_lat'] as double?,
      wgs84Lon: map['wgs84_lon'] as double?,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }

  Map<String, dynamic> toMap() => {
        if (id != null) 'id': id,
        'folder_id': folderId,
        'name': name,
        'landskap': landskap,
        'sweref99_northing': sweref99Northing,
        'sweref99_easting': sweref99Easting,
        'radius_m': radiusMeters,
        'wgs84_lat': wgs84Lat,
        'wgs84_lon': wgs84Lon,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  Site copyWith({
    int? id,
    int? folderId,
    String? name,
    String? landskap,
    double? sweref99Northing,
    double? sweref99Easting,
    int? radiusMeters,
    double? wgs84Lat,
    double? wgs84Lon,
    bool clearFolder = false,
    bool clearLandskap = false,
    bool clearLocation = false,
  }) =>
      Site(
        id: id ?? this.id,
        folderId: clearFolder ? null : (folderId ?? this.folderId),
        name: name ?? this.name,
        landskap: clearLandskap ? null : (landskap ?? this.landskap),
        sweref99Northing: clearLocation ? null : (sweref99Northing ?? this.sweref99Northing),
        sweref99Easting: clearLocation ? null : (sweref99Easting ?? this.sweref99Easting),
        radiusMeters: clearLocation ? null : (radiusMeters ?? this.radiusMeters),
        wgs84Lat: clearLocation ? null : (wgs84Lat ?? this.wgs84Lat),
        wgs84Lon: clearLocation ? null : (wgs84Lon ?? this.wgs84Lon),
        createdAt: createdAt,
      );
}
