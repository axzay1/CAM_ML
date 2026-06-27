import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

// TUNING GUIDE:
// kNoiseGate: increase if distance drifts when still
//             decrease if small movements not detected
//             typical range: 0.08 to 0.20
//
// kStillThreshold: number of quiet readings before
//             velocity is zeroed. At fastest interval
//             ~40 readings = ~0.5 seconds of stillness
//
// kSmoothing: higher = smoother but more lag
//             lower  = more responsive but jumpier
//             typical range: 0.7 to 0.95
//
// kDamping (0.85): higher = less damping, more drift
//                  lower  = more damping, less responsive

class SpatialService extends ChangeNotifier {
  static const double kNoiseGate = 0.12;
  static const int kStillThreshold = 40;
  static const double kSmoothing = 0.85;
  static const double kDamping = 0.85;

  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  vm.Vector3 _position = vm.Vector3.zero();
  vm.Vector3 _velocity = vm.Vector3.zero();
  vm.Vector3 _baseline = vm.Vector3.zero();
  DateTime _lastTime = DateTime.now();
  DateTime? _sessionStartedAt;

  int _calibrationCount = 0;
  final List<vm.Vector3> _calibrationSamples = <vm.Vector3>[];
  DateTime? _calibrationStartedAt;
  Completer<void>? _calibrationCompleter;
  bool _isCalibrating = false;
  bool _isCalibrated = false;

  double _latestBearing = 0.0;
  int _stillnessCount = 0;
  double _smoothedDistanceCm = 0.0;

  vm.Vector3 _lastRawAccel = vm.Vector3.zero();
  vm.Vector3 _lastGatedAccel = vm.Vector3.zero();

  double get currentBearing => _latestBearing;

  bool get isCalibrating => _isCalibrating;

  bool get isCalibrated => _isCalibrated;

  double get distanceCm => _smoothedDistanceCm;

  double get heightDeltaCm => _position.z * 100.0;

  vm.Vector3 get rawAcceleration => _lastRawAccel;

  vm.Vector3 get gatedAcceleration => _lastGatedAccel;

  double get velocityMagnitude => _velocity.length;

  int get stillCount => _stillnessCount;

  int get calibrationCount => _calibrationCount;

  bool get shouldRecommendReset {
    if (_sessionStartedAt == null) {
      return false;
    }
    return DateTime.now().difference(_sessionStartedAt!) >= const Duration(minutes: 3);
  }

  void start() {
    _compassSub ??= FlutterCompass.events?.listen((event) {
      final double heading = event.heading ?? 0.0;
      _latestBearing = _normalizeDegrees(heading);
      notifyListeners();
    });

    _accelSub ??= accelerometerEventStream(
      samplingPeriod: SensorInterval.fastestInterval,
    ).listen(_onAccelerometerEvent);
  }

  Future<void> calibrateAtSetPoint() async {
    _position = vm.Vector3.zero();
    _velocity = vm.Vector3.zero();
    _smoothedDistanceCm = 0.0;
    _stillnessCount = 0;
    _lastTime = DateTime.now();
    _lastRawAccel = vm.Vector3.zero();
    _lastGatedAccel = vm.Vector3.zero();

    _calibrationCount = 0;
    _calibrationSamples.clear();
    _calibrationStartedAt = DateTime.now();
    _isCalibrating = true;
    _isCalibrated = false;

    final completer = Completer<void>();
    _calibrationCompleter = completer;
    notifyListeners();

    await completer.future;
    _sessionStartedAt = DateTime.now();
    _lastTime = DateTime.now();
    _isCalibrating = false;
    _isCalibrated = true;
    notifyListeners();
  }

  void resetPosition() {
    _position = vm.Vector3.zero();
    _velocity = vm.Vector3.zero();
    _smoothedDistanceCm = 0.0;
    _stillnessCount = 0;
    _lastTime = DateTime.now();
    notifyListeners();
  }

  void _collectCalibration(vm.Vector3 raw) {
    _calibrationSamples.add(raw);
    _calibrationCount = _calibrationSamples.length;

    final bool enoughSamples = _calibrationSamples.length >= 100;
    final bool enoughTime = _calibrationStartedAt != null &&
        DateTime.now().difference(_calibrationStartedAt!) >= const Duration(seconds: 2);

    if (enoughSamples && enoughTime) {
      _baseline = _calibrationSamples.reduce((a, b) => a + b) /
          _calibrationSamples.length.toDouble();
      _calibrationSamples.clear();
      _calibrationCompleter?.complete();
    }
  }

  vm.Vector3 _applyNoiseGate(vm.Vector3 accel) {
    if (accel.length < kNoiseGate) {
      return vm.Vector3.zero();
    }
    return accel.normalized() * (accel.length - kNoiseGate);
  }

  void _updateSmoothed() {
    final rawCm = _position.length * 100.0;
    _smoothedDistanceCm =
        kSmoothing * _smoothedDistanceCm + (1 - kSmoothing) * rawCm;
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final vm.Vector3 raw = vm.Vector3(event.x, event.y, event.z);
    _lastRawAccel = raw;

    if (!_isCalibrated) {
      _collectCalibration(raw);
      return;
    }

    final DateTime now = DateTime.now();
    final double dt = now.difference(_lastTime).inMilliseconds / 1000.0;
    _lastTime = now;
    if (dt <= 0 || dt > 0.2) {
      return;
    }
    if (dt > 0.1 || dt <= 0) {
      return;
    }

    final vm.Vector3 residual = raw - _baseline;
    final vm.Vector3 gated = _applyNoiseGate(residual);
    _lastGatedAccel = gated;

    if (gated.length == 0.0) {
      _stillnessCount++;
    } else {
      _stillnessCount = 0;
    }
    if (_stillnessCount >= kStillThreshold) {
      _velocity = vm.Vector3.zero();
    }

    if (gated.length != 0.0) {
      _velocity += gated * dt;
      _velocity *= kDamping;
      if (_velocity.length > 2.0) {
        _velocity = _velocity.normalized() * 2.0;
      }
      _position += _velocity * dt;
    }

    _updateSmoothed();
    notifyListeners();
  }

  bool isInPosition({
    required double currentDistanceCm,
    required double targetDistanceCm,
    required double currentBearing,
    required double anchorBearing,
    required double currentHeightDelta,
  }) {
    final bool distanceOk = (currentDistanceCm - targetDistanceCm).abs() <= 20.0;
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

  @override
  void dispose() {
    _compassSub?.cancel();
    _accelSub?.cancel();
    super.dispose();
  }
}
