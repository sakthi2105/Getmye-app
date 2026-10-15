import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;

class RouteStep {
  final String instruction;
  final String roadName;
  final double distanceMeters;
  final double durationSeconds;
  final String maneuverType;
  final String? maneuverModifier;
  final LatLng location;

  const RouteStep({
    required this.instruction,
    required this.roadName,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.maneuverType,
    this.maneuverModifier,
    required this.location,
  });

  String get formattedDistance {
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)} km';
  }

  IconData get turnIcon {
    final mod = (maneuverModifier ?? '').toLowerCase();
    final type = maneuverType.toLowerCase();

    if (type == 'arrive') return Icons.check_circle_rounded;
    if (type == 'depart') return Icons.navigation_rounded;

    if (mod.contains('sharp left')) return Icons.turn_sharp_left_rounded;
    if (mod.contains('sharp right')) return Icons.turn_sharp_right_rounded;
    if (mod.contains('slight left')) return Icons.turn_slight_left_rounded;
    if (mod.contains('slight right')) return Icons.turn_slight_right_rounded;
    if (mod.contains('left')) return Icons.turn_left_rounded;
    if (mod.contains('right')) return Icons.turn_right_rounded;
    if (mod.contains('u-turn') || mod.contains('uturn')) return Icons.u_turn_left_rounded;
    if (mod.contains('straight')) return Icons.straight_rounded;

    return Icons.near_me_rounded;
  }
}

class RouteDetails {
  final List<LatLng> points;
  final double totalDistanceMeters;
  final double totalDurationSeconds;
  final List<RouteStep> steps;

  const RouteDetails({
    required this.points,
    required this.totalDistanceMeters,
    required this.totalDurationSeconds,
    required this.steps,
  });

  String get formattedDistance {
    if (totalDistanceMeters < 1000) {
      return '${totalDistanceMeters.round()} m';
    }
    return '${(totalDistanceMeters / 1000).toStringAsFixed(1)} km';
  }

  String get formattedDuration {
    final mins = (totalDurationSeconds / 60).round();
    if (mins <= 1) return '1 min';
    if (mins < 60) return '$mins mins';
    final hours = (mins / 60).floor();
    final remMins = mins % 60;
    return '${hours}h ${remMins}m';
  }

  /// Returns the next meaningful turn instruction for the rider
  RouteStep? get currentStep {
    if (steps.isEmpty) return null;
    // If first step is just 'depart' and there is a next turn step, show the upcoming turn
    if (steps.length > 1 && steps.first.maneuverType == 'depart') {
      return steps[1];
    }
    return steps.first;
  }
}

class RouteService {
  // Cache to avoid spamming the routing server repeatedly for the same start/end
  static final Map<String, RouteDetails> _routeCache = {};

  /// Fetches simple road route points (backwards compatible with existing code)
  static Future<List<LatLng>> getRoadRoute(LatLng start, LatLng end) async {
    final details = await getDetailedRoute(start, end);
    return details.points;
  }

