import 'package:cam_ml/services/spatial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialService calculations', () {
    test('haversine distance in cm is positive', () {
      final service = SpatialService();
      final distance = service.haversineDistanceCm(12.34, 56.78, 12.3405, 56.7810);
      expect(distance, greaterThan(0));
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
