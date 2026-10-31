import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

/// Free OpenStreetMap map (no API key). Needs internet on the phone.
class OsmMap extends StatelessWidget {
  final LatLng center;
  final double zoom;
  final List<Marker> markers;

  const OsmMap({
    super.key,
    required this.center,
    this.zoom = 14,
    required this.markers,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      options: MapOptions(initialCenter: center, initialZoom: zoom),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.aers_app',
        ),
        MarkerLayer(markers: markers),
        RichAttributionWidget(
          attributions: [
            TextSourceAttribution('OpenStreetMap contributors'),
          ],
        ),
      ],
    );
  }
}

/// A coloured icon pin for the map.
Marker pin(LatLng p, IconData icon, Color color) => Marker(
      point: p,
      width: 44,
      height: 44,
      child: Icon(icon, color: color, size: 36),
    );