  /// Fetches real road coordinates AND turn-by-turn steps from free OSRM Routing API
  static Future<RouteDetails> getDetailedRoute(LatLng start, LatLng end) async {
    // If start and end are practically identical, return trivial route
    final dLat = (start.latitude - end.latitude).abs();
    final dLng = (start.longitude - end.longitude).abs();
    if (dLat < 0.00005 && dLng < 0.00005) {
      return RouteDetails(
        points: [start, end],
        totalDistanceMeters: 0,
        totalDurationSeconds: 0,
        steps: [
          RouteStep(
            instruction: 'You have arrived at customer location',
            roadName: '',
            distanceMeters: 0,
            durationSeconds: 0,
            maneuverType: 'arrive',
            location: end,
          ),
        ],
      );
    }

    final cacheKey =
        '${start.latitude.toStringAsFixed(4)},${start.longitude.toStringAsFixed(4)}->${end.latitude.toStringAsFixed(4)},${end.longitude.toStringAsFixed(4)}';
    if (_routeCache.containsKey(cacheKey)) {
      return _routeCache[cacheKey]!;
    }

    try {
      // ⚡ Request full overview with geojson geometries AND turn-by-turn steps
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/driving/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?overview=full&geometries=geojson&steps=true',
      );

      final response = await http.get(url).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['code'] == 'Ok' &&
            data['routes'] != null &&
            (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0];
          final List coords = route['geometry']['coordinates'];
          final List<LatLng> points = coords.map<LatLng>((c) {
            final double lng = (c[0] as num).toDouble();
            final double lat = (c[1] as num).toDouble();
            return LatLng(lat, lng);
          }).toList();

          final double totalDist = ((route['distance'] ?? 0) as num).toDouble();
          final double totalDur = ((route['duration'] ?? 0) as num).toDouble();

          final List<RouteStep> parsedSteps = [];
          if (route['legs'] != null && (route['legs'] as List).isNotEmpty) {
            final leg = route['legs'][0];
            final rawSteps = leg['steps'] as List? ?? [];
            for (final s in rawSteps) {
              final stepMap = s as Map<String, dynamic>;
              final maneuver = stepMap['maneuver'] as Map<String, dynamic>? ?? {};
              final stepDist = ((stepMap['distance'] ?? 0) as num).toDouble();
              final stepDur = ((stepMap['duration'] ?? 0) as num).toDouble();
              final road = (stepMap['name'] ?? '').toString().trim();
              final type = (maneuver['type'] ?? 'turn').toString();
              final modifier = maneuver['modifier']?.toString();
              
              List locList = maneuver['location'] as List? ?? [start.longitude, start.latitude];
              final stepLoc = LatLng((locList[1] as num).toDouble(), (locList[0] as num).toDouble());

              final instruction = _buildStepInstruction(type, modifier, road, stepDist);

              parsedSteps.add(RouteStep(
                instruction: instruction,
                roadName: road,
                distanceMeters: stepDist,
                durationSeconds: stepDur,
                maneuverType: type,
                maneuverModifier: modifier,
                location: stepLoc,
              ));
            }
          }

          if (points.isNotEmpty) {
            final details = RouteDetails(
              points: points,
              totalDistanceMeters: totalDist,
              totalDurationSeconds: totalDur,
              steps: parsedSteps,
            );
            _routeCache[cacheKey] = details;
            return details;
          }
        }
      }
    } catch (e) {
      debugPrint('RouteService OSRM error: $e');
    }

    // Fallback: Straight line calculation
    final fallbackDist = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
    final fallbackDur = (fallbackDist / 7.0); // approx 25 km/h

    final fallbackDetails = RouteDetails(
      points: [start, end],
      totalDistanceMeters: fallbackDist,
      totalDurationSeconds: fallbackDur,
      steps: [
        RouteStep(
          instruction: 'Proceed towards customer location (${fallbackDist < 1000 ? '${fallbackDist.round()}m' : '${(fallbackDist / 1000).toStringAsFixed(1)}km'})',
          roadName: '',
          distanceMeters: fallbackDist,
          durationSeconds: fallbackDur,
          maneuverType: 'depart',
          location: start,
        ),
      ],
    );

    return fallbackDetails;
  }

  static String _buildStepInstruction(String type, String? modifier, String road, double dist) {
    final distStr = dist < 1000 ? '${dist.round()}m' : '${(dist / 1000).toStringAsFixed(1)}km';

    if (type == 'arrive') {
      return 'Arrived at destination';
    }
    if (type == 'depart') {
      return road.isNotEmpty ? 'Head towards $road ($distStr)' : 'Start driving towards destination ($distStr)';
    }

    String action = modifier != null ? modifier.replaceAll('_', ' ') : 'turn';

    if (road.isNotEmpty) {
      return 'In $distStr, turn $action onto $road';
    } else {
      return 'In $distStr, turn $action';
    }
  }
}
