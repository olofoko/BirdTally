import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../utils/sweref99.dart';
import 'map_location_picker.dart';

/// Result returned by [showLocationDialog].
class LocationResult {
  final double wgs84Lat;
  final double wgs84Lon;
  final double northing;
  final double easting;
  final int radiusMeters;

  const LocationResult({
    required this.wgs84Lat,
    required this.wgs84Lon,
    required this.northing,
    required this.easting,
    required this.radiusMeters,
  });
}

/// Shows a location prompt after creating a new Lokal.
/// Returns [LocationResult] if the user accepted, null if skipped.
Future<LocationResult?> showLocationDialog(BuildContext context) async {
  // Check/request permission first.
  LocationPermission permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  if (permission == LocationPermission.denied ||
      permission == LocationPermission.deniedForever) {
    return null;
  }

  if (!context.mounted) return null;

  return showDialog<LocationResult>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _LocationDialog(),
  );
}

// ---------------------------------------------------------------------------

class _LocationDialog extends StatefulWidget {
  const _LocationDialog();

  @override
  State<_LocationDialog> createState() => _LocationDialogState();
}

class _LocationDialogState extends State<_LocationDialog> {
  bool _fetching = true;
  String? _error;
  Position? _position;

  // Radius picker state
  int _radiusMeters = 100;

  @override
  void initState() {
    super.initState();
    _fetchPosition();
  }

  Future<void> _fetchPosition() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 15),
      );
      if (mounted) setState(() { _position = pos; _fetching = false; });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _fetching = false; });
    }
  }

  void _confirm() {
    final pos = _position!;
    final (northing, easting) = Sweref99.fromWgs84(pos.latitude, pos.longitude);
    Navigator.pop(
      context,
      LocationResult(
        wgs84Lat: pos.latitude,
        wgs84Lon: pos.longitude,
        northing: northing,
        easting: easting,
        radiusMeters: _radiusMeters,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Plats för lokalen'),
      content: _fetching
          ? const SizedBox(
              height: 80,
              child: Center(child: CircularProgressIndicator()),
            )
          : _error != null
              ? Text('Kunde inte hämta position.\n$_error')
              : _position == null
                  ? const Text('Ingen position tillgänglig.')
                  : _buildContent(),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Hoppa över'),
        ),
        if (!_fetching && _position != null)
          TextButton(
            onPressed: _confirm,
            child: const Text('Använd'),
          ),
      ],
    );
  }

  Future<void> _openMap() async {
    final result = await showMapLocationPicker(
      context,
      initialLat: _position!.latitude,
      initialLon: _position!.longitude,
      initialRadius: _radiusMeters,
    );
    if (result != null && mounted) {
      // Override position with what the user picked on the map.
      setState(() {
        _position = Position(
          latitude: result.wgs84Lat,
          longitude: result.wgs84Lon,
          timestamp: _position!.timestamp,
          accuracy: _position!.accuracy,
          altitude: _position!.altitude,
          altitudeAccuracy: _position!.altitudeAccuracy,
          heading: _position!.heading,
          headingAccuracy: _position!.headingAccuracy,
          speed: _position!.speed,
          speedAccuracy: _position!.speedAccuracy,
        );
        _radiusMeters = result.radiusMeters;
      });
    }
  }

  Widget _buildContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Aktuell plats hittad.'),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.map_outlined),
          label: const Text('Visa på karta'),
          onPressed: _openMap,
        ),
        const SizedBox(height: 20),
        Text(
          'Noggrannhet (lokalens radie)',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        _RadiusPicker(
          value: _radiusMeters,
          onChanged: (v) => setState(() => _radiusMeters = v),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------

class _RadiusPicker extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;

  static const _options = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000];

  const _RadiusPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: _options.map((r) {
        final label = r >= 1000 ? '${r ~/ 1000} km' : '$r m';
        return ChoiceChip(
          label: Text(label),
          selected: value == r,
          onSelected: (_) => onChanged(r),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}
