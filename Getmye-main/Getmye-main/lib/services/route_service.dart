import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteService {
  // Cache to avoid spamming the routing server repeatedly for the same start/end
  static final Map<String, List<LatLng>> _routeCache = {};

  /// Fetches the real road route coordinates using OSRM Open Routing API
  static Future<List<LatLng>> getRoadRoute(LatLng start, LatLng end) async {
    // If start and end are practically identical, return trivial route
    final dLat = (start.latitude - end.latitude).abs();
    final dLng = (start.longitude - end.longitude).abs();
    if (dLat < 0.00005 && dLng < 0.00005) {
      return [start, end];
    }

    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 4));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final List coords = data['routes'][0]['geometry']['coordinates'];
          final List<LatLng> points = coords.map<LatLng>((c) {
            final double lng = (c[0] as num).toDouble();
            final double lat = (c[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          if (points.isNotEmpty) {
            _routeCache[cacheKey] = points;
            return points;
          }
        }
      }
    } catch (e) {
      debugPrint('RouteService OSRM error: $e');
    }

    // Fallback: Return straight line
    return [start, end];
  }
}
