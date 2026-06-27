import 'package:cam_ml/services/spatial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialService calculations', () {
    test('bearing delta wraps correctly', () {
      final service = SpatialService();
      final delta = service.bearingDelta(5, 355);
      expect(delta, closeTo(10, 0.001));
    });

    test('tolerance check succeeds when all deltas are inside threshold', () {
      final service = SpatialService();
      final ok = service.isInPosition(
        currentDistanceCm: 155,
        targetDistanceCm: 150,
        currentBearing: 42,
        anchorBearing: 40,
        currentHeightDelta: 8,
      );
      expect(ok, isTrue);
    });

    test('tolerance check fails when any axis is out of threshold', () {
      final service = SpatialService();
      final ok = service.isInPosition(
        currentDistanceCm: 180,
        targetDistanceCm: 150,
        currentBearing: 58,
        anchorBearing: 40,
        currentHeightDelta: 25,
      );
      expect(ok, isFalse);
    });
  });
}
