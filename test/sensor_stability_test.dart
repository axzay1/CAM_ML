import 'package:cam_ml/models/plot_point.dart';
import 'package:cam_ml/services/position_check_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PositionCheckService calculations', () {
    final service = PositionCheckService();

    PlotPoint makePoint({
      double bearing = 0,
      double elevation = 0,
      double distance = 150,
    }) =>
        PlotPoint(
          index: 0,
          label: 'P1',
          layerIndex: 0,
          pointInLayer: 0,
          azimuthDeg: bearing,
          elevationDeg: elevation,
          distanceCm: distance,
        );

    test('bearing delta wraps correctly across 0/360 boundary', () {
      // current = 5°, requiredBearing = 355° → shortest diff = +10°
      // azimuthDeg = (355 - 180) % 360 = 175
      final status = service.check(
        target: makePoint(bearing: 175),
        currentDistanceCm: 150,
        currentBearingDeg: 5,
        currentPitchDeg: 0,
      );
      expect(status.bearingDelta, closeTo(10.0, 0.001));
    });

    test('bearing OK when within 8° tolerance', () {
      // delta = 5° → within kBearingTolerance (8°)
      // requiredBearing = 40, azimuthDeg = (40 - 180 + 360) % 360 = 220
      final status = service.check(
        target: makePoint(bearing: 220),
        currentDistanceCm: 150,
        currentBearingDeg: 45,
        currentPitchDeg: 0,
      );
      expect(status.bearingOK, isTrue);
    });

    test('bearing NOT OK when outside 8° tolerance', () {
      // delta = 15° → outside kBearingTolerance (8°)
      final status = service.check(
        target: makePoint(bearing: 220),
        currentDistanceCm: 150,
        currentBearingDeg: 55,
        currentPitchDeg: 0,
      );
      expect(status.bearingOK, isFalse);
    });

    test('pitch OK when within 5° tolerance', () {
      final status = service.check(
        target: makePoint(elevation: 0),
        currentDistanceCm: 150,
        currentBearingDeg: 0,
        currentPitchDeg: 3.0,
      );
      expect(status.pitchOK, isTrue);
    });

    test('pitch NOT OK when outside 5° tolerance', () {
      final status = service.check(
        target: makePoint(elevation: 0),
        currentDistanceCm: 150,
        currentBearingDeg: 0,
        currentPitchDeg: 7.0,
      );
      expect(status.pitchOK, isFalse);
    });
  });
}

