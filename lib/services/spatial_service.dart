import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SpatialService extends ChangeNotifier {
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  double _latestBearing = 0.0;
  double _latestPitchDeg = 0.0;
  double _anchorPitchDeg = 0.0;

  double get currentBearing => _latestBearing;

  double get currentPitchDeg => _latestPitchDeg;

  void start() {
    _compassSub ??= FlutterCompass.events?.listen((event) {
      final double heading = event.heading ?? 0.0;
      _latestBearing = _normalizeDegrees(heading);
      notifyListeners();
    });

    _accelSub ??= accelerometerEventStream().listen((event) {
      final double pitchRad = math.atan2(event.y, event.z);
      _latestPitchDeg = pitchRad * 180.0 / math.pi;
      notifyListeners();
    });
  }

  void lockAnchorPitch() {
    _anchorPitchDeg = _latestPitchDeg;
  }

  double calculateHeightDeltaCm(double distanceCm) {
    final double pitchDelta = _latestPitchDeg - _anchorPitchDeg;
    return math.sin(pitchDelta * math.pi / 180.0) * distanceCm;
  }

  double haversineDistanceCm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const double earthRadiusM = 6371000.0;
    final double dLat = _degToRad(lat2 - lat1);
    final double dLng = _degToRad(lng2 - lng1);

    final double a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    final double meters = earthRadiusM * c;
    return meters * 100.0;
  }

  bool isInPosition({
    required double currentDistanceCm,
    required double targetDistanceCm,
    required double currentBearing,
    required double anchorBearing,
    required double currentHeightDelta,
  }) {
    final bool distanceOk = (currentDistanceCm - targetDistanceCm).abs() <= 15.0;
    final bool bearingOk = _bearingDifference(currentBearing, anchorBearing).abs() <= 5.0;
    final bool heightOk = currentHeightDelta.abs() <= 10.0;
    return distanceOk && bearingOk && heightOk;
  }

  double bearingDelta(double current, double anchor) {
    return _bearingDifference(current, anchor);
  }

  double _bearingDifference(double current, double anchor) {
    final double diff = (current - anchor + 540.0) % 360.0 - 180.0;
    return diff;
  }

  double _normalizeDegrees(double angle) {
    final double normalized = angle % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  double _degToRad(double degrees) => degrees * math.pi / 180.0;

  @override
  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }
}
