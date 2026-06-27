import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';

class SpatialService extends ChangeNotifier {
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  static const double _bearingEpsilonDeg = 0.5;
  static const double _pitchEpsilonDeg = 0.25;

  double _latestBearing = 0.0;
  double _latestPitch = 0.0;

  double get currentBearing => _latestBearing;

  double get currentPitch => _latestPitch;

  void start() {
    _compassSub ??= FlutterCompass.events?.listen((event) {
      final heading = event.heading;
      if (heading == null) {
        return;
      }
      final nextBearing = _normalizeDegrees(heading);
      if (_shortestAngleDelta(nextBearing, _latestBearing).abs() < _bearingEpsilonDeg) {
        return;
      }
      _latestBearing = nextBearing;
      notifyListeners();
    });

    _accelSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.uiInterval,
    ).listen((event) {
      final nextPitch = math.atan2(event.y, event.z) * 180 / math.pi;
      if ((nextPitch - _latestPitch).abs() < _pitchEpsilonDeg) {
        return;
      }
      _latestPitch = nextPitch;
      notifyListeners();
    });
  }

  double bearingDelta(double current, double anchor) {
    return (current - anchor + 540.0) % 360.0 - 180.0;
  }

  bool withinBearingTolerance(double current, double anchor, {double tolerance = 3.0}) {
    return bearingDelta(current, anchor).abs() <= tolerance;
  }

  bool withinPitchTolerance(double current, double reference, {double tolerance = 3.0}) {
    return (current - reference).abs() <= tolerance;
  }

  double _normalizeDegrees(double angle) {
    final normalized = angle % 360.0;
    return normalized < 0 ? normalized + 360.0 : normalized;
  }

  double _shortestAngleDelta(double a, double b) {
    return (a - b + 540.0) % 360.0 - 180.0;
  }

  @override
  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }
}
