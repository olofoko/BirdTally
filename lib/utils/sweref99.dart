import 'dart:math';

/// Converts WGS84 geographic coordinates to SWEREF 99 TM (EPSG:3006).
///
/// SWEREF 99 TM parameters:
///   Ellipsoid : GRS80  (a = 6 378 137 m, f = 1/298.257222101)
///   Central meridian : 15° E
///   Scale factor k₀  : 1.0
///   False easting     : 500 000 m
///   False northing    : 0 m
class Sweref99 {
  Sweref99._();

  // GRS80 ellipsoid
  static const double _a = 6378137.0;
  static const double _f = 1.0 / 298.257222101;
  static const double _e2 = _f * (2 - _f);

  // SWEREF 99 TM projection constants
  static const double _k0 = 1.0;
  static const double _lon0 = 15.0 * pi / 180.0; // central meridian in radians
  static const double _falseEasting = 500000.0;
  static const double _falseNorthing = 0.0;

  /// Returns [northing, easting] in metres (SWEREF 99 TM).
  static (double northing, double easting) fromWgs84(double latDeg, double lonDeg) {
    final lat = latDeg * pi / 180.0;
    final lon = lonDeg * pi / 180.0;

    const e2 = _e2;
    final n = _a / sqrt(1 - e2 * sin(lat) * sin(lat));

    final t = tan(lat);
    final t2 = t * t;
    final c = e2 / (1 - e2) * cos(lat) * cos(lat);
    final a_ = (lon - _lon0) * cos(lat);

    // Meridional arc
    const e4 = e2 * e2;
    const e6 = e4 * e2;
    final m = _a *
        ((1 - e2 / 4 - 3 * e4 / 64 - 5 * e6 / 256) * lat -
            (3 * e2 / 8 + 3 * e4 / 32 + 45 * e6 / 1024) * sin(2 * lat) +
            (15 * e4 / 256 + 45 * e6 / 1024) * sin(4 * lat) -
            (35 * e6 / 3072) * sin(6 * lat));

    final easting = _falseEasting +
        _k0 *
            n *
            (a_ +
                (1 - t2 + c) * pow(a_, 3) / 6 +
                (5 - 18 * t2 + t2 * t2 + 72 * c - 58 * e2 / (1 - e2)) *
                    pow(a_, 5) /
                    120);

    final northing = _falseNorthing +
        _k0 *
            (m +
                n *
                    tan(lat) *
                    (pow(a_, 2) / 2 +
                        (5 - t2 + 9 * c + 4 * c * c) * pow(a_, 4) / 24 +
                        (61 - 58 * t2 + t2 * t2 + 600 * c - 330 * e2 / (1 - e2)) *
                            pow(a_, 6) /
                            720));

    return (northing, easting);
  }
}
