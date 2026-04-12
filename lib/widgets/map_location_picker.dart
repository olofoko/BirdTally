import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/sweref99.dart';
import 'location_dialog.dart';

/// Full-screen map picker using Leaflet.js / OpenStreetMap.
/// Returns [LocationResult] on confirm, null on cancel.
Future<LocationResult?> showMapLocationPicker(
  BuildContext context, {
  required double initialLat,
  required double initialLon,
  required int initialRadius,
}) {
  return Navigator.of(context).push<LocationResult>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _MapLocationPicker(
        initialLat: initialLat,
        initialLon: initialLon,
        initialRadius: initialRadius,
      ),
    ),
  );
}

// ---------------------------------------------------------------------------

class _MapLocationPicker extends StatefulWidget {
  final double initialLat;
  final double initialLon;
  final int initialRadius;

  const _MapLocationPicker({
    required this.initialLat,
    required this.initialLon,
    required this.initialRadius,
  });

  @override
  State<_MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<_MapLocationPicker> {
  late double _lat;
  late double _lon;
  late int _radius;
  late final WebViewController _controller;
  bool _mapReady = false;

  static const _radiusOptions = [10, 25, 50, 100, 250, 500, 1000, 2500, 5000];

  @override
  void initState() {
    super.initState();
    _lat = widget.initialLat;
    _lon = widget.initialLon;
    _radius = widget.initialRadius;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel(
        'LocationChannel',
        onMessageReceived: (msg) {
          final data = jsonDecode(msg.message) as Map<String, dynamic>;
          setState(() {
            _lat = (data['lat'] as num).toDouble();
            _lon = (data['lng'] as num).toDouble();
          });
        },
      )
      ..addJavaScriptChannel(
        'ReadyChannel',
        onMessageReceived: (_) => setState(() => _mapReady = true),
      )
      ..loadHtmlString(_buildHtml());
  }

  String _buildHtml() => '''
<!DOCTYPE html>
<html>
<head>
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
  <link rel="stylesheet" href="https://unpkg.com/leaflet@1.9.4/dist/leaflet.css"/>
  <script src="https://unpkg.com/leaflet@1.9.4/dist/leaflet.js"></script>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body, html { width: 100%; height: 100%; }
    #map { width: 100%; height: 100%; }
  </style>
</head>
<body>
  <div id="map"></div>
  <script>
    var lat = $_lat, lng = $_lon, radius = $_radius;
    var map = L.map('map', { zoomControl: true }).setView([lat, lng], 14);
    L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', {
      attribution: '&copy; OpenStreetMap contributors',
      maxZoom: 19
    }).addTo(map);

    var marker = L.marker([lat, lng], { draggable: true }).addTo(map);
    var circle = L.circle([lat, lng], {
      radius: radius,
      color: '#1976D2',
      fillColor: '#1976D2',
      fillOpacity: 0.15,
      weight: 2
    }).addTo(map);

    function updatePosition(newLat, newLng) {
      lat = newLat; lng = newLng;
      marker.setLatLng([lat, lng]);
      circle.setLatLng([lat, lng]);
      LocationChannel.postMessage(JSON.stringify({ lat: lat, lng: lng }));
    }

    marker.on('dragend', function() {
      var p = marker.getLatLng();
      updatePosition(p.lat, p.lng);
    });

    map.on('click', function(e) {
      updatePosition(e.latlng.lat, e.latlng.lng);
    });

    function updateRadius(r) {
      radius = r;
      circle.setRadius(r);
    }

    function centerOn(newLat, newLng) {
      updatePosition(newLat, newLng);
      map.setView([newLat, newLng], 15);
    }

    ReadyChannel.postMessage('ready');
  </script>
</body>
</html>
''';

  void _onRadiusChanged(int r) {
    setState(() => _radius = r);
    if (_mapReady) {
      _controller.runJavaScript('updateRadius($r)');
    }
  }

  Future<void> _recenterOnGps() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
        timeLimit: const Duration(seconds: 10),
      );
      _controller.runJavaScript('centerOn(${pos.latitude}, ${pos.longitude})');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kunde inte hämta GPS-position.')),
        );
      }
    }
  }

  void _confirm() {
    final (northing, easting) = Sweref99.fromWgs84(_lat, _lon);
    Navigator.pop(
      context,
      LocationResult(
        wgs84Lat: _lat,
        wgs84Lon: _lon,
        northing: northing,
        easting: easting,
        radiusMeters: _radius,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Välj plats'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            tooltip: 'Centrera på GPS',
            onPressed: _recenterOnGps,
          ),
          TextButton(
            onPressed: _confirm,
            child: const Text('Klar'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: WebViewWidget(controller: _controller)),
          _RadiusBar(
            value: _radius,
            options: _radiusOptions,
            onChanged: _onRadiusChanged,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _RadiusBar extends StatelessWidget {
  final int value;
  final List<int> options;
  final ValueChanged<int> onChanged;

  const _RadiusBar({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: EdgeInsets.fromLTRB(12, 8, 12, 12 + MediaQuery.of(context).padding.bottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Noggrannhet (radie)',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 6),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: options.map((r) {
                final label = r >= 1000 ? '${r ~/ 1000} km' : '$r m';
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: value == r,
                    onSelected: (_) => onChanged(r),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}
