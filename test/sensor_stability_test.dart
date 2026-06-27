import 'package:cam_ml/services/spatial_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SpatialService calculations', () {
    test('bearing delta wraps correctly', () {
      final service = SpatialService();
      final delta = service.bearingDelta(5, 355);
      expect(delta, closeTo(10, 0.001));
    });

    test('bearing tolerance succeeds when inside threshold', () {
      final service = SpatialService();
      final ok = service.withinBearingTolerance(42, 40, tolerance: 3);
      expect(ok, isTrue);
    });

    test('bearing tolerance fails when outside threshold', () {
      final service = SpatialService();
      final ok = service.withinBearingTolerance(58, 40, tolerance: 3);
      expect(ok, isFalse);
    });

    test('pitch tolerance works for small pitch drift', () {
      final service = SpatialService();
      expect(service.withinPitchTolerance(2.5, 0.0, tolerance: 3.0), isTrue);
      expect(service.withinPitchTolerance(4.2, 0.0, tolerance: 3.0), isFalse);
    });
  });
}
