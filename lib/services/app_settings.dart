import 'package:shared_preferences/shared_preferences.dart';

enum CoordSystem { sweref99, wgs84 }

/// Persistent app-level settings backed by SharedPreferences.
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  static const _keyCoordSystem = 'coord_system';

  CoordSystem _coordSystem = CoordSystem.sweref99;
  CoordSystem get coordSystem => _coordSystem;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_keyCoordSystem);
    if (value == 'wgs84') {
      _coordSystem = CoordSystem.wgs84;
    } else {
      _coordSystem = CoordSystem.sweref99;
    }
  }

  Future<void> setCoordSystem(CoordSystem system) async {
    _coordSystem = system;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyCoordSystem, system.name);
  }
}
