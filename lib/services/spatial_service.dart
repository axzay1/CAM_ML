import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:vector_math/vector_math_64.dart' as vm;

class SpatialService extends ChangeNotifier {
  StreamSubscription<CompassEvent>? _compassSub;
  StreamSubscription<AccelerometerEvent>? _accelSub;

  vm.Vector3 _position = vm.Vector3.zero();
  vm.Vector3 _velocity = vm.Vector3.zero();
  vm.Vector3 _baselineGravity = vm.Vector3.zero();
  DateTime _lastTime = DateTime.now();
  DateTime? _sessionStartedAt;

  final List<vm.Vector3> _calibrationSamples = <vm.Vector3>[];
  DateTime? _calibrationStartedAt;
  Completer<void>? _calibrationCompleter;
  bool _isCalibrating = false;

  double _latestBearing = 0.0;
  int _stillnessCount = 0;

  double get currentBearing => _latestBearing;

  bool get isCalibrating => _isCalibrating;

  double get distanceCm => _position.length * 100.0;

  double get heightDeltaCm => _position.z * 100.0;

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
    _stillnessCount = 0;
    _lastTime = DateTime.now();

    _calibrationSamples.clear();
    _calibrationStartedAt = DateTime.now();
    _isCalibrating = true;

    final completer = Completer<void>();
    _calibrationCompleter = completer;
    notifyListeners();

    await completer.future;
    _sessionStartedAt = DateTime.now();
    _lastTime = DateTime.now();
    _isCalibrating = false;
    notifyListeners();
  }

  void resetPosition() {
    _position = vm.Vector3.zero();
    _velocity = vm.Vector3.zero();
    _stillnessCount = 0;
    _lastTime = DateTime.now();
    notifyListeners();
  }

  void _onAccelerometerEvent(AccelerometerEvent event) {
    final vm.Vector3 raw = vm.Vector3(event.x, event.y, event.z);

    if (_isCalibrating) {
      _calibrationSamples.add(raw);
      final bool enoughSamples = _calibrationSamples.length >= 50;
      final bool enoughTime = _calibrationStartedAt != null &&
          DateTime.now().difference(_calibrationStartedAt!) >= const Duration(seconds: 2);

      if (enoughSamples && enoughTime) {
        final vm.Vector3 sum = _calibrationSamples.fold(
          vm.Vector3.zero(),
          (acc, v) => acc + v,
        );
        _baselineGravity = sum / _calibrationSamples.length.toDouble();
        _calibrationSamples.clear();
        _calibrationCompleter?.complete();
      }
      return;
    }

    final DateTime now = DateTime.now();
    final double dt = now.difference(_lastTime).inMilliseconds / 1000.0;
    _lastTime = now;
    if (dt <= 0 || dt > 0.2) {
      return;
    }

    vm.Vector3 acceleration = raw - _baselineGravity;

    if (acceleration.length < 0.08) {
      acceleration = vm.Vector3.zero();
    }

    _velocity += acceleration * dt;
    _position += _velocity * dt;
    _velocity *= 0.95;

    if (acceleration.length < 0.05) {
      _stillnessCount += 1;
      if (_stillnessCount >= 30) {
        _velocity = vm.Vector3.zero();
      }
    } else {
      _stillnessCount = 0;
    }

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
